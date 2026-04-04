defmodule OcppSimulatorWeb.Auth.RequirePermissionPlug do
  @moduledoc """
  Rejects requests when the current role lacks the required permission.
  """

  import Plug.Conn

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulatorWeb.Api.Response

  @spec init(keyword()) :: atom()
  def init(opts), do: Keyword.fetch!(opts, :permission)

  @spec call(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  def call(conn, permission) do
    role = conn.assigns[:current_role] || :viewer

    case AuthorizationPolicy.authorize(role, permission) do
      :ok ->
        conn

      {:error, :forbidden} ->
        StructuredLogger.warn("auth.permission_denied", %{
          persist: true,
          run_id: "system",
          event: "permission_denied",
          permission: permission,
          role: role,
          path: conn.request_path
        })

        forbid(conn, permission)

      {:error, reason} ->
        StructuredLogger.warn("auth.permission_denied", %{
          persist: true,
          run_id: "system",
          event: "permission_denied",
          permission: permission,
          role: role,
          path: conn.request_path,
          reason: inspect(reason)
        })

        forbid(conn, permission, reason)
    end
  end

  defp forbid(conn, permission, reason \\ :forbidden) do
    conn
    |> Response.error(
      :forbidden,
      "forbidden",
      "You do not have permission.",
      %{permission: to_string(permission), reason: inspect(reason)}
    )
    |> halt()
  end
end
