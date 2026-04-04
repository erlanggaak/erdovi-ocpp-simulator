defmodule OcppSimulatorWeb.LogsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @impl true
  def mount(params, _session, socket) do
    filters = default_filters(params)
    {page, feedback} = load_logs(filters)
    selected_entry = List.first(page.entries)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, filters)

    {:ok,
     assign(socket,
       current_role: socket.assigns[:current_role] || :viewer,
       current_path: "/logs",
       page_title: "Logs Viewer",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: selected_entry,
       run_timeline: run_timeline,
       run_failure_reason: run_failure_reason
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    filters =
      raw_filters
      |> normalize_filters(socket.assigns.filters)
      |> Map.put(:page, 1)

    {page, feedback} = load_logs(filters)
    selected_entry = List.first(page.entries)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: selected_entry,
       run_timeline: run_timeline,
       run_failure_reason: run_failure_reason
     )}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_raw}, socket) do
    page = parse_positive_integer(page_raw, socket.assigns.filters.page)
    filters = Map.put(socket.assigns.filters, :page, page)
    {log_page, feedback} = load_logs(filters)
    selected_entry = List.first(log_page.entries)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: log_page.entries,
       pagination: pagination_from_page(log_page),
       feedback: feedback,
       selected_entry: selected_entry,
       run_timeline: run_timeline,
       run_failure_reason: run_failure_reason
     )}
  end

  @impl true
  def handle_event("select_entry", %{"id" => id}, socket) do
    selected_entry = Enum.find(socket.assigns.entries, fn entry -> to_string(entry.id) == id end)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, socket.assigns.filters)

    {:noreply,
     assign(socket,
       selected_entry: selected_entry,
       run_timeline: run_timeline,
       run_failure_reason: run_failure_reason
     )}
  end

  @impl true
  def handle_event("drill_filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.put(:run_id, Map.get(params, "run_id", socket.assigns.filters.run_id) || "")
      |> Map.put(
        :session_id,
        Map.get(params, "session_id", socket.assigns.filters.session_id) || ""
      )
      |> Map.put(
        :message_id,
        Map.get(params, "message_id", socket.assigns.filters.message_id) || ""
      )
      |> Map.put(:page, 1)

    {page, feedback} = load_logs(filters)
    selected_entry = List.first(page.entries)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: selected_entry,
       run_timeline: run_timeline,
       run_failure_reason: run_failure_reason
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Filter-first log search dengan correlation drill-down."
      current_path={@current_path}
      current_role={@current_role}
      notice={@feedback}
      flash={@flash}
    >
      <section class="sim-section">
        <.form for={%{}} as={:filters} phx-submit="filter">
          <div class="sim-form-grid">
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
          </div>
          <div class="sim-actions">
            <button type="submit">Search Logs</button>
          </div>
        </.form>
      </section>

      <div class="sim-table-wrap">
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
      </div>

      <section class="sim-section">
        <p class="sim-muted">
          Page <%= @pagination.page %> / <%= @pagination.total_pages %> (total entries:
          <%= @pagination.total_entries %>)
        </p>
        <div class="sim-actions">
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
        </div>
      </section>

      <section class="sim-section">
        <h2>Log Detail</h2>
        <%= if @selected_entry do %>
          <p class="sim-muted">ID: <%= @selected_entry.id %></p>
          <p class="sim-muted">Run ID: <%= @selected_entry.run_id %></p>
          <p class="sim-muted">Session ID: <%= @selected_entry.session_id || "-" %></p>
          <p class="sim-muted">Message ID: <%= @selected_entry.message_id || "-" %></p>
          <p class="sim-muted">Failure Reason: <%= @run_failure_reason || "none" %></p>
          <pre><%= payload_json(@selected_entry.payload) %></pre>
          <h3>Run Timeline Detail</h3>
          <div class="sim-code-block">
            <p :for={entry <- @run_timeline}>[<%= entry.severity %>] <%= format_event_line(entry) %></p>
          </div>
        <% else %>
          <p class="sim-muted">Select a log row to inspect payload details.</p>
        <% end %>
      </section>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)

  defp load_logs(filters) do
    repository =
      LiveData.repository(
        :log_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository
      )

    if filter_first_missing?(filters) do
      {%{
         entries: [],
         page: filters.page,
         page_size: filters.page_size,
         total_entries: 0,
         total_pages: 1
       }, "Apply at least one filter (run/session/message/severity/event) before querying logs."}
    else
      query_filters =
        filters
        |> Map.take([
          :run_id,
          :session_id,
          :message_id,
          :severity,
          :event_type,
          :page,
          :page_size
        ])
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
          {%{
             entries: [],
             page: filters.page,
             page_size: filters.page_size,
             total_entries: 0,
             total_pages: 1
           }, "Unable to load logs: #{inspect(reason)}"}
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
      page_size:
        parse_positive_integer(Map.get(raw_filters, "page_size"), existing_filters.page_size)
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

  defp format_event_line(entry) when is_map(entry) do
    event_type = to_string(entry.event_type || "")
    payload = entry.payload || %{}
    event_payload = fetch_value(payload, :payload) || payload
    step_id = fetch_value(entry, :step_id)
    action = fetch_value(entry, :action)

    case event_type do
      "scenario.step.running" ->
        "running step #{step_id || "-"} action=#{action || "-"}"

      "scenario.ws.connecting" ->
        "connect to ws (step #{step_id || "-"})"

      "scenario.ws.connected" ->
        "ws connected (step #{step_id || "-"})"

      "protocol.outbound_sent" ->
        "send #{action || "action"} payload=#{inline_payload(fetch_value(event_payload, :frame_payload) || event_payload)}"

      "protocol.inbound_received" ->
        "receive #{action || "action"} response payload=#{inline_payload(fetch_value(event_payload, :response) || event_payload)}"

      "scenario.step.succeeded" ->
        "step #{step_id || "-"} successful"

      "scenario.step.failed" ->
        "step #{step_id || "-"} failed because #{fetch_value(event_payload, :reason) || "unknown"}"

      "scenario.step.timed_out" ->
        "step #{step_id || "-"} timed out"

      "scenario.step.canceled" ->
        "step #{step_id || "-"} canceled"

      "scenario.run.executed" ->
        "scenario.run.executed run finished state=#{fetch_value(event_payload, :state) || "-"} reason=#{fetch_value(event_payload, :failure_reason) || "none"} elapsed_ms=#{fetch_value(event_payload, :elapsed_ms) || 0}"

      _ ->
        "#{event_type} run=#{entry.run_id} session=#{entry.session_id || "-"}"
    end
  end

  defp format_event_line(_entry), do: "-"

  defp inline_payload(payload) when is_map(payload) do
    payload
    |> Jason.encode!()
    |> String.slice(0, 220)
  end

  defp inline_payload(payload), do: to_string(payload)

  defp load_run_context(nil, filters) do
    run_id = filters.run_id |> to_string() |> String.trim()
    {load_run_timeline(run_id), load_failure_reason(run_id)}
  end

  defp load_run_context(selected_entry, _filters) do
    run_id = to_string(selected_entry.run_id || "")
    {load_run_timeline(run_id), load_failure_reason(run_id)}
  end

  defp load_run_timeline(run_id) when is_binary(run_id) do
    normalized = String.trim(run_id)

    if normalized == "" do
      []
    else
      repository =
        LiveData.repository(
          :log_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository
        )

      case apply(repository, :list, [%{run_id: normalized, page: 1, page_size: 250}]) do
        {:ok, %{entries: entries}} when is_list(entries) -> Enum.reverse(entries)
        _ -> []
      end
    end
  end

  defp load_run_timeline(_run_id), do: []

  defp load_failure_reason(run_id) when is_binary(run_id) do
    normalized = String.trim(run_id)

    if normalized == "" do
      nil
    else
      repository =
        LiveData.repository(
          :scenario_run_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
        )

      case apply(repository, :get, [normalized]) do
        {:ok, run} ->
          run.metadata
          |> fetch_value(:failure_reason)
          |> normalize_failure_reason()

        _ ->
          nil
      end
    end
  end

  defp load_failure_reason(_run_id), do: nil

  defp normalize_failure_reason(nil), do: nil
  defp normalize_failure_reason(value) when is_binary(value), do: value
  defp normalize_failure_reason(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_failure_reason(value), do: inspect(value)

  defp fetch_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch_value(_map, _key), do: nil
end
