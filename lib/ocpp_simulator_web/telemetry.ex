defmodule OcppSimulatorWeb.Telemetry do
  @moduledoc """
  Telemetry poller supervisor for interface metrics.
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      )
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :dispatch_runtime_metrics, []}
    ]
  end

  def dispatch_runtime_metrics do
    runtime = OcppSimulator.runtime_config()

    :telemetry.execute(
      [:ocpp_simulator, :runtime, :limits],
      %{
        max_concurrent_runs: runtime[:max_concurrent_runs],
        max_active_sessions: runtime[:max_active_sessions],
        ws_max_reconnect_attempts: runtime[:ws_max_reconnect_attempts],
        ws_outbound_max_queue_size: runtime[:ws_outbound_max_queue_size],
        ws_outbound_max_in_flight: runtime[:ws_outbound_max_in_flight],
        webhook_delivery_timeout_ms: runtime[:webhook_delivery_timeout_ms]
      },
      %{}
    )
  end
end
