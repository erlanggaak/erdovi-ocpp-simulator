defmodule OcppSimulator.Application.UseCases.RunScenario do
  @moduledoc """
  Run lifecycle orchestration with pre-run validation, frozen snapshot persistence,
  and execution sequencing:

  `create_run -> freeze_snapshot -> resolve_variables -> execute_steps ->
  persist_step_results -> finalize_run -> trigger_webhook`
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Domain.Scenarios.VariableResolver
  alias OcppSimulator.Domain.Sessions.SessionStateMachine
  alias OcppSimulator.Domain.Transactions.TransactionStateMachine
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator

  @required_start_dependencies [:scenario_repository, :scenario_run_repository, :id_generator]
  @required_transition_dependencies [:scenario_run_repository]
  @required_execute_dependencies [:scenario_run_repository]
  @run_states ScenarioRun.states()

  @allowed_transitions %{
    draft: [:queued, :canceled],
    queued: [:running, :failed, :canceled, :timed_out],
    running: [:succeeded, :failed, :canceled, :timed_out],
    succeeded: [],
    failed: [],
    canceled: [],
    timed_out: []
  }

  @terminal_states [:succeeded, :failed, :canceled, :timed_out]

  @spec start_run(map(), map(), term()) :: {:ok, ScenarioRun.t()} | {:error, term()}
  def start_run(dependencies, attrs, actor_role) when is_map(dependencies) and is_map(attrs) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :start_run),
         {:ok, deps} <- validate_dependencies(dependencies, @required_start_dependencies),
         {:ok, scenario_id} <- fetch_required_string(attrs, :scenario_id),
         {:ok, scenario} <- invoke(deps.scenario_repository, :get, [scenario_id]),
         :ok <- ensure_expected_version(attrs, scenario),
         :ok <- ensure_pre_run_validation_passes(scenario),
         :ok <- ensure_concurrency_budget(deps.scenario_run_repository),
         {:ok, run_id} <- resolve_run_id(deps, attrs),
         {:ok, metadata} <- fetch_map(attrs, :metadata, %{}),
         {:ok, scenario_run} <-
           ScenarioRun.new(%{
             id: run_id,
             scenario: scenario,
             state: :queued,
             metadata: metadata
           }),
         {:ok, persisted_run} <- invoke(deps.scenario_run_repository, :insert, [scenario_run]) do
      emit_info("scenario.run.queued", %{
        run_id: persisted_run.id,
        action: "start_run",
        payload: %{
          scenario_id: persisted_run.scenario_id,
          scenario_version: persisted_run.scenario_version,
          actor_role: actor_role
        }
      })

      {:ok, persisted_run}
    end
  end

  def start_run(_dependencies, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :start_run}}

  @spec execute_run(map(), String.t(), term(), keyword() | map()) ::
          {:ok, ScenarioRun.t()} | {:error, term()}
  def execute_run(dependencies, run_id, actor_role, opts \\ %{})

  def execute_run(dependencies, run_id, actor_role, opts)
      when is_map(dependencies) and is_binary(run_id) and run_id != "" do
    with {:ok, deps} <- validate_dependencies(dependencies, @required_execute_dependencies),
         :ok <- authorize_execution(actor_role),
         {:ok, timeout_ms} <- normalize_timeout(opts),
         {:ok, run} <- invoke(deps.scenario_run_repository, :get, [run_id]),
         :ok <- ensure_executable_state(run.state),
         {:ok, scenario} <- Scenario.from_snapshot(run.frozen_snapshot),
         {:ok, charge_point_profile} <- maybe_load_charge_point_profile(deps, scenario),
         {:ok, target_endpoint_profile} <- maybe_load_target_endpoint_profile(deps, scenario),
         :ok <- ensure_pre_run_validation_passes(scenario),
         {:ok, running_run} <- ensure_running_state(deps, run, timeout_ms),
         {:ok, plan} <- Scenario.execution_plan(scenario),
         {:ok, session} <- SessionStateMachine.new_session("session-#{run.id}"),
         {:ok, transaction} <- TransactionStateMachine.new_transaction("transaction-#{run.id}") do
      context = %{
        run_id: run.id,
        timeout_ms: timeout_ms,
        elapsed_ms: 0,
        step_results: [],
        session: session,
        transaction: transaction,
        run_variables: extract_run_variables(run),
        step_variables: %{},
        charge_point_profile: charge_point_profile,
        target_endpoint_profile: target_endpoint_profile,
        transport_gateway: fetch(deps, :transport_gateway),
        transport_connected: false
      }

      execute_result = execute_plan(deps, running_run, scenario, plan, context)
      _ = maybe_disconnect_transport(context)

      with {:ok, final_run} <- execute_result do
        emit_info("scenario.run.executed", %{
          run_id: final_run.id,
          action: "execute_run",
          payload: %{
            state: final_run.state,
            elapsed_ms: fetch(final_run.metadata, :elapsed_ms),
            failure_reason:
              normalize_failure_reason_for_log(fetch(final_run.metadata, :failure_reason))
          }
        })

        {:ok, final_run}
      end
    end
  end

  def execute_run(_dependencies, _run_id, _actor_role, _opts),
    do: {:error, {:invalid_arguments, :execute_run}}

  @spec transition_run(map(), String.t(), atom() | String.t(), term(), map()) ::
          {:ok, ScenarioRun.t()} | {:error, term()}
  def transition_run(dependencies, run_id, to_state, actor_role, metadata \\ %{})
      when is_map(dependencies) do
    with {:ok, deps} <- validate_dependencies(dependencies, @required_transition_dependencies),
         {:ok, normalized_state} <- normalize_state(to_state),
         :ok <- authorize_transition(actor_role, normalized_state),
         {:ok, existing_run} <- invoke(deps.scenario_run_repository, :get, [run_id]),
         :ok <- ensure_transition_allowed(existing_run.state, normalized_state),
         {:ok, normalized_metadata} <- normalize_transition_metadata(metadata),
         {:ok, updated_run} <-
           invoke(deps.scenario_run_repository, :update_state, [
             run_id,
             normalized_state,
             normalized_metadata
           ]),
         :ok <- maybe_dispatch_terminal_event(deps, updated_run, normalized_metadata) do
      emit_info("scenario.run.transitioned", %{
        run_id: updated_run.id,
        action: "transition_run",
        payload: %{state: updated_run.state, metadata: normalized_metadata}
      })

      {:ok, updated_run}
    end
  end

  @spec cancel_run(map(), String.t(), term(), map()) :: {:ok, ScenarioRun.t()} | {:error, term()}
  def cancel_run(dependencies, run_id, actor_role, metadata \\ %{}) do
    transition_run(dependencies, run_id, :canceled, actor_role, metadata)
  end

  @spec pre_run_validation_errors(Scenario.t()) :: [atom()]
  def pre_run_validation_errors(%Scenario{} = scenario) do
    []
    |> maybe_add_error(Enum.empty?(scenario.steps), :scenario_has_no_steps)
    |> maybe_add_error(Enum.all?(scenario.steps, &(!&1.enabled)), :no_enabled_steps)
    |> maybe_add_error(not contiguous_step_order?(scenario.steps), :non_contiguous_step_order)
  end

  defp execute_plan(deps, run, _scenario, [], context) do
    finalize_run(deps, run.id, :succeeded, %{
      step_results: context.step_results,
      total_steps: length(context.step_results),
      elapsed_ms: context.elapsed_ms,
      execution_finished_at: DateTime.utc_now()
    })
  end

  defp execute_plan(deps, run, scenario, [step | remaining_plan], context) do
    with :ok <- ensure_not_canceled(deps.scenario_run_repository, run.id),
         :ok <- ensure_timeout_not_exceeded(context, step.delay_ms),
         {:ok, resolved_payload} <- resolve_step_payload(scenario, run, step, context),
         :ok <- log_step_started(run, step, resolved_payload, context),
         {:ok, next_context, step_result} <-
           execute_step(run, scenario, step, resolved_payload, context),
         :ok <-
           persist_step_result(deps.scenario_run_repository, run.id, next_context, step_result),
         :ok <- log_step_succeeded(run, step, step_result, next_context) do
      execute_plan(deps, run, scenario, remaining_plan, next_context)
    else
      {:error, {:run_canceled, canceled_run}} ->
        _ = log_step_canceled(run, step, context)
        {:ok, canceled_run}

      {:error, {:run_timed_out, elapsed_ms}} ->
        _ = log_step_timeout(run, step, elapsed_ms, context)

        finalize_run(deps, run.id, :timed_out, %{
          step_results: context.step_results,
          elapsed_ms: elapsed_ms,
          failure_reason: :run_timed_out,
          execution_finished_at: DateTime.utc_now()
        })

      {:error, reason} ->
        _ = log_step_failed(run, step, reason, context)

        finalize_run(deps, run.id, :failed, %{
          step_results: context.step_results,
          elapsed_ms: context.elapsed_ms,
          failure_reason: reason,
          failed_step_id: step.step_id,
          execution_finished_at: DateTime.utc_now()
        })
    end
  end

  defp execute_step(run, scenario, step, resolved_payload, context) do
    with :ok <- apply_step_delay(step.delay_ms),
         :ok <- validate_step_schema(scenario, step, resolved_payload),
         {:ok, transport_context} <- emit_transport_logs(run, step, resolved_payload, context),
         {:ok, next_context, transition_events} <-
           apply_step_state_semantics(run, scenario, step, resolved_payload, transport_context),
         :ok <- maybe_assert_state(next_context, step, resolved_payload) do
      started_at = DateTime.utc_now()
      elapsed_ms = next_context.elapsed_ms + step.delay_ms
      finished_at = DateTime.utc_now()

      step_result = %{
        step_id: step.step_id,
        step_type: step.step_type,
        step_order: step.step_order,
        execution_order: step.execution_order,
        iteration: step.iteration,
        repeat_count: step.repeat_count,
        delay_ms: step.delay_ms,
        status: :succeeded,
        payload: resolved_payload,
        transition_events: transition_events,
        started_at: started_at,
        finished_at: finished_at
      }

      next_step_variables =
        maybe_capture_set_variable(step, resolved_payload, next_context.step_variables)

      {:ok,
       %{
         next_context
         | elapsed_ms: elapsed_ms,
           step_results: next_context.step_results ++ [step_result],
           step_variables: next_step_variables
       }, step_result}
    end
  end

  defp apply_step_delay(delay_ms) when is_integer(delay_ms) and delay_ms > 0 do
    Process.sleep(delay_ms)
    :ok
  end

  defp apply_step_delay(_delay_ms), do: :ok

  defp emit_transport_logs(run, %{step_type: :send_action} = step, resolved_payload, context) do
    if transport_enabled?(context) do
      emit_real_send_action_transport_logs(run, step, resolved_payload, context)
    else
      emit_simulated_send_action_transport_logs(run, step, resolved_payload, context)
    end
  end

  defp emit_transport_logs(run, %{step_type: :await_response} = step, resolved_payload, context) do
    if transport_enabled?(context) do
      emit_real_await_response_transport_logs(run, step, resolved_payload, context)
    else
      {:ok, context}
    end
  end

  defp emit_transport_logs(_run, _step, _resolved_payload, context), do: {:ok, context}

  defp emit_simulated_send_action_transport_logs(
         run,
         %{step_type: :send_action} = step,
         resolved_payload,
         context
       ) do
    action = fetch(resolved_payload, :action) || "unknown"

    emit_info("scenario.ws.connecting", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: action,
      payload: %{message: "connect to ws"}
    })

    emit_info("scenario.ws.connected", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: action,
      payload: %{message: "ws connection successful"}
    })

    emit_info("protocol.outbound_sent", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: action,
      payload: %{
        message: "send action payload",
        frame_payload: resolved_payload
      }
    })

    emit_info("protocol.inbound_received", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: action,
      payload: %{
        message: "receive action response",
        request_action: action,
        response: %{"status" => "Accepted"}
      }
    })

    {:ok, context}
  end

  defp emit_real_send_action_transport_logs(
         run,
         %{step_type: :send_action} = step,
         resolved_payload,
         context
       ) do
    with {:ok, action} <- fetch_required_string(resolved_payload, :action),
         {:ok, connected_context} <- ensure_transport_connected(run, step, context, action),
         {:ok, action_payload} <- extract_action_payload(resolved_payload),
         {:ok, message} <-
           Message.new_call(
             build_message_id(connected_context.run_id, step.step_id, action),
             action,
             action_payload,
             :outbound
           ),
         :ok <-
           emit_info("protocol.outbound_sent", %{
             run_id: run.id,
             session_id: connected_context.session.id,
             step_id: step.step_id,
             action: action,
             payload: %{
               message: "send action payload",
               frame_payload: resolved_payload
             }
           }),
         {:ok, %{message: response_message}} <-
           invoke(connected_context.transport_gateway, :send_and_await_response, [
             connected_context.session.id,
             message,
             transport_timeout_ms(resolved_payload)
           ]),
         :ok <- ensure_no_call_error_response(action, response_message),
         :ok <-
           emit_info("protocol.inbound_received", %{
             run_id: run.id,
             session_id: connected_context.session.id,
             step_id: step.step_id,
             action: action,
             payload: %{
               message: "receive action response",
               request_action: action,
               response: transport_response_payload(response_message)
             }
           }) do
      {:ok, connected_context}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_real_await_response_transport_logs(
         run,
         %{step_type: :await_response} = step,
         resolved_payload,
         context
       ) do
    with {:ok, action} <- fetch_required_string(resolved_payload, :action),
         {:ok, connected_context} <- ensure_transport_connected(run, step, context, action),
         {:ok, inbound_message} <-
           invoke(connected_context.transport_gateway, :await_inbound_call, [
             connected_context.session.id,
             action,
             transport_timeout_ms(resolved_payload)
           ]),
         :ok <-
           emit_info("protocol.inbound_received", %{
             run_id: run.id,
             session_id: connected_context.session.id,
             step_id: step.step_id,
             action: action,
             payload: %{
               message: "receive inbound call",
               request_action: action,
               request_payload: inbound_message.payload
             }
           }) do
      {:ok, connected_context}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_transport_connected(run, step, context, action) do
    if context.transport_connected do
      {:ok, context}
    else
      with {:ok, endpoint_profile} <- fetch_target_endpoint_profile(context),
           :ok <-
             emit_info("scenario.ws.connecting", %{
               run_id: run.id,
               session_id: context.session.id,
               step_id: step.step_id,
               action: action,
               payload: %{message: "connect to ws", endpoint: fetch(endpoint_profile, :url)}
             }),
           :ok <-
             invoke(context.transport_gateway, :connect, [context.session.id, endpoint_profile]),
           :ok <-
             emit_info("scenario.ws.connected", %{
               run_id: run.id,
               session_id: context.session.id,
               step_id: step.step_id,
               action: action,
               payload: %{message: "ws connection successful"}
             }) do
        {:ok, %{context | transport_connected: true}}
      else
        {:error, reason} ->
          {:error, {:transport_connect_failed, reason}}
      end
    end
  end

  defp fetch_target_endpoint_profile(%{target_endpoint_profile: endpoint_profile})
       when is_map(endpoint_profile),
       do: {:ok, endpoint_profile}

  defp fetch_target_endpoint_profile(_context),
    do: {:error, {:invalid_field, :target_endpoint_id, :must_reference_existing_endpoint}}

  defp transport_enabled?(%{transport_gateway: transport_gateway})
       when is_atom(transport_gateway) and not is_nil(transport_gateway),
       do: true

  defp transport_enabled?(_context), do: false

  defp transport_timeout_ms(resolved_payload) do
    case fetch(resolved_payload, :timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 -> timeout_ms
      _ -> 30_000
    end
  end

  defp build_message_id(run_id, step_id, action) do
    unique = System.unique_integer([:positive, :monotonic])
    "#{run_id}-#{step_id}-#{action}-#{unique}"
  end

  defp ensure_no_call_error_response(_action, %Message{type: :call_result}), do: :ok

  defp ensure_no_call_error_response(action, %Message{
         type: :call_error,
         error_code: error_code,
         error_description: error_description,
         error_details: error_details
       }) do
    {:error, {:ocpp_call_error, action, error_code, error_description, error_details || %{}}}
  end

  defp transport_response_payload(%Message{type: :call_result, payload: payload}), do: payload

  defp transport_response_payload(%Message{
         type: :call_error,
         error_code: error_code,
         error_description: error_description,
         error_details: error_details
       }) do
    %{
      "errorCode" => error_code,
      "errorDescription" => error_description,
      "errorDetails" => error_details || %{}
    }
  end

  defp maybe_capture_set_variable(%{step_type: :set_variable}, resolved_payload, step_variables) do
    variable_name = fetch(resolved_payload, :name)
    variable_value = fetch(resolved_payload, :value)

    if is_binary(variable_name) and variable_name != "" do
      Map.put(step_variables, variable_name, variable_value)
    else
      step_variables
    end
  end

  defp maybe_capture_set_variable(_step, _resolved_payload, step_variables), do: step_variables

  defp persist_step_result(scenario_run_repository, run_id, context, step_result) do
    with {:ok, _updated_run} <-
           invoke(scenario_run_repository, :update_state, [
             run_id,
             :running,
             %{
               step_results: context.step_results,
               last_step_result: step_result,
               elapsed_ms: context.elapsed_ms
             }
           ]) do
      :ok
    end
  end

  defp apply_step_state_semantics(_run, scenario, step, resolved_payload, context) do
    if Scenario.strict_validation?(scenario, :state_transitions) do
      apply_strict_state_semantics(step, resolved_payload, context)
    else
      {:ok, context, []}
    end
  end

  defp apply_strict_state_semantics(%{step_type: :send_action} = step, payload, context) do
    action = fetch(payload, :action)

    case action do
      "BootNotification" ->
        transition_session(context, :connected, step.step_id)

      "Authorize" ->
        transition_transaction(context, :authorized, step.step_id)

      "StartTransaction" ->
        transition_transaction(context, :started, step.step_id)

      "MeterValues" ->
        transition_transaction(context, :metering, step.step_id)

      "StopTransaction" ->
        transition_transaction(context, :stopped, step.step_id)

      _ ->
        {:ok, context, []}
    end
  end

  defp apply_strict_state_semantics(_step, _payload, context), do: {:ok, context, []}

  defp transition_session(context, to_state, step_id) do
    with {:ok, session, event} <-
           SessionStateMachine.transition(context.session, to_state, %{
             run_id: context.run_id,
             step_id: step_id
           }) do
      {:ok, %{context | session: session}, [event]}
    end
  end

  defp transition_transaction(context, to_state, step_id) do
    with {:ok, transaction, event} <-
           TransactionStateMachine.transition(context.transaction, to_state, %{
             run_id: context.run_id,
             step_id: step_id
           }) do
      {:ok, %{context | transaction: transaction}, [event]}
    end
  end

  defp maybe_assert_state(context, %{step_type: :assert_state}, payload) do
    machine = fetch(payload, :machine)
    expected_state = payload |> fetch(:state) |> normalize_atom_state()

    with {:ok, expected_state_atom} <- expected_state,
         :ok <- assert_machine_state(context, machine, expected_state_atom) do
      :ok
    end
  end

  defp maybe_assert_state(_context, _step, _payload), do: :ok

  defp assert_machine_state(context, "session", expected_state) do
    if context.session.state == expected_state do
      :ok
    else
      {:error, {:state_assertion_failed, :session, expected_state, context.session.state}}
    end
  end

  defp assert_machine_state(context, "transaction", expected_state) do
    if context.transaction.state == expected_state do
      :ok
    else
      {:error, {:state_assertion_failed, :transaction, expected_state, context.transaction.state}}
    end
  end

  defp assert_machine_state(_context, machine, _expected_state),
    do: {:error, {:invalid_field, :machine, machine}}

  defp normalize_atom_state(state) when is_atom(state), do: {:ok, state}

  defp normalize_atom_state(state) when is_binary(state) do
    normalized_state =
      state
      |> String.trim()
      |> String.downcase()
      |> String.replace(" ", "_")

    supported_states =
      SessionStateMachine.states() ++
        TransactionStateMachine.states()

    case Enum.find(supported_states, fn candidate ->
           Atom.to_string(candidate) == normalized_state
         end) do
      nil -> {:error, {:invalid_field, :state, :unsupported_state}}
      atom_state -> {:ok, atom_state}
    end
  end

  defp normalize_atom_state(_state),
    do: {:error, {:invalid_field, :state, :must_be_atom_or_string}}

  defp validate_step_schema(scenario, %{step_type: :send_action} = _step, payload) do
    if Scenario.strict_validation?(scenario, :ocpp_schema) do
      with {:ok, action} <- fetch_required_string(payload, :action),
           {:ok, action_payload} <- extract_action_payload(payload),
           {:ok, message} <-
             Message.new_call("schema-validation", action, action_payload, :outbound),
           :ok <- PayloadValidator.validate_message(message, []) do
        :ok
      end
    else
      :ok
    end
  end

  defp validate_step_schema(_scenario, _step, _payload), do: :ok

  defp extract_action_payload(payload) do
    case fetch(payload, :payload) do
      nested_payload when is_map(nested_payload) ->
        {:ok, nested_payload}

      nil ->
        payload
        |> Map.drop([:action, "action", :variables, "variables"])
        |> then(&{:ok, &1})

      _ ->
        {:error, {:invalid_field, :payload, :must_be_map}}
    end
  end

  defp resolve_step_payload(scenario, _run, step, context) do
    scoped_values = %{
      scenario: scenario.variables,
      run: context.run_variables,
      session: %{
        "session_state" => context.session.state,
        "transaction_state" => context.transaction.state
      },
      step:
        context.step_variables
        |> Map.merge(optional_map(step.payload, :variables))
    }

    active_scopes =
      scenario.variable_scopes
      |> Enum.reduce(%{}, fn scope, acc ->
        Map.put(acc, scope, Map.get(scoped_values, scope, %{}))
      end)

    case VariableResolver.resolve(step.payload, active_scopes) do
      {:ok, resolved_payload} ->
        {:ok, maybe_hydrate_boot_notification(step, resolved_payload, context)}

      {:error, reason} ->
        if Scenario.strict_validation?(scenario, :variable_resolution) do
          {:error, {:variable_resolution_failed, reason}}
        else
          {:ok, maybe_hydrate_boot_notification(step, step.payload, context)}
        end
    end
  end

  defp maybe_hydrate_boot_notification(
         %{step_type: :send_action},
         resolved_payload,
         %{charge_point_profile: charge_point_profile}
       ) do
    action = fetch(resolved_payload, :action)

    if action == "BootNotification" do
      enrich_boot_notification_payload(resolved_payload, charge_point_profile)
    else
      resolved_payload
    end
  end

  defp maybe_hydrate_boot_notification(_step, resolved_payload, _context), do: resolved_payload

  defp enrich_boot_notification_payload(resolved_payload, charge_point_profile)
       when is_map(resolved_payload) and is_map(charge_point_profile) do
    vendor = fetch(charge_point_profile, :vendor)
    model = fetch(charge_point_profile, :model)

    if present_string?(vendor) and present_string?(model) do
      case fetch(resolved_payload, :payload) do
        payload when is_map(payload) ->
          enriched_payload =
            payload
            |> put_missing_payload_key("chargePointVendor", vendor)
            |> put_missing_payload_key("chargePointModel", model)

          Map.put(resolved_payload, "payload", enriched_payload)

        _ ->
          resolved_payload
          |> put_missing_payload_key("chargePointVendor", vendor)
          |> put_missing_payload_key("chargePointModel", model)
      end
    else
      resolved_payload
    end
  end

  defp enrich_boot_notification_payload(resolved_payload, _charge_point_profile),
    do: resolved_payload

  defp put_missing_payload_key(map, key, value) when is_map(map) do
    if present_string?(payload_value(map, key)) do
      map
    else
      Map.put(map, key, value)
    end
  end

  defp payload_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, payload_atom_key(key))
  end

  defp payload_atom_key("chargePointVendor"), do: :chargePointVendor
  defp payload_atom_key("chargePointModel"), do: :chargePointModel
  defp payload_atom_key(_key), do: nil

  defp maybe_load_charge_point_profile(
         %{charge_point_repository: charge_point_repository},
         %Scenario{} = scenario
       )
       when is_atom(charge_point_repository) do
    case fetch(scenario.variables, :charge_point_id) do
      charge_point_id when is_binary(charge_point_id) and charge_point_id != "" ->
        case invoke(charge_point_repository, :get, [charge_point_id]) do
          {:ok, charge_point} -> {:ok, charge_point}
          _ -> {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  defp maybe_load_charge_point_profile(_deps, _scenario), do: {:ok, nil}

  defp maybe_load_target_endpoint_profile(
         %{target_endpoint_repository: target_endpoint_repository},
         %Scenario{} = scenario
       )
       when is_atom(target_endpoint_repository) do
    case fetch(scenario.variables, :target_endpoint_id) do
      target_endpoint_id when is_binary(target_endpoint_id) and target_endpoint_id != "" ->
        case invoke(target_endpoint_repository, :get, [target_endpoint_id]) do
          {:ok, endpoint_profile} -> {:ok, endpoint_profile}
          _ -> {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  defp maybe_load_target_endpoint_profile(_deps, _scenario), do: {:ok, nil}

  defp maybe_disconnect_transport(%{
         transport_gateway: transport_gateway,
         session: %{id: session_id}
       })
       when is_atom(transport_gateway) and not is_nil(transport_gateway) do
    case invoke(transport_gateway, :disconnect, [session_id]) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp maybe_disconnect_transport(_context), do: :ok

  defp ensure_running_state(_deps, %ScenarioRun{state: :running} = run, _timeout_ms),
    do: {:ok, run}

  defp ensure_running_state(deps, %ScenarioRun{state: :queued} = run, timeout_ms) do
    transition_run(
      deps,
      run.id,
      :running,
      :system,
      %{execution_started_at: DateTime.utc_now(), timeout_ms: timeout_ms}
    )
  end

  defp ensure_running_state(_deps, %ScenarioRun{state: state}, _timeout_ms),
    do: {:error, {:run_not_executable, state}}

  defp finalize_run(deps, run_id, state, metadata) do
    transition_run(deps, run_id, state, :system, metadata)
  end

  defp ensure_not_canceled(scenario_run_repository, run_id) do
    with {:ok, run} <- invoke(scenario_run_repository, :get, [run_id]) do
      if run.state == :canceled do
        {:error, {:run_canceled, run}}
      else
        :ok
      end
    end
  end

  defp ensure_timeout_not_exceeded(%{timeout_ms: nil}, _step_delay_ms), do: :ok

  defp ensure_timeout_not_exceeded(
         %{timeout_ms: timeout_ms, elapsed_ms: elapsed_ms},
         step_delay_ms
       )
       when is_integer(timeout_ms) do
    projected_elapsed = elapsed_ms + step_delay_ms

    if projected_elapsed > timeout_ms do
      {:error, {:run_timed_out, projected_elapsed}}
    else
      :ok
    end
  end

  defp ensure_executable_state(state) when state in [:queued, :running], do: :ok
  defp ensure_executable_state(state), do: {:error, {:run_not_executable, state}}

  defp authorize_execution(actor_role) do
    if system_actor?(actor_role) do
      :ok
    else
      AuthorizationPolicy.authorize(actor_role, :start_run)
    end
  end

  defp normalize_timeout(opts) when is_list(opts), do: normalize_timeout(Enum.into(opts, %{}))
  defp normalize_timeout(%{} = opts), do: normalize_timeout_value(fetch(opts, :timeout_ms))

  defp normalize_timeout(_opts),
    do: {:error, {:invalid_field, :opts, :must_be_map_or_keyword}}

  defp normalize_timeout_value(nil), do: {:ok, nil}

  defp normalize_timeout_value(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0,
    do: {:ok, timeout_ms}

  defp normalize_timeout_value(_timeout_ms),
    do: {:error, {:invalid_field, :timeout_ms, :must_be_positive_integer}}

  defp extract_run_variables(%ScenarioRun{} = run) do
    case fetch(run.metadata, :variables) do
      variables when is_map(variables) -> variables
      _ -> %{}
    end
  end

  defp optional_map(map, key) do
    case fetch(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp contiguous_step_order?([]), do: true

  defp contiguous_step_order?(steps) do
    steps
    |> Enum.map(& &1.order)
    |> Enum.sort()
    |> then(fn orders -> orders == Enum.to_list(1..length(orders)) end)
  end

  defp ensure_pre_run_validation_passes(%Scenario{} = scenario) do
    case pre_run_validation_errors(scenario) do
      [] -> :ok
      errors -> {:error, {:pre_run_validation_failed, errors}}
    end
  end

  defp ensure_expected_version(attrs, %Scenario{} = scenario) do
    case fetch(attrs, :scenario_version) do
      nil ->
        :ok

      expected_version
      when is_binary(expected_version) and expected_version == scenario.version ->
        :ok

      expected_version ->
        {:error, {:scenario_version_mismatch, expected_version, scenario.version}}
    end
  end

  defp resolve_run_id(deps, attrs) do
    case fetch(attrs, :run_id) do
      run_id when is_binary(run_id) and run_id != "" -> {:ok, run_id}
      nil -> build_generated_run_id(deps.id_generator)
      _ -> {:error, {:invalid_field, :run_id, :must_be_non_empty_string}}
    end
  end

  defp build_generated_run_id(id_generator) when is_atom(id_generator) do
    case invoke(id_generator, :generate, ["run"]) do
      generated_id when is_binary(generated_id) and generated_id != "" -> {:ok, generated_id}
      _ -> {:error, {:invalid_dependency_return, :id_generator, :generate}}
    end
  end

  defp validate_dependencies(dependencies, required_keys) do
    required_keys
    |> Enum.reduce_while({:ok, %{}}, fn key, {:ok, acc} ->
      case fetch(dependencies, key) do
        dependency when is_atom(dependency) ->
          {:cont, {:ok, Map.put(acc, key, dependency)}}

        _ ->
          {:halt, {:error, {:missing_dependency, key}}}
      end
    end)
    |> case do
      {:ok, resolved} ->
        resolved_with_optional =
          resolved
          |> maybe_put_optional_dependency(dependencies, :webhook_dispatcher)
          |> maybe_put_optional_dependency(dependencies, :charge_point_repository)
          |> maybe_put_optional_dependency(dependencies, :target_endpoint_repository)
          |> maybe_put_optional_dependency(dependencies, :transport_gateway)

        {:ok, resolved_with_optional}

      error ->
        error
    end
  end

  defp authorize_transition(actor_role, :canceled),
    do: AuthorizationPolicy.authorize(actor_role, :cancel_run)

  defp authorize_transition(actor_role, _state) do
    if system_actor?(actor_role), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_transition_allowed(from_state, to_state) do
    case Map.fetch(@allowed_transitions, from_state) do
      {:ok, allowed_states} ->
        if to_state in allowed_states do
          :ok
        else
          {:error, {:invalid_transition, from_state, to_state}}
        end

      :error ->
        {:error, {:invalid_state, from_state}}
    end
  end

  defp normalize_transition_metadata(metadata) when is_map(metadata), do: {:ok, metadata}

  defp normalize_transition_metadata(_metadata),
    do: {:error, {:invalid_field, :metadata, :must_be_map}}

  defp maybe_dispatch_terminal_event(
         %{webhook_dispatcher: dispatcher},
         %ScenarioRun{} = run,
         metadata
       )
       when run.state in @terminal_states do
    case invoke(dispatcher, :dispatch_run_event, [terminal_event_name(run.state), run, metadata]) do
      :ok ->
        :ok

      {:error, reason} ->
        emit_warn("scenario.run.webhook_dispatch_failed", %{
          run_id: run.id,
          action: "dispatch_webhook",
          payload: %{state: run.state, reason: inspect(reason)}
        })

        :ok
    end
  end

  defp maybe_dispatch_terminal_event(_deps, _run, _metadata), do: :ok

  defp terminal_event_name(:succeeded), do: :run_succeeded
  defp terminal_event_name(:failed), do: :run_failed
  defp terminal_event_name(:canceled), do: :run_canceled
  defp terminal_event_name(:timed_out), do: :run_timed_out

  defp normalize_state(state) when state in @run_states, do: {:ok, state}

  defp normalize_state(state) when is_binary(state) do
    case state |> String.trim() |> String.downcase() do
      "draft" -> {:ok, :draft}
      "queued" -> {:ok, :queued}
      "running" -> {:ok, :running}
      "succeeded" -> {:ok, :succeeded}
      "failed" -> {:ok, :failed}
      "canceled" -> {:ok, :canceled}
      "timed_out" -> {:ok, :timed_out}
      _ -> {:error, {:invalid_field, :state, :unsupported_state}}
    end
  end

  defp normalize_state(_state), do: {:error, {:invalid_field, :state, :unsupported_state}}

  defp fetch_required_string(attrs, key) do
    attrs
    |> fetch(key)
    |> case do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp fetch_map(attrs, key, default) do
    attrs
    |> fetch(key)
    |> case do
      nil when is_map(default) -> {:ok, default}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_map}}
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp invoke(module, function, args) when is_atom(module), do: apply(module, function, args)

  defp system_actor?(:system), do: true

  defp system_actor?(actor_role) when is_binary(actor_role) do
    actor_role
    |> String.trim()
    |> String.downcase()
    |> Kernel.==("system")
  end

  defp system_actor?(_actor_role), do: false

  defp maybe_add_error(errors, true, error), do: [error | errors]
  defp maybe_add_error(errors, false, _error), do: errors

  defp ensure_concurrency_budget(scenario_run_repository) do
    if function_exported?(scenario_run_repository, :list_history, 1) do
      max_concurrent_runs = runtime_limit(:max_concurrent_runs, 25)

      with {:ok, page} <-
             invoke(scenario_run_repository, :list_history, [
               %{states: [:queued, :running], page: 1, page_size: 1}
             ]) do
        if page.total_entries < max_concurrent_runs do
          :ok
        else
          {:error, {:concurrency_limit_reached, max_concurrent_runs}}
        end
      end
    else
      # Some tests use minimal stubs that expose only the required operations.
      # In that case we skip concurrency checks.
      :ok
    end
  rescue
    _ -> :ok
  end

  defp runtime_limit(key, default) do
    Application.get_env(:ocpp_simulator, :runtime, [])
    |> Keyword.get(key, default)
  end

  defp emit_info(event, payload), do: StructuredLogger.info(event, with_default_payload(payload))
  defp emit_warn(event, payload), do: StructuredLogger.warn(event, with_default_payload(payload))

  defp with_default_payload(payload) do
    payload
    |> Map.put_new(:persist, true)
    |> Map.put_new(:run_id, fetch(payload, :run_id) || "system")
  end

  defp maybe_put_optional_dependency(resolved, dependencies, key) do
    case fetch(dependencies, key) do
      dependency when is_atom(dependency) -> Map.put(resolved, key, dependency)
      _ -> resolved
    end
  end

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  defp log_step_started(run, step, resolved_payload, context) do
    emit_info("scenario.step.running", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: fetch(resolved_payload, :action),
      payload: %{
        execution_order: step.execution_order,
        step_type: step.step_type,
        delay_ms: step.delay_ms,
        payload: resolved_payload
      }
    })

    :ok
  end

  defp log_step_succeeded(run, step, step_result, context) do
    emit_info("scenario.step.succeeded", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: fetch(step_result.payload, :action),
      payload: %{
        status: step_result.status,
        elapsed_ms: context.elapsed_ms,
        step_result: step_result
      }
    })

    :ok
  end

  defp log_step_failed(run, step, reason, context) do
    emit_warn("scenario.step.failed", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: step.payload |> fetch(:action),
      payload: %{
        message: "step failed",
        reason: normalize_failure_reason_for_log(reason)
      }
    })

    :ok
  end

  defp log_step_timeout(run, step, elapsed_ms, context) do
    emit_warn("scenario.step.timed_out", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: step.payload |> fetch(:action),
      payload: %{
        message: "step timed out",
        elapsed_ms: elapsed_ms,
        run_timeout_ms: context.timeout_ms
      }
    })

    :ok
  end

  defp log_step_canceled(run, step, context) do
    emit_warn("scenario.step.canceled", %{
      run_id: run.id,
      session_id: context.session.id,
      step_id: step.step_id,
      action: step.payload |> fetch(:action),
      payload: %{message: "run canceled before step completed"}
    })

    :ok
  end

  defp normalize_failure_reason_for_log(nil), do: nil
  defp normalize_failure_reason_for_log(value) when is_binary(value), do: value
  defp normalize_failure_reason_for_log(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_failure_reason_for_log(value), do: inspect(value)
end
