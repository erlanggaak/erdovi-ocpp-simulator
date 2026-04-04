defmodule OcppSimulatorWeb.Api.RunController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulatorWeb.Api.Response

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def create(conn, params) do
    role = current_role(conn)

    with {:ok, run} <- RunScenario.start_run(start_dependencies(), params, role) do
      execute_after_start_result = maybe_execute_after_start(run.id, params, role)

      StructuredLogger.info("api.run.created", %{
        persist: true,
        run_id: run.id,
        action: "start_run",
        payload: %{
          scenario_id: run.scenario_id,
          state: run.state,
          execute_after_start: execute_after_start_result
        }
      })

      run_response =
        %{
          resource: "run",
          id: run.id,
          state: run.state,
          scenario_id: run.scenario_id,
          scenario_version: run.scenario_version
        }
        |> maybe_put_execute_after_start(execute_after_start_result)

      Response.success(conn, :accepted, run_response)
    else
      {:error, reason} -> Response.from_reason(conn, reason)
    end
  end

  def cancel(conn, %{"id" => run_id}) do
    role = current_role(conn)

    case RunScenario.cancel_run(cancel_dependencies(), run_id, role, %{source: "api"}) do
      {:ok, run} ->
        StructuredLogger.info("api.run.canceled", %{
          persist: true,
          run_id: run.id,
          action: "cancel_run",
          payload: %{state: run.state}
        })

        Response.success(conn, :ok, %{
          resource: "run",
          id: run.id,
          state: run.state,
          action: "cancel"
        })

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def cancel(conn, _params) do
    Response.error(
      conn,
      :unprocessable_entity,
      "invalid_field",
      "Run ID is required.",
      %{field: :id}
    )
  end

  defp maybe_execute_after_start(run_id, params, actor_role) do
    if execute_after_start?(params) do
      timeout_ms = parse_positive_integer(fetch(params, :timeout_ms))

      task_fun = fn ->
        execute_dependencies()
        |> RunScenario.execute_run(run_id, actor_role, %{timeout_ms: timeout_ms})
      end

      case Task.Supervisor.start_child(OcppSimulator.Application.UseCaseTaskSupervisor, task_fun) do
        {:ok, _pid} ->
          :scheduled

        {:error, reason} ->
          StructuredLogger.error("api.run.execute_after_start_schedule_failed", %{
            persist: true,
            run_id: run_id,
            action: "execute_run",
            payload: %{reason: inspect(reason)}
          })

          :schedule_failed
      end
    else
      :not_requested
    end
  end

  defp execute_after_start?(params) do
    case fetch(params, :execute_after_start) do
      true -> true
      "true" -> true
      "1" -> true
      _ -> false
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp maybe_put_execute_after_start(payload, :not_requested),
    do: Map.put(payload, :execute_after_start, %{requested: false})

  defp maybe_put_execute_after_start(payload, :scheduled),
    do: Map.put(payload, :execute_after_start, %{requested: true, scheduled: true})

  defp maybe_put_execute_after_start(payload, :schedule_failed),
    do: Map.put(payload, :execute_after_start, %{requested: true, scheduled: false})

  defp start_dependencies do
    %{
      scenario_repository:
        Application.get_env(
          :ocpp_simulator,
          :scenario_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
        ),
      scenario_run_repository:
        Application.get_env(
          :ocpp_simulator,
          :scenario_run_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
        ),
      id_generator:
        Application.get_env(
          :ocpp_simulator,
          :id_generator,
          OcppSimulator.Infrastructure.Support.IdGenerator
        ),
      webhook_dispatcher:
        Application.get_env(
          :ocpp_simulator,
          :webhook_dispatcher,
          OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
        )
    }
  end

  defp cancel_dependencies do
    %{
      scenario_run_repository:
        Application.get_env(
          :ocpp_simulator,
          :scenario_run_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
        ),
      webhook_dispatcher:
        Application.get_env(
          :ocpp_simulator,
          :webhook_dispatcher,
          OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
        )
    }
  end

  defp execute_dependencies do
    %{
      scenario_run_repository:
        Application.get_env(
          :ocpp_simulator,
          :scenario_run_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
        ),
      charge_point_repository:
        Application.get_env(
          :ocpp_simulator,
          :charge_point_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
        ),
      target_endpoint_repository:
        Application.get_env(
          :ocpp_simulator,
          :target_endpoint_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
        ),
      transport_gateway:
        Application.get_env(
          :ocpp_simulator,
          :transport_gateway,
          OcppSimulator.Infrastructure.Transport.WebSocket.SessionManager
        ),
      webhook_dispatcher:
        Application.get_env(
          :ocpp_simulator,
          :webhook_dispatcher,
          OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
        )
    }
  end

  defp current_role(conn), do: conn.assigns[:current_role] || :viewer
  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
