defmodule OcppSimulator.Application.UseCases.RunScenarioTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario

  defmodule ScenarioRepositoryStub do
    alias OcppSimulator.Domain.Scenarios.Scenario

    def get("scn-ready"), do: {:ok, build_scenario!("scn-ready", ready_steps())}
    def get("scn-empty"), do: {:ok, build_scenario!("scn-empty", [])}
    def get(_id), do: {:error, :not_found}

    def list(_filters), do: {:ok, []}
    def insert(scenario), do: {:ok, scenario}

    defp ready_steps do
      [
        %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}},
        %{id: "wait", type: :wait, order: 2, delay_ms: 100}
      ]
    end

    defp build_scenario!(id, steps) do
      attrs = %{
        id: id,
        name: "Scenario #{id}",
        version: "1.0.0",
        steps: steps
      }

      {:ok, scenario} = Scenario.new(attrs)
      scenario
    end
  end

  defmodule ScenarioRunRepositoryStub do
    alias OcppSimulator.Application.UseCases.RunScenarioTest.ScenarioRepositoryStub
    alias OcppSimulator.Domain.Runs.ScenarioRun

    def insert(run), do: {:ok, run}

    def get("run-running") do
      {:ok, scenario} = ScenarioRepositoryStub.get("scn-ready")

      {:ok, run} = ScenarioRun.new(%{id: "run-running", scenario: scenario, state: :running})

      {:ok, run}
    end

    def get(_id), do: {:error, :not_found}

    def update_state(run_id, state, metadata) do
      {:ok, run} = get(run_id)
      {:ok, %{run | state: state, metadata: Map.merge(run.metadata, metadata)}}
    end
  end

  defmodule IdGeneratorStub do
    def generate("run"), do: "run-generated-1"
  end

  defmodule WebhookDispatcherStub do
    def dispatch_run_event(event, run, metadata) do
      send(self(), {:webhook_dispatched, event, run.id, metadata})
      :ok
    end
  end

  test "start_run/3 validates, queues, and persists frozen snapshot" do
    deps = %{
      scenario_repository: ScenarioRepositoryStub,
      scenario_run_repository: ScenarioRunRepositoryStub,
      id_generator: IdGeneratorStub
    }

    assert {:ok, run} = RunScenario.start_run(deps, %{scenario_id: "scn-ready"}, :operator)
    assert run.id == "run-generated-1"
    assert run.state == :queued
    assert run.scenario_id == "scn-ready"
    assert run.scenario_version == "1.0.0"

    assert run.frozen_snapshot ==
             Scenario.to_snapshot(elem(ScenarioRepositoryStub.get("scn-ready"), 1))
  end

  test "start_run/3 blocks execution when pre-run validation fails" do
    deps = %{
      scenario_repository: ScenarioRepositoryStub,
      scenario_run_repository: ScenarioRunRepositoryStub,
      id_generator: IdGeneratorStub
    }

    assert {:error, {:pre_run_validation_failed, errors}} =
             RunScenario.start_run(deps, %{scenario_id: "scn-empty"}, :operator)

    assert :scenario_has_no_steps in errors
    assert :no_enabled_steps in errors
  end

  test "transition_run/5 updates run state and dispatches terminal webhook event" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, run} =
             RunScenario.transition_run(deps, "run-running", :succeeded, :system, %{
               source: "test"
             })

    assert run.state == :succeeded
    assert_received {:webhook_dispatched, :run_succeeded, "run-running", %{source: "test"}}
  end

  test "cancel_run/4 enforces cancel permission" do
    deps = %{scenario_run_repository: ScenarioRunRepositoryStub}

    assert {:error, :forbidden} = RunScenario.cancel_run(deps, "run-running", :viewer)
  end

  test "transition_run/5 enforces finalize permission for terminal states" do
    deps = %{scenario_run_repository: ScenarioRunRepositoryStub}

    assert {:error, :forbidden} =
             RunScenario.transition_run(deps, "run-running", :succeeded, :operator, %{})
  end
end
