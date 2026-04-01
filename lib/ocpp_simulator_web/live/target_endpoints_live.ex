defmodule OcppSimulatorWeb.TargetEndpointsLive do
  use OcppSimulatorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Target Endpoints")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Target endpoint profiles are managed through authorization-gated flows.</p>
    </main>
    """
  end
end
