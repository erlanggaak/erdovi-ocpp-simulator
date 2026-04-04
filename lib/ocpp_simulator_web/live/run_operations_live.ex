defmodule OcppSimulatorWeb.RunOperationsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.UITheme

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Run Operations",
       current_role: socket.assigns[:current_role] || Map.get(session, "current_role") || :viewer,
       current_path: "/runs"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Kelola lifecycle run dari workspace utama simulator."
      current_path={@current_path}
      current_role={@current_role}
      flash={@flash}
    >
      <section class="sim-section">
        <p class="sim-muted">
          Operasi start/execute run tersedia di Dashboard Control Center agar tetap satu alur kerja.
        </p>
        <div class="sim-actions">
          <.link navigate={~p"/dashboard"} class="sim-button-link">Open Dashboard Control Center</.link>
          <.link navigate={~p"/run-history"} class="sim-button-link">Open Run History</.link>
          <.link navigate={~p"/live-console"} class="sim-button-link">Open Live Console</.link>
        </div>
      </section>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)
end
