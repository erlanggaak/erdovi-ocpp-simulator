defmodule OcppSimulatorWeb.TemplatesLive do
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
       page_title: "Template Library",
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
      <p :if={LiveData.can?(@permission_grants, :manage_templates)}>
        You can create and update templates from this screen.
      </p>
      <p :if={!LiveData.can?(@permission_grants, :manage_templates)}>
        Read-only mode is active for your role.
      </p>

      <.form for={%{}} as={:filters} phx-submit="filter">
        <label>
          Template ID
          <input type="text" name="filters[id]" value={@filters.id} />
        </label>
        <label>
          Name
          <input type="text" name="filters[name]" value={@filters.name} />
        </label>
        <label>
          Type
          <input type="text" name="filters[type]" value={@filters.type} />
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
            <th>Name</th>
            <th>Version</th>
            <th>Type</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries}>
            <td><%= entry.id %></td>
            <td><%= entry.name %></td>
            <td><%= entry.version %></td>
            <td><%= entry.type %></td>
          </tr>
        </tbody>
      </table>
    </main>
    """
  end

  defp load_entries(role, filters) do
    repository =
      LiveData.repository(
        :template_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
      )

    case ManageScenarios.list_templates(repository, role, LiveData.compact_filters(filters)) do
      {:ok, %{entries: entries}} when is_list(entries) ->
        {entries, nil}

      {:ok, entries} when is_list(entries) ->
        {entries, nil}

      {:error, reason} ->
        {[], "Unable to load templates: #{inspect(reason)}"}
    end
  end

  defp default_filters do
    %{id: "", name: "", type: ""}
  end

  defp normalize_filters(raw_filters) when is_map(raw_filters) do
    %{
      id: LiveData.normalize_filter(raw_filters, :id) || "",
      name: LiveData.normalize_filter(raw_filters, :name) || "",
      type: LiveData.normalize_filter(raw_filters, :type) || ""
    }
  end

  defp normalize_filters(_raw_filters), do: default_filters()
end
