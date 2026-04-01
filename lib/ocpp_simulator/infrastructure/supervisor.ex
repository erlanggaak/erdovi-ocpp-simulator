defmodule OcppSimulator.Infrastructure.Supervisor do
  @moduledoc """
  Infrastructure-layer supervisor for adapters and integration workers.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: OcppSimulator.Infrastructure.SessionRegistry},
      {DynamicSupervisor,
       strategy: :one_for_one, name: OcppSimulator.Infrastructure.WebSocketConnectionSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
