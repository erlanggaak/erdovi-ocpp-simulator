defmodule OcppSimulator.Domain.ChargePoints.ChargePointTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.ChargePoints.ChargePoint

  test "new/1 builds a valid charge point aggregate" do
    attrs = %{
      id: "CP-001",
      vendor: "Erdovi",
      model: "Simulator",
      firmware_version: "1.0.0",
      connector_count: 2,
      heartbeat_interval_seconds: 30,
      behavior_profile: "default"
    }

    assert {:ok, charge_point} = ChargePoint.new(attrs)
    assert charge_point.id == "CP-001"
    assert charge_point.behavior_profile == :default
    assert charge_point.connector_count == 2
  end

  test "new/1 rejects invalid connector count" do
    attrs = %{
      id: "CP-001",
      vendor: "Erdovi",
      model: "Simulator",
      firmware_version: "1.0.0",
      connector_count: 0
    }

    assert {:error, {:invalid_field, :connector_count, :must_be_positive_integer}} =
             ChargePoint.new(attrs)
  end
end
