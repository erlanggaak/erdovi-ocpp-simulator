defmodule OcppSimulatorWeb.LogsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(params, _session, socket) do
    filters = default_filters(params)
    {page, feedback} = load_logs(filters)

    {:ok,
     assign(socket,
       page_title: "Logs Viewer",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: nil
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    filters =
      raw_filters
      |> normalize_filters(socket.assigns.filters)
      |> Map.put(:page, 1)

    {page, feedback} = load_logs(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: nil
     )}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_raw}, socket) do
    page = parse_positive_integer(page_raw, socket.assigns.filters.page)
    filters = Map.put(socket.assigns.filters, :page, page)
    {log_page, feedback} = load_logs(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: log_page.entries,
       pagination: pagination_from_page(log_page),
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("select_entry", %{"id" => id}, socket) do
    selected_entry = Enum.find(socket.assigns.entries, fn entry -> to_string(entry.id) == id end)
    {:noreply, assign(socket, selected_entry: selected_entry)}
  end

  @impl true
  def handle_event("drill_filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.put(:run_id, Map.get(params, "run_id", socket.assigns.filters.run_id) || "")
      |> Map.put(:session_id, Map.get(params, "session_id", socket.assigns.filters.session_id) || "")
      |> Map.put(:message_id, Map.get(params, "message_id", socket.assigns.filters.message_id) || "")
      |> Map.put(:page, 1)

    {page, feedback} = load_logs(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Filter-first log search with correlation drill-down.</p>

      <.form for={%{}} as={:filters} phx-submit="filter">
        <label>
          Run ID
          <input type="text" name="filters[run_id]" value={@filters.run_id} />
        </label>
        <label>
          Session ID
          <input type="text" name="filters[session_id]" value={@filters.session_id} />
        </label>
        <label>
          Message ID
          <input type="text" name="filters[message_id]" value={@filters.message_id} />
        </label>
        <label>
          Severity
          <input type="text" name="filters[severity]" value={@filters.severity} />
        </label>
        <label>
          Event Type
          <input type="text" name="filters[event_type]" value={@filters.event_type} />
        </label>
        <label>
          Page Size
          <input type="number" min="1" name="filters[page_size]" value={@filters.page_size} />
        </label>
        <button type="submit">Search Logs</button>
      </.form>

      <p :if={@feedback}><%= @feedback %></p>

      <table>
        <thead>
          <tr>
            <th>Timestamp</th>
            <th>Severity</th>
            <th>Event</th>
            <th>Run</th>
            <th>Session</th>
            <th>Message</th>
            <th>Drill-Down</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries}>
            <td><%= entry.timestamp %></td>
            <td><%= entry.severity %></td>
            <td>
              <button type="button" phx-click="select_entry" phx-value-id={entry.id}>
                <%= entry.event_type %>
              </button>
            </td>
            <td><%= entry.run_id %></td>
            <td><%= entry.session_id || "-" %></td>
            <td><%= entry.message_id || "-" %></td>
            <td>
              <button
                type="button"
                phx-click="drill_filter"
                phx-value-run_id={entry.run_id}
                phx-value-session_id={entry.session_id || ""}
                phx-value-message_id={entry.message_id || ""}
              >
                Correlate
              </button>
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

      <section>
        <h2>Log Detail</h2>
        <%= if @selected_entry do %>
          <p>ID: <%= @selected_entry.id %></p>
          <p>Run ID: <%= @selected_entry.run_id %></p>
          <p>Session ID: <%= @selected_entry.session_id || "-" %></p>
          <p>Message ID: <%= @selected_entry.message_id || "-" %></p>
          <pre><%= payload_json(@selected_entry.payload) %></pre>
        <% else %>
          <p>Select a log row to inspect payload details.</p>
        <% end %>
      </section>
    </main>
    """
  end

  defp load_logs(filters) do
    repository =
      LiveData.repository(:log_repository, OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository)

    if filter_first_missing?(filters) do
      {%{entries: [], page: filters.page, page_size: filters.page_size, total_entries: 0, total_pages: 1},
       "Apply at least one filter (run/session/message/severity/event) before querying logs."}
    else
      query_filters =
        filters
        |> Map.take([:run_id, :session_id, :message_id, :severity, :event_type, :page, :page_size])
        |> LiveData.compact_filters()

      case apply(repository, :list, [query_filters]) do
        {:ok, page} ->
          feedback =
            if Enum.empty?(page.entries) do
              "No logs match the selected filters."
            else
              nil
            end

          {page, feedback}

        {:error, reason} ->
          {%{entries: [], page: filters.page, page_size: filters.page_size, total_entries: 0, total_pages: 1},
           "Unable to load logs: #{inspect(reason)}"}
      end
    end
  end

  defp filter_first_missing?(filters) do
    Enum.all?(
      [:run_id, :session_id, :message_id, :severity, :event_type],
      fn key ->
        value = Map.get(filters, key, "")
        to_string(value) |> String.trim() == ""
      end
    )
  end

  defp default_filters(params) do
    %{
      run_id: LiveData.normalize_filter(params, :run_id) || "",
      session_id: LiveData.normalize_filter(params, :session_id) || "",
      message_id: LiveData.normalize_filter(params, :message_id) || "",
      severity: LiveData.normalize_filter(params, :severity) || "",
      event_type: LiveData.normalize_filter(params, :event_type) || "",
      page: LiveData.parse_positive_integer(params, :page, 1),
      page_size: LiveData.parse_positive_integer(params, :page_size, 50)
    }
  end

  defp normalize_filters(raw_filters, existing_filters) when is_map(raw_filters) do
    %{
      run_id: LiveData.normalize_filter(raw_filters, :run_id) || "",
      session_id: LiveData.normalize_filter(raw_filters, :session_id) || "",
      message_id: LiveData.normalize_filter(raw_filters, :message_id) || "",
      severity: LiveData.normalize_filter(raw_filters, :severity) || "",
      event_type: LiveData.normalize_filter(raw_filters, :event_type) || "",
      page: existing_filters.page,
      page_size: parse_positive_integer(Map.get(raw_filters, "page_size"), existing_filters.page_size)
    }
  end

  defp normalize_filters(_raw_filters, existing_filters), do: existing_filters

  defp parse_positive_integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp pagination_from_page(page) do
    %{
      page: page.page || 1,
      page_size: page.page_size || 50,
      total_entries: page.total_entries || 0,
      total_pages: max(page.total_pages || 1, 1)
    }
  end

  defp payload_json(payload) when is_map(payload), do: Jason.encode!(payload, pretty: true)
  defp payload_json(payload), do: inspect(payload)
end
