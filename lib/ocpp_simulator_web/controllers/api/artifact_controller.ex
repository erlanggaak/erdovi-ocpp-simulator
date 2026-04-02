defmodule OcppSimulatorWeb.Api.ArtifactController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ImportExportArtifacts
  alias OcppSimulator.Application.UseCases.StarterTemplates

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def export_scenarios(conn, params) do
    case ImportExportArtifacts.export_scenarios(
           scenario_repository(),
           current_role(conn),
           params
         ) do
      {:ok, bundle} ->
        conn
        |> put_status(:ok)
        |> json(%{data: bundle})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def import_scenarios(conn, params) do
    case ImportExportArtifacts.import_scenarios(
           scenario_repository(),
           current_role(conn),
           params
         ) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{data: result})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def export_templates(conn, params) do
    case ImportExportArtifacts.export_templates(
           template_repository(),
           current_role(conn),
           params
         ) do
      {:ok, bundle} ->
        conn
        |> put_status(:ok)
        |> json(%{data: bundle})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def import_templates(conn, params) do
    case ImportExportArtifacts.import_templates(
           template_repository(),
           current_role(conn),
           params
         ) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{data: result})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def seed_starter_templates(conn, _params) do
    case StarterTemplates.seed_starter_templates(
           template_repository(),
           current_role(conn)
         ) do
      {:ok, entries} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{artifact: "templates", imported_count: length(entries), entries: entries}
        })

      {:error, reason} ->
        render_error(conn, reason)
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

  defp render_error(conn, reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "invalid_request", reason: inspect(reason)}})
  end
end
