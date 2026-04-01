defmodule OcppSimulatorWeb.Auth.CurrentRolePlug do
  @moduledoc """
  Resolves the current actor role from session or API headers.
  """

  import Plug.Conn

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  @type source :: :session | :header | :header_or_session

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    source = Keyword.get(opts, :source, :session)

    allow_untrusted_role_header =
      Keyword.get(
        opts,
        :allow_untrusted_role_header,
        Application.get_env(:ocpp_simulator, :allow_untrusted_role_header, false)
      )

    role =
      source
      |> fetch_role_value(conn, allow_untrusted_role_header)
      |> normalize_role()

    assign(conn, :current_role, role)
  end

  defp fetch_role_value(:session, conn, _allow_untrusted_role_header),
    do: get_session(conn, "current_role")

  defp fetch_role_value(:header, conn, true), do: List.first(get_req_header(conn, "x-ocpp-role"))
  defp fetch_role_value(:header, _conn, false), do: nil

  defp fetch_role_value(:header_or_session, conn, true) do
    List.first(get_req_header(conn, "x-ocpp-role")) || get_session(conn, "current_role")
  end

  defp fetch_role_value(:header_or_session, conn, false), do: get_session(conn, "current_role")

  defp fetch_role_value(_source, conn, _allow_untrusted_role_header),
    do: get_session(conn, "current_role")

  defp normalize_role(role) do
    case AuthorizationPolicy.normalize_role(role) do
      {:ok, normalized_role} -> normalized_role
      {:error, _reason} -> :viewer
    end
  end
end
