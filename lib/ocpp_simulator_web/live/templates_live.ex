defmodule OcppSimulatorWeb.TemplatesLive do
  use OcppSimulatorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Templates")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Template management routes are authorization-gated.</p>
    </main>
    """
  end
end
