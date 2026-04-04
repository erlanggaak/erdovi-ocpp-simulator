defmodule OcppSimulatorWeb.Auth.EnsureRoleSelectedPlug do
  @moduledoc """
  Redirects browser routes to role-selection page when no role is stored in session.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @default_exempt_paths ["/", "/health", "/session/role"]

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    role_in_session = get_session(conn, "current_role")
    exempt_paths = Keyword.get(opts, :exempt_paths, @default_exempt_paths)

    cond do
      is_binary(role_in_session) and String.trim(role_in_session) != "" ->
        conn

      conn.request_path in exempt_paths ->
        conn

      true ->
        conn
        |> redirect(to: "/")
        |> halt()
    end
  end
end
