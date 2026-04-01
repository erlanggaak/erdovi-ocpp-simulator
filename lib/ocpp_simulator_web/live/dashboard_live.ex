defmodule OcppSimulatorWeb.DashboardLive do
  use OcppSimulatorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "OCPP 1.6J Simulator",
       max_concurrent_runs: OcppSimulator.runtime_config()[:max_concurrent_runs],
       max_active_sessions: OcppSimulator.runtime_config()[:max_active_sessions]
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="dashboard-shell">
      <h1><%= @page_title %></h1>
      <p>Bootstrap runtime is up and ready for scenario-engine implementation.</p>
      <ul>
        <li>Max concurrent runs: <%= @max_concurrent_runs %></li>
        <li>Max active sessions: <%= @max_active_sessions %></li>
      </ul>
    </main>
    """
  end
end
