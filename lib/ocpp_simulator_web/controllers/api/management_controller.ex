defmodule OcppSimulatorWeb.Api.ManagementController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ManageChargePoints
  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulatorWeb.Api.Response

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def create_charge_point(conn, params) do
    role = current_role(conn)

    case ManageChargePoints.register_charge_point(charge_point_repository(), params, role) do
      {:ok, charge_point} ->
        StructuredLogger.info("api.management.charge_point.created", %{
          persist: true,
          run_id: "system",
          action: "create_charge_point",
          payload: %{charge_point_id: charge_point.id}
        })

        Response.success(conn, :created, %{
          resource: "charge_point",
          id: charge_point.id,
          charge_point: Map.from_struct(charge_point)
        })

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def create_target_endpoint(conn, params) do
    role = current_role(conn)

    case ManageTargetEndpoints.create_target_endpoint(target_endpoint_repository(), params, role) do
      {:ok, endpoint} ->
        StructuredLogger.info("api.management.target_endpoint.created", %{
          persist: true,
          run_id: "system",
          action: "create_target_endpoint",
          payload: %{endpoint_id: endpoint.id}
        })

        Response.success(conn, :created, %{
          resource: "target_endpoint",
          id: endpoint.id,
          endpoint: endpoint
        })

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def create_scenario(conn, params) do
    role = current_role(conn)

    case ManageScenarios.create_scenario(scenario_repository(), params, role) do
      {:ok, scenario} ->
        StructuredLogger.info("api.management.scenario.created", %{
          persist: true,
          run_id: "system",
          action: "create_scenario",
          payload: %{scenario_id: scenario.id}
        })

        Response.success(conn, :created, %{
          resource: "scenario",
          id: scenario.id,
          scenario: Scenario.to_snapshot(scenario)
        })

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def create_template(conn, params) do
    role = current_role(conn)

    create_template_result =
      case normalize_template_type(params) do
        {:ok, :action} ->
          ManageScenarios.upsert_action_template(template_repository(), params, role)

        {:ok, :scenario} ->
          ManageScenarios.upsert_scenario_template(template_repository(), params, role)

        {:error, reason} ->
          {:error, reason}
      end

    case create_template_result do
      {:ok, template} ->
        StructuredLogger.info("api.management.template.upserted", %{
          persist: true,
          run_id: "system",
          action: "upsert_template",
          payload: %{template_id: template.id, type: template.type}
        })

        Response.success(conn, :created, %{
          resource: "template",
          id: template.id,
          template: template
        })

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  defp normalize_template_type(params) do
    case fetch(params, :type) do
      :action -> {:ok, :action}
      :scenario -> {:ok, :scenario}
      "action" -> {:ok, :action}
      "scenario" -> {:ok, :scenario}
      _ -> {:error, {:invalid_field, :type, :unsupported_template_type}}
    end
  end

  defp current_role(conn), do: conn.assigns[:current_role] || :viewer

  defp charge_point_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :charge_point_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
      )

  defp target_endpoint_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :target_endpoint_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
      )

  defp scenario_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :scenario_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
      )

  defp template_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :template_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
      )

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
