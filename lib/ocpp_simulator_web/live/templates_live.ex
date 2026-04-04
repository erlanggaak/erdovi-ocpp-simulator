defmodule OcppSimulatorWeb.TemplatesLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Domain.Ocpp.PayloadTemplates
  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @sortable_fields ["id", "name", "version", "type"]
  @template_types ["action", "scenario"]

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    {page, feedback} = load_page(role, filters)
    scenario_options = load_scenario_options(role)

    {:ok,
     assign(socket,
       current_role: role,
       current_path: "/templates",
       page_title: "Template Library",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: nil,
       form_mode: :create,
       form: default_form(),
       form_errors: %{},
       delete_candidate: nil,
       scenario_options: scenario_options
     )}
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
  def handle_event("select_detail", %{"id" => id, "type" => type}, socket) do
    role = socket.assigns.current_role

    with {:ok, template_type} <- normalize_template_type(type),
         {:ok, template} <-
           ManageScenarios.get_template(repository(), id, template_type, role) do
      {:noreply, assign(socket, selected_entry: template, feedback: nil)}
    else
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
  def handle_event("begin_edit", %{"id" => id, "type" => type}, socket) do
    role = socket.assigns.current_role

    with {:ok, template_type} <- normalize_template_type(type),
         {:ok, template} <- ManageScenarios.get_template(repository(), id, template_type, role) do
      {:noreply,
       assign(socket,
         form_mode: :edit,
         form: form_from_entry(template),
         form_errors: %{}
       )}
    else
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
  def handle_event("save", %{"template" => raw_form}, socket) do
    role = socket.assigns.current_role
    form = normalize_form(raw_form)

    case build_attrs(form, socket.assigns.form_mode) do
      {:ok, attrs, :action} ->
        persist_template(socket, role, form, fn ->
          ManageScenarios.upsert_action_template(repository(), attrs, role)
        end)

      {:ok, attrs, :scenario} ->
        persist_template(socket, role, form, fn ->
          ManageScenarios.upsert_scenario_template(repository(), attrs, role)
        end)

      {:error, errors} ->
        {:noreply,
         assign(socket,
           form: form,
           form_errors: errors,
           feedback: "Please fix validation errors before submitting."
         )}
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id, "type" => type}, socket) do
    role = socket.assigns.current_role

    with {:ok, template_type} <- normalize_template_type(type),
         {:ok, template} <- ManageScenarios.get_template(repository(), id, template_type, role) do
      {:noreply, assign(socket, delete_candidate: template)}
    else
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
      with {:ok, template_type} <- normalize_template_type(fetch_nested(candidate, :type)),
           :ok <- ManageScenarios.delete_template(repository(), candidate.id, template_type, role) do
        {page, _feedback} = load_page(role, socket.assigns.filters)

        {:noreply,
         assign(socket,
           entries: page.entries,
           pagination: pagination_from_page(page),
           selected_entry: maybe_clear_selected(socket.assigns.selected_entry, candidate.id),
           delete_candidate: nil,
           feedback: "Template was deleted successfully."
         )}
      else
        {:error, reason} ->
          {:noreply,
           assign(socket,
             delete_candidate: nil,
             feedback: "Unable to delete template: #{inspect(reason)}"
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
      subtitle="Kelola template dengan filter/order/pagination dan CRUD penuh."
      current_path={@current_path}
      current_role={@current_role}
      notice={@feedback}
      flash={@flash}
    >
      <section class="sim-section">
        <.form for={%{}} as={:filters} phx-submit="filter">
          <div class="sim-form-grid">
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
              <select name="filters[type]" value={@filters.type}>
                <option value="">-- all --</option>
                <option :for={type <- template_types()} value={type} selected={@filters.type == type}>
                  <%= type %>
                </option>
              </select>
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

      <%= if LiveData.can?(@permission_grants, :manage_templates) do %>
        <section class="sim-section">
          <div class="sim-row-between">
            <h2><%= if @form_mode == :create, do: "Add New Template", else: "Edit Template" %></h2>
            <button type="button" phx-click="begin_create" class="sim-button-secondary">New Form</button>
          </div>
          <.form
            for={%{}}
            as={:template}
            phx-submit="save"
            action={~p"/templates"}
            method="post"
          >
            <input type="hidden" name="template[form_mode]" value={Atom.to_string(@form_mode)} />
            <div class="sim-form-grid">
              <label>
                ID
                <input type="text" name="template[id]" value={@form.id} readonly={@form_mode == :edit} />
                <p :if={@form_errors[:id]} class="sim-error-text"><%= @form_errors[:id] %></p>
              </label>
              <label>
                Name
                <input type="text" name="template[name]" value={@form.name} />
                <p :if={@form_errors[:name]} class="sim-error-text"><%= @form_errors[:name] %></p>
              </label>
              <label>
                Version
                <input type="text" name="template[version]" value={@form.version} />
                <p :if={@form_errors[:version]} class="sim-error-text"><%= @form_errors[:version] %></p>
              </label>
              <label>
                Type
                <select name="template[type]" value={@form.type} disabled={@form_mode == :edit}>
                  <option :for={type <- template_types()} value={type} selected={@form.type == type}>
                    <%= type %>
                  </option>
                </select>
                <input :if={@form_mode == :edit} type="hidden" name="template[type]" value={@form.type} />
              </label>
              <label>
                Source Scenario (from backend API)
                <select name="template[source_scenario_id]" value={@form.source_scenario_id}>
                  <option value="">-- none --</option>
                  <option
                    :for={option <- @scenario_options}
                    value={option.id}
                    selected={@form.source_scenario_id == option.id}
                  >
                    <%= option.label %>
                  </option>
                </select>
              </label>
            </div>
            <label>
              Payload Template JSON
              <textarea name="template[payload_template_json]" rows="10"><%= @form.payload_template_json %></textarea>
              <p :if={@form_errors[:payload_template_json]} class="sim-error-text">
                <%= @form_errors[:payload_template_json] %>
              </p>
            </label>
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
                <th>Version</th>
                <th>Type</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @entries}>
                <td><%= entry.id %></td>
                <td><%= entry.name %></td>
                <td><%= entry.version %></td>
                <td><%= entry.type %></td>
                <td>
                  <div class="sim-actions">
                    <button
                      type="button"
                      phx-click="select_detail"
                      phx-value-id={entry.id}
                      phx-value-type={entry.type}
                    >
                      Detail
                    </button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_templates)}
                      type="button"
                      phx-click="begin_edit"
                      phx-value-id={entry.id}
                      phx-value-type={entry.type}
                    >
                      Edit
                    </button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_templates)}
                      type="button"
                      phx-click="confirm_delete"
                      phx-value-id={entry.id}
                      phx-value-type={entry.type}
                      class="sim-button-danger"
                    >
                      Delete
                    </button>
                  </div>
                </td>
              </tr>
              <tr :if={Enum.empty?(@entries)}>
                <td colspan="5">No template found for current filter.</td>
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
          <p><strong>Version:</strong> <%= @selected_entry.version %></p>
          <p><strong>Type:</strong> <%= @selected_entry.type %></p>
          <p>
            <strong>Source Scenario Ref:</strong>
            <%= extract_metadata(@selected_entry.metadata, "source_scenario_id") || "-" %>
          </p>
        </div>
      </section>

      <div :if={@delete_candidate} class="sim-modal-backdrop">
        <section class="sim-modal">
          <h2>Delete Template</h2>
          <p>
            Template <strong><%= @delete_candidate.id %></strong> akan dihapus permanen. Lanjutkan?
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

  defp repository do
    LiveData.repository(
      :template_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
    )
  end

  defp scenario_repository do
    LiveData.repository(
      :scenario_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
    )
  end

  defp sortable_fields, do: @sortable_fields
  defp template_types, do: @template_types

  defp load_page(role, filters) do
    payload =
      filters
      |> Map.take([:id, :name, :type, :page, :page_size])
      |> Map.put(:sort, %{filters.sort_field => sort_direction(filters.sort_dir)})
      |> LiveData.compact_filters()

    case ManageScenarios.list_templates(repository(), role, payload) do
      {:ok, %{entries: entries} = page} when is_list(entries) ->
        {page, nil}

      {:ok, entries} when is_list(entries) ->
        {%{
           entries: entries,
           page: 1,
           page_size: filters.page_size,
           total_entries: length(entries),
           total_pages: 1
         }, nil}

      {:error, reason} ->
        {%{entries: [], page: 1, page_size: filters.page_size, total_entries: 0, total_pages: 1},
         "Unable to load templates: #{inspect(reason)}"}
    end
  end

  defp load_scenario_options(role) do
    case ManageScenarios.list_scenarios(scenario_repository(), role, %{page: 1, page_size: 200}) do
      {:ok, %{entries: entries}} when is_list(entries) ->
        Enum.map(entries, fn scenario ->
          %{id: scenario.id, label: "#{scenario.id} (#{scenario.name})"}
        end)

      _ ->
        []
    end
  end

  defp default_filters do
    %{
      id: "",
      name: "",
      type: "",
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
      type: LiveData.normalize_filter(raw_filters, :type) || "",
      page: existing_filters.page,
      page_size:
        parse_positive_integer(Map.get(raw_filters, "page_size"), existing_filters.page_size),
      sort_field: sort_field,
      sort_dir: sort_dir
    }
  end

  defp normalize_filters(_raw_filters, existing_filters), do: existing_filters

  defp normalize_form(raw_form) when is_map(raw_form) do
    %{
      id: normalize_string(fetch_form(raw_form, :id)),
      name: normalize_string(fetch_form(raw_form, :name)),
      version: normalize_string(fetch_form(raw_form, :version)),
      type: normalize_string(fetch_form(raw_form, :type)),
      source_scenario_id: normalize_string(fetch_form(raw_form, :source_scenario_id)),
      payload_template_json: normalize_multiline(fetch_form(raw_form, :payload_template_json))
    }
  end

  defp normalize_form(_raw_form), do: default_form()

  defp build_attrs(form, mode) do
    errors =
      %{}
      |> maybe_required(:id, form.id)
      |> maybe_required(:name, form.name)
      |> maybe_required(:version, form.version)
      |> maybe_required(:type, form.type)
      |> maybe_required(:payload_template_json, form.payload_template_json)

    errors =
      if mode == :edit do
        Map.delete(errors, :id)
      else
        errors
      end

    with true <- map_size(errors) == 0 || {:error, errors},
         {:ok, template_type} <- normalize_template_type(form.type),
         {:ok, payload_template} <- parse_payload_template_json(form.payload_template_json) do
      metadata =
        %{}
        |> maybe_put_metadata("source_scenario_id", form.source_scenario_id)

      attrs = %{
        id: form.id,
        name: form.name,
        version: form.version,
        type: template_type,
        payload_template: payload_template,
        metadata: metadata
      }

      {:ok, attrs, template_type}
    else
      {:error, %{} = validation_errors} ->
        {:error, validation_errors}

      {:error, _reason} ->
        {:error,
         Map.put(errors, :payload_template_json, "Payload template must be valid JSON object.")}

      false ->
        {:error, Map.put(errors, :base, "Invalid form values.")}
    end
  end

  defp persist_template(socket, role, form, save_fun) when is_function(save_fun, 0) do
    case save_fun.() do
      {:ok, template} ->
        {page, _feedback} = load_page(role, socket.assigns.filters)

        {:noreply,
         assign(socket,
           entries: page.entries,
           pagination: pagination_from_page(page),
           selected_entry: template,
           form_mode: :create,
           form: default_form(),
           form_errors: %{},
           feedback:
             if(socket.assigns.form_mode == :create,
               do: "Template was created successfully.",
               else: "Template was updated successfully."
             )
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           form: form,
           form_errors: form_errors_from_reason(reason),
           feedback: "Unable to save template: #{inspect(reason)}"
         )}
    end
  end

  defp form_from_entry(entry) when is_map(entry) do
    %{
      id: fetch_nested(entry, :id) || "",
      name: fetch_nested(entry, :name) || "",
      version: fetch_nested(entry, :version) || "",
      type: normalize_template_type_string(fetch_nested(entry, :type) || :action),
      source_scenario_id:
        extract_metadata(fetch_nested(entry, :metadata), "source_scenario_id") || "",
      payload_template_json:
        Jason.encode!(fetch_nested(entry, :payload_template) || %{}, pretty: true)
    }
  end

  defp default_form do
    %{
      id: "",
      name: "",
      version: "1.0.0",
      type: "action",
      source_scenario_id: "",
      payload_template_json:
        Jason.encode!(PayloadTemplates.send_action_step_payload("Heartbeat"), pretty: true)
    }
  end

  defp parse_payload_template_json(raw_json) when is_binary(raw_json) do
    case Jason.decode(raw_json) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _decoded} -> {:error, :not_object}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp parse_payload_template_json(_raw_json), do: {:error, :invalid_json}

  defp normalize_template_type(:action), do: {:ok, :action}
  defp normalize_template_type(:scenario), do: {:ok, :scenario}
  defp normalize_template_type("action"), do: {:ok, :action}
  defp normalize_template_type("scenario"), do: {:ok, :scenario}
  defp normalize_template_type(_type), do: {:error, :invalid_template_type}

  defp normalize_template_type_string(type) do
    case normalize_template_type(type) do
      {:ok, :scenario} -> "scenario"
      _ -> "action"
    end
  end

  defp maybe_put_metadata(metadata, _key, ""), do: metadata
  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp extract_metadata(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp extract_metadata(_metadata, _key), do: nil

  defp fetch_nested(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch_nested(_map, _key), do: nil

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

  defp normalize_string(value), do: value |> to_string() |> String.trim()

  defp normalize_multiline(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> ""
      normalized -> normalized <> "\n"
    end
  end

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

  defp maybe_clear_selected(nil, _deleted_id), do: nil

  defp maybe_clear_selected(selected_entry, deleted_id) when is_map(selected_entry) do
    if fetch_nested(selected_entry, :id) == deleted_id, do: nil, else: selected_entry
  end

  defp maybe_clear_selected(selected_entry, _deleted_id), do: selected_entry
end
