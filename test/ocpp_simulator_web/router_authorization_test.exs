defmodule OcppSimulatorWeb.RouterAuthorizationTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint OcppSimulatorWeb.Endpoint

  defmodule ScenarioRepositoryStub do
    alias OcppSimulator.Domain.Scenarios.Scenario

    def list(_filters) do
      {:ok, scenario} =
        Scenario.new(%{
          id: "scn-api-export-1",
          name: "API Export",
          version: "1.0.0",
          steps: [
            %{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}
          ]
        })

      {:ok, %{entries: [scenario], page: 1, page_size: 50, total_entries: 1, total_pages: 1}}
    end

    def insert(scenario), do: {:ok, scenario}
  end

  defmodule TemplateRepositoryStub do
    def list(_filters) do
      {:ok,
       %{
         entries: [
           %{
             id: "tpl-api-export-1",
             name: "API Template",
             version: "1.0.0",
             type: :action,
             payload_template: %{"action" => "Heartbeat"},
             metadata: %{}
           }
         ],
         page: 1,
         page_size: 50,
         total_entries: 1,
         total_pages: 1
       }}
    end

    def upsert(template), do: {:ok, template}
  end

  defmodule ChargePointRepositoryStub do
    alias OcppSimulator.Domain.ChargePoints.ChargePoint

    def list(_filters) do
      {:ok, charge_point} =
        ChargePoint.new(%{
          id: "cp-router-1",
          vendor: "Erdovi",
          model: "AC-100",
          firmware_version: "1.0.0",
          connector_count: 2,
          heartbeat_interval_seconds: 60,
          behavior_profile: :default
        })

      {:ok, %{entries: [charge_point], page: 1, page_size: 50, total_entries: 1, total_pages: 1}}
    end
  end

  defmodule TargetEndpointRepositoryStub do
    def list(_filters) do
      {:ok,
       %{
         entries: [
           %{
             id: "endpoint-router-1",
             name: "Router CSMS",
             url: "ws://localhost:9000/ocpp",
             protocol_options: %{},
             retry_policy: %{max_attempts: 3, backoff_ms: 1_000},
             metadata: %{}
           }
         ],
         page: 1,
         page_size: 50,
         total_entries: 1,
         total_pages: 1
       }}
    end

    def insert(endpoint), do: {:ok, endpoint}
  end

  defmodule ScenarioRunRepositoryStub do
    alias OcppSimulator.Domain.Runs.ScenarioRun
    alias OcppSimulator.Domain.Scenarios.Scenario

    def list(_filters) do
      {:ok, %{entries: [sample_run()], page: 1, page_size: 25, total_entries: 1, total_pages: 1}}
    end

    def list_history(_filters) do
      {:ok, %{entries: [sample_run()], page: 1, page_size: 25, total_entries: 1, total_pages: 1}}
    end

    defp sample_run do
      {:ok, scenario} =
        Scenario.new(%{
          id: "scn-history-1",
          name: "History Scenario",
          version: "1.0.0",
          steps: [
            %{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}
          ]
        })

      %ScenarioRun{
        id: "run-history-1",
        scenario_id: scenario.id,
        scenario_version: scenario.version,
        state: :failed,
        frozen_snapshot: Scenario.to_snapshot(scenario),
        metadata: %{failure_reason: :timeout},
        created_at: DateTime.utc_now()
      }
    end
  end

  defmodule LogRepositoryStub do
    def list(filters) do
      run_id = filters[:run_id] || filters["run_id"]
      session_id = filters[:session_id] || filters["session_id"]
      message_id = filters[:message_id] || filters["message_id"]

      entries =
        if run_id in [nil, ""] and session_id in [nil, ""] and message_id in [nil, ""] do
          []
        else
          [
            %{
              id: "log-router-1",
              run_id: run_id || "run-history-1",
              session_id: session_id || "session-1",
              charge_point_id: "cp-router-1",
              message_id: message_id || "msg-1",
              severity: "info",
              event_type: "ocpp_frame",
              payload: %{"reason" => "none"},
              timestamp: DateTime.utc_now()
            }
          ]
        end

      {:ok,
       %{
         entries: entries,
         page: filters[:page] || 1,
         page_size: filters[:page_size] || 50,
         total_entries: length(entries),
         total_pages: 1
       }}
    end
  end

  setup do
    previous_charge_point_repository = Application.get_env(:ocpp_simulator, :charge_point_repository)
    previous_target_endpoint_repository =
      Application.get_env(:ocpp_simulator, :target_endpoint_repository)

    previous_scenario_repository = Application.get_env(:ocpp_simulator, :scenario_repository)
    previous_template_repository = Application.get_env(:ocpp_simulator, :template_repository)
    previous_scenario_run_repository = Application.get_env(:ocpp_simulator, :scenario_run_repository)
    previous_log_repository = Application.get_env(:ocpp_simulator, :log_repository)

    Application.put_env(:ocpp_simulator, :charge_point_repository, ChargePointRepositoryStub)
    Application.put_env(:ocpp_simulator, :target_endpoint_repository, TargetEndpointRepositoryStub)
    Application.put_env(:ocpp_simulator, :scenario_repository, ScenarioRepositoryStub)
    Application.put_env(:ocpp_simulator, :template_repository, TemplateRepositoryStub)
    Application.put_env(:ocpp_simulator, :scenario_run_repository, ScenarioRunRepositoryStub)
    Application.put_env(:ocpp_simulator, :log_repository, LogRepositoryStub)

    on_exit(fn ->
      if previous_charge_point_repository do
        Application.put_env(:ocpp_simulator, :charge_point_repository, previous_charge_point_repository)
      else
        Application.delete_env(:ocpp_simulator, :charge_point_repository)
      end

      if previous_target_endpoint_repository do
        Application.put_env(
          :ocpp_simulator,
          :target_endpoint_repository,
          previous_target_endpoint_repository
        )
      else
        Application.delete_env(:ocpp_simulator, :target_endpoint_repository)
      end

      if previous_scenario_repository do
        Application.put_env(:ocpp_simulator, :scenario_repository, previous_scenario_repository)
      else
        Application.delete_env(:ocpp_simulator, :scenario_repository)
      end

      if previous_template_repository do
        Application.put_env(:ocpp_simulator, :template_repository, previous_template_repository)
      else
        Application.delete_env(:ocpp_simulator, :template_repository)
      end

      if previous_scenario_run_repository do
        Application.put_env(:ocpp_simulator, :scenario_run_repository, previous_scenario_run_repository)
      else
        Application.delete_env(:ocpp_simulator, :scenario_run_repository)
      end

      if previous_log_repository do
        Application.put_env(:ocpp_simulator, :log_repository, previous_log_repository)
      else
        Application.delete_env(:ocpp_simulator, :log_repository)
      end
    end)

    :ok
  end

  test "scenario builder route redirects unauthorized viewer" do
    conn =
      build_conn()
      |> get("/scenario-builder")

    assert redirected_to(conn, 302) == "/"
  end

  test "charge point registry route allows viewer" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/charge-points")

    assert html_response(conn, 200) =~ "Charge Point Registry"
  end

  test "scenario builder route allows operator from session role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> get("/scenario-builder")

    response = html_response(conn, 200)
    assert response =~ "Scenario Builder"
    assert response =~ "Run Validation Summary"
    assert response =~ "Request/Response Preview"
  end

  test "target endpoint screen renders retry policy form and validation panel" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> get("/target-endpoints")

    response = html_response(conn, 200)
    assert response =~ "Target Endpoints"
    assert response =~ "Retry Max Attempts"
    assert response =~ "Retry Backoff (ms)"
  end

  test "run history and logs routes are accessible for viewer role" do
    run_history_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/run-history")

    assert html_response(run_history_conn, 200) =~ "Run History"

    logs_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/logs")

    assert html_response(logs_conn, 200) =~ "Apply at least one filter"
  end

  test "live console requires run filter and renders timeline context" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/live-console")

    response = html_response(conn, 200)
    assert response =~ "Live Console"
    assert response =~ "Enter a run ID"
  end

  test "scenario builder shows field-level error when steps JSON is invalid" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(%{}, %{}, live_socket(%{current_role: :operator}))

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event("update_visual", %{
        "scenario" => %{
          "steps_json" => "{invalid-json"
        }
      }, socket)

    assert socket.assigns.field_errors[:steps] == "Steps must be valid JSON array format."
  end

  test "target endpoint create keeps inline validation errors for invalid form input" do
    {:ok, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.mount(%{}, %{}, live_socket(%{current_role: :operator}))

    {:noreply, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.handle_event("create_endpoint", %{
        "endpoint" => %{
          "id" => "endpoint-invalid-1",
          "name" => "Bad Endpoint",
          "url" => "http://invalid-url",
          "retry_max_attempts" => "0",
          "retry_backoff_ms" => "0"
        }
      }, socket)

    assert socket.assigns.endpoint_errors[:url] == "URL must use `ws://` in v1."
    assert socket.assigns.endpoint_errors[:retry_max_attempts] == "Must be a positive integer."
    assert socket.assigns.endpoint_errors[:retry_backoff_ms] == "Must be a positive integer."
    assert socket.assigns.feedback == "Please fix validation errors before submitting."
  end

  test "logs live supports filter-first query and correlation drill-down" do
    {:ok, socket} = OcppSimulatorWeb.LogsLive.mount(%{}, %{}, live_socket(%{current_role: :viewer}))
    assert socket.assigns.feedback =~ "Apply at least one filter"

    {:noreply, filtered_socket} =
      OcppSimulatorWeb.LogsLive.handle_event("filter", %{
        "filters" => %{
          "run_id" => "run-history-1",
          "session_id" => "",
          "message_id" => "",
          "severity" => "",
          "event_type" => "",
          "page_size" => "50"
        }
      }, socket)

    assert length(filtered_socket.assigns.entries) == 1
    assert hd(filtered_socket.assigns.entries).run_id == "run-history-1"

    {:noreply, drilled_socket} =
      OcppSimulatorWeb.LogsLive.handle_event("drill_filter", %{
        "run_id" => "run-correlation-1",
        "session_id" => "session-correlation-1",
        "message_id" => "message-correlation-1"
      }, filtered_socket)

    assert drilled_socket.assigns.filters.run_id == "run-correlation-1"
    assert drilled_socket.assigns.filters.session_id == "session-correlation-1"
    assert drilled_socket.assigns.filters.message_id == "message-correlation-1"
    assert hd(drilled_socket.assigns.entries).run_id == "run-correlation-1"
    assert hd(drilled_socket.assigns.entries).session_id == "session-correlation-1"
    assert hd(drilled_socket.assigns.entries).message_id == "message-correlation-1"
  end

  test "run history replay action shows replay entry feedback" do
    {:ok, socket} = OcppSimulatorWeb.RunHistoryLive.mount(%{}, %{}, live_socket(%{current_role: :viewer}))
    {:noreply, socket} = OcppSimulatorWeb.RunHistoryLive.handle_event("replay", %{"id" => "run-history-1"}, socket)
    assert socket.assigns.replay_feedback =~ "Replay requested for run run-history-1"
  end

  test "api run start denies viewer role" do
    conn =
      build_conn()
      |> post("/api/runs", %{})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "api run start allows operator role from session" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/runs", %{})

    assert %{"data" => %{"resource" => "run", "status" => "accepted"}} = json_response(conn, 202)
  end

  test "api run start ignores untrusted role header by default" do
    conn =
      build_conn()
      |> put_req_header("x-ocpp-role", "operator")
      |> post("/api/runs", %{})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "api management endpoints enforce role permissions" do
    operator_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/charge-points", %{})

    assert %{"data" => %{"resource" => "charge_point"}} = json_response(operator_conn, 202)

    viewer_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/api/charge-points", %{})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(viewer_conn, 403)
  end

  test "api artifact export/import endpoints are role-gated and return structured data" do
    export_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> get("/api/scenarios/export")

    assert %{"data" => %{"artifact" => "scenarios", "count" => 1}} =
             json_response(export_conn, 200)

    import_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/templates/import", %{
        "entries" => [
          %{
            "id" => "tpl-api-import-1",
            "name" => "Imported API Template",
            "version" => "1.0.0",
            "type" => "scenario",
            "payload_template" => %{"definition" => %{"steps" => []}},
            "metadata" => %{}
          }
        ]
      })

    assert %{"data" => %{"artifact" => "templates", "imported_count" => 1}} =
             json_response(import_conn, 201)

    forbidden_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/api/templates/export")

    assert %{"error" => %{"code" => "forbidden"}} = json_response(forbidden_conn, 403)
  end

  defp live_socket(assigns) when is_map(assigns) do
    base_assigns =
      %{
        __changed__: %{},
        current_role: :viewer,
        permission_grants: %{}
      }
      |> Map.merge(assigns)

    %Phoenix.LiveView.Socket{assigns: base_assigns}
  end
end
