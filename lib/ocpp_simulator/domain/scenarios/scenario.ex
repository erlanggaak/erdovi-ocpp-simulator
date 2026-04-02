defmodule OcppSimulator.Domain.Scenarios.Scenario do
  @moduledoc """
  Scenario aggregate with deterministic step ordering, schema-versioned definitions,
  and explicit validation defaults for run execution.
  """

  alias OcppSimulator.Domain.Scenarios.VariableResolver

  @semver ~r/^\d+\.\d+\.\d+$/
  @default_schema_version "1.0"
  @supported_variable_scopes [:scenario, :run, :session, :step]
  @default_variable_scopes VariableResolver.resolution_order()
  @validation_policy_defaults %{
    strict_ocpp_schema: true,
    strict_state_transitions: true,
    strict_variable_resolution: true
  }
  @supported_step_types [
    :send_action,
    :await_response,
    :wait,
    :loop,
    :set_variable,
    :assert_state
  ]

  defmodule Step do
    @moduledoc false

    @supported_step_types [
      :send_action,
      :await_response,
      :wait,
      :loop,
      :set_variable,
      :assert_state
    ]

    @enforce_keys [:id, :type, :order]
    defstruct [:id, :type, :order, :payload, :delay_ms, :loop_count, :enabled]

    @type t :: %__MODULE__{
            id: String.t(),
            type: atom(),
            order: pos_integer(),
            payload: map(),
            delay_ms: non_neg_integer(),
            loop_count: pos_integer(),
            enabled: boolean()
          }

    @spec new(map(), pos_integer()) :: {:ok, t()} | {:error, term()}
    def new(attrs, fallback_order) when is_map(attrs) and is_integer(fallback_order) do
      with {:ok, id} <- fetch_required_string(attrs, :id),
           {:ok, type} <- fetch_step_type(attrs),
           {:ok, order} <- fetch_positive_integer(attrs, :order, fallback_order),
           {:ok, payload} <- fetch_map(attrs, :payload, %{}),
           {:ok, delay_ms} <- fetch_non_negative_integer(attrs, :delay_ms, 0),
           {:ok, loop_count} <- fetch_positive_integer(attrs, :loop_count, 1),
           {:ok, enabled} <- fetch_boolean(attrs, :enabled, true) do
        step = %__MODULE__{
          id: id,
          type: type,
          order: order,
          payload: payload,
          delay_ms: delay_ms,
          loop_count: loop_count,
          enabled: enabled
        }

        with :ok <- validate_semantics(step) do
          {:ok, step}
        end
      end
    end

    def new(_attrs, _fallback_order), do: {:error, {:invalid_field, :step, :must_be_map}}

    @spec supported_step_types() :: [atom()]
    def supported_step_types, do: @supported_step_types

    defp fetch_step_type(attrs) do
      case fetch(attrs, :type) do
        value when is_atom(value) and value in @supported_step_types ->
          {:ok, value}

        value when is_binary(value) ->
          value
          |> String.trim()
          |> String.downcase()
          |> step_type_from_string()

        _ ->
          {:error, {:invalid_field, :type, :unsupported_step_type}}
      end
    end

    defp step_type_from_string("send_action"), do: {:ok, :send_action}
    defp step_type_from_string("await_response"), do: {:ok, :await_response}
    defp step_type_from_string("wait"), do: {:ok, :wait}
    defp step_type_from_string("loop"), do: {:ok, :loop}
    defp step_type_from_string("set_variable"), do: {:ok, :set_variable}
    defp step_type_from_string("assert_state"), do: {:ok, :assert_state}

    defp step_type_from_string(_value),
      do: {:error, {:invalid_field, :type, :unsupported_step_type}}

    defp validate_semantics(%__MODULE__{type: :send_action, payload: payload}) do
      with {:ok, action} <- fetch_required_string(payload, :action),
           :ok <- ensure_supported_action(action) do
        :ok
      end
    end

    defp validate_semantics(%__MODULE__{type: :await_response, payload: payload}) do
      case fetch(payload, :action) do
        nil ->
          :ok

        action when is_binary(action) and action != "" ->
          ensure_supported_action(action)

        _ ->
          {:error, {:invalid_field, :payload, :await_response_action_must_be_string}}
      end
    end

    defp validate_semantics(%__MODULE__{type: :wait, delay_ms: delay_ms}) do
      if delay_ms > 0 do
        :ok
      else
        {:error, {:invalid_field, :delay_ms, :must_be_positive_for_wait_step}}
      end
    end

    defp validate_semantics(%__MODULE__{type: :set_variable, payload: payload}) do
      with {:ok, _name} <- fetch_required_string(payload, :name),
           :ok <- ensure_payload_key(payload, :value) do
        :ok
      end
    end

    defp validate_semantics(%__MODULE__{type: :assert_state, payload: payload}) do
      with {:ok, machine} <- fetch_required_string(payload, :machine),
           :ok <- ensure_state_machine_name(machine),
           {:ok, _state} <- fetch_required_string(payload, :state) do
        :ok
      end
    end

    defp validate_semantics(%__MODULE__{}), do: :ok

    defp ensure_payload_key(payload, key) do
      if fetch(payload, key) == nil do
        {:error, {:invalid_field, key, :must_be_present_in_payload}}
      else
        :ok
      end
    end

    defp ensure_supported_action(action) do
      if OcppSimulator.Domain.Ocpp.Message.supported_action?(action) do
        :ok
      else
        {:error, {:invalid_field, :action, :unsupported_ocpp_action}}
      end
    end

    defp ensure_state_machine_name(machine) when machine in ["session", "transaction"], do: :ok

    defp ensure_state_machine_name(_machine),
      do: {:error, {:invalid_field, :machine, :must_be_session_or_transaction}}

    defp fetch_required_string(attrs, key) do
      attrs
      |> fetch(key)
      |> case do
        value when is_binary(value) and value != "" -> {:ok, value}
        _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
      end
    end

    defp fetch_positive_integer(attrs, key, default) do
      attrs
      |> fetch(key)
      |> case do
        nil when is_integer(default) and default > 0 -> {:ok, default}
        value when is_integer(value) and value > 0 -> {:ok, value}
        _ -> {:error, {:invalid_field, key, :must_be_positive_integer}}
      end
    end

    defp fetch_non_negative_integer(attrs, key, default) do
      attrs
      |> fetch(key)
      |> case do
        nil when is_integer(default) and default >= 0 -> {:ok, default}
        value when is_integer(value) and value >= 0 -> {:ok, value}
        _ -> {:error, {:invalid_field, key, :must_be_non_negative_integer}}
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

    defp fetch_boolean(attrs, key, default) do
      attrs
      |> fetch(key)
      |> case do
        nil when is_boolean(default) -> {:ok, default}
        value when is_boolean(value) -> {:ok, value}
        _ -> {:error, {:invalid_field, key, :must_be_boolean}}
      end
    end

    defp fetch(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  @enforce_keys [
    :id,
    :name,
    :version,
    :schema_version,
    :variables,
    :variable_scopes,
    :validation_policy,
    :steps
  ]
  defstruct [
    :id,
    :name,
    :version,
    :schema_version,
    :variables,
    :variable_scopes,
    :validation_policy,
    :steps
  ]

  @type variable_scope :: :scenario | :run | :session | :step

  @type validation_policy :: %{
          strict_ocpp_schema: boolean(),
          strict_state_transitions: boolean(),
          strict_variable_resolution: boolean()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          schema_version: String.t(),
          variables: map(),
          variable_scopes: [variable_scope()],
          validation_policy: validation_policy(),
          steps: [Step.t()]
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- fetch_required_string(attrs, :id),
         {:ok, name} <- fetch_required_string(attrs, :name),
         {:ok, version} <- fetch_semver(attrs),
         {:ok, schema_version} <-
           fetch_required_string(attrs, :schema_version, @default_schema_version),
         {:ok, variables} <- fetch_map(attrs, :variables, %{}),
         {:ok, variable_scopes} <- fetch_variable_scopes(attrs),
         {:ok, validation_policy} <- fetch_validation_policy(attrs),
         {:ok, steps} <- fetch_steps(attrs) do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         version: version,
         schema_version: schema_version,
         variables: variables,
         variable_scopes: variable_scopes,
         validation_policy: validation_policy,
         steps: steps
       }}
    end
  end

  def new(_attrs), do: {:error, {:invalid_field, :scenario, :must_be_map}}

  @spec supported_step_types() :: [atom()]
  def supported_step_types, do: @supported_step_types

  @spec supported_variable_scopes() :: [variable_scope()]
  def supported_variable_scopes, do: @supported_variable_scopes

  @spec default_variable_scopes() :: [variable_scope()]
  def default_variable_scopes, do: @default_variable_scopes

  @spec validation_policy_defaults() :: validation_policy()
  def validation_policy_defaults, do: @validation_policy_defaults

  @spec strict_validation?(t(), :ocpp_schema | :state_transitions | :variable_resolution) ::
          boolean()
  def strict_validation?(%__MODULE__{} = scenario, type) do
    key =
      case type do
        :ocpp_schema -> :strict_ocpp_schema
        :state_transitions -> :strict_state_transitions
        :variable_resolution -> :strict_variable_resolution
      end

    Map.get(scenario.validation_policy, key, true)
  end

  @spec execution_plan(t()) :: {:ok, [map()]}
  def execution_plan(%__MODULE__{} = scenario) do
    {plan, _next_order} =
      scenario.steps
      |> Enum.filter(& &1.enabled)
      |> Enum.reduce({[], 1}, fn step, {acc, next_order} ->
        repetitions = max(step.loop_count, 1)

        planned_steps =
          Enum.map(1..repetitions, fn iteration ->
            %{
              execution_order: next_order + iteration - 1,
              step_id: step.id,
              step_type: step.type,
              step_order: step.order,
              iteration: iteration,
              repeat_count: repetitions,
              delay_ms: step.delay_ms,
              payload: step.payload
            }
          end)

        {acc ++ planned_steps, next_order + repetitions}
      end)

    {:ok, plan}
  end

  @spec to_snapshot(t()) :: map()
  def to_snapshot(%__MODULE__{} = scenario) do
    %{
      id: scenario.id,
      name: scenario.name,
      version: scenario.version,
      schema_version: scenario.schema_version,
      variables: scenario.variables,
      variable_scopes: scenario.variable_scopes,
      validation_policy: scenario.validation_policy,
      steps:
        Enum.map(scenario.steps, fn step ->
          %{
            id: step.id,
            type: step.type,
            order: step.order,
            payload: step.payload,
            delay_ms: step.delay_ms,
            loop_count: step.loop_count,
            enabled: step.enabled
          }
        end)
    }
  end

  @spec from_snapshot(map()) :: {:ok, t()} | {:error, term()}
  def from_snapshot(snapshot) when is_map(snapshot), do: new(snapshot)

  def from_snapshot(_snapshot), do: {:error, {:invalid_field, :snapshot, :must_be_map}}

  @spec to_template_payload(t()) :: map()
  def to_template_payload(%__MODULE__{} = scenario) do
    %{
      "schema_version" => scenario.schema_version,
      "variables" => scenario.variables,
      "variable_scopes" => Enum.map(scenario.variable_scopes, &Atom.to_string/1),
      "validation_policy" => %{
        "strict_ocpp_schema" => scenario.validation_policy.strict_ocpp_schema,
        "strict_state_transitions" => scenario.validation_policy.strict_state_transitions,
        "strict_variable_resolution" => scenario.validation_policy.strict_variable_resolution
      },
      "steps" =>
        Enum.map(scenario.steps, fn step ->
          %{
            "id" => step.id,
            "type" => Atom.to_string(step.type),
            "order" => step.order,
            "payload" => step.payload,
            "delay_ms" => step.delay_ms,
            "loop_count" => step.loop_count,
            "enabled" => step.enabled
          }
        end)
    }
  end

  @spec from_template_payload(map(), map()) :: {:ok, t()} | {:error, term()}
  def from_template_payload(identity_attrs, template_payload)
      when is_map(identity_attrs) and is_map(template_payload) do
    attrs =
      identity_attrs
      |> Map.put_new(:schema_version, fetch(template_payload, :schema_version))
      |> Map.put_new(:variables, fetch(template_payload, :variables))
      |> Map.put_new(:variable_scopes, fetch(template_payload, :variable_scopes))
      |> Map.put_new(:validation_policy, fetch(template_payload, :validation_policy))
      |> Map.put_new(:steps, fetch(template_payload, :steps))

    new(attrs)
  end

  def from_template_payload(_identity_attrs, _template_payload),
    do: {:error, {:invalid_field, :template_payload, :must_be_map}}

  defp fetch_steps(attrs) do
    attrs
    |> fetch(:steps)
    |> case do
      steps when is_list(steps) ->
        steps
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {step_attrs, fallback_order}, {:ok, acc} ->
          case Step.new(step_attrs, fallback_order) do
            {:ok, step} -> {:cont, {:ok, [step | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, parsed_steps} ->
            parsed_steps
            |> Enum.reverse()
            |> normalize_step_order()

          error ->
            error
        end

      _ ->
        {:error, {:invalid_field, :steps, :must_be_list}}
    end
  end

  defp fetch_variable_scopes(attrs) do
    scope_value = fetch(attrs, :variable_scopes) || fetch(attrs, :variable_scope_order)

    case scope_value do
      nil ->
        {:ok, @default_variable_scopes}

      scopes when is_list(scopes) and scopes != [] ->
        scopes
        |> Enum.reduce_while({:ok, []}, fn scope, {:ok, acc} ->
          case normalize_scope(scope) do
            {:ok, normalized_scope} ->
              if normalized_scope in acc do
                {:halt, {:error, {:invalid_field, :variable_scopes, :duplicate_scope}}}
              else
                {:cont, {:ok, acc ++ [normalized_scope]}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      _ ->
        {:error, {:invalid_field, :variable_scopes, :must_be_non_empty_list}}
    end
  end

  defp normalize_scope(scope) when scope in @supported_variable_scopes, do: {:ok, scope}

  defp normalize_scope(scope) when is_binary(scope) do
    case scope |> String.trim() |> String.downcase() do
      "scenario" -> {:ok, :scenario}
      "run" -> {:ok, :run}
      "session" -> {:ok, :session}
      "step" -> {:ok, :step}
      _ -> {:error, {:invalid_field, :variable_scopes, :unsupported_scope}}
    end
  end

  defp normalize_scope(_scope),
    do: {:error, {:invalid_field, :variable_scopes, :unsupported_scope}}

  defp fetch_validation_policy(attrs) do
    attrs
    |> fetch_map(:validation_policy, @validation_policy_defaults)
    |> case do
      {:ok, policy} ->
        with {:ok, strict_ocpp_schema} <- fetch_boolean(policy, :strict_ocpp_schema, true),
             {:ok, strict_state_transitions} <-
               fetch_boolean(policy, :strict_state_transitions, true),
             {:ok, strict_variable_resolution} <-
               fetch_boolean(policy, :strict_variable_resolution, true) do
          {:ok,
           %{
             strict_ocpp_schema: strict_ocpp_schema,
             strict_state_transitions: strict_state_transitions,
             strict_variable_resolution: strict_variable_resolution
           }}
        end

      error ->
        error
    end
  end

  defp normalize_step_order(steps) do
    case duplicate_step_id(steps) do
      nil ->
        steps
        |> Enum.sort_by(fn step -> {step.order, step.id} end)
        |> Enum.with_index(1)
        |> Enum.map(fn {step, order} -> %{step | order: order} end)
        |> then(&{:ok, &1})

      duplicate_id ->
        {:error, {:duplicate_step_id, duplicate_id}}
    end
  end

  defp duplicate_step_id(steps) do
    steps
    |> Enum.reduce_while(MapSet.new(), fn step, seen ->
      if MapSet.member?(seen, step.id) do
        {:halt, step.id}
      else
        {:cont, MapSet.put(seen, step.id)}
      end
    end)
    |> case do
      %MapSet{} -> nil
      duplicate_id -> duplicate_id
    end
  end

  defp fetch_semver(attrs) do
    with {:ok, version} <- fetch_required_string(attrs, :version) do
      if Regex.match?(@semver, version) do
        {:ok, version}
      else
        {:error, {:invalid_field, :version, :must_be_semver}}
      end
    end
  end

  defp fetch_required_string(attrs, key, default \\ nil) do
    attrs
    |> fetch(key)
    |> case do
      nil when is_binary(default) and default != "" -> {:ok, default}
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

  defp fetch_boolean(attrs, key, default) do
    attrs
    |> fetch(key)
    |> case do
      nil when is_boolean(default) -> {:ok, default}
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_boolean}}
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
