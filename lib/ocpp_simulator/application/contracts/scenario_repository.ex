defmodule OcppSimulator.Application.Contracts.ScenarioRepository do
  @moduledoc """
  Contract for scenario persistence and retrieval.
  """

  alias OcppSimulator.Domain.Scenarios.Scenario

  @callback insert(Scenario.t()) :: {:ok, Scenario.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, Scenario.t()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, [Scenario.t()]} | {:error, term()}
end
