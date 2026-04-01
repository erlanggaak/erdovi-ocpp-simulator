defmodule OcppSimulator.Domain.Scenarios.Scenario do
  @moduledoc """
  Scenario aggregate with deterministic step ordering and immutable version identity.
  """

  @semver ~r/^\d+\.\d+\.\d+$/
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
        {:ok,
         %__MODULE__{
           id: id,
           type: type,
           order: order,
           payload: payload,
           delay_ms: delay_ms,
           loop_count: loop_count,
           enabled: enabled
         }}
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

  @enforce_keys [:id, :name, :version, :schema_version, :variables, :steps]
  defstruct [:id, :name, :version, :schema_version, :variables, :steps]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          schema_version: String.t(),
          variables: map(),
          steps: [Step.t()]
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- fetch_required_string(attrs, :id),
         {:ok, name} <- fetch_required_string(attrs, :name),
         {:ok, version} <- fetch_semver(attrs),
         {:ok, schema_version} <- fetch_required_string(attrs, :schema_version, "1.0"),
         {:ok, variables} <- fetch_map(attrs, :variables, %{}),
         {:ok, steps} <- fetch_steps(attrs) do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         version: version,
         schema_version: schema_version,
         variables: variables,
         steps: steps
       }}
    end
  end

  def new(_attrs), do: {:error, {:invalid_field, :scenario, :must_be_map}}

  @spec supported_step_types() :: [atom()]
  def supported_step_types, do: @supported_step_types

  @spec to_snapshot(t()) :: map()
  def to_snapshot(%__MODULE__{} = scenario) do
    %{
      id: scenario.id,
      name: scenario.name,
      version: scenario.version,
      schema_version: scenario.schema_version,
      variables: scenario.variables,
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

  defp fetch(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
