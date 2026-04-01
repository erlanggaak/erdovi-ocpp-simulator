defmodule OcppSimulatorWeb.ChargePointsLive do
  use OcppSimulatorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Charge Points")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Charge point management routes are authorization-gated.</p>
    </main>
    """
  end
end
