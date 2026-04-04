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

    def get("scn-api-export-1") do
      Scenario.new(%{
        id: "scn-api-export-1",
        name: "API Export",
        version: "1.0.0",
        steps: [
          %{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}
        ]
      })
    end

    def get(_id), do: {:error, :not_found}

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

    def insert(charge_point), do: {:ok, charge_point}
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

    def insert(run), do: {:ok, run}
    def get("run-history-1"), do: {:ok, sample_run()}
    def get(_id), do: {:error, :not_found}

    def update_state("run-history-1", state, metadata) do
      {:ok, %{sample_run() | state: state, metadata: Map.merge(sample_run().metadata, metadata)}}
    end

    def update_state(_id, _state, _metadata), do: {:error, :not_found}

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
    def insert(log_entry), do: {:ok, log_entry}

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

  defmodule IdGeneratorStub do
    def generate("run"), do: "run-api-generated-1"
    def generate(_namespace), do: "generated-id-1"
  end

  defmodule WebhookEndpointRepositoryStub do
    def upsert(endpoint), do: {:ok, endpoint}

    def list(_filters) do
      {:ok,
       %{
         entries: [
           %{
             id: "wh-api-1",
             name: "Webhook API",
             url: "https://example.test/webhook",
             events: ["run.succeeded"],
             retry_policy: %{max_attempts: 2, backoff_ms: 100},
             secret_ref: "whsec_test",
             metadata: %{}
           }
         ],
         page: 1,
         page_size: 50,
         total_entries: 1,
         total_pages: 1
       }}
    end
  end

  setup do
    previous_charge_point_repository =
      Application.get_env(:ocpp_simulator, :charge_point_repository)

    previous_target_endpoint_repository =
      Application.get_env(:ocpp_simulator, :target_endpoint_repository)

    previous_scenario_repository = Application.get_env(:ocpp_simulator, :scenario_repository)
    previous_template_repository = Application.get_env(:ocpp_simulator, :template_repository)

    previous_scenario_run_repository =
      Application.get_env(:ocpp_simulator, :scenario_run_repository)

    previous_log_repository = Application.get_env(:ocpp_simulator, :log_repository)
    previous_id_generator = Application.get_env(:ocpp_simulator, :id_generator)

    previous_webhook_endpoint_repository =
      Application.get_env(:ocpp_simulator, :webhook_endpoint_repository)

    Application.put_env(:ocpp_simulator, :charge_point_repository, ChargePointRepositoryStub)

    Application.put_env(
      :ocpp_simulator,
      :target_endpoint_repository,
      TargetEndpointRepositoryStub
    )

    Application.put_env(:ocpp_simulator, :scenario_repository, ScenarioRepositoryStub)
    Application.put_env(:ocpp_simulator, :template_repository, TemplateRepositoryStub)
    Application.put_env(:ocpp_simulator, :scenario_run_repository, ScenarioRunRepositoryStub)
    Application.put_env(:ocpp_simulator, :log_repository, LogRepositoryStub)
    Application.put_env(:ocpp_simulator, :id_generator, IdGeneratorStub)

    Application.put_env(
      :ocpp_simulator,
      :webhook_endpoint_repository,
      WebhookEndpointRepositoryStub
    )

    on_exit(fn ->
      if previous_charge_point_repository do
        Application.put_env(
          :ocpp_simulator,
          :charge_point_repository,
          previous_charge_point_repository
        )
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
        Application.put_env(
          :ocpp_simulator,
          :scenario_run_repository,
          previous_scenario_run_repository
        )
      else
        Application.delete_env(:ocpp_simulator, :scenario_run_repository)
      end

      if previous_log_repository do
        Application.put_env(:ocpp_simulator, :log_repository, previous_log_repository)
      else
        Application.delete_env(:ocpp_simulator, :log_repository)
      end

      if previous_id_generator do
        Application.put_env(:ocpp_simulator, :id_generator, previous_id_generator)
      else
        Application.delete_env(:ocpp_simulator, :id_generator)
      end

      if previous_webhook_endpoint_repository do
        Application.put_env(
          :ocpp_simulator,
          :webhook_endpoint_repository,
          previous_webhook_endpoint_repository
        )
      else
        Application.delete_env(:ocpp_simulator, :webhook_endpoint_repository)
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

  test "root route renders role-selection page" do
    conn =
      build_conn()
      |> get("/")

    response = html_response(conn, 200)
    assert response =~ "Pilih Role Login"
    assert response =~ "Viewer"
    assert response =~ "Operator"
    assert response =~ "Admin"
  end

  test "dashboard route redirects to role selection when session role is missing" do
    conn =
      build_conn()
      |> get("/dashboard")

    assert redirected_to(conn, 302) == "/"
  end

  test "dashboard route renders for viewer role after role selection" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/dashboard")

    response = html_response(conn, 200)
    assert response =~ "Simulator Control Center"
    assert response =~ "Run Orchestrator"
  end

  test "dashboard run form includes browser fallback action for start run" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/dashboard")

    response = html_response(conn, 200)
    assert response =~ ~s(action="/runs" method="post" phx-submit="start_run")
  end

  test "charge point registry route allows viewer" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/charge-points")

    assert html_response(conn, 200) =~ "Charge Point Registry"
  end

  test "browser fallback post /charge-points creates charge point for admin role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "admin"})
      |> post("/charge-points", %{
        "charge_point" => %{
          "id" => "cp-browser-post-1",
          "vendor" => "Erdovi",
          "model" => "AC-200",
          "firmware_version" => "1.2.3",
          "connector_count" => "2",
          "heartbeat_interval_seconds" => "60",
          "behavior_profile" => "default"
        }
      })

    assert redirected_to(conn, 302) == "/charge-points"
  end

  test "browser fallback post /charge-points redirects with viewer role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/charge-points", %{
        "charge_point" => %{
          "id" => "cp-browser-post-viewer",
          "vendor" => "Erdovi",
          "model" => "AC-200",
          "firmware_version" => "1.2.3",
          "connector_count" => "2",
          "heartbeat_interval_seconds" => "60",
          "behavior_profile" => "default"
        }
      })

    assert redirected_to(conn, 302) == "/charge-points"
  end

  test "browser fallback post /scenarios creates scenario for admin role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "admin"})
      |> post("/scenarios", %{
        "scenario" => %{
          "id" => "scn-browser-post-1",
          "name" => "Browser Scenario",
          "version" => "1.0.0",
          "steps_json" =>
            Jason.encode!([
              %{
                "id" => "boot",
                "type" => "send_action",
                "order" => 1,
                "payload" => %{"action" => "BootNotification"},
                "delay_ms" => 0,
                "loop_count" => 1,
                "enabled" => true
              }
            ])
        }
      })

    assert redirected_to(conn, 302) == "/scenarios"
  end

  test "browser fallback post /scenarios redirects with viewer role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/scenarios", %{
        "scenario" => %{
          "id" => "scn-browser-post-viewer",
          "name" => "Viewer Scenario",
          "version" => "1.0.0",
          "steps_json" =>
            Jason.encode!([
              %{
                "id" => "boot",
                "type" => "send_action",
                "order" => 1,
                "payload" => %{"action" => "BootNotification"},
                "delay_ms" => 0,
                "loop_count" => 1,
                "enabled" => true
              }
            ])
        }
      })

    assert redirected_to(conn, 302) == "/scenarios"
  end

  test "browser fallback post /templates saves template for admin role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "admin"})
      |> post("/templates", %{
        "template" => %{
          "id" => "tpl-browser-post-1",
          "name" => "Browser Template",
          "version" => "1.0.0",
          "type" => "action",
          "payload_template_json" => Jason.encode!(%{"action" => "Heartbeat"})
        }
      })

    assert redirected_to(conn, 302) == "/templates"
  end

  test "browser fallback post /templates redirects with viewer role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/templates", %{
        "template" => %{
          "id" => "tpl-browser-post-viewer",
          "name" => "Viewer Template",
          "version" => "1.0.0",
          "type" => "action",
          "payload_template_json" => Jason.encode!(%{"action" => "Heartbeat"})
        }
      })

    assert redirected_to(conn, 302) == "/templates"
  end

  test "browser fallback post /runs queues run for operator role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/runs", %{
        "run" => %{
          "scenario_id" => "scn-api-export-1",
          "execute_after_start" => "false",
          "timeout_ms" => "15000"
        }
      })

    assert redirected_to(conn, 302) == "/dashboard"
  end

  test "browser fallback post /runs redirects with viewer role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/runs", %{
        "run" => %{
          "scenario_id" => "scn-api-export-1",
          "execute_after_start" => "false",
          "timeout_ms" => "15000"
        }
      })

    assert redirected_to(conn, 302) == "/dashboard"
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
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "update_visual",
        %{
          "scenario" => %{
            "steps_json" => "{invalid-json"
          }
        },
        socket
      )

    assert socket.assigns.field_errors[:steps] == "Steps must be valid JSON array format."
  end

  test "scenario builder add_step appends a new ordered step" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    initial_step_count = length(socket.assigns.visual_model["steps"])

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "add_step",
        %{},
        socket
      )

    updated_steps = socket.assigns.visual_model["steps"]
    assert length(updated_steps) == initial_step_count + 1

    assert List.last(updated_steps)["id"] == "step_#{initial_step_count + 1}"
    assert List.last(updated_steps)["order"] == initial_step_count + 1
    assert List.last(updated_steps)["payload"]["action"] == "BootNotification"
    assert Map.has_key?(List.last(updated_steps)["payload"], "payload")
  end

  test "scenario builder updates send_action payload template when action changes" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    existing_step = Enum.at(socket.assigns.visual_model["steps"], 0)

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "update_step",
        %{
          "index" => "0",
          "step" => %{
            "id" => existing_step["id"],
            "type" => "send_action",
            "action" => "Authorize",
            "payload_json" => Jason.encode!(existing_step["payload"]),
            "delay_ms" => to_string(existing_step["delay_ms"]),
            "loop_count" => to_string(existing_step["loop_count"]),
            "enabled" => "true"
          }
        },
        socket
      )

    updated_step = Enum.at(socket.assigns.visual_model["steps"], 0)
    assert updated_step["payload"]["action"] == "Authorize"
    assert updated_step["payload"]["payload"] == %{"idTag" => "RFID-1"}
  end

  test "scenario builder save_scenario persists draft and returns success feedback" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "save_scenario",
        %{},
        socket
      )

    assert socket.assigns.feedback =~ "was created successfully"
  end

  test "scenario builder supports switching visual and json mode with synced payload" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "switch_mode",
        %{"mode" => "json"},
        socket
      )

    assert socket.assigns.mode == "json"

    updated_raw_json =
      Jason.encode!(%{
        "id" => "scenario-builder-preview",
        "name" => "Edited From JSON",
        "version" => "1.0.0",
        "schema_version" => "1.0",
        "variables" => %{},
        "variable_scopes" => ["scenario", "run", "session", "step"],
        "validation_policy" => %{
          "strict_ocpp_schema" => true,
          "strict_state_transitions" => true,
          "strict_variable_resolution" => true
        },
        "steps" => [
          %{
            "id" => "boot",
            "type" => "send_action",
            "order" => 1,
            "payload" => %{"action" => "BootNotification", "chargePointVendor" => "Erdovi"},
            "delay_ms" => 0,
            "loop_count" => 1,
            "enabled" => true
          }
        ]
      })

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "update_raw",
        %{"scenario" => %{"raw_json" => updated_raw_json}},
        socket
      )

    assert socket.assigns.visual_model["name"] == "Edited From JSON"

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "switch_mode",
        %{"mode" => "visual"},
        socket
      )

    assert socket.assigns.mode == "visual"
    assert socket.assigns.visual_model["name"] == "Edited From JSON"
  end

  test "scenario builder keeps json mode and surfaces raw json error when switching from invalid json" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "switch_mode",
        %{"mode" => "json"},
        socket
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "update_raw",
        %{"scenario" => %{"raw_json" => "{invalid-json"}},
        socket
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "switch_mode",
        %{"mode" => "visual"},
        socket
      )

    assert socket.assigns.mode == "json"
    assert socket.assigns.field_errors[:raw_json] =~ "JSON document is invalid"
  end

  test "target endpoint create keeps inline validation errors for invalid form input" do
    {:ok, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.handle_event(
        "create_endpoint",
        %{
          "endpoint" => %{
            "id" => "endpoint-invalid-1",
            "name" => "Bad Endpoint",
            "url" => "http://invalid-url",
            "retry_max_attempts" => "0",
            "retry_backoff_ms" => "0"
          }
        },
        socket
      )

    assert socket.assigns.endpoint_errors[:url] == "URL must use `ws://` in v1."
    assert socket.assigns.endpoint_errors[:retry_max_attempts] == "Must be a positive integer."
    assert socket.assigns.endpoint_errors[:retry_backoff_ms] == "Must be a positive integer."
    assert socket.assigns.feedback == "Please fix validation errors before submitting."
  end

  test "target endpoint create auto-prefixes ws:// when url has no scheme" do
    {:ok, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.handle_event(
        "create_endpoint",
        %{
          "endpoint" => %{
            "id" => "endpoint-auto-1",
            "name" => "Auto Prefix Endpoint",
            "url" => "localhost:9000/ocpp",
            "retry_max_attempts" => "3",
            "retry_backoff_ms" => "1000"
          }
        },
        socket
      )

    assert socket.assigns.feedback == "Target endpoint was created successfully."
    assert socket.assigns.endpoint_errors == %{}
  end

  test "target endpoint create returns actionable message for viewer role" do
    {:ok, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :viewer})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.TargetEndpointsLive.handle_event(
        "create_endpoint",
        %{
          "endpoint" => %{
            "id" => "endpoint-viewer-1",
            "name" => "Viewer Endpoint",
            "url" => "ws://localhost:9000/ocpp",
            "retry_max_attempts" => "3",
            "retry_backoff_ms" => "1000"
          }
        },
        socket
      )

    assert socket.assigns.feedback =~ "Ganti role ke Operator/Admin"
    assert socket.assigns.endpoint_errors[:base] =~ "tidak punya izin"
  end

  test "browser fallback post /target-endpoints creates endpoint for admin role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "admin"})
      |> post("/target-endpoints", %{
        "endpoint" => %{
          "id" => "endpoint-browser-post-1",
          "name" => "Browser Post Endpoint",
          "url" => "localhost:9000/ocpp",
          "retry_max_attempts" => "3",
          "retry_backoff_ms" => "1000"
        }
      })

    assert redirected_to(conn, 302) == "/target-endpoints"
  end

  test "browser fallback post /target-endpoints redirects with viewer role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/target-endpoints", %{
        "endpoint" => %{
          "id" => "endpoint-browser-post-viewer",
          "name" => "Viewer Endpoint",
          "url" => "ws://localhost:9000/ocpp",
          "retry_max_attempts" => "3",
          "retry_backoff_ms" => "1000"
        }
      })

    assert redirected_to(conn, 302) == "/target-endpoints"
  end

  test "logs live supports filter-first query and correlation drill-down" do
    {:ok, socket} =
      OcppSimulatorWeb.LogsLive.mount(%{}, %{}, live_socket(%{current_role: :viewer}))

    assert socket.assigns.feedback =~ "Apply at least one filter"

    {:noreply, filtered_socket} =
      OcppSimulatorWeb.LogsLive.handle_event(
        "filter",
        %{
          "filters" => %{
            "run_id" => "run-history-1",
            "session_id" => "",
            "message_id" => "",
            "severity" => "",
            "event_type" => "",
            "page_size" => "50"
          }
        },
        socket
      )

    assert length(filtered_socket.assigns.entries) == 1
    assert hd(filtered_socket.assigns.entries).run_id == "run-history-1"

    {:noreply, drilled_socket} =
      OcppSimulatorWeb.LogsLive.handle_event(
        "drill_filter",
        %{
          "run_id" => "run-correlation-1",
          "session_id" => "session-correlation-1",
          "message_id" => "message-correlation-1"
        },
        filtered_socket
      )

    assert drilled_socket.assigns.filters.run_id == "run-correlation-1"
    assert drilled_socket.assigns.filters.session_id == "session-correlation-1"
    assert drilled_socket.assigns.filters.message_id == "message-correlation-1"
    assert hd(drilled_socket.assigns.entries).run_id == "run-correlation-1"
    assert hd(drilled_socket.assigns.entries).session_id == "session-correlation-1"
    assert hd(drilled_socket.assigns.entries).message_id == "message-correlation-1"
  end

  test "run history replay action shows replay entry feedback" do
    {:ok, socket} =
      OcppSimulatorWeb.RunHistoryLive.mount(%{}, %{}, live_socket(%{current_role: :viewer}))

    {:noreply, socket} =
      OcppSimulatorWeb.RunHistoryLive.handle_event("replay", %{"id" => "run-history-1"}, socket)

    assert socket.assigns.replay_feedback =~ "Replay requested for run run-history-1"
  end

  test "api run start denies viewer role" do
    conn =
      build_conn()
      |> post("/api/runs", %{"scenario_id" => "scn-api-export-1"})

    assert %{"ok" => false, "error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "api run start allows operator role from session" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/runs", %{"scenario_id" => "scn-api-export-1"})

    assert %{
             "ok" => true,
             "data" => %{
               "resource" => "run",
               "id" => "run-api-generated-1",
               "state" => "queued",
               "execute_after_start" => %{"requested" => false}
             }
           } = json_response(conn, 202)
  end

  test "api run start remains accepted when execute_after_start is requested" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/runs", %{
        "scenario_id" => "scn-api-export-1",
        "execute_after_start" => true,
        "timeout_ms" => 500
      })

    assert %{
             "ok" => true,
             "data" => %{
               "resource" => "run",
               "execute_after_start" => %{"requested" => true, "scheduled" => true}
             }
           } = json_response(conn, 202)
  end

  test "api run start ignores untrusted role header by default" do
    conn =
      build_conn()
      |> put_req_header("x-ocpp-role", "operator")
      |> post("/api/runs", %{"scenario_id" => "scn-api-export-1"})

    assert %{"ok" => false, "error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "api management endpoints enforce role permissions" do
    operator_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/charge-points", %{
        "id" => "cp-api-1",
        "vendor" => "Erdovi",
        "model" => "SIM",
        "firmware_version" => "1.0.0",
        "connector_count" => 2,
        "heartbeat_interval_seconds" => 60
      })

    assert %{"ok" => true, "data" => %{"resource" => "charge_point"}} =
             json_response(operator_conn, 201)

    viewer_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/api/charge-points", %{})

    assert %{"ok" => false, "error" => %{"code" => "forbidden"}} = json_response(viewer_conn, 403)
  end

  test "api artifact export/import endpoints are role-gated and return structured data" do
    export_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> get("/api/scenarios/export")

    assert %{"ok" => true, "data" => %{"artifact" => "scenarios", "count" => 1}} =
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

    assert %{"ok" => true, "data" => %{"artifact" => "templates", "imported_count" => 1}} =
             json_response(import_conn, 201)

    forbidden_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> get("/api/templates/export")

    assert %{"ok" => false, "error" => %{"code" => "forbidden"}} =
             json_response(forbidden_conn, 403)
  end

  test "api webhook endpoint config supports upsert and list for operator role" do
    upsert_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/webhooks/endpoints", %{
        "id" => "wh-api-created-1",
        "name" => "Run Events",
        "url" => "https://example.test/webhook",
        "events" => ["run.succeeded", "run.failed"],
        "retry_policy" => %{"max_attempts" => 3, "backoff_ms" => 500},
        "secret_ref" => "whsec_api",
        "metadata" => %{"team" => "qa"}
      })

    assert %{"ok" => true, "data" => %{"resource" => "webhook_endpoint"}} =
             json_response(upsert_conn, 201)

    list_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> get("/api/webhooks/endpoints")

    assert %{"ok" => true, "data" => %{"entries" => entries}} = json_response(list_conn, 200)
    assert length(entries) == 1
  end

  test "api webhook endpoint config rejects invalid callback URL scheme" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/webhooks/endpoints", %{
        "id" => "wh-api-created-2",
        "name" => "Run Events",
        "url" => "ws://example.test/webhook",
        "events" => ["run.succeeded"]
      })

    assert %{
             "ok" => false,
             "error" => %{
               "code" => "invalid_field",
               "details" => %{"field" => "url", "detail" => "must_be_http_or_https_url"}
             }
           } = json_response(conn, 422)
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
