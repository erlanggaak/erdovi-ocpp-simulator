defmodule OcppSimulator.Application.Contracts.ScenarioRunRepository do
  @moduledoc """
  Contract for scenario run persistence and lifecycle updates.
  """

  alias OcppSimulator.Domain.Runs.ScenarioRun

  @type page :: %{
          required(:entries) => [ScenarioRun.t()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback insert(ScenarioRun.t()) :: {:ok, ScenarioRun.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, ScenarioRun.t()} | {:error, :not_found | term()}
  @callback list_history(map()) :: {:ok, page()} | {:error, term()}

  @callback update_state(String.t(), ScenarioRun.state(), map()) ::
              {:ok, ScenarioRun.t()} | {:error, term()}
end
