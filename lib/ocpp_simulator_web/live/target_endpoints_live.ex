defmodule OcppSimulatorWeb.TargetEndpointsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints
  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @sortable_fields ["id", "name", "url"]

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    {page, feedback} = load_page(role, filters)

    {:ok,
     assign(socket,
       current_role: role,
       current_path: "/target-endpoints",
       page_title: "Target Endpoints",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: nil,
       form_mode: :create,
       form: default_form(),
       form_errors: %{},
       endpoint_form: default_form(),
       endpoint_errors: %{},
       delete_candidate: nil
     )}
  end

  @impl true
  def handle_event("create_endpoint", %{"endpoint" => raw_form}, socket) do
    role = socket.assigns.current_role
    form = normalize_form(raw_form)
    errors = legacy_validate_form(form)

    if map_size(errors) > 0 do
      {:noreply,
       assign(socket,
         form: form,
         form_errors: errors,
         endpoint_form: form,
         endpoint_errors: errors,
         feedback: "Please fix validation errors before submitting."
       )}
    else
      case build_attrs(form, :create) do
        {:ok, attrs} ->
          case ManageTargetEndpoints.create_target_endpoint(repository(), attrs, role) do
            {:ok, _endpoint} ->
              {page, _feedback} = load_page(role, socket.assigns.filters)

              {:noreply,
               assign(socket,
                 entries: page.entries,
                 pagination: pagination_from_page(page),
                 form: default_form(),
                 form_errors: %{},
                 endpoint_form: default_form(),
                 endpoint_errors: %{},
                 feedback: "Target endpoint was created successfully."
               )}

            {:error, :forbidden} ->
              permission_errors = %{base: "Role ini tidak punya izin untuk create endpoint."}

              {:noreply,
               assign(socket,
                 form: form,
                 form_errors: permission_errors,
                 endpoint_form: form,
                 endpoint_errors: permission_errors,
                 feedback: "Ganti role ke Operator/Admin untuk melakukan aksi ini."
               )}

            {:error, reason} ->
              fallback_errors = %{base: "Unable to create endpoint: #{inspect(reason)}"}

              {:noreply,
               assign(socket,
                 form: form,
                 form_errors: fallback_errors,
                 endpoint_form: form,
                 endpoint_errors: fallback_errors,
                 feedback: "Unable to save endpoint: #{inspect(reason)}"
               )}
          end

        {:error, attrs_errors} ->
          {:noreply,
           assign(socket,
             form: form,
             form_errors: attrs_errors,
             endpoint_form: form,
             endpoint_errors: attrs_errors,
             feedback: "Please fix validation errors before submitting."
           )}
      end
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => raw_filters}, socket) do
    role = socket.assigns.current_role

    filters =
      raw_filters
      |> normalize_filters(socket.assigns.filters)
      |> Map.put(:page, 1)

    {page, feedback} = load_page(role, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    role = socket.assigns.current_role
    filters = default_filters()
    {page, feedback} = load_page(role, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("paginate", %{"page" => raw_page}, socket) do
    role = socket.assigns.current_role
    page = parse_positive_integer(raw_page, socket.assigns.filters.page)
    filters = Map.put(socket.assigns.filters, :page, page)
    {page_data, feedback} = load_page(role, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       entries: page_data.entries,
       pagination: pagination_from_page(page_data),
       feedback: feedback
     )}
  end

  @impl true
  def handle_event("select_detail", %{"id" => id}, socket) do
    role = socket.assigns.current_role

    case ManageTargetEndpoints.get_target_endpoint(repository(), id, role) do
      {:ok, endpoint} ->
        {:noreply, assign(socket, selected_entry: endpoint, feedback: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, feedback: "Unable to load detail: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("begin_create", _params, socket) do
    {:noreply,
     assign(socket,
       form_mode: :create,
       form: default_form(),
       form_errors: %{}
     )}
  end

  @impl true
  def handle_event("begin_edit", %{"id" => id}, socket) do
    role = socket.assigns.current_role

    case ManageTargetEndpoints.get_target_endpoint(repository(), id, role) do
      {:ok, endpoint} ->
        {:noreply,
         assign(socket,
           form_mode: :edit,
           form: form_from_entry(endpoint),
           form_errors: %{}
         )}

      {:error, reason} ->
        {:noreply, assign(socket, feedback: "Unable to load data for edit: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply,
     assign(socket,
       form_mode: :create,
       form: default_form(),
       form_errors: %{}
     )}
  end

  @impl true
  def handle_event("save", %{"endpoint" => raw_form}, socket) do
    role = socket.assigns.current_role
    mode = socket.assigns.form_mode
    form = normalize_form(raw_form)

    case build_attrs(form, mode) do
      {:ok, attrs} ->
        save_result =
          case mode do
            :create ->
              ManageTargetEndpoints.create_target_endpoint(repository(), attrs, role)

            :edit ->
              ManageTargetEndpoints.update_target_endpoint(repository(), form.id, attrs, role)
          end

        case save_result do
          {:ok, endpoint} ->
            {page, _feedback} = load_page(role, socket.assigns.filters)

            {:noreply,
             assign(socket,
               entries: page.entries,
               pagination: pagination_from_page(page),
               selected_entry: endpoint,
               form_mode: :create,
               form: default_form(),
               form_errors: %{},
               endpoint_form: default_form(),
               endpoint_errors: %{},
               feedback:
                 if(mode == :create,
                   do: "Target endpoint was created successfully.",
                   else: "Target endpoint was updated successfully."
                 )
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               form: form,
               form_errors: form_errors_from_reason(reason),
               endpoint_form: form,
               endpoint_errors: form_errors_from_reason(reason),
               feedback: "Unable to save endpoint: #{inspect(reason)}"
             )}
        end

      {:error, errors} ->
        {:noreply,
         assign(socket,
           form: form,
           form_errors: errors,
           endpoint_form: form,
           endpoint_errors: errors,
           feedback: "Please fix validation errors before submitting."
         )}
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    role = socket.assigns.current_role

    case ManageTargetEndpoints.get_target_endpoint(repository(), id, role) do
      {:ok, endpoint} ->
        {:noreply, assign(socket, delete_candidate: endpoint)}

      {:error, reason} ->
        {:noreply, assign(socket, feedback: "Unable to open delete modal: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, delete_candidate: nil)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    role = socket.assigns.current_role
    candidate = socket.assigns.delete_candidate

    if candidate do
      case ManageTargetEndpoints.delete_target_endpoint(repository(), candidate.id, role) do
        :ok ->
          {page, _feedback} = load_page(role, socket.assigns.filters)

          {:noreply,
           assign(socket,
             entries: page.entries,
             pagination: pagination_from_page(page),
             selected_entry: maybe_clear_selected(socket.assigns.selected_entry, candidate.id),
             delete_candidate: nil,
             feedback: "Target endpoint was deleted successfully."
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             delete_candidate: nil,
             feedback: "Unable to delete endpoint: #{inspect(reason)}"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Kelola endpoint WS target dengan CRUD lengkap."
      current_path={@current_path}
      current_role={@current_role}
      notice={@feedback}
      flash={@flash}
    >
      <section class="sim-section">
        <.form for={%{}} as={:filters} phx-submit="filter">
          <div class="sim-form-grid">
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
            <label>
              Order By
              <select name="filters[sort_field]" value={@filters.sort_field}>
                <option :for={field <- sortable_fields()} value={field} selected={@filters.sort_field == field}>
                  <%= field %>
                </option>
              </select>
            </label>
            <label>
              Direction
              <select name="filters[sort_dir]" value={@filters.sort_dir}>
                <option value="asc" selected={@filters.sort_dir == "asc"}>asc</option>
                <option value="desc" selected={@filters.sort_dir == "desc"}>desc</option>
              </select>
            </label>
            <label>
              Page Size
              <input type="number" min="1" name="filters[page_size]" value={@filters.page_size} />
            </label>
          </div>
          <div class="sim-actions">
            <button type="submit">Apply</button>
            <button type="button" phx-click="clear_filters">Clear</button>
          </div>
        </.form>
      </section>

      <%= if LiveData.can?(@permission_grants, :manage_target_endpoints) do %>
        <section class="sim-section">
          <div class="sim-row-between">
            <h2><%= if @form_mode == :create, do: "Add New Endpoint", else: "Edit Endpoint" %></h2>
            <button type="button" phx-click="begin_create" class="sim-button-secondary">New Form</button>
          </div>
          <.form
            for={%{}}
            as={:endpoint}
            phx-submit="save"
            action={~p"/target-endpoints"}
            method="post"
          >
            <div class="sim-form-grid">
              <label>
                ID
                <input type="text" name="endpoint[id]" value={@form.id} readonly={@form_mode == :edit} />
                <p :if={@form_errors[:id]} class="sim-error-text"><%= @form_errors[:id] %></p>
              </label>
              <label>
                Name
                <input type="text" name="endpoint[name]" value={@form.name} />
                <p :if={@form_errors[:name]} class="sim-error-text"><%= @form_errors[:name] %></p>
              </label>
              <label>
                URL (`ws://`)
                <input type="text" name="endpoint[url]" value={@form.url} />
                <p :if={@form_errors[:url]} class="sim-error-text"><%= @form_errors[:url] %></p>
              </label>
              <label>
                Retry Max Attempts
                <input
                  type="number"
                  min="1"
                  name="endpoint[retry_max_attempts]"
                  value={@form.retry_max_attempts}
                />
                <p :if={@form_errors[:retry_max_attempts]} class="sim-error-text">
                  <%= @form_errors[:retry_max_attempts] %>
                </p>
              </label>
              <label>
                Retry Backoff (ms)
                <input
                  type="number"
                  min="1"
                  name="endpoint[retry_backoff_ms]"
                  value={@form.retry_backoff_ms}
                />
                <p :if={@form_errors[:retry_backoff_ms]} class="sim-error-text">
                  <%= @form_errors[:retry_backoff_ms] %>
                </p>
              </label>
            </div>
            <div class="sim-actions">
              <button type="submit"><%= if @form_mode == :create, do: "Create", else: "Update" %></button>
              <button type="button" phx-click="cancel_form" class="sim-button-secondary">Cancel</button>
            </div>
          </.form>
        </section>
      <% end %>

      <section class="sim-section">
        <p class="sim-muted">
          Page <%= @pagination.page %>/<%= @pagination.total_pages %> • total entries: <%= @pagination.total_entries %>
        </p>
        <div class="sim-table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Name</th>
                <th>URL</th>
                <th>Retry Policy</th>
                <th>Actions</th>
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
                <td>
                  <div class="sim-actions">
                    <button type="button" phx-click="select_detail" phx-value-id={entry.id}>Detail</button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_target_endpoints)}
                      type="button"
                      phx-click="begin_edit"
                      phx-value-id={entry.id}
                    >
                      Edit
                    </button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_target_endpoints)}
                      type="button"
                      phx-click="confirm_delete"
                      phx-value-id={entry.id}
                      class="sim-button-danger"
                    >
                      Delete
                    </button>
                  </div>
                </td>
              </tr>
              <tr :if={Enum.empty?(@entries)}>
                <td colspan="5">No endpoint found for current filter.</td>
              </tr>
            </tbody>
          </table>
        </div>
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

      <section class="sim-section" :if={@selected_entry}>
        <h2>Instance Detail</h2>
        <div class="sim-detail-grid">
          <p><strong>ID:</strong> <%= @selected_entry.id %></p>
          <p><strong>Name:</strong> <%= @selected_entry.name %></p>
          <p><strong>URL:</strong> <%= @selected_entry.url %></p>
          <p>
            <strong>Retry Max Attempts:</strong>
            <%= fetch_nested(@selected_entry.retry_policy, :max_attempts) || "-" %>
          </p>
          <p>
            <strong>Retry Backoff (ms):</strong>
            <%= fetch_nested(@selected_entry.retry_policy, :backoff_ms) || "-" %>
          </p>
        </div>
      </section>

      <div :if={@delete_candidate} class="sim-modal-backdrop">
        <section class="sim-modal">
          <h2>Delete Target Endpoint</h2>
          <p>
            Endpoint <strong><%= @delete_candidate.id %></strong> akan dihapus permanen. Lanjutkan?
          </p>
          <div class="sim-actions">
            <button type="button" phx-click="delete" class="sim-button-danger">Yes, Delete</button>
            <button type="button" phx-click="cancel_delete" class="sim-button-secondary">Cancel</button>
          </div>
        </section>
      </div>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)

  defp sortable_fields, do: @sortable_fields

  defp repository do
    LiveData.repository(
      :target_endpoint_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
    )
  end

  defp load_page(role, filters) do
    payload =
      filters
      |> Map.take([:id, :name, :url, :page, :page_size])
      |> Map.put(:sort, %{filters.sort_field => sort_direction(filters.sort_dir)})
      |> LiveData.compact_filters()

    case ManageTargetEndpoints.list_target_endpoints(repository(), role, payload) do
      {:ok, %{entries: entries} = page} when is_list(entries) ->
        {page, nil}

      {:ok, entries} when is_list(entries) ->
        {%{entries: entries, page: 1, page_size: filters.page_size, total_entries: length(entries), total_pages: 1},
         nil}

      {:error, reason} ->
        {%{entries: [], page: 1, page_size: filters.page_size, total_entries: 0, total_pages: 1},
         "Unable to load target endpoints: #{inspect(reason)}"}
    end
  end

  defp default_filters do
    %{
      id: "",
      name: "",
      url: "",
      page: 1,
      page_size: 10,
      sort_field: "name",
      sort_dir: "asc"
    }
  end

  defp normalize_filters(raw_filters, existing_filters) when is_map(raw_filters) do
    sort_field =
      LiveData.normalize_filter(raw_filters, :sort_field)
      |> normalize_sort_field(existing_filters.sort_field)

    sort_dir =
      LiveData.normalize_filter(raw_filters, :sort_dir)
      |> normalize_sort_dir(existing_filters.sort_dir)

    %{
      id: LiveData.normalize_filter(raw_filters, :id) || "",
      name: LiveData.normalize_filter(raw_filters, :name) || "",
      url: LiveData.normalize_filter(raw_filters, :url) || "",
      page: existing_filters.page,
      page_size: parse_positive_integer(Map.get(raw_filters, "page_size"), existing_filters.page_size),
      sort_field: sort_field,
      sort_dir: sort_dir
    }
  end

  defp normalize_filters(_raw_filters, existing_filters), do: existing_filters

  defp normalize_form(raw_form) when is_map(raw_form) do
    %{
      id: normalize_string(fetch_form(raw_form, :id)),
      name: normalize_string(fetch_form(raw_form, :name)),
      url: normalize_string(fetch_form(raw_form, :url)),
      retry_max_attempts: normalize_string(fetch_form(raw_form, :retry_max_attempts)),
      retry_backoff_ms: normalize_string(fetch_form(raw_form, :retry_backoff_ms))
    }
  end

  defp normalize_form(_raw_form), do: default_form()

  defp build_attrs(form, mode) do
    errors =
      %{}
      |> maybe_required(:id, form.id)
      |> maybe_required(:name, form.name)
      |> maybe_required(:url, form.url)
      |> maybe_required(:retry_max_attempts, form.retry_max_attempts)
      |> maybe_required(:retry_backoff_ms, form.retry_backoff_ms)

    errors =
      if mode == :edit do
        Map.delete(errors, :id)
      else
        errors
      end

    with true <- map_size(errors) == 0 || {:error, errors},
         {:ok, retry_max_attempts} <- parse_positive_integer(form.retry_max_attempts),
         {:ok, retry_backoff_ms} <- parse_positive_integer(form.retry_backoff_ms),
         normalized_url <- normalize_ws_url(form.url),
         true <- String.starts_with?(normalized_url, "ws://") ||
                   {:error, Map.put(errors, :url, "URL must use ws:// scheme.")} do
      {:ok,
       %{
         id: form.id,
         name: form.name,
         url: normalized_url,
         retry_policy: %{max_attempts: retry_max_attempts, backoff_ms: retry_backoff_ms},
         protocol_options: %{},
         metadata: %{}
       }}
    else
      {:error, %{} = validation_errors} -> {:error, validation_errors}
      {:error, _reason} -> {:error, Map.put(errors, :base, "Invalid numeric values.")}
      false -> {:error, Map.put(errors, :base, "Invalid form values.")}
    end
  end

  defp form_from_entry(entry) when is_map(entry) do
    %{
      id: fetch_nested(entry, :id) || "",
      name: fetch_nested(entry, :name) || "",
      url: fetch_nested(entry, :url) || "",
      retry_max_attempts: to_string(fetch_nested(entry.retry_policy, :max_attempts) || 3),
      retry_backoff_ms: to_string(fetch_nested(entry.retry_policy, :backoff_ms) || 1000)
    }
  end

  defp default_form do
    %{
      id: "",
      name: "",
      url: "ws://",
      retry_max_attempts: "3",
      retry_backoff_ms: "1000"
    }
  end

  defp form_errors_from_reason({:invalid_field, field, _reason}) when is_atom(field) do
    %{field => "Invalid value."}
  end

  defp form_errors_from_reason(_reason), do: %{}

  defp maybe_required(errors, key, value) do
    if is_binary(value) and String.trim(value) != "" do
      errors
    else
      Map.put(errors, key, "Must be a non-empty value.")
    end
  end

  defp fetch_form(form, key), do: Map.get(form, key) || Map.get(form, Atom.to_string(key)) || ""

  defp legacy_validate_form(form) do
    %{}
    |> maybe_add_legacy_required(:id, form.id)
    |> maybe_add_legacy_required(:name, form.name)
    |> maybe_add_legacy_url_error(form.url)
    |> maybe_add_legacy_positive_integer(:retry_max_attempts, form.retry_max_attempts)
    |> maybe_add_legacy_positive_integer(:retry_backoff_ms, form.retry_backoff_ms)
  end

  defp maybe_add_legacy_required(errors, key, value) do
    if is_binary(value) and String.trim(value) != "" do
      errors
    else
      Map.put(errors, key, "Must be a non-empty value.")
    end
  end

  defp maybe_add_legacy_url_error(errors, value) do
    normalized = normalize_ws_url(value)

    if String.starts_with?(normalized, "ws://") do
      errors
    else
      Map.put(errors, :url, "URL must use `ws://` in v1.")
    end
  end

  defp maybe_add_legacy_positive_integer(errors, key, value) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> errors
      _ -> Map.put(errors, key, "Must be a positive integer.")
    end
  end

  defp normalize_string(value), do: value |> to_string() |> String.trim()

  defp normalize_ws_url(url) do
    normalized = normalize_string(url)

    cond do
      normalized == "" -> ""
      String.contains?(normalized, "://") -> normalized
      true -> "ws://" <> normalized
    end
  end

  defp fetch_nested(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch_nested(_map, _key), do: nil

  defp pagination_from_page(page) do
    %{
      page: page.page || 1,
      page_size: page.page_size || 10,
      total_entries: page.total_entries || 0,
      total_pages: max(page.total_pages || 1, 1)
    }
  end

  defp sort_direction("desc"), do: -1
  defp sort_direction(_dir), do: 1

  defp normalize_sort_field(field, _fallback) when field in @sortable_fields, do: field
  defp normalize_sort_field(_field, fallback), do: fallback

  defp normalize_sort_dir("desc", _fallback), do: "desc"
  defp normalize_sort_dir("asc", _fallback), do: "asc"
  defp normalize_sort_dir(_dir, fallback), do: fallback

  defp parse_positive_integer(raw, default) when is_integer(default) and default > 0 do
    case Integer.parse(to_string(raw || "")) do
      {value, ""} when value > 0 -> value
      _ -> default
    end
  end

  defp parse_positive_integer(raw) do
    case Integer.parse(to_string(raw || "")) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_positive_integer}
    end
  end

  defp maybe_clear_selected(nil, _deleted_id), do: nil

  defp maybe_clear_selected(selected_entry, deleted_id) when is_map(selected_entry) do
    if fetch_nested(selected_entry, :id) == deleted_id, do: nil, else: selected_entry
  end

  defp maybe_clear_selected(selected_entry, _deleted_id), do: selected_entry
end
