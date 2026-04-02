defmodule OcppSimulator.Infrastructure.Supervisor do
  @moduledoc """
  Infrastructure-layer supervisor for adapters and integration workers.
  """

  use Supervisor

  alias OcppSimulator.Infrastructure.Persistence.Mongo.IndexBootstrapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Topology

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children =
      [
        {Registry, keys: :unique, name: OcppSimulator.Infrastructure.SessionRegistry},
        {DynamicSupervisor,
         strategy: :one_for_one, name: OcppSimulator.Infrastructure.WebSocketConnectionSupervisor}
      ] ++ mongo_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp mongo_children do
    if Application.get_env(:ocpp_simulator, :mongo_autostart, false) do
      [Topology] ++ maybe_index_bootstrapper()
    else
      []
    end
  end

  defp maybe_index_bootstrapper do
    if Application.get_env(:ocpp_simulator, :mongo_index_bootstrap, true) do
      [IndexBootstrapper]
    else
      []
    end
  end
end
