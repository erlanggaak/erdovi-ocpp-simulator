defmodule OcppSimulator.Infrastructure.Persistence.Mongo.Topology do
  @moduledoc """
  Named Mongo topology process used by persistence adapters.
  """

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_init_arg) do
    %{
      id: __MODULE__,
      start: {Mongo, :start_link, [start_options()]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_options() :: keyword()
  def start_options do
    OcppSimulator.mongo_config()
    |> Keyword.put(:name, __MODULE__)
  end
end
