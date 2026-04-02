defmodule OcppSimulator.Infrastructure.Persistence.Mongo.IndexBootstrapper do
  @moduledoc """
  Applies Mongo index definitions at startup and retries on transient failures.
  """

  use GenServer

  require Logger

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Indexes

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    send(self(), :ensure_indexes)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:ensure_indexes, state) do
    case Indexes.ensure_all() do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error("mongo index bootstrap failed: #{inspect(reason)}")
        Process.send_after(self(), :ensure_indexes, retry_delay_ms())
        {:noreply, state}
    end
  end

  defp retry_delay_ms do
    Application.get_env(:ocpp_simulator, :mongo_index_bootstrap_retry_ms, 5_000)
  end
end
