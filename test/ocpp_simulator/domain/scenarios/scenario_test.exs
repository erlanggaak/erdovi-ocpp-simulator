defmodule OcppSimulator.Domain.Scenarios.ScenarioTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Scenarios.Scenario

  test "new/1 normalizes deterministic step order" do
    attrs = %{
      id: "scn-1",
      name: "Boot and heartbeat",
      version: "1.0.0",
      variables: %{"charge_point_id" => "CP-001"},
      steps: [
        %{id: "step-b", type: :wait, order: 2, delay_ms: 10},
        %{id: "step-a", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}},
        %{id: "step-c", type: :wait, order: 2, delay_ms: 20}
      ]
    }

    assert {:ok, scenario} = Scenario.new(attrs)
    assert Enum.map(scenario.steps, & &1.id) == ["step-a", "step-b", "step-c"]
    assert Enum.map(scenario.steps, & &1.order) == [1, 2, 3]
  end

  test "new/1 rejects duplicate step ids" do
    attrs = %{
      id: "scn-1",
      name: "invalid",
      version: "1.0.0",
      steps: [
        %{id: "step-a", type: :wait},
        %{id: "step-a", type: :wait}
      ]
    }

    assert {:error, {:duplicate_step_id, "step-a"}} = Scenario.new(attrs)
  end

  test "new/1 validates scenario version format" do
    attrs = %{
      id: "scn-1",
      name: "invalid-version",
      version: "v1",
      steps: []
    }

    assert {:error, {:invalid_field, :version, :must_be_semver}} = Scenario.new(attrs)
  end
end
