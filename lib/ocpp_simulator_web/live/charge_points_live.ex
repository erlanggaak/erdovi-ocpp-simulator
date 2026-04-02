defmodule OcppSimulatorWeb.ChargePointsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageChargePoints
  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()

    {entries, feedback} = load_entries(role, filters)

    {:ok,
     assign(socket,
       page_title: "Charge Point Registry",
       filters: filters,
       entries: entries,
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = normalize_filters(raw_filters)
    {entries, feedback} = load_entries(role, filters)

    {:noreply, assign(socket, filters: filters, entries: entries, feedback: feedback)}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    {entries, feedback} = load_entries(role, filters)

    {:noreply, assign(socket, filters: filters, entries: entries, feedback: feedback)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p :if={LiveData.can?(@permission_grants, :manage_charge_points)}>
        You can create and update charge points from this screen.
      </p>
      <p :if={!LiveData.can?(@permission_grants, :manage_charge_points)}>
        Read-only mode is active for your role.
      </p>

      <.form for={%{}} as={:filters} phx-submit="filter">
        <label>
          Charge Point ID
          <input type="text" name="filters[id]" value={@filters.id} />
        </label>
        <label>
          Vendor
          <input type="text" name="filters[vendor]" value={@filters.vendor} />
        </label>
        <label>
          Model
          <input type="text" name="filters[model]" value={@filters.model} />
        </label>
        <label>
          Behavior Profile
          <input type="text" name="filters[behavior_profile]" value={@filters.behavior_profile} />
        </label>
        <button type="submit">Apply Filters</button>
        <button type="button" phx-click="clear_filters">Clear</button>
      </.form>

      <p :if={@feedback}><%= @feedback %></p>

      <p>Result count: <%= length(@entries) %></p>

      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Vendor</th>
            <th>Model</th>
            <th>Firmware</th>
            <th>Connectors</th>
            <th>Heartbeat (s)</th>
            <th>Behavior</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries}>
            <td><%= entry.id %></td>
            <td><%= entry.vendor %></td>
            <td><%= entry.model %></td>
            <td><%= entry.firmware_version %></td>
            <td><%= entry.connector_count %></td>
            <td><%= entry.heartbeat_interval_seconds %></td>
            <td><%= entry.behavior_profile %></td>
          </tr>
        </tbody>
      </table>
    </main>
    """
  end

  defp load_entries(role, filters) do
    repository =
      LiveData.repository(
        :charge_point_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
      )

    case ManageChargePoints.list_charge_points(repository, role, LiveData.compact_filters(filters)) do
      {:ok, %{entries: entries}} when is_list(entries) ->
        {entries, nil}

      {:ok, entries} when is_list(entries) ->
        {entries, nil}

      {:error, reason} ->
        {[], "Unable to load charge points: #{inspect(reason)}"}
    end
  end

  defp default_filters do
    %{id: "", vendor: "", model: "", behavior_profile: ""}
  end

  defp normalize_filters(raw_filters) when is_map(raw_filters) do
    %{
      id: LiveData.normalize_filter(raw_filters, :id) || "",
      vendor: LiveData.normalize_filter(raw_filters, :vendor) || "",
      model: LiveData.normalize_filter(raw_filters, :model) || "",
      behavior_profile: LiveData.normalize_filter(raw_filters, :behavior_profile) || ""
    }
  end

  defp normalize_filters(_raw_filters), do: default_filters()
end
