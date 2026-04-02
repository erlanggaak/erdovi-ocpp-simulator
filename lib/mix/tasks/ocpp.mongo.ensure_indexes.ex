defmodule Mix.Tasks.Ocpp.Mongo.EnsureIndexes do
  use Mix.Task

  @shortdoc "Ensures MongoDB indexes for OCPP simulator persistence"

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Indexes
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Topology

  @impl true
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: [collection: :string])

    if invalid != [] or length(positional) > 1 do
      Mix.raise(usage())
    end

    collection = Keyword.get(opts, :collection) || List.first(positional)

    {topology_pid, started_here?} = ensure_topology!()

    result =
      case collection do
        nil -> Indexes.ensure_all()
        value -> Indexes.ensure_collection(value)
      end

    maybe_stop_topology(topology_pid, started_here?)

    case result do
      :ok ->
        if is_binary(collection) do
          Mix.shell().info("Mongo indexes ensured for collection '#{collection}'.")
        else
          Mix.shell().info("Mongo indexes ensured for all collections.")
        end

      {:error, reason} ->
        Mix.raise("failed to ensure Mongo indexes: #{inspect(reason)}")
    end
  end

  defp ensure_topology! do
    case Process.whereis(Topology) do
      nil ->
        _ = Application.ensure_all_started(:mongodb_driver)

        case Mongo.start_link(Topology.start_options()) do
          {:ok, pid} -> {pid, true}
          {:error, {:already_started, pid}} -> {pid, false}
          {:error, reason} -> Mix.raise("failed to start Mongo topology: #{inspect(reason)}")
        end

      pid ->
        {pid, false}
    end
  end

  defp maybe_stop_topology(pid, true) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 5_000)
    end
  end

  defp maybe_stop_topology(_pid, false), do: :ok

  defp usage do
    """
    Usage:
      mix ocpp.mongo.ensure_indexes
      mix ocpp.mongo.ensure_indexes <collection>
      mix ocpp.mongo.ensure_indexes --collection <collection>
    """
  end
end
