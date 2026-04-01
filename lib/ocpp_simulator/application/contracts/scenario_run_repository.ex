defmodule OcppSimulator.Application.Contracts.ScenarioRunRepository do
  @moduledoc """
  Contract for scenario run persistence and lifecycle updates.
  """

  alias OcppSimulator.Domain.Runs.ScenarioRun

  @callback insert(ScenarioRun.t()) :: {:ok, ScenarioRun.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, ScenarioRun.t()} | {:error, :not_found | term()}

  @callback update_state(String.t(), ScenarioRun.state(), map()) ::
              {:ok, ScenarioRun.t()} | {:error, term()}
end
