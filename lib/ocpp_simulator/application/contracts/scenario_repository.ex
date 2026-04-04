defmodule OcppSimulator.Application.Contracts.ScenarioRepository do
  @moduledoc """
  Contract for scenario persistence and retrieval.
  """

  alias OcppSimulator.Domain.Scenarios.Scenario

  @type page :: %{
          required(:entries) => [Scenario.t()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback insert(Scenario.t()) :: {:ok, Scenario.t()} | {:error, term()}
  @callback update(Scenario.t()) :: {:ok, Scenario.t()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, :not_found | term()}
  @callback get(String.t()) :: {:ok, Scenario.t()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
