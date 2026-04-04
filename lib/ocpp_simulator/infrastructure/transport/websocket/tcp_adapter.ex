defmodule OcppSimulator.Infrastructure.Transport.WebSocket.TcpAdapter do
  @moduledoc """
  Plain WebSocket (ws://) adapter backed by TCP sockets.
  """

  @behaviour OcppSimulator.Infrastructure.Transport.WebSocket.Adapter

  alias OcppSimulator.Infrastructure.Transport.WebSocket.TcpConnection

  @registry OcppSimulator.Infrastructure.SessionRegistry
  @connection_key_prefix :tcp_ws_connection
  @connection_supervisor OcppSimulator.Infrastructure.WebSocketConnectionSupervisor

  @impl true
  def connect(session_id, endpoint_profile)
      when is_binary(session_id) and is_map(endpoint_profile) do
    with :ok <- ensure_registry_available(),
         :ok <- disconnect(session_id, :reconnect),
         {:ok, _pid} <- start_connection(session_id, endpoint_profile) do
      :ok
    end
  end

  @impl true
  def disconnect(session_id, reason) when is_binary(session_id) do
    case lookup_connection_pid(session_id) do
      {:ok, pid} -> TcpConnection.disconnect(pid, reason)
      :error -> :ok
    end
  end

  @impl true
  def send_frame(session_id, payload)
      when is_binary(session_id) and is_binary(payload) do
    with {:ok, pid} <- lookup_connection_pid(session_id) do
      TcpConnection.send_frame(pid, payload)
    end
  end

  defp start_connection(session_id, endpoint_profile) do
    child_spec = {TcpConnection, [session_id: session_id, endpoint_profile: endpoint_profile]}

    case Process.whereis(@connection_supervisor) do
      nil ->
        TcpConnection.start_link(session_id: session_id, endpoint_profile: endpoint_profile)

      _pid ->
        DynamicSupervisor.start_child(@connection_supervisor, child_spec)
    end
  end

  defp lookup_connection_pid(session_id) do
    case Registry.lookup(@registry, connection_key(session_id)) do
      [{pid, _value} | _rest] when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, pid}, else: :error

      _ ->
        :error
    end
  end

  defp connection_key(session_id), do: {@connection_key_prefix, session_id}

  defp ensure_registry_available do
    if Process.whereis(@registry), do: :ok, else: {:error, :session_registry_not_started}
  end
end
