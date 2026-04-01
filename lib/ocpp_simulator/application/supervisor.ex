defmodule OcppSimulator.Application.Supervisor do
  @moduledoc """
  Application-layer supervisor for use-case execution services.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Task.Supervisor, name: OcppSimulator.Application.UseCaseTaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
