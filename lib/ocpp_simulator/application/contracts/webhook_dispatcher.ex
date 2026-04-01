defmodule OcppSimulator.Application.Contracts.WebhookDispatcher do
  @moduledoc """
  Contract for outbound webhook delivery tied to run terminal events.
  """

  alias OcppSimulator.Domain.Runs.ScenarioRun

  @type run_event :: :run_succeeded | :run_failed | :run_canceled | :run_timed_out

  @callback dispatch_run_event(run_event(), ScenarioRun.t(), map()) :: :ok | {:error, term()}
end
