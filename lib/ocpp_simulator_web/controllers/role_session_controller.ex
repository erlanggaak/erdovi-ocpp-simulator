defmodule OcppSimulatorWeb.RoleSessionController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  def switch(conn, %{"role" => role_param} = params) do
    return_to = normalize_return_to(Map.get(params, "return_to"))

    case AuthorizationPolicy.normalize_role(role_param) do
      {:ok, role} ->
        conn
        |> put_session("current_role", Atom.to_string(role))
        |> redirect(to: return_to)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid role selection.")
        |> redirect(to: return_to)
    end
  end

  def switch(conn, _params) do
    conn
    |> put_flash(:error, "Role is required.")
    |> redirect(to: "/")
  end

  defp normalize_return_to(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" ->
        "/"

      String.starts_with?(trimmed, "/") and not String.contains?(trimmed, "://") ->
        trimmed

      true ->
        "/"
    end
  end

  defp normalize_return_to(_path), do: "/"
end
