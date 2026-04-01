defmodule OcppSimulator.Domain.Runs.ScenarioRun do
  @moduledoc """
  Scenario run aggregate that freezes scenario snapshots for reproducibility.
  """

  alias OcppSimulator.Domain.Scenarios.Scenario

  @states [:draft, :queued, :running, :succeeded, :failed, :canceled, :timed_out]

  @enforce_keys [
    :id,
    :scenario_id,
    :scenario_version,
    :state,
    :frozen_snapshot,
    :metadata,
    :created_at
  ]
  defstruct [
    :id,
    :scenario_id,
    :scenario_version,
    :state,
    :frozen_snapshot,
    :metadata,
    :created_at
  ]

  @type state :: :draft | :queued | :running | :succeeded | :failed | :canceled | :timed_out

  @type t :: %__MODULE__{
          id: String.t(),
          scenario_id: String.t(),
          scenario_version: String.t(),
          state: state(),
          frozen_snapshot: map(),
          metadata: map(),
          created_at: DateTime.t()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- fetch_required_string(attrs, :id),
         {:ok, scenario} <- fetch_scenario(attrs),
         {:ok, state} <- fetch_state(attrs),
         {:ok, metadata} <- fetch_map(attrs, :metadata, %{}) do
      {:ok,
       %__MODULE__{
         id: id,
         scenario_id: scenario.id,
         scenario_version: scenario.version,
         state: state,
         frozen_snapshot: Scenario.to_snapshot(scenario),
         metadata: metadata,
         created_at: DateTime.utc_now()
       }}
    end
  end

  def new(_attrs), do: {:error, {:invalid_field, :scenario_run, :must_be_map}}

  @spec states() :: [state()]
  def states, do: @states

  @spec ensure_scenario_version(t(), Scenario.t()) :: :ok | {:error, term()}
  def ensure_scenario_version(%__MODULE__{} = run, %Scenario{} = scenario) do
    if run.scenario_version == scenario.version do
      :ok
    else
      {:error,
       {:immutable_version_mismatch,
        run_id: run.id, run_version: run.scenario_version, scenario_version: scenario.version}}
    end
  end

  @spec verify_snapshot(t(), Scenario.t()) :: :ok | {:error, term()}
  def verify_snapshot(%__MODULE__{} = run, %Scenario{} = scenario) do
    with :ok <- ensure_scenario_version(run, scenario) do
      current_snapshot = Scenario.to_snapshot(scenario)

      if run.frozen_snapshot == current_snapshot do
        :ok
      else
        {:error, {:snapshot_mismatch, run_id: run.id}}
      end
    end
  end

  defp fetch_scenario(attrs) do
    case fetch(attrs, :scenario) do
      %Scenario{} = scenario -> {:ok, scenario}
      _ -> {:error, {:invalid_field, :scenario, :must_be_scenario_struct}}
    end
  end

  defp fetch_state(attrs) do
    case fetch(attrs, :state) do
      nil -> {:ok, :draft}
      state when state in @states -> {:ok, state}
      _ -> {:error, {:invalid_field, :state, :unsupported_state}}
    end
  end

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
end
