defmodule OcppSimulator.Application do
  @moduledoc """
  OTP application entrypoint.

  Startup order keeps boundaries explicit:
  Domain layer -> Application layer -> Infrastructure layer -> Interface layer.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OcppSimulator.Domain.Supervisor,
      OcppSimulator.Application.Supervisor,
      OcppSimulator.Infrastructure.Supervisor,
      OcppSimulatorWeb.Telemetry,
      {Phoenix.PubSub, name: OcppSimulator.PubSub},
      OcppSimulatorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: OcppSimulator.RootSupervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    OcppSimulatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
