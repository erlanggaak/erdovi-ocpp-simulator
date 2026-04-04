defmodule OcppSimulatorWeb.ScenariosLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageChargePoints
  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints
  alias OcppSimulator.Domain.Ocpp.PayloadTemplates
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @sortable_fields ["id", "name", "version", "schema_version"]

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    {page, feedback} = load_page(role, filters)
    {charge_point_options, endpoint_options} = load_reference_options(role)

    {:ok,
     assign(socket,
       current_role: role,
       current_path: "/scenarios",
       page_title: "Scenario Library",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: nil,
       form_mode: :create,
       form: default_form(),
       form_errors: %{},
       delete_candidate: nil,
       charge_point_options: charge_point_options,
       endpoint_options: endpoint_options
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
  def handle_event("select_detail", %{"id" => id}, socket) do
    role = socket.assigns.current_role

    case ManageScenarios.get_scenario(repository(), id, role) do
      {:ok, scenario} ->
        {:noreply, assign(socket, selected_entry: scenario, feedback: nil)}

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

    case ManageScenarios.get_scenario(repository(), id, role) do
      {:ok, scenario} ->
        {:noreply,
         assign(socket,
           form_mode: :edit,
           form: form_from_entry(scenario),
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
  def handle_event("save", %{"scenario" => raw_form}, socket) do
    role = socket.assigns.current_role
    mode = socket.assigns.form_mode
    form = normalize_form(raw_form)

    case build_attrs(form, mode) do
      {:ok, attrs} ->
        save_result =
          case mode do
            :create ->
              ManageScenarios.create_scenario(repository(), attrs, role)

            :edit ->
              ManageScenarios.update_scenario(repository(), form.id, attrs, role)
          end

        case save_result do
          {:ok, scenario} ->
            {page, _feedback} = load_page(role, socket.assigns.filters)

            {:noreply,
             assign(socket,
               entries: page.entries,
               pagination: pagination_from_page(page),
               selected_entry: scenario,
               form_mode: :create,
               form: default_form(),
               form_errors: %{},
               feedback:
                 if(mode == :create,
                   do: "Scenario was created successfully.",
                   else: "Scenario was updated successfully."
                 )
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               form: form,
               form_errors: form_errors_from_reason(reason),
               feedback: "Unable to save scenario: #{inspect(reason)}"
             )}
        end

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
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    role = socket.assigns.current_role

    case ManageScenarios.get_scenario(repository(), id, role) do
      {:ok, scenario} ->
        {:noreply, assign(socket, delete_candidate: scenario)}

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
      case ManageScenarios.delete_scenario(repository(), candidate.id, role) do
        :ok ->
          {page, _feedback} = load_page(role, socket.assigns.filters)

          {:noreply,
           assign(socket,
             entries: page.entries,
             pagination: pagination_from_page(page),
             selected_entry: maybe_clear_selected(socket.assigns.selected_entry, candidate.id),
             delete_candidate: nil,
             feedback: "Scenario was deleted successfully."
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             delete_candidate: nil,
             feedback: "Unable to delete scenario: #{inspect(reason)}"
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
      subtitle="Kelola scenario dengan filter, pagination, relasi dropdown, dan CRUD penuh."
      current_path={@current_path}
      current_role={@current_role}
      notice={@feedback}
      flash={@flash}
    >
      <section class="sim-section">
        <.form for={%{}} as={:filters} phx-submit="filter">
          <div class="sim-form-grid">
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

      <p class="sim-inline-link" :if={LiveData.can?(@permission_grants, :manage_scenarios)}>
        <.link navigate={~p"/scenario-builder"}>Open Scenario Builder</.link>
      </p>

      <%= if LiveData.can?(@permission_grants, :manage_scenarios) do %>
        <section class="sim-section">
          <div class="sim-row-between">
            <h2><%= if @form_mode == :create, do: "Add New Scenario", else: "Edit Scenario" %></h2>
            <button type="button" phx-click="begin_create" class="sim-button-secondary">New Form</button>
          </div>
          <.form
            for={%{}}
            as={:scenario}
            phx-submit="save"
            action={~p"/scenarios"}
            method="post"
          >
            <input type="hidden" name="scenario[form_mode]" value={Atom.to_string(@form_mode)} />
            <div class="sim-form-grid">
              <label>
                ID
                <input type="text" name="scenario[id]" value={@form.id} readonly={@form_mode == :edit} />
                <p :if={@form_errors[:id]} class="sim-error-text"><%= @form_errors[:id] %></p>
              </label>
              <label>
                Name
                <input type="text" name="scenario[name]" value={@form.name} />
                <p :if={@form_errors[:name]} class="sim-error-text"><%= @form_errors[:name] %></p>
              </label>
              <label>
                Version
                <input type="text" name="scenario[version]" value={@form.version} />
                <p :if={@form_errors[:version]} class="sim-error-text"><%= @form_errors[:version] %></p>
              </label>
              <label>
                Charge Point (from backend API)
                <select name="scenario[charge_point_id]" value={@form.charge_point_id}>
                  <option value="">-- none --</option>
                  <option
                    :for={option <- @charge_point_options}
                    value={option.id}
                    selected={@form.charge_point_id == option.id}
                  >
                    <%= option.label %>
                  </option>
                </select>
              </label>
              <label>
                Target Endpoint (from backend API)
                <select name="scenario[target_endpoint_id]" value={@form.target_endpoint_id}>
                  <option value="">-- none --</option>
                  <option
                    :for={option <- @endpoint_options}
                    value={option.id}
                    selected={@form.target_endpoint_id == option.id}
                  >
                    <%= option.label %>
                  </option>
                </select>
              </label>
            </div>
            <label>
              Steps JSON
              <textarea name="scenario[steps_json]" rows="12"><%= @form.steps_json %></textarea>
              <p :if={@form_errors[:steps_json]} class="sim-error-text"><%= @form_errors[:steps_json] %></p>
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
                <th>Schema</th>
                <th>Steps</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @entries}>
                <td><%= entry.id %></td>
                <td><%= entry.name %></td>
                <td><%= entry.version %></td>
                <td><%= entry.schema_version %></td>
                <td><%= length(entry.steps) %></td>
                <td>
                  <div class="sim-actions">
                    <button type="button" phx-click="select_detail" phx-value-id={entry.id}>Detail</button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_scenarios)}
                      type="button"
                      phx-click="begin_edit"
                      phx-value-id={entry.id}
                    >
                      Edit
                    </button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_scenarios)}
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
                <td colspan="6">No scenario found for current filter.</td>
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
          <p><strong>Schema Version:</strong> <%= @selected_entry.schema_version %></p>
          <p><strong>Step Count:</strong> <%= length(@selected_entry.steps) %></p>
          <p>
            <strong>Charge Point Ref:</strong>
            <%= extract_variable(@selected_entry.variables, "charge_point_id") || "-" %>
          </p>
          <p>
            <strong>Target Endpoint Ref:</strong>
            <%= extract_variable(@selected_entry.variables, "target_endpoint_id") || "-" %>
          </p>
        </div>
      </section>

      <div :if={@delete_candidate} class="sim-modal-backdrop">
        <section class="sim-modal">
          <h2>Delete Scenario</h2>
          <p>
            Scenario <strong><%= @delete_candidate.id %></strong> akan dihapus permanen. Lanjutkan?
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
      :scenario_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
    )
  end

  defp charge_point_repository do
    LiveData.repository(
      :charge_point_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
    )
  end

  defp target_endpoint_repository do
    LiveData.repository(
      :target_endpoint_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
    )
  end

  defp load_page(role, filters) do
    payload =
      filters
      |> Map.take([:id, :name, :version, :page, :page_size])
      |> Map.put(:sort, %{filters.sort_field => sort_direction(filters.sort_dir)})
      |> LiveData.compact_filters()

    case ManageScenarios.list_scenarios(repository(), role, payload) do
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
         "Unable to load scenarios: #{inspect(reason)}"}
    end
  end

  defp load_reference_options(role) do
    charge_point_options =
      case ManageChargePoints.list_charge_points(charge_point_repository(), role, %{
             page: 1,
             page_size: 200
           }) do
        {:ok, %{entries: entries}} when is_list(entries) ->
          Enum.map(entries, fn cp ->
            %{id: cp.id, label: "#{cp.id} (#{cp.vendor}/#{cp.model})"}
          end)

        _ ->
          []
      end

    endpoint_options =
      case ManageTargetEndpoints.list_target_endpoints(target_endpoint_repository(), role, %{
             page: 1,
             page_size: 200
           }) do
        {:ok, %{entries: entries}} when is_list(entries) ->
          Enum.map(entries, fn endpoint ->
            %{id: endpoint.id, label: "#{endpoint.id} (#{endpoint.url})"}
          end)

        _ ->
          []
      end

    {charge_point_options, endpoint_options}
  end

  defp default_filters do
    %{
      id: "",
      name: "",
      version: "",
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
      version: LiveData.normalize_filter(raw_filters, :version) || "",
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
      charge_point_id: normalize_string(fetch_form(raw_form, :charge_point_id)),
      target_endpoint_id: normalize_string(fetch_form(raw_form, :target_endpoint_id)),
      steps_json: normalize_multiline(fetch_form(raw_form, :steps_json))
    }
  end

  defp normalize_form(_raw_form), do: default_form()

  defp build_attrs(form, mode) do
    errors =
      %{}
      |> maybe_required(:id, form.id)
      |> maybe_required(:name, form.name)
      |> maybe_required(:version, form.version)
      |> maybe_required(:steps_json, form.steps_json)

    errors =
      if mode == :edit do
        Map.delete(errors, :id)
      else
        errors
      end

    with true <- map_size(errors) == 0 || {:error, errors},
         {:ok, steps} <- parse_steps_json(form.steps_json) do
      variables =
        %{}
        |> maybe_put_variable("charge_point_id", form.charge_point_id)
        |> maybe_put_variable("target_endpoint_id", form.target_endpoint_id)

      {:ok,
       %{
         id: form.id,
         name: form.name,
         version: form.version,
         schema_version: "1.0",
         variables: variables,
         variable_scopes: Scenario.default_variable_scopes(),
         validation_policy: Scenario.validation_policy_defaults(),
         steps: steps
       }}
    else
      {:error, %{} = validation_errors} ->
        {:error, validation_errors}

      {:error, _reason} ->
        {:error, Map.put(errors, :steps_json, "Steps JSON must be a valid array.")}

      false ->
        {:error, Map.put(errors, :base, "Invalid form values.")}
    end
  end

  defp form_from_entry(%Scenario{} = scenario) do
    %{
      id: scenario.id,
      name: scenario.name,
      version: scenario.version,
      charge_point_id: extract_variable(scenario.variables, "charge_point_id") || "",
      target_endpoint_id: extract_variable(scenario.variables, "target_endpoint_id") || "",
      steps_json: Jason.encode!(Enum.map(scenario.steps, &step_to_map/1), pretty: true)
    }
  end

  defp default_form do
    %{
      id: "",
      name: "",
      version: "1.0.0",
      charge_point_id: "",
      target_endpoint_id: "",
      steps_json:
        Jason.encode!(
          [
            %{
              "id" => "boot",
              "type" => "send_action",
              "order" => 1,
              "payload" => PayloadTemplates.send_action_step_payload("BootNotification"),
              "delay_ms" => 0,
              "loop_count" => 1,
              "enabled" => true
            }
          ],
          pretty: true
        )
    }
  end

  defp parse_steps_json(raw_json) when is_binary(raw_json) do
    case Jason.decode(raw_json) do
      {:ok, steps} when is_list(steps) -> {:ok, steps}
      {:ok, _decoded} -> {:error, :not_array}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp parse_steps_json(_raw_json), do: {:error, :invalid_json}

  defp maybe_put_variable(vars, _key, ""), do: vars
  defp maybe_put_variable(vars, _key, nil), do: vars
  defp maybe_put_variable(vars, key, value), do: Map.put(vars, key, value)

  defp step_to_map(step) do
    %{
      "id" => step.id,
      "type" => Atom.to_string(step.type),
      "order" => step.order,
      "payload" => step.payload,
      "delay_ms" => step.delay_ms,
      "loop_count" => step.loop_count,
      "enabled" => step.enabled
    }
  end

  defp extract_variable(vars, key) when is_map(vars) do
    Map.get(vars, key) || Map.get(vars, String.to_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp extract_variable(_vars, _key), do: nil

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

  defp maybe_clear_selected(%Scenario{id: id}, id), do: nil

  defp maybe_clear_selected(selected_entry, _deleted_id), do: selected_entry
end
