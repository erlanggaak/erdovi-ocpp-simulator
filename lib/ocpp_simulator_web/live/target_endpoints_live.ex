defmodule OcppSimulatorWeb.TargetEndpointsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints
  alias OcppSimulatorWeb.Live.LiveData

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    endpoint_form = default_endpoint_form()
    {entries, feedback} = load_entries(role, filters)

    {:ok,
     assign(socket,
       page_title: "Target Endpoints",
       filters: filters,
       entries: entries,
       feedback: feedback,
       endpoint_form: endpoint_form,
       endpoint_errors: %{}
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
  def handle_event("validate_endpoint", %{"endpoint" => endpoint_form}, socket) do
    errors = validate_endpoint_form(endpoint_form)
    {:noreply, assign(socket, endpoint_form: merge_endpoint_form(endpoint_form), endpoint_errors: errors)}
  end

  @impl true
  def handle_event("create_endpoint", %{"endpoint" => endpoint_form}, socket) do
    role = socket.assigns[:current_role] || :viewer
    normalized_form = merge_endpoint_form(endpoint_form)
    errors = validate_endpoint_form(normalized_form)

    if map_size(errors) > 0 do
      {:noreply,
       assign(socket,
         endpoint_form: normalized_form,
         endpoint_errors: errors,
         feedback: "Please fix validation errors before submitting."
       )}
    else
      case create_endpoint(role, normalized_form) do
        {:ok, _endpoint} ->
          {entries, _feedback} = load_entries(role, socket.assigns.filters)

          {:noreply,
           assign(socket,
             entries: entries,
             endpoint_form: default_endpoint_form(),
             endpoint_errors: %{},
             feedback: "Target endpoint was created successfully."
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             endpoint_form: normalized_form,
             endpoint_errors: %{},
             feedback: "Unable to create endpoint: #{inspect(reason)}"
           )}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p :if={LiveData.can?(@permission_grants, :manage_target_endpoints)}>
        You can manage endpoint profiles, including retry settings.
      </p>
      <p :if={!LiveData.can?(@permission_grants, :manage_target_endpoints)}>
        Read-only mode is active for your role.
      </p>

      <.form for={%{}} as={:filters} phx-submit="filter">
        <label>
          Endpoint ID
          <input type="text" name="filters[id]" value={@filters.id} />
        </label>
        <label>
          Name
          <input type="text" name="filters[name]" value={@filters.name} />
        </label>
        <label>
          URL
          <input type="text" name="filters[url]" value={@filters.url} />
        </label>
        <button type="submit">Apply Filters</button>
        <button type="button" phx-click="clear_filters">Clear</button>
      </.form>

      <%= if LiveData.can?(@permission_grants, :manage_target_endpoints) do %>
        <section>
          <h2>Create Endpoint</h2>
          <.form for={%{}} as={:endpoint} phx-change="validate_endpoint" phx-submit="create_endpoint">
            <label>
              ID
              <input type="text" name="endpoint[id]" value={@endpoint_form.id} />
            </label>
            <p :if={@endpoint_errors[:id]}><%= @endpoint_errors[:id] %></p>

            <label>
              Name
              <input type="text" name="endpoint[name]" value={@endpoint_form.name} />
            </label>
            <p :if={@endpoint_errors[:name]}><%= @endpoint_errors[:name] %></p>

            <label>
              URL (`ws://` only)
              <input type="text" name="endpoint[url]" value={@endpoint_form.url} />
            </label>
            <p :if={@endpoint_errors[:url]}><%= @endpoint_errors[:url] %></p>

            <label>
              Retry Max Attempts
              <input
                type="number"
                min="1"
                name="endpoint[retry_max_attempts]"
                value={@endpoint_form.retry_max_attempts}
              />
            </label>
            <p :if={@endpoint_errors[:retry_max_attempts]}><%= @endpoint_errors[:retry_max_attempts] %></p>

            <label>
              Retry Backoff (ms)
              <input
                type="number"
                min="1"
                name="endpoint[retry_backoff_ms]"
                value={@endpoint_form.retry_backoff_ms}
              />
            </label>
            <p :if={@endpoint_errors[:retry_backoff_ms]}><%= @endpoint_errors[:retry_backoff_ms] %></p>

            <button type="submit">Create Endpoint</button>
          </.form>
        </section>
      <% end %>

      <p :if={@feedback}><%= @feedback %></p>
      <p>Result count: <%= length(@entries) %></p>

      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>URL</th>
            <th>Retry Policy</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries}>
            <td><%= entry.id %></td>
            <td><%= entry.name %></td>
            <td><%= entry.url %></td>
            <td>
              attempts=<%= fetch_nested(entry.retry_policy, :max_attempts) || "-" %>,
              backoff_ms=<%= fetch_nested(entry.retry_policy, :backoff_ms) || "-" %>
            </td>
          </tr>
        </tbody>
      </table>
    </main>
    """
  end

  defp load_entries(role, filters) do
    repository =
      LiveData.repository(
        :target_endpoint_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
      )

    case ManageTargetEndpoints.list_target_endpoints(
           repository,
           role,
           LiveData.compact_filters(filters)
         ) do
      {:ok, %{entries: entries}} when is_list(entries) ->
        {entries, nil}

      {:ok, entries} when is_list(entries) ->
        {entries, nil}

      {:error, reason} ->
        {[], "Unable to load target endpoints: #{inspect(reason)}"}
    end
  end

  defp create_endpoint(role, endpoint_form) do
    with {:ok, retry_max_attempts} <-
           parse_positive_integer(fetch_form(endpoint_form, :retry_max_attempts)),
         {:ok, retry_backoff_ms} <- parse_positive_integer(fetch_form(endpoint_form, :retry_backoff_ms)) do
      attrs = %{
        id: fetch_form(endpoint_form, :id),
        name: fetch_form(endpoint_form, :name),
        url: fetch_form(endpoint_form, :url),
        retry_policy: %{max_attempts: retry_max_attempts, backoff_ms: retry_backoff_ms},
        protocol_options: %{},
        metadata: %{}
      }

      repository =
        LiveData.repository(
          :target_endpoint_repository,
          OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
        )

      ManageTargetEndpoints.create_target_endpoint(repository, attrs, role)
    end
  end

  defp parse_positive_integer(value) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp validate_endpoint_form(endpoint_form) do
    %{}
    |> maybe_add_required_error(:id, fetch_form(endpoint_form, :id))
    |> maybe_add_required_error(:name, fetch_form(endpoint_form, :name))
    |> maybe_add_ws_url_error(fetch_form(endpoint_form, :url))
    |> maybe_add_positive_integer_error(
      :retry_max_attempts,
      fetch_form(endpoint_form, :retry_max_attempts)
    )
    |> maybe_add_positive_integer_error(
      :retry_backoff_ms,
      fetch_form(endpoint_form, :retry_backoff_ms)
    )
  end

  defp maybe_add_required_error(errors, key, value) do
    if is_binary(value) and String.trim(value) != "" do
      errors
    else
      Map.put(errors, key, "Must be a non-empty value.")
    end
  end

  defp maybe_add_ws_url_error(errors, value) do
    normalized = to_string(value || "") |> String.trim()

    cond do
      normalized == "" ->
        Map.put(errors, :url, "Must be a non-empty value.")

      String.starts_with?(normalized, "ws://") ->
        errors

      true ->
        Map.put(errors, :url, "URL must use `ws://` in v1.")
    end
  end

  defp maybe_add_positive_integer_error(errors, key, value) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> errors
      _ -> Map.put(errors, key, "Must be a positive integer.")
    end
  end

  defp default_filters do
    %{id: "", name: "", url: ""}
  end

  defp normalize_filters(raw_filters) when is_map(raw_filters) do
    %{
      id: LiveData.normalize_filter(raw_filters, :id) || "",
      name: LiveData.normalize_filter(raw_filters, :name) || "",
      url: LiveData.normalize_filter(raw_filters, :url) || ""
    }
  end

  defp normalize_filters(_raw_filters), do: default_filters()

  defp default_endpoint_form do
    %{
      id: "",
      name: "",
      url: "",
      retry_max_attempts: "3",
      retry_backoff_ms: "1000"
    }
  end

  defp merge_endpoint_form(raw_form) when is_map(raw_form) do
    default_endpoint_form()
    |> Enum.reduce(%{}, fn {key, default_value}, acc ->
      value =
        raw_form
        |> Map.get(Atom.to_string(key), Map.get(raw_form, key, default_value))
        |> to_string()

      Map.put(acc, key, value)
    end)
  end

  defp merge_endpoint_form(_raw_form), do: default_endpoint_form()

  defp fetch_nested(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp fetch_nested(_map, _key), do: nil

  defp fetch_form(form, key) when is_map(form), do: Map.get(form, key) || Map.get(form, Atom.to_string(key))
  defp fetch_form(_form, _key), do: nil
end
