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

    case AuthorizationPolicy.authorize(role, permission) do
      :ok ->
        {:cont, assign(socket, :current_role, role)}

      _ ->
        {:halt,
         socket
         |> put_flash(:error, "Not authorized")
         |> redirect(to: "/")}
    end
  end

  defp normalize_role(role) do
    case AuthorizationPolicy.normalize_role(role) do
      {:ok, normalized_role} -> normalized_role
      {:error, _reason} -> :viewer
    end
  end
end
