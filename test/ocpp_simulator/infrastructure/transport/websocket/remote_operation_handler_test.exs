defmodule OcppSimulator.Infrastructure.Transport.WebSocket.RemoteOperationHandlerTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Transport.WebSocket.RemoteOperationHandler

  test "accepts remote start when charge point is available and idle" do
    {:ok, request} =
      Message.new_call(
        "msg-remote-start",
        "RemoteStartTransaction",
        %{"idTag" => "AABBCC", "connectorId" => 1},
        :inbound
      )

    context = %{
      charge_point_state: :available,
      transaction_state: :none,
      availability: :operative
    }

    assert {:ok, response, updated_context} =
             RemoteOperationHandler.handle_inbound(request, context)

    assert response.type == :call_result
    assert response.message_id == "msg-remote-start"
    assert response.payload["status"] == "Accepted"
    assert updated_context.transaction_state == :authorized
  end

  test "rejects remote stop when no active transaction exists" do
    {:ok, request} =
      Message.new_call(
        "msg-remote-stop",
        "RemoteStopTransaction",
        %{"transactionId" => 10},
        :inbound
      )

    context = %{charge_point_state: :available, transaction_state: :none}

    assert {:ok, response, _updated_context} =
             RemoteOperationHandler.handle_inbound(request, context)

    assert response.payload == %{"status" => "Rejected"}
  end

  test "schedules change availability while transaction is active" do
    {:ok, request} =
      Message.new_call(
        "msg-change-availability",
        "ChangeAvailability",
        %{"connectorId" => 1, "type" => "Inoperative"},
        :inbound
      )

    context = %{charge_point_state: :charging, transaction_state: :metering}

    assert {:ok, response, updated_context} =
             RemoteOperationHandler.handle_inbound(request, context)

    assert response.payload == %{"status" => "Scheduled"}
    assert updated_context.pending_availability == :inoperative
  end

  test "handles trigger message request and records requested message" do
    {:ok, request} =
      Message.new_call(
        "msg-trigger",
        "TriggerMessage",
        %{"requestedMessage" => "Heartbeat"},
        :inbound
      )

    assert {:ok, response, updated_context} =
             RemoteOperationHandler.handle_inbound(request, %{availability: :operative})

    assert response.payload == %{"status" => "Accepted"}
    assert updated_context.last_triggered_message == "Heartbeat"
  end

  test "rejects soft reset while transaction is running" do
    {:ok, request} = Message.new_call("msg-reset", "Reset", %{"type" => "Soft"}, :inbound)

    assert {:ok, response, _updated_context} =
             RemoteOperationHandler.handle_inbound(request, %{transaction_state: :started})

    assert response.payload == %{"status" => "Rejected"}
  end

  test "returns call error for unsupported inbound call action" do
    {:ok, request} =
      Message.new_call("msg-unsup", "UnknownAction", %{"connectorId" => 1}, :inbound)

    assert {:ok, response, _updated_context} =
             RemoteOperationHandler.handle_inbound(request, %{})

    assert response.type == :call_error
    assert response.error_code == "NotSupported"
    assert response.message_id == "msg-unsup"
  end

  test "returns formation violation call error for invalid payload" do
    {:ok, request} =
      Message.new_call("msg-invalid", "RemoteStartTransaction", %{"connectorId" => 1}, :inbound)

    assert {:ok, response, _updated_context} =
             RemoteOperationHandler.handle_inbound(request, %{})

    assert response.type == :call_error
    assert response.error_code == "FormationViolation"
  end
end
