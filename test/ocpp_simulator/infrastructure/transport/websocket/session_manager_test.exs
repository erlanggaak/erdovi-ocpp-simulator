defmodule OcppSimulator.Infrastructure.Transport.WebSocket.SessionManagerTest do
  use ExUnit.Case, async: false

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson
  alias OcppSimulator.Infrastructure.Transport.WebSocket.SessionManager

  defmodule SessionAdapterStub do
    def connect(session_id, _endpoint_profile) do
      notify(:connect, session_id)
      run_script({:connect, session_id}, :ok)
    end

    def disconnect(session_id, _reason) do
      notify(:disconnect, session_id)
      run_script({:disconnect, session_id}, :ok)
    end

    def send_frame(session_id, payload) do
      notify(:send_started, session_id)
      store_sent_payload(session_id, payload)

      case run_script({:send, session_id}, :ok) do
        {:sleep_then_ok, delay_ms} when is_integer(delay_ms) and delay_ms >= 0 ->
          Process.sleep(delay_ms)
          notify(:send_completed, session_id)
          :ok

        :ok ->
          notify(:send_completed, session_id)
          :ok

        {:error, reason} ->
          notify(:send_failed, session_id)
          {:error, reason}
      end
    end

    defp run_script(key, default) do
      case table() do
        nil ->
          default

        tid ->
          case :ets.lookup(tid, key) do
            [{^key, [next | rest]}] ->
              :ets.insert(tid, {key, rest})
              next

            [{^key, []}] ->
              default

            [] ->
              default
          end
      end
    end

    defp store_sent_payload(session_id, payload) do
      case table() do
        nil ->
          :ok

        tid ->
          key = {:sent, session_id}

          existing =
            case :ets.lookup(tid, key) do
              [{^key, sent_payloads}] -> sent_payloads
              [] -> []
            end

          :ets.insert(tid, {key, existing ++ [payload]})
      end

      :ok
    end

    defp table do
      Application.get_env(:ocpp_simulator, :session_manager_adapter_table)
    end

    defp notify(event, session_id) do
      if pid = Application.get_env(:ocpp_simulator, :session_manager_test_pid) do
        send(pid, {event, session_id})
      end

      :ok
    end
  end

  setup do
    table = :ets.new(__MODULE__, [:set, :public])
    original_table = Application.get_env(:ocpp_simulator, :session_manager_adapter_table)
    original_test_pid = Application.get_env(:ocpp_simulator, :session_manager_test_pid)

    Application.put_env(:ocpp_simulator, :session_manager_adapter_table, table)
    Application.put_env(:ocpp_simulator, :session_manager_test_pid, self())

    on_exit(fn ->
      if original_table do
        Application.put_env(:ocpp_simulator, :session_manager_adapter_table, original_table)
      else
        Application.delete_env(:ocpp_simulator, :session_manager_adapter_table)
      end

      if original_test_pid do
        Application.put_env(:ocpp_simulator, :session_manager_test_pid, original_test_pid)
      else
        Application.delete_env(:ocpp_simulator, :session_manager_test_pid)
      end

      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end
    end)

    manager_name = Module.concat(__MODULE__, "Manager#{System.unique_integer([:positive])}")

    manager =
      start_supervised!({
        SessionManager,
        [
          name: manager_name,
          adapter: SessionAdapterStub,
          retry_base_delay_ms: 5,
          max_reconnect_attempts: 2,
          max_queue_size: 20,
          max_in_flight: 1,
          max_queue_retry_attempts: 0
        ]
      })

    %{table: table, manager: manager}
  end

  test "connect and disconnect synchronize session lifecycle state", %{manager: manager} do
    assert :ok =
             GenServer.call(manager, {
               :connect,
               "session-lifecycle-1",
               %{url: "ws://localhost:9000/ocpp"}
             })

    assert {:ok, present} = GenServer.call(manager, {:session, "session-lifecycle-1"})
    assert present.session_state == :connected
    assert is_map(present.queue_stats)

    assert :ok = GenServer.call(manager, {:disconnect, "session-lifecycle-1", :requested})
    assert {:ok, present_after_disconnect} = GenServer.call(manager, {:session, "session-lifecycle-1"})
    assert present_after_disconnect.session_state == :disconnected
  end

  test "connect retries after transient failure and eventually reaches connected state", %{manager: manager, table: table} do
    :ets.insert(table, {{:connect, "session-retry-1"}, [{:error, :tcp_closed}, :ok]})

    assert {:error, {:connect_failed, :tcp_closed}} =
             GenServer.call(manager, {
               :connect,
               "session-retry-1",
               %{url: "ws://localhost:9000/ocpp"}
             })

    assert eventually(fn ->
             case GenServer.call(manager, {:session, "session-retry-1"}) do
               {:ok, present} ->
                 present.session_state == :connected and present.reconnect_attempt == 0

               _ ->
                 false
             end
           end)
  end

  test "connect failure transitions to disconnected after retry budget is exhausted", %{
    manager: manager,
    table: table
  } do
    :ets.insert(
      table,
      {{:connect, "session-retry-exhausted-1"}, [{:error, :tcp_closed}, {:error, :tcp_closed}, {:error, :tcp_closed}]}
    )

    assert {:error, {:connect_failed, :tcp_closed}} =
             GenServer.call(manager, {
               :connect,
               "session-retry-exhausted-1",
               %{url: "ws://localhost:9000/ocpp"}
             })

    assert eventually(fn ->
             case GenServer.call(manager, {:session, "session-retry-exhausted-1"}) do
               {:ok, present} ->
                 present.session_state == :disconnected and
                   present.last_error == :tcp_closed

               _ ->
                 false
             end
           end)
  end

  test "tracks outbound call correlation and correlates inbound call result", %{manager: manager} do
    assert :ok =
             GenServer.call(manager, {
               :connect,
               "session-correlation-1",
               %{url: "ws://localhost:9000/ocpp"}
             })

    {:ok, outbound_call} =
      Message.new_call(
        "msg-correlation-1",
        "BootNotification",
        %{"chargePointVendor" => "Erdovi", "chargePointModel" => "Sim-1"},
        :outbound
      )

    assert :ok = GenServer.call(manager, {:send_message, "session-correlation-1", outbound_call})

    {:ok, inbound_result} =
      Message.new_call_result(
        "msg-correlation-1",
        %{"status" => "Accepted", "currentTime" => "2026-04-02T05:00:00Z", "interval" => 60},
        :inbound
      )

    {:ok, encoded_result} = OcppJson.encode(inbound_result, request_action: "BootNotification")

    assert {:ok, %{correlation_event: event}} =
             GenServer.call(manager, {:ingest_inbound, "session-correlation-1", encoded_result})

    assert event.message_id == "msg-correlation-1"
    assert event.request_action == "BootNotification"

    assert {:ok, present} = GenServer.call(manager, {:session, "session-correlation-1"})
    assert present.pending_correlation_count == 0
  end

  test "handles inbound remote command and emits correlated call result", %{manager: manager, table: table} do
    assert :ok =
             GenServer.call(manager, {
               :connect,
               "session-remote-1",
               %{url: "ws://localhost:9000/ocpp"}
             })

    {:ok, inbound_remote} =
      Message.new_call(
        "msg-remote-1",
        "RemoteStartTransaction",
        %{"idTag" => "AABBCC", "connectorId" => 1},
        :inbound
      )

    {:ok, encoded_remote} = OcppJson.encode(inbound_remote)

    assert {:ok, %{response: response}} =
             GenServer.call(manager, {:ingest_inbound, "session-remote-1", encoded_remote})

    assert response.type == :call_result
    assert response.message_id == "msg-remote-1"
    assert response.payload == %{"status" => "Accepted"}

    assert eventually(fn ->
             case :ets.lookup(table, {:sent, "session-remote-1"}) do
               [{{:sent, "session-remote-1"}, [encoded_payload | _]}] ->
                 match?({:ok, %Message{type: :call_result, message_id: "msg-remote-1"}},
                   OcppJson.decode(
                     encoded_payload,
                     :outbound,
                     request_action: "RemoteStartTransaction"
                   )
                 )

               _ ->
                 false
             end
           end)
  end

  test "disconnect cancels in-flight outbound send", %{manager: manager, table: table} do
    :ets.insert(table, {{:send, "session-disconnect-1"}, [{:sleep_then_ok, 200}]})

    assert :ok =
             GenServer.call(manager, {
               :connect,
               "session-disconnect-1",
               %{url: "ws://localhost:9000/ocpp"}
             })

    {:ok, outbound_call} =
      Message.new_call(
        "msg-disconnect-1",
        "Heartbeat",
        %{},
        :outbound
      )

    assert :ok = GenServer.call(manager, {:send_message, "session-disconnect-1", outbound_call})
    assert_receive {:send_started, "session-disconnect-1"}, 100

    assert :ok = GenServer.call(manager, {:disconnect, "session-disconnect-1", :requested})
    assert_receive {:disconnect, "session-disconnect-1"}, 100
    refute_receive {:send_completed, "session-disconnect-1"}, 250
  end

  defp eventually(fun, attempts \\ 30)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, _attempts), do: false
end
