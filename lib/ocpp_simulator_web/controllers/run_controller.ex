defmodule OcppSimulatorWeb.RunController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulatorWeb.Live.LiveData

  def create(conn, %{"run" => run_params}) when is_map(run_params) do
    role = conn.assigns[:current_role] || :viewer

    with {:ok, run_attrs} <- build_start_run_attrs(run_params),
         {:ok, run} <- RunScenario.start_run(start_dependencies(), run_attrs, role),
         {:ok, execution_message} <- maybe_execute_after_start(run.id, run_params, role) do
      conn
      |> put_flash(:info, "Run `#{run.id}` queued. #{execution_message}")
      |> redirect(to: "/dashboard")
    else
      {:error, :forbidden} ->
        conn
        |> put_flash(:error, "Current role is not allowed to start run.")
        |> redirect(to: "/dashboard")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Run request failed: #{inspect(reason)}")
        |> redirect(to: "/dashboard")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Run payload is required.")
    |> redirect(to: "/dashboard")
  end

  defp build_start_run_attrs(run_form) do
    scenario_id = normalize_string(fetch(run_form, :scenario_id))

    if scenario_id == "" do
      {:error, {:invalid_field, :scenario_id, :must_be_non_empty_string}}
    else
      {:ok,
       %{
         scenario_id: scenario_id,
         metadata: %{"source" => "dashboard_browser_fallback"}
       }}
    end
  end

  defp maybe_execute_after_start(run_id, run_form, actor_role) do
    if truthy?(fetch(run_form, :execute_after_start)) do
      timeout_ms = parse_positive_integer(fetch(run_form, :timeout_ms))

      task_fun = fn ->
        opts = if is_integer(timeout_ms), do: %{timeout_ms: timeout_ms}, else: %{}
        RunScenario.execute_run(execute_dependencies(), run_id, actor_role, opts)
      end

      case Task.Supervisor.start_child(OcppSimulator.Application.UseCaseTaskSupervisor, task_fun) do
        {:ok, _pid} -> {:ok, "Execution scheduled in background."}
        {:error, reason} -> {:error, {:execution_schedule_failed, reason}}
      end
    else
      {:ok, "Execution not requested (queued only)."}
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp start_dependencies do
    %{
      scenario_repository:
        LiveData.repository(
          :scenario_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
        ),
      scenario_run_repository:
        LiveData.repository(
          :scenario_run_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
        ),
      id_generator:
        LiveData.repository(:id_generator, OcppSimulator.Infrastructure.Support.IdGenerator),
      webhook_dispatcher:
        LiveData.repository(
          :webhook_dispatcher,
          OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
        )
    }
  end

  defp execute_dependencies do
    %{
      scenario_run_repository:
        LiveData.repository(
          :scenario_run_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
        ),
      charge_point_repository:
        LiveData.repository(
          :charge_point_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
        ),
      target_endpoint_repository:
        LiveData.repository(
          :target_endpoint_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
        ),
      transport_gateway:
        LiveData.repository(
          :transport_gateway,
          OcppSimulator.Infrastructure.Transport.WebSocket.SessionManager
        ),
      webhook_dispatcher:
        LiveData.repository(
          :webhook_dispatcher,
          OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
        )
    }
  end

  defp truthy?(value) when value in [true, "true", "1", "on", 1], do: true
  defp truthy?(_value), do: false

  defp normalize_string(nil), do: ""

  defp normalize_string(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
