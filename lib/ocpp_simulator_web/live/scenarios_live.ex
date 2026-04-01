defmodule OcppSimulatorWeb.ScenariosLive do
  use OcppSimulatorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Scenarios")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Scenario management routes are authorization-gated.</p>
    </main>
    """
  end
end
