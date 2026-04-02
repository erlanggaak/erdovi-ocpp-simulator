defmodule OcppSimulator.Application.UseCases.StarterTemplates do
  @moduledoc """
  Ships minimally OCPP-compliant starter scenario templates for:
  - normal transaction flow
  - fault recovery flow
  - remote-operation flow
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Domain.Scenarios.Scenario

  @spec starter_templates() :: [map()]
  def starter_templates do
    [
      normal_transaction_template(),
      fault_recovery_template(),
      remote_operation_template()
    ]
  end

  @spec seed_starter_templates(module(), term()) ::
          {:ok, [map()]} | {:error, term()}
  def seed_starter_templates(template_repository, actor_role)
      when is_atom(template_repository) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_templates) do
      starter_templates()
      |> Enum.reduce_while({:ok, []}, fn template, {:ok, acc} ->
        case invoke(template_repository, :upsert, [template]) do
          {:ok, persisted_template} -> {:cont, {:ok, acc ++ [persisted_template]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  def seed_starter_templates(_template_repository, _actor_role),
    do: {:error, {:invalid_arguments, :seed_starter_templates}}

  defp normal_transaction_template do
    scenario =
      build_scenario!(%{
        id: "starter-normal-transaction",
        name: "Starter Normal Transaction",
        version: "1.0.0",
        steps: [
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
            id: "heartbeat",
            type: :send_action,
            order: 2,
            payload: %{
              "action" => "Heartbeat",
              "payload" => %{}
            }
          },
          %{
            id: "authorize",
            type: :send_action,
            order: 3,
            payload: %{
              "action" => "Authorize",
              "payload" => %{"idTag" => "{{id_tag}}"}
            }
          },
          %{
            id: "start_transaction",
            type: :send_action,
            order: 4,
            payload: %{
              "action" => "StartTransaction",
              "payload" => %{
                "connectorId" => 1,
                "idTag" => "{{id_tag}}",
                "meterStart" => 0,
                "timestamp" => "{{timestamps.start}}"
              }
            }
          },
          %{
            id: "meter_values",
            type: :send_action,
            order: 5,
            loop_count: 2,
            delay_ms: 500,
            payload: %{
              "action" => "MeterValues",
              "payload" => %{
                "connectorId" => 1,
                "transactionId" => 1,
                "meterValue" => [
                  %{
                    "timestamp" => "{{timestamps.sample}}",
                    "sampledValue" => [
                      %{"value" => "1.25", "measurand" => "Energy.Active.Import.Register"}
                    ]
                  }
                ]
              }
            }
          },
          %{
            id: "stop_transaction",
            type: :send_action,
            order: 6,
            payload: %{
              "action" => "StopTransaction",
              "payload" => %{
                "meterStop" => 1250,
                "timestamp" => "{{timestamps.stop}}",
                "transactionId" => 1
              }
            }
          }
        ],
        variables: %{
          "id_tag" => "RFID-10001",
          "timestamps" => %{
            "start" => "2026-04-01T10:00:00Z",
            "sample" => "2026-04-01T10:00:30Z",
            "stop" => "2026-04-01T10:02:00Z"
          }
        }
      })

    build_template(scenario, "starter-template-normal-transaction", "Normal Transaction")
  end

  defp fault_recovery_template do
    scenario =
      build_scenario!(%{
        id: "starter-fault-recovery",
        name: "Starter Fault Recovery",
        version: "1.0.0",
        steps: [
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
            id: "status_faulted",
            type: :send_action,
            order: 2,
            payload: %{
              "action" => "StatusNotification",
              "payload" => %{
                "connectorId" => 1,
                "status" => "Faulted",
                "errorCode" => "GroundFailure"
              }
            }
          },
          %{
            id: "wait_recovery_window",
            type: :wait,
            order: 3,
            delay_ms: 1_000
          },
          %{
            id: "status_recovered",
            type: :send_action,
            order: 4,
            payload: %{
              "action" => "StatusNotification",
              "payload" => %{
                "connectorId" => 1,
                "status" => "Available",
                "errorCode" => "NoError"
              }
            }
          },
          %{
            id: "post_recovery_heartbeat",
            type: :send_action,
            order: 5,
            payload: %{
              "action" => "Heartbeat",
              "payload" => %{}
            }
          }
        ]
      })

    build_template(scenario, "starter-template-fault-recovery", "Fault Recovery")
  end

  defp remote_operation_template do
    scenario =
      build_scenario!(%{
        id: "starter-remote-operations",
        name: "Starter Remote Operations",
        version: "1.0.0",
        steps: [
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
            payload: %{
              "action" => "RemoteStartTransaction",
              "timeout_ms" => 30_000
            }
          },
          %{
            id: "start_transaction",
            type: :send_action,
            order: 3,
            payload: %{
              "action" => "StartTransaction",
              "payload" => %{
                "connectorId" => 1,
                "idTag" => "{{id_tag}}",
                "meterStart" => 0,
                "timestamp" => "{{timestamp}}"
              }
            }
          },
          %{
            id: "await_remote_stop",
            type: :await_response,
            order: 4,
            payload: %{
              "action" => "RemoteStopTransaction",
              "timeout_ms" => 30_000
            }
          },
          %{
            id: "stop_transaction",
            type: :send_action,
            order: 5,
            payload: %{
              "action" => "StopTransaction",
              "payload" => %{
                "meterStop" => 10,
                "timestamp" => "{{timestamp}}",
                "transactionId" => 1
              }
            }
          }
        ],
        variables: %{
          "id_tag" => "RFID-20001",
          "timestamp" => "2026-04-01T11:00:00Z"
        }
      })

    build_template(scenario, "starter-template-remote-operations", "Remote Operations")
  end

  defp build_template(scenario, template_id, template_name) do
    %{
      id: template_id,
      name: template_name,
      version: "1.0.0",
      type: :scenario,
      payload_template: %{
        "scenario_id" => scenario.id,
        "scenario_name" => scenario.name,
        "scenario_version" => scenario.version,
        "definition" => Scenario.to_template_payload(scenario)
      },
      metadata: %{
        "starter" => true,
        "category" => "scenario",
        "strict_validation_defaults" => true
      }
    }
  end

  defp build_scenario!(attrs) do
    attrs =
      attrs
      |> Map.put_new(:schema_version, "1.0")
      |> Map.put_new(:validation_policy, Scenario.validation_policy_defaults())
      |> Map.put_new(:variable_scopes, Scenario.default_variable_scopes())

    {:ok, scenario} = Scenario.new(attrs)
    scenario
  end

  defp invoke(module, function, args), do: apply(module, function, args)
end
