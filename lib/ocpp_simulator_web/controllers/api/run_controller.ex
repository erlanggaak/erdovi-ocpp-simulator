defmodule OcppSimulatorWeb.Api.RunController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def create(conn, _params), do: guarded_accept(conn, :start_run, %{resource: "run"})

  def cancel(conn, %{"id" => run_id}) do
    guarded_accept(conn, :cancel_run, %{resource: "run", run_id: run_id, action: "cancel"})
  end

  defp guarded_accept(conn, permission, payload) do
    case AuthorizationPolicy.authorize(conn.assigns[:current_role] || :viewer, permission) do
      :ok ->
        conn
        |> put_status(:accepted)
        |> json(%{data: Map.put(payload, :status, "accepted")})

      {:error, reason} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          error: %{code: "forbidden", permission: to_string(permission), reason: inspect(reason)}
        })
    end
  end
end
