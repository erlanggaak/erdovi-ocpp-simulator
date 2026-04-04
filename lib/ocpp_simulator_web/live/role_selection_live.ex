defmodule OcppSimulatorWeb.RoleSelectionLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @impl true
  def mount(_params, session, socket) do
    current_role = LiveData.normalize_role(Map.get(session, "current_role"))

    {:ok,
     assign(socket,
       page_title: "Pilih Role Login",
       current_role: current_role,
       current_path: "/",
       permission_grants: socket.assigns[:permission_grants] || %{}
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Pilih role untuk session browser ini. Semua aksi berikutnya akan mengikuti role yang kamu pilih."
      current_path={@current_path}
      current_role={@current_role}
      flash={@flash}
      show_nav={false}
    >
      <section class="sim-section">
        <p class="sim-muted">
          Current session role: <strong><%= UITheme.role_label(@current_role) %></strong>
        </p>

        <div class="sim-role-choices">
          <form method="post" action={~p"/session/role"}>
            <input type="hidden" name="_csrf_token" value={csrf_token_value()} />
            <input type="hidden" name="return_to" value="/dashboard" />
            <input type="hidden" name="role" value="viewer" />
            <button class="sim-role-choice" type="submit">
              <strong>Viewer</strong>
              <span>Read-only monitoring mode for dashboard, logs, and history.</span>
            </button>
          </form>

          <form method="post" action={~p"/session/role"}>
            <input type="hidden" name="_csrf_token" value={csrf_token_value()} />
            <input type="hidden" name="return_to" value="/dashboard" />
            <input type="hidden" name="role" value="operator" />
            <button class="sim-role-choice" type="submit">
              <strong>Operator</strong>
              <span>Manage simulator resources and run scenarios.</span>
            </button>
          </form>

          <form method="post" action={~p"/session/role"}>
            <input type="hidden" name="_csrf_token" value={csrf_token_value()} />
            <input type="hidden" name="return_to" value="/dashboard" />
            <input type="hidden" name="role" value="admin" />
            <button class="sim-role-choice" type="submit">
              <strong>Admin</strong>
              <span>Full access to all simulator functionality and automation flows.</span>
            </button>
          </form>
        </div>
      </section>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)

  defp csrf_token_value, do: Plug.CSRFProtection.get_csrf_token()
end
