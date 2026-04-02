defmodule OcppSimulatorWeb.LiveConsoleLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(params, _session, socket) do
    filters = default_filters(params)
    {entries, feedback} = load_entries(filters)

    {:ok,
     assign(socket,
       page_title: "Live Console",
       filters: filters,
       entries: entries,
       selected_entry: nil,
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    filters = normalize_filters(raw_filters, socket.assigns.filters)
    {entries, feedback} = load_entries(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: entries,
       selected_entry: List.first(entries),
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("select_entry", %{"id" => id}, socket) do
    selected_entry = Enum.find(socket.assigns.entries, fn entry -> to_string(entry.id) == id end)
    {:noreply, assign(socket, selected_entry: selected_entry)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Timeline diagnostics for a selected run/session stream.</p>

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
        <button type="submit">Load Timeline</button>
      </.form>

      <p :if={@feedback}><%= @feedback %></p>

      <section>
        <h2>Timeline</h2>
        <ul>
          <li :for={entry <- @entries}>
            <button type="button" phx-click="select_entry" phx-value-id={entry.id}>
              [<%= entry.severity %>] <%= entry.event_type %> run=<%= entry.run_id %> session=<%= entry.session_id || "-" %> message=<%= entry.message_id || "-" %>
            </button>
          </li>
        </ul>
      </section>

      <section>
        <h2>Frame Details</h2>
        <%= if @selected_entry do %>
          <p>ID: <%= @selected_entry.id %></p>
          <p>Run ID: <%= @selected_entry.run_id %></p>
          <p>Session ID: <%= @selected_entry.session_id || "-" %></p>
          <p>Message ID: <%= @selected_entry.message_id || "-" %></p>
          <p>Error Reason: <%= error_reason(@selected_entry.payload) %></p>
          <pre><%= payload_json(@selected_entry.payload) %></pre>
        <% else %>
          <p>Select a timeline item to inspect frame details.</p>
        <% end %>
      </section>
    </main>
    """
  end

  defp load_entries(filters) do
    run_id = filters.run_id |> to_string() |> String.trim()

    if run_id == "" do
      {[], "Enter a run ID to load timeline diagnostics."}
    else
      repository =
        LiveData.repository(:log_repository, OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository)

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

  defp error_reason(payload) when is_map(payload) do
    Map.get(payload, "reason") || Map.get(payload, :reason) || "none"
  end

  defp error_reason(_payload), do: "none"
end
