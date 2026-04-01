defmodule OcppSimulatorWeb.RunOperationsLive do
  use OcppSimulatorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Run Operations")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Run operations are protected by role-based authorization hooks.</p>
    </main>
    """
  end
end
