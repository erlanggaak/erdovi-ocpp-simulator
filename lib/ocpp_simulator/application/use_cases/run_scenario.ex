defmodule OcppSimulator.Application.UseCases.RunScenario do
  @moduledoc """
  Run lifecycle orchestration with pre-run validation and frozen snapshot persistence.
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario

  @required_start_dependencies [:scenario_repository, :scenario_run_repository, :id_generator]
  @required_transition_dependencies [:scenario_run_repository]
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
      {:ok, persisted_run}
    end
  end

  def start_run(_dependencies, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :start_run}}

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
          case fetch(dependencies, :webhook_dispatcher) do
            dispatcher when is_atom(dispatcher) ->
              Map.put(resolved, :webhook_dispatcher, dispatcher)

            _ ->
              resolved
          end

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
    invoke(dispatcher, :dispatch_run_event, [terminal_event_name(run.state), run, metadata])
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
end
