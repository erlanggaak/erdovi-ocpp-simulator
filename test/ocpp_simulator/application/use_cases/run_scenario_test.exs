defmodule OcppSimulator.Application.UseCases.RunScenarioTest do
  use ExUnit.Case, async: false

  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario

  defmodule ScenarioRepositoryStub do
    alias OcppSimulator.Domain.Scenarios.Scenario

    def get("scn-ready"), do: {:ok, build_scenario!("scn-ready", ready_steps())}
    def get("scn-empty"), do: {:ok, build_scenario!("scn-empty", [])}

    def get("scn-timeout"),
      do:
        {:ok,
         build_scenario!("scn-timeout", [
           %{id: "wait", type: :wait, order: 1, delay_ms: 1_000}
         ])}

    def get("scn-delay"),
      do:
        {:ok,
         build_scenario!("scn-delay", [
           %{id: "wait", type: :wait, order: 1, delay_ms: 30}
         ])}

    def get("scn-invalid-schema"),
      do:
        {:ok,
         build_scenario!("scn-invalid-schema", [
           %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}}
         ])}

    def get("scn-variable-default"),
      do:
        {:ok,
         build_scenario!(
           "scn-variable-default",
           [
             %{
               id: "set-token",
               type: :set_variable,
               order: 1,
               payload: %{"name" => "resolved_token", "value" => "{{token}}"}
             }
           ],
           %{
             variables: %{"token" => "scenario-token"}
           }
         )}

    def get("scn-variable-order"),
      do:
        {:ok,
         build_scenario!(
           "scn-variable-order",
           [
             %{
               id: "set-token",
               type: :set_variable,
               order: 1,
               payload: %{"name" => "resolved_token", "value" => "{{token}}"}
             }
           ],
           %{
             variable_scopes: [:scenario, :session, :step],
             variables: %{"token" => "scenario-token"}
           }
         )}

    def get("scn-invalid-transition"),
      do:
        {:ok,
         build_scenario!("scn-invalid-transition", [
           %{
             id: "stop",
             type: :send_action,
             order: 1,
             payload: %{
               "action" => "StopTransaction",
               "payload" => %{
                 "transactionId" => 1,
                 "meterStop" => 10,
                 "timestamp" => "2026-04-01T10:00:00Z"
               }
             }
           }
         ])}

    def get("scn-cp-hydrated"),
      do:
        {:ok,
         build_scenario!(
           "scn-cp-hydrated",
           [
             %{
               id: "boot",
               type: :send_action,
               order: 1,
               payload: %{"action" => "BootNotification"}
             }
           ],
           %{variables: %{"charge_point_id" => "cp-hydrated"}}
         )}

    def get("scn-ready-with-endpoint"),
      do:
        {:ok,
         build_scenario!(
           "scn-ready-with-endpoint",
           ready_steps(),
           %{variables: %{"target_endpoint_id" => "endpoint-1"}}
         )}

    def get("scn-await-remote-with-endpoint"),
      do:
        {:ok,
         build_scenario!(
           "scn-await-remote-with-endpoint",
           [
             %{
               id: "boot",
               type: :send_action,
               order: 1,
               payload: %{
                 "action" => "BootNotification",
                 "payload" => %{
                   "chargePointVendor" => "Erdovi",
                   "chargePointModel" => "Simulator"
                 }
               }
             },
             %{
               id: "await_remote_start",
               type: :await_response,
               order: 2,
               payload: %{"action" => "RemoteStartTransaction", "timeout_ms" => 1000}
             }
           ],
           %{variables: %{"target_endpoint_id" => "endpoint-1"}}
         )}

    def get(_id), do: {:error, :not_found}

    def list(_filters), do: {:ok, []}
    def insert(scenario), do: {:ok, scenario}

    defp ready_steps do
      [
        %{
          id: "boot",
          type: :send_action,
          order: 1,
          payload: %{
            "action" => "BootNotification",
            "payload" => %{"chargePointVendor" => "Erdovi", "chargePointModel" => "Simulator"}
          }
        },
        %{
          id: "authorize",
          type: :send_action,
          order: 2,
          payload: %{"action" => "Authorize", "payload" => %{"idTag" => "RFID-1"}}
        },
        %{
          id: "start",
          type: :send_action,
          order: 3,
          payload: %{
            "action" => "StartTransaction",
            "payload" => %{
              "connectorId" => 1,
              "idTag" => "RFID-1",
              "meterStart" => 0,
              "timestamp" => "2026-04-01T10:00:00Z"
            }
          }
        },
        %{
          id: "meter",
          type: :send_action,
          order: 4,
          payload: %{
            "action" => "MeterValues",
            "payload" => %{
              "connectorId" => 1,
              "meterValue" => [
                %{
                  "timestamp" => "2026-04-01T10:00:30Z",
                  "sampledValue" => [%{"value" => "1.25"}]
                }
              ],
              "transactionId" => 1
            }
          }
        },
        %{
          id: "stop",
          type: :send_action,
          order: 5,
          payload: %{
            "action" => "StopTransaction",
            "payload" => %{
              "meterStop" => 100,
              "timestamp" => "2026-04-01T10:01:00Z",
              "transactionId" => 1
            }
          }
        }
      ]
    end

    defp build_scenario!(id, steps, extra_attrs \\ %{}) do
      attrs =
        %{
          id: id,
          name: "Scenario #{id}",
          version: "1.0.0",
          steps: steps
        }
        |> Map.merge(extra_attrs)

      {:ok, scenario} = Scenario.new(attrs)
      scenario
    end
  end

  defmodule ScenarioRunRepositoryStub do
    alias OcppSimulator.Application.UseCases.RunScenarioTest.ScenarioRepositoryStub
    alias OcppSimulator.Domain.Runs.ScenarioRun

    def insert(run), do: {:ok, run}

    def get("run-running"), do: {:ok, build_run!("run-running", "scn-ready", :running)}
    def get("run-timeout"), do: {:ok, build_run!("run-timeout", "scn-timeout", :running)}
    def get("run-delay"), do: {:ok, build_run!("run-delay", "scn-delay", :running)}

    def get("run-invalid-schema"),
      do: {:ok, build_run!("run-invalid-schema", "scn-invalid-schema", :running)}

    def get("run-invalid-transition"),
      do: {:ok, build_run!("run-invalid-transition", "scn-invalid-transition", :running)}

    def get("run-cp-hydrated"),
      do: {:ok, build_run!("run-cp-hydrated", "scn-cp-hydrated", :running)}

    def get("run-ready-with-endpoint"),
      do: {:ok, build_run!("run-ready-with-endpoint", "scn-ready-with-endpoint", :running)}

    def get("run-await-remote-with-endpoint"),
      do:
        {:ok,
         build_run!(
           "run-await-remote-with-endpoint",
           "scn-await-remote-with-endpoint",
           :running
         )}

    def get("run-variable-default"),
      do:
        {:ok,
         build_run!(
           "run-variable-default",
           "scn-variable-default",
           :running,
           %{"source" => "test", "variables" => %{"token" => "run-token"}}
         )}

    def get("run-variable-order"),
      do:
        {:ok,
         build_run!(
           "run-variable-order",
           "scn-variable-order",
           :running,
           %{"source" => "test", "variables" => %{"token" => "run-token"}}
         )}

    def get("run-canceled"), do: {:ok, build_run!("run-canceled", "scn-ready", :canceled)}

    def get(_id), do: {:error, :not_found}

    def update_state(run_id, state, metadata) do
      {:ok, run} = get(run_id)
      {:ok, %{run | state: state, metadata: Map.merge(run.metadata, metadata)}}
    end

    defp build_run!(run_id, scenario_id, state, metadata \\ %{"source" => "test"}) do
      {:ok, scenario} = ScenarioRepositoryStub.get(scenario_id)

      {:ok, run} =
        ScenarioRun.new(%{
          id: run_id,
          scenario: scenario,
          state: state,
          metadata: metadata
        })

      run
    end
  end

  defmodule ChargePointRepositoryStub do
    def get("cp-hydrated") do
      {:ok,
       %{
         id: "cp-hydrated",
         vendor: "Hardhitter",
         model: "HT1"
       }}
    end

    def get(_id), do: {:error, :not_found}
  end

  defmodule TargetEndpointRepositoryStub do
    def get("endpoint-1") do
      {:ok,
       %{
         id: "endpoint-1",
         name: "Local CSMS",
         url: "ws://localhost:9000/ocpp",
         protocol_options: %{},
         retry_policy: %{}
       }}
    end

    def get(_id), do: {:error, :not_found}
  end

  defmodule TransportGatewayStub do
    alias OcppSimulator.Domain.Ocpp.Message

    def connect(session_id, endpoint_profile) do
      notify({:transport_connect, session_id, endpoint_profile})
      :ok
    end

    def disconnect(session_id) do
      notify({:transport_disconnect, session_id})
      :ok
    end

    def send_message(_session_id, _message), do: :ok

    def send_and_await_response(session_id, %Message{} = message, timeout_ms) do
      notify({:transport_send_and_await, session_id, message.action, timeout_ms})

      {:ok, response} =
        Message.new_call_result(message.message_id, %{"status" => "Accepted"}, :inbound)

      {:ok, %{message: response, correlation_event: %{request_action: message.action}}}
    end

    def await_inbound_call(session_id, action, timeout_ms) do
      notify({:transport_await_inbound, session_id, action, timeout_ms})
      Message.new_call("msg-inbound-1", action, %{"idTag" => "RFID-1"}, :inbound)
    end

    defp notify(event) do
      if pid = Process.get(:run_scenario_test_pid) do
        send(pid, event)
      end
    end
  end

  defmodule IdGeneratorStub do
    def generate("run"), do: "run-generated-1"
  end

  defmodule ScenarioRunRepositoryConcurrencyStub do
    def list_history(_filters) do
      {:ok, %{entries: [], page: 1, page_size: 1, total_entries: 1, total_pages: 1}}
    end

    def insert(run), do: {:ok, run}
  end

  defmodule ScenarioRunRepositoryConcurrencyProbeStub do
    def list_history(filters) do
      if pid = Process.get(:run_scenario_probe_pid) do
        send(pid, {:concurrency_probe_filters, filters})
      end

      {:ok, %{entries: [], page: 1, page_size: 1, total_entries: 25, total_pages: 25}}
    end

    def insert(run), do: {:ok, run}
  end

  defmodule WebhookDispatcherStub do
    def dispatch_run_event(event, run, metadata) do
      send(self(), {:webhook_dispatched, event, run.id, metadata})
      :ok
    end
  end

  setup do
    Process.put(:run_scenario_test_pid, self())

    on_exit(fn ->
      Process.delete(:run_scenario_test_pid)
    end)

    :ok
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

  test "start_run/3 enforces max concurrent runs limit" do
    previous_runtime = Application.get_env(:ocpp_simulator, :runtime)
    Application.put_env(:ocpp_simulator, :runtime, max_concurrent_runs: 1)

    on_exit(fn ->
      if previous_runtime do
        Application.put_env(:ocpp_simulator, :runtime, previous_runtime)
      else
        Application.delete_env(:ocpp_simulator, :runtime)
      end
    end)

    deps = %{
      scenario_repository: ScenarioRepositoryStub,
      scenario_run_repository: ScenarioRunRepositoryConcurrencyStub,
      id_generator: IdGeneratorStub
    }

    assert {:error, {:concurrency_limit_reached, 1}} =
             RunScenario.start_run(deps, %{scenario_id: "scn-ready"}, :operator)
  end

  test "start_run/3 uses bounded history query shape for concurrency enforcement" do
    Process.put(:run_scenario_probe_pid, self())

    on_exit(fn ->
      Process.delete(:run_scenario_probe_pid)
    end)

    deps = %{
      scenario_repository: ScenarioRepositoryStub,
      scenario_run_repository: ScenarioRunRepositoryConcurrencyProbeStub,
      id_generator: IdGeneratorStub
    }

    assert {:error, {:concurrency_limit_reached, 25}} =
             RunScenario.start_run(deps, %{scenario_id: "scn-ready"}, :operator)

    assert_receive {:concurrency_probe_filters,
                    %{states: [:queued, :running], page: 1, page_size: 1}}
  end

  test "execute_run/4 succeeds and persists step-level results" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-running", :system)
    assert final_run.state == :succeeded
    assert length(final_run.metadata.step_results) == 5
    assert_received {:webhook_dispatched, :run_succeeded, "run-running", _metadata}
  end

  test "execute_run/4 fails when transport is enabled but scenario has no target endpoint reference" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      transport_gateway: TransportGatewayStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-running", :system)
    assert final_run.state == :failed

    assert match?(
             {:transport_connect_failed,
              {:invalid_field, :target_endpoint_id, :must_reference_existing_endpoint}},
             final_run.metadata.failure_reason
           )
  end

  test "execute_run/4 uses transport gateway and waits for real protocol exchange when endpoint is configured" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      target_endpoint_repository: TargetEndpointRepositoryStub,
      transport_gateway: TransportGatewayStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-ready-with-endpoint", :system)
    assert final_run.state == :succeeded

    assert_receive {:transport_connect, "session-run-ready-with-endpoint", %{id: "endpoint-1"}}

    assert_receive {:transport_send_and_await, "session-run-ready-with-endpoint",
                    "BootNotification", 30_000}

    assert_receive {:transport_send_and_await, "session-run-ready-with-endpoint", "Authorize",
                    30_000}

    assert_receive {:transport_send_and_await, "session-run-ready-with-endpoint",
                    "StartTransaction", 30_000}

    assert_receive {:transport_send_and_await, "session-run-ready-with-endpoint", "MeterValues",
                    30_000}

    assert_receive {:transport_send_and_await, "session-run-ready-with-endpoint",
                    "StopTransaction", 30_000}

    assert_receive {:transport_disconnect, "session-run-ready-with-endpoint"}
  end

  test "execute_run/4 waits inbound remote operation on await_response step" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      target_endpoint_repository: TargetEndpointRepositoryStub,
      transport_gateway: TransportGatewayStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} =
             RunScenario.execute_run(deps, "run-await-remote-with-endpoint", :system)

    assert final_run.state == :succeeded

    assert_receive {:transport_await_inbound, "session-run-await-remote-with-endpoint",
                    "RemoteStartTransaction", 1000}
  end

  test "execute_run/4 fails when strict schema validation rejects a step payload" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-invalid-schema", :system)
    assert final_run.state == :failed
    assert match?({:invalid_payload, "BootNotification", _, _}, final_run.metadata.failure_reason)
    assert_received {:webhook_dispatched, :run_failed, "run-invalid-schema", _metadata}
  end

  test "execute_run/4 fails when strict state-transition validation rejects a step sequence" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-invalid-transition", :system)
    assert final_run.state == :failed
    assert match?({:invalid_transition, :none, :stopped}, final_run.metadata.failure_reason)
  end

  test "execute_run/4 transitions run to timed_out when timeout budget is exceeded" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} =
             RunScenario.execute_run(deps, "run-timeout", :system, timeout_ms: 100)

    assert final_run.state == :timed_out
    assert final_run.metadata.failure_reason == :run_timed_out
    assert_received {:webhook_dispatched, :run_timed_out, "run-timeout", _metadata}
  end

  test "execute_run/4 uses configured scenario variable scopes as runtime allowlist" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-variable-order", :system)

    resolved_payload =
      final_run.metadata.step_results
      |> Enum.at(0)
      |> Map.fetch!(:payload)

    assert resolved_payload["value"] == "scenario-token"
  end

  test "execute_run/4 keeps default deterministic precedence when run scope is enabled" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-variable-default", :system)

    resolved_payload =
      final_run.metadata.step_results
      |> Enum.at(0)
      |> Map.fetch!(:payload)

    assert resolved_payload["value"] == "run-token"
  end

  test "execute_run/4 applies real step delay for wait semantics" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    started_at = System.monotonic_time(:millisecond)
    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-delay", :system)
    finished_at = System.monotonic_time(:millisecond)

    assert final_run.state == :succeeded
    assert finished_at - started_at >= 25
  end

  test "execute_run/4 auto-hydrates BootNotification payload from selected charge point" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub,
      charge_point_repository: ChargePointRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub
    }

    assert {:ok, final_run} = RunScenario.execute_run(deps, "run-cp-hydrated", :system)
    assert final_run.state == :succeeded

    boot_payload =
      final_run.metadata.step_results
      |> Enum.at(0)
      |> Map.fetch!(:payload)

    assert boot_payload["action"] == "BootNotification"
    assert boot_payload["chargePointVendor"] == "Hardhitter"
    assert boot_payload["chargePointModel"] == "HT1"
  end

  test "execute_run/4 exits early when run has already been canceled" do
    deps = %{
      scenario_run_repository: ScenarioRunRepositoryStub
    }

    assert {:error, {:run_not_executable, :canceled}} =
             RunScenario.execute_run(deps, "run-canceled", :system)
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
