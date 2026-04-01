defmodule OcppSimulatorWeb.Api.ManagementController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def create_charge_point(conn, _params),
    do: guarded_accept(conn, "charge_point", :manage_charge_points)

  def create_target_endpoint(conn, _params),
    do: guarded_accept(conn, "target_endpoint", :manage_target_endpoints)

  def create_scenario(conn, _params), do: guarded_accept(conn, "scenario", :manage_scenarios)
  def create_template(conn, _params), do: guarded_accept(conn, "template", :manage_templates)

  defp guarded_accept(conn, resource, permission) do
    case AuthorizationPolicy.authorize(conn.assigns[:current_role] || :viewer, permission) do
      :ok -> accepted(conn, resource)
      {:error, reason} -> forbidden(conn, permission, reason)
    end
  end

  defp accepted(conn, resource) do
    conn
    |> put_status(:accepted)
    |> json(%{data: %{status: "accepted", resource: resource}})
  end

  defp forbidden(conn, permission, reason) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{code: "forbidden", permission: to_string(permission), reason: inspect(reason)}
    })
  end
end
