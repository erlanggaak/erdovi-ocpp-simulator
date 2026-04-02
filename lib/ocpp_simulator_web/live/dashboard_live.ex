defmodule OcppSimulatorWeb.DashboardLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(_params, session, socket) do
    role = LiveData.normalize_role(Map.get(session, "current_role"))

    {assigns, feedback} = build_assigns()

    {:ok,
     assign(socket,
       current_role: role,
       page_title: "Dashboard",
       max_concurrent_runs: OcppSimulator.runtime_config()[:max_concurrent_runs],
       max_active_sessions: OcppSimulator.runtime_config()[:max_active_sessions],
       stats: assigns,
       feedback: feedback
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="dashboard-shell">
      <h1><%= @page_title %></h1>
      <p>Signed in as role: <strong><%= @current_role %></strong></p>

      <%= if @feedback do %>
        <p><%= @feedback %></p>
      <% end %>

      <section>
        <h2>System Limits</h2>
        <ul>
          <li>Max concurrent runs: <%= @max_concurrent_runs %></li>
          <li>Max active sessions: <%= @max_active_sessions %></li>
        </ul>
      </section>

      <section>
        <h2>Repository Snapshot</h2>
        <ul>
          <li>Charge points: <%= @stats.charge_points %></li>
          <li>Scenarios: <%= @stats.scenarios %></li>
          <li>Templates: <%= @stats.templates %></li>
          <li>Runs: <%= @stats.runs %></li>
        </ul>
      </section>

      <section>
        <h2>Quick Navigation</h2>
        <ul>
          <li><.link navigate={~p"/charge-points"}>Charge Point Registry</.link></li>
          <li><.link navigate={~p"/scenarios"}>Scenario Library</.link></li>
          <li><.link navigate={~p"/templates"}>Template Library</.link></li>
          <li><.link navigate={~p"/target-endpoints"}>Target Endpoints</.link></li>
          <li><.link navigate={~p"/scenario-builder"}>Scenario Builder</.link></li>
          <li><.link navigate={~p"/live-console"}>Live Console</.link></li>
          <li><.link navigate={~p"/run-history"}>Run History</.link></li>
          <li><.link navigate={~p"/logs"}>Logs Viewer</.link></li>
        </ul>
      </section>
    </main>
    """
  end

  defp build_assigns do
    charge_point_repository =
      LiveData.repository(
        :charge_point_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
      )

    scenario_repository =
      LiveData.repository(
        :scenario_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
      )

    template_repository =
      LiveData.repository(
        :template_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
      )

    scenario_run_repository =
      LiveData.repository(
        :scenario_run_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
      )

    snapshot = %{
      charge_points: count_entries(charge_point_repository, :list),
      scenarios: count_entries(scenario_repository, :list),
      templates: count_entries(template_repository, :list),
      runs: count_entries(scenario_run_repository, :list_history)
    }

    feedback =
      if Enum.any?(Map.values(snapshot), &(&1 == :error)) do
        "Some dashboard metrics are unavailable because one or more repositories failed."
      else
        nil
      end

    normalized_snapshot =
      snapshot
      |> Enum.into(%{}, fn {key, value} ->
        normalized_value =
          case value do
            :error -> "unavailable"
            count when is_integer(count) -> count
          end

        {key, normalized_value}
      end)

    {normalized_snapshot, feedback}
  end

  defp count_entries(repository, list_function) do
    case apply(repository, list_function, [%{page: 1, page_size: 1, allow_unfiltered: true}]) do
      {:ok, %{total_entries: total_entries}} when is_integer(total_entries) ->
        total_entries

      _ ->
        :error
    end
  rescue
    _ -> :error
  end
end
