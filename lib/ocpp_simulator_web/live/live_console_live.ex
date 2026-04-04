defmodule OcppSimulatorWeb.LiveConsoleLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @impl true
  def mount(params, _session, socket) do
    filters = default_filters(params)
    {entries, feedback} = load_entries(filters)
    selected_entry = List.first(entries)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, filters)

    {:ok,
     assign(socket,
       current_role: socket.assigns[:current_role] || :viewer,
       current_path: "/live-console",
       page_title: "Live Console",
       filters: filters,
       entries: entries,
       selected_entry: selected_entry,
       feedback: feedback,
       run_timeline: run_timeline,
       run_failure_reason: run_failure_reason
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    filters = normalize_filters(raw_filters, socket.assigns.filters)
    {entries, feedback} = load_entries(filters)
    selected_entry = List.first(entries)
    {run_timeline, run_failure_reason} = load_run_context(selected_entry, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: entries,
       selected_entry: selected_entry,
       feedback: feedback,
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
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Diagnostik timeline run secara real-time dengan detail frame."
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
          </div>
          <div class="sim-actions">
            <button type="submit">Load Timeline</button>
          </div>
        </.form>
      </section>

      <section class="sim-section">
        <h2>Timeline</h2>
        <div class="sim-code-block">
          <p :for={entry <- @entries}>
            [<%= entry.severity %>] <%= format_event_line(entry) %>
          </p>
        </div>
      </section>

      <section class="sim-section">
        <h2>Frame Details</h2>
        <%= if @selected_entry do %>
          <p class="sim-muted">ID: <%= @selected_entry.id %></p>
          <p class="sim-muted">Run ID: <%= @selected_entry.run_id %></p>
          <p class="sim-muted">Session ID: <%= @selected_entry.session_id || "-" %></p>
          <p class="sim-muted">Message ID: <%= @selected_entry.message_id || "-" %></p>
          <p class="sim-muted">Failure Reason: <%= @run_failure_reason || "none" %></p>
          <p class="sim-muted">Error Reason: <%= error_reason(@selected_entry.payload) %></p>
          <pre><%= payload_json(@selected_entry.payload) %></pre>

          <h3>Run Timeline Detail</h3>
          <div class="sim-code-block">
            <p :for={entry <- @run_timeline}>
              [<%= entry.severity %>] <%= format_event_line(entry) %>
            </p>
          </div>
        <% else %>
          <p class="sim-muted">Select a timeline item to inspect frame details.</p>
        <% end %>
      </section>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)

  defp load_entries(filters) do
    run_id = filters.run_id |> to_string() |> String.trim()

    if run_id == "" do
      {[], "Enter a run ID to load timeline diagnostics."}
    else
      repository =
        LiveData.repository(
          :log_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository
        )

      query_filters =
        filters
        |> Map.take([:run_id, :session_id, :message_id, :severity, :event_type])
        |> LiveData.compact_filters()
        |> Map.put(:page, 1)
        |> Map.put(:page_size, 100)

      case apply(repository, :list, [query_filters]) do
        {:ok, %{entries: entries}} when is_list(entries) ->
          feedback =
            if Enum.empty?(entries) do
              "No timeline events match the selected filters."
            else
              nil
            end

          {entries, feedback}

        {:error, reason} ->
          {[], "Unable to load timeline: #{inspect(reason)}"}
      end
    end
  end

  defp default_filters(params) do
    %{
      run_id: LiveData.normalize_filter(params, :run_id) || "",
      session_id: LiveData.normalize_filter(params, :session_id) || "",
      message_id: LiveData.normalize_filter(params, :message_id) || "",
      severity: LiveData.normalize_filter(params, :severity) || "",
      event_type: LiveData.normalize_filter(params, :event_type) || ""
    }
  end

  defp normalize_filters(raw_filters, existing_filters) when is_map(raw_filters) do
    %{
      run_id: LiveData.normalize_filter(raw_filters, :run_id) || existing_filters.run_id || "",
      session_id: LiveData.normalize_filter(raw_filters, :session_id) || "",
      message_id: LiveData.normalize_filter(raw_filters, :message_id) || "",
      severity: LiveData.normalize_filter(raw_filters, :severity) || "",
      event_type: LiveData.normalize_filter(raw_filters, :event_type) || ""
    }
  end

  defp normalize_filters(_raw_filters, existing_filters), do: existing_filters

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

  defp error_reason(payload) when is_map(payload) do
    nested_payload = Map.get(payload, "payload") || Map.get(payload, :payload) || %{}

    Map.get(payload, "reason") ||
      Map.get(payload, :reason) ||
      Map.get(nested_payload, "reason") ||
      Map.get(nested_payload, :reason) ||
      "none"
  end

  defp error_reason(_payload), do: "none"

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

      query_filters = %{run_id: normalized, page: 1, page_size: 250}

      case apply(repository, :list, [query_filters]) do
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
