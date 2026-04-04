defmodule OcppSimulatorWeb.Api.ArtifactController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ImportExportArtifacts
  alias OcppSimulator.Application.UseCases.StarterTemplates
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulatorWeb.Api.Response

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def export_scenarios(conn, params) do
    case ImportExportArtifacts.export_scenarios(
           scenario_repository(),
           current_role(conn),
           params
         ) do
      {:ok, bundle} ->
        StructuredLogger.info("api.artifacts.scenarios.exported", %{
          persist: true,
          run_id: "system",
          action: "export_scenarios",
          payload: %{count: bundle.count}
        })

        Response.success(conn, :ok, bundle)

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def import_scenarios(conn, params) do
    case ImportExportArtifacts.import_scenarios(
           scenario_repository(),
           current_role(conn),
           params
         ) do
      {:ok, result} ->
        StructuredLogger.info("api.artifacts.scenarios.imported", %{
          persist: true,
          run_id: "system",
          action: "import_scenarios",
          payload: %{imported_count: result.imported_count}
        })

        Response.success(conn, :created, result)

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def export_templates(conn, params) do
    case ImportExportArtifacts.export_templates(
           template_repository(),
           current_role(conn),
           params
         ) do
      {:ok, bundle} ->
        StructuredLogger.info("api.artifacts.templates.exported", %{
          persist: true,
          run_id: "system",
          action: "export_templates",
          payload: %{count: bundle.count}
        })

        Response.success(conn, :ok, bundle)

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def import_templates(conn, params) do
    case ImportExportArtifacts.import_templates(
           template_repository(),
           current_role(conn),
           params
         ) do
      {:ok, result} ->
        StructuredLogger.info("api.artifacts.templates.imported", %{
          persist: true,
          run_id: "system",
          action: "import_templates",
          payload: %{imported_count: result.imported_count}
        })

        Response.success(conn, :created, result)

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  def seed_starter_templates(conn, _params) do
    case StarterTemplates.seed_starter_templates(
           template_repository(),
           current_role(conn)
         ) do
      {:ok, entries} ->
        StructuredLogger.info("api.artifacts.templates.starter_seeded", %{
          persist: true,
          run_id: "system",
          action: "seed_starter_templates",
          payload: %{imported_count: length(entries)}
        })

        Response.success(conn, :created, %{
          artifact: "templates",
          imported_count: length(entries),
          entries: entries
        })

      {:error, reason} ->
        Response.from_reason(conn, reason)
    end
  end

  defp current_role(conn), do: conn.assigns[:current_role] || :viewer

  defp scenario_repository do
    Application.get_env(
      :ocpp_simulator,
      :scenario_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
    )
  end

  defp template_repository do
    Application.get_env(
      :ocpp_simulator,
      :template_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
    )
  end
end
