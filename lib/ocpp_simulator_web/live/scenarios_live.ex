defmodule OcppSimulatorWeb.ScenariosLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    {entries, feedback} = load_entries(role, filters)

    {:ok,
     assign(socket,
       page_title: "Scenario Library",
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
      <p :if={LiveData.can?(@permission_grants, :manage_scenarios)}>
        You can manage scenarios and open the builder.
      </p>
      <p :if={!LiveData.can?(@permission_grants, :manage_scenarios)}>
        Read-only mode is active for your role.
      </p>

      <.form for={%{}} as={:filters} phx-submit="filter">
        <label>
          Scenario ID
          <input type="text" name="filters[id]" value={@filters.id} />
        </label>
        <label>
          Name
          <input type="text" name="filters[name]" value={@filters.name} />
        </label>
        <label>
          Version
          <input type="text" name="filters[version]" value={@filters.version} />
        </label>
        <button type="submit">Apply Filters</button>
        <button type="button" phx-click="clear_filters">Clear</button>
      </.form>

      <p :if={@feedback}><%= @feedback %></p>
      <p>Result count: <%= length(@entries) %></p>
      <p :if={LiveData.can?(@permission_grants, :manage_scenarios)}>
        <.link navigate={~p"/scenario-builder"}>Open Scenario Builder</.link>
      </p>

      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Version</th>
            <th>Schema</th>
            <th>Steps</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries}>
            <td><%= entry.id %></td>
            <td><%= entry.name %></td>
            <td><%= entry.version %></td>
            <td><%= entry.schema_version %></td>
            <td><%= length(entry.steps) %></td>
          </tr>
        </tbody>
      </table>
    </main>
    """
  end

  defp load_entries(role, filters) do
    repository =
      LiveData.repository(
        :scenario_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
      )

    case ManageScenarios.list_scenarios(repository, role, LiveData.compact_filters(filters)) do
      {:ok, %{entries: entries}} when is_list(entries) ->
        {entries, nil}

      {:ok, entries} when is_list(entries) ->
        {entries, nil}

      {:error, reason} ->
        {[], "Unable to load scenarios: #{inspect(reason)}"}
    end
  end

  defp default_filters do
    %{id: "", name: "", version: ""}
  end

  defp normalize_filters(raw_filters) when is_map(raw_filters) do
    %{
      id: LiveData.normalize_filter(raw_filters, :id) || "",
      name: LiveData.normalize_filter(raw_filters, :name) || "",
      version: LiveData.normalize_filter(raw_filters, :version) || ""
    }
  end

  defp normalize_filters(_raw_filters), do: default_filters()
end
