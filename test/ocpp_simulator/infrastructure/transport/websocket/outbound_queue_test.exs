defmodule OcppSimulator.Infrastructure.Transport.WebSocket.OutboundQueueTest do
  use ExUnit.Case, async: false

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson
  alias OcppSimulator.Infrastructure.Transport.WebSocket.OutboundQueue

  defmodule QueueAdapterStub do
    def send_frame(session_id, payload) do
      test_pid = Application.get_env(:ocpp_simulator, :queue_adapter_test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:adapter_send, session_id, payload})
      end

      case Application.get_env(:ocpp_simulator, :queue_adapter_mode, :ok) do
        :ok ->
          :ok

        :always_error ->
          {:error, :forced_failure}

        {:sleep_then_ok, delay_ms} ->
          Process.sleep(delay_ms)
          :ok
      end
    end
  end

  setup do
    original_mode = Application.get_env(:ocpp_simulator, :queue_adapter_mode)
    original_pid = Application.get_env(:ocpp_simulator, :queue_adapter_test_pid)

    Application.put_env(:ocpp_simulator, :queue_adapter_mode, :ok)
    Application.put_env(:ocpp_simulator, :queue_adapter_test_pid, self())

    on_exit(fn ->
      restore_env(:queue_adapter_mode, original_mode)
      restore_env(:queue_adapter_test_pid, original_pid)
    end)

    :ok
  end

  test "dispatches outbound message through adapter" do
    queue_pid =
      start_supervised!({
        OutboundQueue,
        [
          session_id: "session-queue-1",
          adapter: QueueAdapterStub,
          max_queue_size: 10,
          max_in_flight: 2,
          max_retry_attempts: 0,
          retry_base_delay_ms: 5
        ]
      })

    {:ok, message} = Message.new_call("msg-1", "Heartbeat", %{}, :outbound)

    assert :ok = OutboundQueue.enqueue(queue_pid, message)
    assert_receive {:adapter_send, "session-queue-1", encoded_frame}, 100

    assert {:ok, decoded} = OcppJson.decode(encoded_frame, :outbound)
    assert decoded.action == "Heartbeat"

    assert eventually(fn ->
             stats = OutboundQueue.stats(queue_pid)
             stats.queued_count == 0 and stats.in_flight_count == 0
           end)
  end

  test "returns backpressure error when queue is full" do
    Application.put_env(:ocpp_simulator, :queue_adapter_mode, {:sleep_then_ok, 50})

    queue_pid =
      start_supervised!({
        OutboundQueue,
        [
          session_id: "session-queue-2",
          adapter: QueueAdapterStub,
          max_queue_size: 1,
          max_in_flight: 1,
          max_retry_attempts: 0,
          retry_base_delay_ms: 5
        ]
      })

    {:ok, first} = Message.new_call("msg-a", "Heartbeat", %{}, :outbound)
    {:ok, second} = Message.new_call("msg-b", "Heartbeat", %{}, :outbound)

    assert :ok = OutboundQueue.enqueue(queue_pid, first)
    assert {:error, {:backpressure, :queue_full}} = OutboundQueue.enqueue(queue_pid, second)
  end

  test "backpressure rejection remains low-latency while queue is saturated" do
    Application.put_env(:ocpp_simulator, :queue_adapter_mode, {:sleep_then_ok, 100})

    queue_pid =
      start_supervised!({
        OutboundQueue,
        [
          session_id: "session-queue-2-latency",
          adapter: QueueAdapterStub,
          max_queue_size: 1,
          max_in_flight: 1,
          max_retry_attempts: 0,
          retry_base_delay_ms: 5
        ]
      })

    {:ok, first} = Message.new_call("msg-latency-a", "Heartbeat", %{}, :outbound)
    {:ok, second} = Message.new_call("msg-latency-b", "Heartbeat", %{}, :outbound)

    assert :ok = OutboundQueue.enqueue(queue_pid, first)

    started_at = System.monotonic_time(:millisecond)
    assert {:error, {:backpressure, :queue_full}} = OutboundQueue.enqueue(queue_pid, second)
    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    assert elapsed_ms < 200
  end

  test "retries failed sends and drops after retry budget is exhausted" do
    Application.put_env(:ocpp_simulator, :queue_adapter_mode, :always_error)

    queue_pid =
      start_supervised!({
        OutboundQueue,
        [
          session_id: "session-queue-3",
          adapter: QueueAdapterStub,
          max_queue_size: 10,
          max_in_flight: 1,
          max_retry_attempts: 1,
          retry_base_delay_ms: 5
        ]
      })

    {:ok, message} = Message.new_call("msg-retry", "Heartbeat", %{}, :outbound)

    assert :ok = OutboundQueue.enqueue(queue_pid, message)

    assert eventually(fn ->
             stats = OutboundQueue.stats(queue_pid)

             stats.retry_count >= 1 and stats.dropped_count == 1 and
               stats.queued_count == 0 and stats.in_flight_count == 0
           end)
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

  defp restore_env(key, nil), do: Application.delete_env(:ocpp_simulator, key)
  defp restore_env(key, value), do: Application.put_env(:ocpp_simulator, key, value)
end
