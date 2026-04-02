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

  test "new/1 applies strict validation defaults and variable scope order" do
    attrs = %{
      id: "scn-defaults",
      name: "Defaults",
      version: "1.0.0",
      steps: [
        %{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}
      ]
    }

    assert {:ok, scenario} = Scenario.new(attrs)
    assert scenario.variable_scopes == [:scenario, :run, :session, :step]
    assert scenario.validation_policy.strict_ocpp_schema
    assert scenario.validation_policy.strict_state_transitions
    assert scenario.validation_policy.strict_variable_resolution
  end

  test "new/1 rejects duplicate step ids" do
    attrs = %{
      id: "scn-1",
      name: "invalid",
      version: "1.0.0",
      steps: [
        %{id: "step-a", type: :send_action, payload: %{"action" => "Heartbeat"}},
        %{id: "step-a", type: :send_action, payload: %{"action" => "Heartbeat"}}
      ]
    }

    assert {:error, {:duplicate_step_id, "step-a"}} = Scenario.new(attrs)
  end

  test "new/1 validates wait step delay semantics" do
    attrs = %{
      id: "scn-invalid-wait",
      name: "Invalid wait delay",
      version: "1.0.0",
      steps: [
        %{id: "wait", type: :wait, delay_ms: 0}
      ]
    }

    assert {:error, {:invalid_field, :delay_ms, :must_be_positive_for_wait_step}} =
             Scenario.new(attrs)
  end

  test "execution_plan/1 expands loop counts deterministically" do
    attrs = %{
      id: "scn-loop",
      name: "Loop scenario",
      version: "1.0.0",
      steps: [
        %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}},
        %{
          id: "heartbeat-loop",
          type: :send_action,
          order: 2,
          loop_count: 3,
          payload: %{"action" => "Heartbeat"}
        }
      ]
    }

    assert {:ok, scenario} = Scenario.new(attrs)
    assert {:ok, plan} = Scenario.execution_plan(scenario)
    assert length(plan) == 4

    assert Enum.map(plan, & &1.step_id) == [
             "boot",
             "heartbeat-loop",
             "heartbeat-loop",
             "heartbeat-loop"
           ]

    assert Enum.map(plan, & &1.execution_order) == [1, 2, 3, 4]
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
