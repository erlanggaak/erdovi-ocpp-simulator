defmodule OcppSimulatorWeb.RunHistoryLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(params, _session, socket) do
    filters = default_filters(params)
    {page, feedback} = load_history(filters)

    {:ok,
     assign(socket,
       page_title: "Run History",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       replay_feedback: nil
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    filters =
      raw_filters
      |> normalize_filters(socket.assigns.filters)
      |> Map.put(:page, 1)

    {page, feedback} = load_history(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       replay_feedback: nil
     )}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_raw}, socket) do
    page = parse_positive_integer(page_raw, socket.assigns.filters.page)
    filters = Map.put(socket.assigns.filters, :page, page)
    {history_page, feedback} = load_history(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: history_page.entries,
       pagination: pagination_from_page(history_page),
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("replay", %{"id" => run_id}, socket) do
    {:noreply,
     assign(socket,
       replay_feedback:
         "Replay requested for run #{run_id}. Open Live Console with this run ID to inspect frame timeline."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Historical run timeline with replay entry points.</p>

      <.form for={%{}} as={:filters} phx-submit="filter">
        <label>
          Scenario ID
          <input type="text" name="filters[scenario_id]" value={@filters.scenario_id} />
        </label>
        <label>
          State
          <input type="text" name="filters[state]" value={@filters.state} />
        </label>
        <label>
          Page Size
          <input type="number" min="1" name="filters[page_size]" value={@filters.page_size} />
        </label>
        <button type="submit">Apply Filters</button>
      </.form>

      <p :if={@feedback}><%= @feedback %></p>
      <p :if={@replay_feedback}><%= @replay_feedback %></p>

      <table>
        <thead>
          <tr>
            <th>Run ID</th>
            <th>Scenario</th>
            <th>Version</th>
            <th>State</th>
            <th>Created At</th>
            <th>Error Reason</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries}>
            <td><%= entry.id %></td>
            <td><%= entry.scenario_id %></td>
            <td><%= entry.scenario_version %></td>
            <td><%= entry.state %></td>
            <td><%= entry.created_at %></td>
            <td><%= extract_failure_reason(entry.metadata) %></td>
            <td>
              <button type="button" phx-click="replay" phx-value-id={entry.id}>Replay</button>
              <.link navigate={~p"/live-console?run_id=#{entry.id}"}>Open Console</.link>
            </td>
          </tr>
        </tbody>
      </table>

      <section>
        <p>
          Page <%= @pagination.page %> / <%= @pagination.total_pages %> (total entries:
          <%= @pagination.total_entries %>)
        </p>
        <button
          type="button"
          phx-click="paginate"
          phx-value-page={max(@pagination.page - 1, 1)}
          disabled={@pagination.page <= 1}
        >
          Previous
        </button>
        <button
          type="button"
          phx-click="paginate"
          phx-value-page={min(@pagination.page + 1, @pagination.total_pages)}
          disabled={@pagination.page >= @pagination.total_pages}
        >
          Next
        </button>
      </section>
    </main>
    """
  end

  defp load_history(filters) do
    repository =
      LiveData.repository(
        :scenario_run_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
      )

    query_filters =
      filters
      |> Map.take([:scenario_id, :state, :page, :page_size])
      |> LiveData.compact_filters()

    case apply(repository, :list_history, [query_filters]) do
      {:ok, page} ->
        feedback =
          if Enum.empty?(page.entries) do
            "No historical runs match the selected filters."
          else
            nil
          end

        {page, feedback}

      {:error, reason} ->
        {%{entries: [], page: 1, page_size: filters.page_size, total_entries: 0, total_pages: 1},
         "Unable to load run history: #{inspect(reason)}"}
    end
  end

  defp default_filters(params) do
    %{
      scenario_id: LiveData.normalize_filter(params, :scenario_id) || "",
      state: LiveData.normalize_filter(params, :state) || "",
      page: LiveData.parse_positive_integer(params, :page, 1),
      page_size: LiveData.parse_positive_integer(params, :page_size, 25)
    }
  end

  defp normalize_filters(raw_filters, existing_filters) when is_map(raw_filters) do
    %{
      scenario_id: LiveData.normalize_filter(raw_filters, :scenario_id) || "",
      state: LiveData.normalize_filter(raw_filters, :state) || "",
      page: existing_filters.page,
      page_size: parse_positive_integer(Map.get(raw_filters, "page_size"), existing_filters.page_size)
    }
  end

  defp normalize_filters(_raw_filters, existing_filters), do: existing_filters

  defp pagination_from_page(page) do
    %{
      page: page.page || 1,
      page_size: page.page_size || 25,
      total_entries: page.total_entries || 0,
      total_pages: max(page.total_pages || 1, 1)
    }
  end

  defp parse_positive_integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp extract_failure_reason(metadata) when is_map(metadata) do
    Map.get(metadata, :failure_reason) || Map.get(metadata, "failure_reason") || "-"
  end

  defp extract_failure_reason(_metadata), do: "-"
end
