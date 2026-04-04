defmodule OcppSimulator.Infrastructure.Serialization.OcppJsonTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson

  @action_payloads [
    {"BootNotification", %{"chargePointVendor" => "Erdovi", "chargePointModel" => "Sim-1"}},
    {"Heartbeat", %{}},
    {"StatusNotification",
     %{"connectorId" => 1, "status" => "Available", "errorCode" => "NoError"}},
    {"Authorize", %{"idTag" => "AABBCC"}},
    {"StartTransaction",
     %{
       "connectorId" => 1,
       "idTag" => "AABBCC",
       "meterStart" => 10,
       "timestamp" => "2026-04-02T05:00:00Z"
     }},
    {"MeterValues",
     %{
       "connectorId" => 1,
       "meterValue" => [
         %{
           "timestamp" => "2026-04-02T05:01:00Z",
           "sampledValue" => [
             %{"value" => "42.0", "measurand" => "Energy.Active.Import.Register"}
           ]
         }
       ]
     }},
    {"StopTransaction",
     %{"meterStop" => 100, "timestamp" => "2026-04-02T05:05:00Z", "transactionId" => 99}},
    {"RemoteStartTransaction", %{"idTag" => "AABBCC", "connectorId" => 1}},
    {"RemoteStopTransaction", %{"transactionId" => 99}},
    {"Reset", %{"type" => "Hard"}},
    {"ChangeAvailability", %{"connectorId" => 1, "type" => "Inoperative"}},
    {"CancelReservation", %{"reservationId" => 1001}},
    {"TriggerMessage", %{"requestedMessage" => "Heartbeat"}},
    {"ChangeConfiguration", %{"key" => "MeterValueSampleInterval", "value" => "60"}},
    {"GetConfiguration", %{"key" => ["HeartbeatInterval"]}},
    {"ClearCache", %{}},
    {"UnlockConnector", %{"connectorId" => 1}},
    {"UpdateFirmware",
     %{
       "location" => "https://example.com/fw-v2.bin",
       "retrieveDate" => "2026-04-02T06:00:00Z"
     }}
  ]

  test "encodes and decodes supported OCPP v1 call actions" do
    Enum.with_index(@action_payloads, 1)
    |> Enum.each(fn {{action, payload}, index} ->
      message_id = "msg-#{index}"
      {:ok, message} = Message.new_call(message_id, action, payload, :outbound)

      assert {:ok, encoded} = OcppJson.encode(message)
      assert {:ok, decoded} = OcppJson.decode(encoded, :outbound)
      assert decoded.type == :call
      assert decoded.message_id == message_id
      assert decoded.action == action
    end)
  end

  test "validates correlated call result payload for remote operation" do
    frame = [3, "msg-remote-1", %{"status" => "Accepted"}]

    assert {:ok, message} =
             OcppJson.decode_frame(frame, :inbound, request_action: "RemoteStartTransaction")

    assert message.type == :call_result
    assert message.message_id == "msg-remote-1"
  end

  test "rejects invalid payload shape for strict action schema" do
    {:ok, invalid_start_tx} =
      Message.new_call(
        "msg-invalid-1",
        "StartTransaction",
        %{"connectorId" => 1, "meterStart" => 10, "timestamp" => "2026-04-02T05:00:00Z"},
        :outbound
      )

    assert {:error, {:invalid_payload, "StartTransaction", :missing_required_keys, ["idTag"]}} =
             OcppJson.encode(invalid_start_tx)
  end

  test "rejects unsupported call action" do
    {:ok, message} = Message.new_call("msg-unsupported", "UnknownAction", %{}, :outbound)

    assert {:error, {:unsupported_action, "UnknownAction"}} = OcppJson.encode(message)
  end

  test "rejects payload that exceeds schema maxLength" do
    {:ok, message} =
      Message.new_call(
        "msg-authorize-too-long",
        "Authorize",
        %{"idTag" => String.duplicate("A", 21)},
        :outbound
      )

    assert {:error,
            {:invalid_payload, "Authorize", :invalid_field_type, "idTag",
             %{type: "string", maxLength: 20}}} = OcppJson.encode(message)
  end

  test "rejects payload with invalid date-time format" do
    {:ok, message} =
      Message.new_call(
        "msg-invalid-time",
        "StartTransaction",
        %{
          "connectorId" => 1,
          "idTag" => "AABBCC",
          "meterStart" => 10,
          "timestamp" => "2026-04-02 05:00:00"
        },
        :outbound
      )

    assert {:error,
            {:invalid_payload, "StartTransaction", :invalid_field_type, "timestamp",
             %{type: "string", format: "date-time"}}} = OcppJson.encode(message)
  end

  test "supports call error frames for basic fault scenarios" do
    {:ok, message} =
      Message.new_call_error(
        "msg-fault-1",
        "InternalError",
        "simulated processing failure",
        %{"fault" => "transient"},
        :outbound
      )

    assert {:ok, encoded} = OcppJson.encode(message)
    assert {:ok, decoded} = OcppJson.decode(encoded, :inbound)
    assert decoded.type == :call_error
    assert decoded.error_code == "InternalError"
  end

  test "requires request action when encoding call result frame" do
    {:ok, result} = Message.new_call_result("msg-result-1", %{"status" => "Accepted"}, :outbound)

    assert {:error, {:missing_request_action, :call_result}} = OcppJson.encode(result)
  end

  test "rejects invalid nested payload shape for meter values" do
    {:ok, meter_values} =
      Message.new_call(
        "msg-meter-invalid",
        "MeterValues",
        %{
          "connectorId" => 1,
          "meterValue" => [%{"timestamp" => "2026-04-02T05:01:00Z", "sampledValue" => [%{}]}]
        },
        :outbound
      )

    assert {:error,
            {:invalid_payload, "MeterValues", :missing_required_keys,
             ["meterValue[0].sampledValue[0].value"]}} =
             OcppJson.encode(meter_values)
  end

  test "rejects invalid JSON frames" do
    assert {:error, {:invalid_frame, :invalid_json}} = OcppJson.decode("not-json", :inbound)
  end
end
