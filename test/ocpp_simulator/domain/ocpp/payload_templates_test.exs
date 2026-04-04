defmodule OcppSimulator.Domain.Ocpp.PayloadTemplatesTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Ocpp.PayloadTemplates

  test "payload_for_action/1 builds required schema fields for BootNotification" do
    assert %{
             "chargePointVendor" => "Erdovi",
             "chargePointModel" => "Simulator"
           } = PayloadTemplates.payload_for_action("BootNotification")
  end

  test "payload_for_action/1 builds required schema fields for Authorize" do
    assert %{"idTag" => "RFID-1"} = PayloadTemplates.payload_for_action("Authorize")
  end

  test "send_action_step_payload/1 wraps action and payload" do
    assert %{
             "action" => "Heartbeat",
             "payload" => %{}
           } = PayloadTemplates.send_action_step_payload("Heartbeat")
  end
end
