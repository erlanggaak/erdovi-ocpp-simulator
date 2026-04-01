defmodule OcppSimulatorWeb.Auth.RequirePermissionPlug do
  @moduledoc """
  Rejects requests when the current role lacks the required permission.
  """

  import Plug.Conn

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  @spec init(keyword()) :: atom()
  def init(opts), do: Keyword.fetch!(opts, :permission)

  @spec call(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  def call(conn, permission) do
    role = conn.assigns[:current_role] || :viewer

    case AuthorizationPolicy.authorize(role, permission) do
      :ok ->
        conn

      {:error, :forbidden} ->
        forbid(conn, permission)

      {:error, reason} ->
        forbid(conn, permission, reason)
    end
  end

  defp forbid(conn, permission, reason \\ :forbidden) do
    body =
      Jason.encode!(%{
        error: %{
          code: "forbidden",
          permission: to_string(permission),
          reason: inspect(reason)
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:forbidden, body)
    |> halt()
  end
end
