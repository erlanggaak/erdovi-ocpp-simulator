defmodule OcppSimulator.Domain.Ocpp.MessageAndCorrelationPolicyTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Ocpp.CorrelationPolicy
  alias OcppSimulator.Domain.Ocpp.Message

  test "message converts to and from ocpp frame" do
    {:ok, message} = Message.new_call("msg-1", "Heartbeat", %{"foo" => "bar"}, :outbound)
    frame = Message.to_frame(message)

    assert frame == [2, "msg-1", "Heartbeat", %{"foo" => "bar"}]
    assert {:ok, parsed} = Message.from_frame(frame, :inbound)
    assert parsed.type == :call
    assert parsed.message_id == "msg-1"
    assert parsed.action == "Heartbeat"
    assert parsed.direction == :inbound
  end

  test "from_frame/2 rejects unsupported frame shape" do
    assert {:error, {:invalid_frame, :unsupported_shape}} =
             Message.from_frame([99, "x"], :inbound)
  end

  test "correlation policy tracks calls and correlates responses" do
    now = ~U[2026-04-01 10:00:00Z]

    {:ok, policy} = CorrelationPolicy.new(timeout_ms: 1_000)
    {:ok, call} = Message.new_call("msg-1", "BootNotification", %{}, :outbound)
    {:ok, policy} = CorrelationPolicy.track_call(policy, call, now)
    {:ok, response} = Message.new_call_result("msg-1", %{"status" => "Accepted"}, :inbound)

    assert {:ok, event, policy} =
             CorrelationPolicy.correlate_response(
               policy,
               response,
               DateTime.add(now, 250, :millisecond)
             )

    assert event.message_id == "msg-1"
    assert event.request_action == "BootNotification"
    assert event.response_type == :call_result
    assert event.round_trip_ms == 250
    assert CorrelationPolicy.pending_count(policy) == 0
  end

  test "correlation policy expires timed out calls" do
    now = ~U[2026-04-01 10:00:00Z]

    {:ok, policy} = CorrelationPolicy.new(timeout_ms: 1_000)
    {:ok, call} = Message.new_call("msg-timeout", "Heartbeat", %{}, :outbound)
    {:ok, policy} = CorrelationPolicy.track_call(policy, call, now)

    assert {:ok, [%{message_id: "msg-timeout", timeout_ms: 1_000}], policy} =
             CorrelationPolicy.expire(policy, DateTime.add(now, 2, :second))

    assert CorrelationPolicy.pending_count(policy) == 0
  end

  test "correlation policy rejects inbound calls for tracking" do
    {:ok, policy} = CorrelationPolicy.new(timeout_ms: 1_000)
    {:ok, inbound_call} = Message.new_call("msg-2", "Heartbeat", %{}, :inbound)

    assert {:error, {:invalid_field, :message, :must_be_outbound_call_message}} =
             CorrelationPolicy.track_call(policy, inbound_call)
  end

  test "correlation policy rejects outbound responses for correlation" do
    {:ok, policy} = CorrelationPolicy.new(timeout_ms: 1_000)
    {:ok, call} = Message.new_call("msg-3", "BootNotification", %{}, :outbound)
    {:ok, policy} = CorrelationPolicy.track_call(policy, call)

    {:ok, outbound_response} =
      Message.new_call_result("msg-3", %{"status" => "Accepted"}, :outbound)

    assert {:error, {:invalid_field, :message, :must_be_inbound_call_result_or_call_error}} =
             CorrelationPolicy.correlate_response(policy, outbound_response)
  end
end
