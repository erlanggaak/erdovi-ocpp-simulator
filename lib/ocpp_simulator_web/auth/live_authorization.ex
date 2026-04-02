defmodule OcppSimulatorWeb.Auth.LiveAuthorization do
  @moduledoc """
  LiveView on_mount hook that enforces authorization policies per route group.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(permission, _params, session, socket) do
    role =
      session
      |> Map.get("current_role")
      |> normalize_role()

    grants = permission_grants(role)
    socket = assign(socket, :permission_grants, grants)

    case authorize(role, permission) do
      :ok ->
        {:cont, assign(socket, :current_role, role)}

      _ ->
        {:halt,
         socket
         |> put_flash(:error, "Not authorized")
         |> redirect(to: "/")}
    end
  end

  @spec can?(term(), atom()) :: boolean()
  def can?(role, permission), do: AuthorizationPolicy.allowed?(role, permission)

  defp authorize(role, {:any_of, permissions}) when is_list(permissions) do
    if Enum.any?(permissions, &AuthorizationPolicy.allowed?(role, &1)) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize(role, permission), do: AuthorizationPolicy.authorize(role, permission)

  defp permission_grants(role) do
    AuthorizationPolicy.permissions()
    |> Enum.reduce(%{}, fn permission, acc ->
      Map.put(acc, permission, AuthorizationPolicy.allowed?(role, permission))
    end)
  end

  defp normalize_role(role) do
    case AuthorizationPolicy.normalize_role(role) do
      {:ok, normalized_role} -> normalized_role
      {:error, _reason} -> :viewer
    end
  end
end
