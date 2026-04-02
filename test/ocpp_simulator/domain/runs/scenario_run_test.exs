defmodule OcppSimulator.Domain.Runs.ScenarioRunTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario

  test "new/1 freezes the full scenario snapshot with source version" do
    scenario = build_scenario!("1.0.0")

    assert {:ok, run} =
             ScenarioRun.new(%{
               id: "run-1",
               scenario: scenario,
               metadata: %{triggered_by: "qa-user"}
             })

    assert run.scenario_id == scenario.id
    assert run.scenario_version == "1.0.0"
    assert run.frozen_snapshot == Scenario.to_snapshot(scenario)
  end

  test "ensure_scenario_version/2 rejects version drift" do
    scenario_v1 = build_scenario!("1.0.0")
    scenario_v2 = %{scenario_v1 | version: "2.0.0"}

    {:ok, run} = ScenarioRun.new(%{id: "run-2", scenario: scenario_v1})

    assert {:error, {:immutable_version_mismatch, _details}} =
             ScenarioRun.ensure_scenario_version(run, scenario_v2)
  end

  test "verify_snapshot/2 rejects snapshot drift when content changes" do
    scenario = build_scenario!("1.0.0")
    {:ok, run} = ScenarioRun.new(%{id: "run-3", scenario: scenario})
    changed_scenario = %{scenario | name: "Changed name"}

    assert {:error, {:snapshot_mismatch, run_id: "run-3"}} =
             ScenarioRun.verify_snapshot(run, changed_scenario)
  end

  defp build_scenario!(version) do
    attrs = %{
      id: "scn-run",
      name: "Transaction flow",
      version: version,
      steps: [
        %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}},
        %{id: "heartbeat", type: :loop, order: 2}
      ]
    }

    {:ok, scenario} = Scenario.new(attrs)
    scenario
  end
end
