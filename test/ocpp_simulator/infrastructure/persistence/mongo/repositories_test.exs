defmodule OcppSimulator.Infrastructure.Persistence.Mongo.RepositoriesTest do
  use ExUnit.Case, async: false

  alias OcppSimulator.Domain.Sessions.SessionStateMachine
  alias OcppSimulator.Domain.ChargePoints.ChargePoint
  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Indexes
  alias OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.UserRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.WebhookDeliveryRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.WebhookEndpointRepository
  alias OcppSimulator.TestSupport.InMemoryMongoClient

  setup_all do
    original_client = Application.get_env(:ocpp_simulator, :mongo_persistence_client)
    original_topology = Application.get_env(:ocpp_simulator, :mongo_persistence_topology)

    Application.put_env(:ocpp_simulator, :mongo_persistence_client, InMemoryMongoClient)
    Application.put_env(:ocpp_simulator, :mongo_persistence_topology, :in_memory_test_topology)

    on_exit(fn ->
      if original_client do
        Application.put_env(:ocpp_simulator, :mongo_persistence_client, original_client)
      else
        Application.delete_env(:ocpp_simulator, :mongo_persistence_client)
      end

      if original_topology do
        Application.put_env(:ocpp_simulator, :mongo_persistence_topology, original_topology)
      else
        Application.delete_env(:ocpp_simulator, :mongo_persistence_topology)
      end
    end)

    :ok
  end

  setup do
    InMemoryMongoClient.reset!()
    :ok
  end

  test "charge point repository satisfies insert/get/list contract" do
    charge_point = build_charge_point!("CP-MONGO-1")

    assert {:ok, persisted} = ChargePointRepository.insert(charge_point)
    assert persisted.id == "CP-MONGO-1"

    assert {:ok, fetched} = ChargePointRepository.get("CP-MONGO-1")
    assert fetched.vendor == charge_point.vendor

    assert {:ok, page} = ChargePointRepository.list(%{vendor: "Erdovi"})
    assert page.total_entries == 1
    assert Enum.map(page.entries, & &1.id) == ["CP-MONGO-1"]
  end

  test "charge point list is page-aware with explicit metadata" do
    Enum.each(1..55, fn index ->
      charge_point =
        build_charge_point!("CP-BULK-#{String.pad_leading(Integer.to_string(index), 3, "0")}")

      assert {:ok, _} = ChargePointRepository.insert(charge_point)
    end)

    assert {:ok, page_1} = ChargePointRepository.list(%{vendor: "Erdovi"})
    assert page_1.page == 1
    assert page_1.page_size == 50
    assert page_1.total_entries == 55
    assert page_1.total_pages == 2
    assert length(page_1.entries) == 50

    assert {:ok, page_2} = ChargePointRepository.list(%{vendor: "Erdovi", page: 2, page_size: 50})
    assert page_2.page == 2
    assert length(page_2.entries) == 5
  end

  test "target endpoint repository persists endpoint maps" do
    endpoint = %{
      id: "ep-mongo-1",
      name: "Primary",
      url: "ws://localhost:9000/ocpp",
      protocol_options: %{"subprotocol" => "ocpp1.6"},
      retry_policy: %{max_attempts: 5, backoff_ms: 1_000},
      metadata: %{region: "id"}
    }

    assert {:ok, persisted} = TargetEndpointRepository.insert(endpoint)
    assert persisted.id == "ep-mongo-1"

    assert {:ok, fetched} = TargetEndpointRepository.get("ep-mongo-1")
    assert fetched.url == endpoint.url

    assert {:ok, page} = TargetEndpointRepository.list(%{name: "Primary"})
    assert page.total_entries == 1
    assert Enum.map(page.entries, & &1.id) == ["ep-mongo-1"]
  end

  test "template repository upsert/get/list uses type-aware mapping" do
    template = %{
      id: "tpl-boot-1",
      name: "BootNotification",
      version: "1.0.0",
      type: :action,
      payload_template: %{"action" => "BootNotification"},
      metadata: %{starter: true}
    }

    assert {:ok, persisted} = TemplateRepository.upsert(template)
    assert persisted.type == :action

    assert {:ok, fetched} = TemplateRepository.get("tpl-boot-1", :action)
    assert fetched.name == "BootNotification"

    assert {:ok, page} = TemplateRepository.list(%{type: "action"})
    assert page.total_entries == 1
    assert Enum.any?(page.entries, &(&1.id == "tpl-boot-1"))
  end

  test "scenario repository persists and loads domain aggregate" do
    scenario = build_scenario!("scn-mongo-1")

    assert {:ok, persisted} = ScenarioRepository.insert(scenario)
    assert persisted.id == scenario.id

    assert {:ok, fetched} = ScenarioRepository.get("scn-mongo-1")
    assert fetched.version == "1.0.0"

    assert {:ok, page} = ScenarioRepository.list(%{name: scenario.name})
    assert page.total_entries == 1
    assert Enum.any?(page.entries, &(&1.id == scenario.id))
  end

  test "scenario run repository supports lifecycle updates" do
    scenario = build_scenario!("scn-run-1")
    run = build_run!("run-mongo-1", scenario)

    assert {:ok, persisted} = ScenarioRunRepository.insert(run)
    assert persisted.state == :queued

    assert {:ok, updated} =
             ScenarioRunRepository.update_state("run-mongo-1", :running, %{attempt: 1})

    assert updated.state == :running
    assert updated.metadata["source"] == "test"
    assert updated.metadata["attempt"] == 1
    refute Map.has_key?(updated.metadata, :attempt)

    assert {:ok, failed} =
             ScenarioRunRepository.update_state("run-mongo-1", :failed, %{
               failure_reason:
                 {:invalid_payload, "BootNotification", :missing_required_keys,
                  ["chargePointModel", "chargePointVendor"]}
             })

    assert failed.metadata["failure_reason"] == [
             "invalid_payload",
             "BootNotification",
             "missing_required_keys",
             ["chargePointModel", "chargePointVendor"]
           ]

    transition_event = %SessionStateMachine.TransitionEvent{
      session_id: "session-run-mongo-1",
      from_state: :idle,
      to_state: :connected,
      occurred_at: ~U[2026-04-01 10:00:00Z],
      correlation: %{run_id: "run-mongo-1", step_id: "boot"}
    }

    assert {:ok, running} =
             ScenarioRunRepository.update_state("run-mongo-1", :running, %{
               transition_events: [transition_event]
             })

    assert [%{} = stored_event] = running.metadata["transition_events"]
    assert stored_event["session_id"] == "session-run-mongo-1"
    assert stored_event["from_state"] == "idle"
    assert stored_event["to_state"] == "connected"
    assert stored_event["correlation"]["step_id"] == "boot"

    assert {:ok, page} = ScenarioRunRepository.list_history(%{scenario_id: "scn-run-1"})
    assert page.total_entries == 1
    assert Enum.at(page.entries, 0).id == "run-mongo-1"
  end

  test "scenario run update_state returns precise validation errors" do
    scenario = build_scenario!("scn-run-2")
    run = build_run!("run-mongo-2", scenario)

    assert {:ok, _} = ScenarioRunRepository.insert(run)

    assert {:error, {:invalid_field, :id, :must_be_non_empty_string}} =
             ScenarioRunRepository.update_state("", :running, %{})

    assert {:error, {:invalid_field, :metadata, :must_be_map}} =
             ScenarioRunRepository.update_state("run-mongo-2", :running, :invalid)

    assert {:error, {:invalid_field, :state, :unsupported_state}} =
             ScenarioRunRepository.update_state("run-mongo-2", :not_a_real_state, %{})
  end

  test "user repository supports upsert/get/get_by_email/list" do
    user = %{
      id: "usr-1",
      email: "qa@example.com",
      role: "operator",
      password_hash: "hash",
      metadata: %{team: "qa"}
    }

    assert {:ok, persisted} = UserRepository.upsert(user)
    assert persisted.email == "qa@example.com"

    assert {:ok, fetched_by_id} = UserRepository.get("usr-1")
    assert fetched_by_id.role == "operator"

    assert {:ok, fetched_by_email} = UserRepository.get_by_email("qa@example.com")
    assert fetched_by_email.id == "usr-1"

    assert {:ok, page} = UserRepository.list(%{role: "operator"})
    assert page.total_entries == 1
    assert Enum.any?(page.entries, &(&1.id == "usr-1"))
  end

  test "webhook endpoint repository supports upsert/get/list" do
    endpoint = %{
      id: "wh-ep-1",
      name: "Run Events",
      url: "https://example.test/webhook",
      events: ["run.succeeded", "run.failed"],
      retry_policy: %{max_attempts: 3, backoff_ms: 1_000},
      secret_ref: "whsec_1",
      metadata: %{owner: "qa"}
    }

    assert {:ok, persisted} = WebhookEndpointRepository.upsert(endpoint)
    assert persisted.id == "wh-ep-1"

    assert {:ok, fetched} = WebhookEndpointRepository.get("wh-ep-1")
    assert fetched.url == endpoint.url

    assert {:ok, page} = WebhookEndpointRepository.list(%{event: "run.failed"})
    assert page.total_entries == 1
    assert Enum.any?(page.entries, &(&1.id == "wh-ep-1"))
  end

  test "webhook delivery repository supports insert/update_status/list" do
    delivery = %{
      id: "wh-del-1",
      run_id: "run-99",
      event: "run.failed",
      status: :queued,
      attempts: 0,
      payload: %{"run_id" => "run-99"},
      metadata: %{"source" => "test"}
    }

    assert {:ok, persisted} = WebhookDeliveryRepository.insert(delivery)
    assert persisted.status == :queued

    assert {:ok, updated} =
             WebhookDeliveryRepository.update_status("wh-del-1", :failed, %{
               attempts: 2,
               last_error: "timeout"
             })

    assert updated.status == :failed
    assert updated.attempts == 2
    assert updated.last_error == "timeout"

    assert {:ok, page} = WebhookDeliveryRepository.list(%{status: :failed})
    assert page.total_entries == 1
    assert Enum.any?(page.entries, &(&1.id == "wh-del-1"))
  end

  test "log repository persists entries and returns paginated results" do
    log_entry = %{
      id: "log-1",
      run_id: "run-log-1",
      session_id: "session-1",
      charge_point_id: "CP-LOG-1",
      message_id: "msg-1",
      severity: "info",
      event_type: "protocol",
      payload: %{"frame" => [2, "msg-1", "Heartbeat", %{}]},
      timestamp: ~U[2026-04-01 10:00:00Z]
    }

    assert {:ok, persisted} = LogRepository.insert(log_entry)
    assert persisted.id == "log-1"

    assert {:ok, page} = LogRepository.list(%{run_id: "run-log-1", page: 1, page_size: 10})
    assert page.total_entries == 1
    assert Enum.at(page.entries, 0).message_id == "msg-1"
  end

  test "index registry applies configured indexes to all collections" do
    assert :ok = Indexes.ensure_all()

    scenario_run_indexes = InMemoryMongoClient.indexes_for("scenario_runs")
    log_indexes = InMemoryMongoClient.indexes_for("logs")

    assert Enum.any?(
             scenario_run_indexes,
             &(Keyword.get(&1, :name) == "scenario_runs_history_idx")
           )

    assert Enum.any?(log_indexes, &(Keyword.get(&1, :name) == "logs_run_timestamp_idx"))
  end

  defp build_charge_point!(id) do
    {:ok, charge_point} =
      ChargePoint.new(%{
        id: id,
        vendor: "Erdovi",
        model: "Simulator",
        firmware_version: "1.0.0",
        connector_count: 2,
        heartbeat_interval_seconds: 30,
        behavior_profile: :default
      })

    charge_point
  end

  defp build_scenario!(id) do
    {:ok, scenario} =
      Scenario.new(%{
        id: id,
        name: "Scenario #{id}",
        version: "1.0.0",
        schema_version: "1.0",
        steps: [
          %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}},
          %{id: "wait", type: :wait, order: 2, delay_ms: 100}
        ]
      })

    scenario
  end

  defp build_run!(id, scenario) do
    {:ok, run} =
      ScenarioRun.new(%{
        id: id,
        scenario: scenario,
        state: :queued,
        metadata: %{"source" => "test"}
      })

    run
  end
end
