defmodule OcppSimulatorWeb.ChargePointsLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageChargePoints
  alias OcppSimulator.Domain.ChargePoints.ChargePoint
  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @sortable_fields ["id", "vendor", "model", "firmware_version", "behavior_profile"]

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns[:current_role] || :viewer
    filters = default_filters()
    {page, feedback} = load_page(role, filters)

    {:ok,
     assign(socket,
       current_role: role,
       current_path: "/charge-points",
       page_title: "Charge Point Registry",
       filters: filters,
       entries: page.entries,
       pagination: pagination_from_page(page),
       feedback: feedback,
       selected_entry: nil,
       form_mode: :create,
       form: default_form(),
       form_errors: %{},
       delete_candidate: nil
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

    case ManageChargePoints.get_charge_point(repository(), id, role) do
      {:ok, charge_point} ->
        {:noreply, assign(socket, selected_entry: charge_point, feedback: nil)}

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

    case ManageChargePoints.get_charge_point(repository(), id, role) do
      {:ok, charge_point} ->
        {:noreply,
         assign(socket,
           form_mode: :edit,
           form: form_from_entry(charge_point),
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
  def handle_event("create_charge_point", %{"charge_point" => raw_form}, socket) do
    socket = assign(socket, form_mode: :create)
    handle_event("save", %{"charge_point" => raw_form}, socket)
  end

  @impl true
  def handle_event("save", %{"charge_point" => raw_form}, socket) do
    role = socket.assigns.current_role
    mode = socket.assigns.form_mode
    form = normalize_form(raw_form)

    case build_attrs(form, mode) do
      {:ok, attrs} ->
        save_result =
          case mode do
            :create ->
              ManageChargePoints.register_charge_point(repository(), attrs, role)

            :edit ->
              ManageChargePoints.update_charge_point(repository(), form.id, attrs, role)
          end

        case save_result do
          {:ok, charge_point} ->
            {page, _feedback} = load_page(role, socket.assigns.filters)

            {:noreply,
             assign(socket,
               entries: page.entries,
               pagination: pagination_from_page(page),
               selected_entry: charge_point,
               form_mode: :create,
               form: default_form(),
               form_errors: %{},
               feedback:
                 if(mode == :create,
                   do: "Charge point was created successfully.",
                   else: "Charge point was updated successfully."
                 )
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               form: form,
               form_errors: form_errors_from_reason(reason),
               feedback: "Unable to save charge point: #{inspect(reason)}"
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

    case ManageChargePoints.get_charge_point(repository(), id, role) do
      {:ok, charge_point} ->
        {:noreply, assign(socket, delete_candidate: charge_point)}

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
      case ManageChargePoints.delete_charge_point(repository(), candidate.id, role) do
        :ok ->
          {page, _feedback} = load_page(role, socket.assigns.filters)

          {:noreply,
           assign(socket,
             entries: page.entries,
             pagination: pagination_from_page(page),
             selected_entry: maybe_clear_selected(socket.assigns.selected_entry, candidate.id),
             delete_candidate: nil,
             feedback: "Charge point was deleted successfully."
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             delete_candidate: nil,
             feedback: "Unable to delete charge point: #{inspect(reason)}"
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
      subtitle="Kelola seluruh charge point instance dengan CRUD lengkap."
      current_path={@current_path}
      current_role={@current_role}
      notice={@feedback}
      flash={@flash}
    >
      <section class="sim-section">
        <.form for={%{}} as={:filters} phx-submit="filter">
          <div class="sim-form-grid">
            <label>
              Search ID
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
              Behavior
              <input type="text" name="filters[behavior_profile]" value={@filters.behavior_profile} />
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

      <%= if LiveData.can?(@permission_grants, :manage_charge_points) do %>
        <section class="sim-section">
          <div class="sim-row-between">
            <h2><%= if @form_mode == :create, do: "Add New Charge Point", else: "Edit Charge Point" %></h2>
            <button type="button" phx-click="begin_create" class="sim-button-secondary">New Form</button>
          </div>
          <.form
            for={%{}}
            as={:charge_point}
            phx-submit="save"
            action={~p"/charge-points"}
            method="post"
          >
            <div class="sim-form-grid">
              <label>
                ID
                <input type="text" name="charge_point[id]" value={@form.id} readonly={@form_mode == :edit} />
                <p :if={@form_errors[:id]} class="sim-error-text"><%= @form_errors[:id] %></p>
              </label>
              <label>
                Vendor
                <input type="text" name="charge_point[vendor]" value={@form.vendor} />
                <p :if={@form_errors[:vendor]} class="sim-error-text"><%= @form_errors[:vendor] %></p>
              </label>
              <label>
                Model
                <input type="text" name="charge_point[model]" value={@form.model} />
                <p :if={@form_errors[:model]} class="sim-error-text"><%= @form_errors[:model] %></p>
              </label>
              <label>
                Firmware Version
                <input
                  type="text"
                  name="charge_point[firmware_version]"
                  value={@form.firmware_version}
                />
                <p :if={@form_errors[:firmware_version]} class="sim-error-text">
                  <%= @form_errors[:firmware_version] %>
                </p>
              </label>
              <label>
                Connector Count
                <input
                  type="number"
                  min="1"
                  name="charge_point[connector_count]"
                  value={@form.connector_count}
                />
                <p :if={@form_errors[:connector_count]} class="sim-error-text">
                  <%= @form_errors[:connector_count] %>
                </p>
              </label>
              <label>
                Heartbeat (seconds)
                <input
                  type="number"
                  min="1"
                  name="charge_point[heartbeat_interval_seconds]"
                  value={@form.heartbeat_interval_seconds}
                />
                <p :if={@form_errors[:heartbeat_interval_seconds]} class="sim-error-text">
                  <%= @form_errors[:heartbeat_interval_seconds] %>
                </p>
              </label>
              <label>
                Behavior Profile
                <select name="charge_point[behavior_profile]" value={@form.behavior_profile}>
                  <option value="default" selected={@form.behavior_profile == "default"}>default</option>
                  <option
                    value="intermittent_disconnects"
                    selected={@form.behavior_profile == "intermittent_disconnects"}
                  >
                    intermittent_disconnects
                  </option>
                  <option value="faulted" selected={@form.behavior_profile == "faulted"}>faulted</option>
                </select>
                <p :if={@form_errors[:behavior_profile]} class="sim-error-text">
                  <%= @form_errors[:behavior_profile] %>
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
                <th>Vendor</th>
                <th>Model</th>
                <th>Firmware</th>
                <th>Connectors</th>
                <th>Heartbeat</th>
                <th>Behavior</th>
                <th>Actions</th>
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
                <td>
                  <div class="sim-actions">
                    <button type="button" phx-click="select_detail" phx-value-id={entry.id}>Detail</button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_charge_points)}
                      type="button"
                      phx-click="begin_edit"
                      phx-value-id={entry.id}
                    >
                      Edit
                    </button>
                    <button
                      :if={LiveData.can?(@permission_grants, :manage_charge_points)}
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
                <td colspan="8">No charge point found for current filter.</td>
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
          <p><strong>Vendor:</strong> <%= @selected_entry.vendor %></p>
          <p><strong>Model:</strong> <%= @selected_entry.model %></p>
          <p><strong>Firmware:</strong> <%= @selected_entry.firmware_version %></p>
          <p><strong>Connector Count:</strong> <%= @selected_entry.connector_count %></p>
          <p><strong>Heartbeat:</strong> <%= @selected_entry.heartbeat_interval_seconds %></p>
          <p><strong>Behavior:</strong> <%= @selected_entry.behavior_profile %></p>
        </div>
      </section>

      <div :if={@delete_candidate} class="sim-modal-backdrop">
        <section class="sim-modal">
          <h2>Delete Charge Point</h2>
          <p>
            Data <strong><%= @delete_candidate.id %></strong> akan dihapus permanen. Lanjutkan?
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
      :charge_point_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
    )
  end

  defp load_page(role, filters) do
    payload =
      filters
      |> Map.take([:id, :vendor, :model, :behavior_profile, :page, :page_size])
      |> Map.put(:sort, %{filters.sort_field => sort_direction(filters.sort_dir)})
      |> LiveData.compact_filters()

    case ManageChargePoints.list_charge_points(repository(), role, payload) do
      {:ok, %{entries: entries} = page} when is_list(entries) ->
        {page, nil}

      {:ok, entries} when is_list(entries) ->
        {%{entries: entries, page: 1, page_size: filters.page_size, total_entries: length(entries), total_pages: 1},
         nil}

      {:error, reason} ->
        {%{entries: [], page: 1, page_size: filters.page_size, total_entries: 0, total_pages: 1},
         "Unable to load charge points: #{inspect(reason)}"}
    end
  end

  defp default_filters do
    %{
      id: "",
      vendor: "",
      model: "",
      behavior_profile: "",
      page: 1,
      page_size: 10,
      sort_field: "id",
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
      vendor: LiveData.normalize_filter(raw_filters, :vendor) || "",
      model: LiveData.normalize_filter(raw_filters, :model) || "",
      behavior_profile: LiveData.normalize_filter(raw_filters, :behavior_profile) || "",
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
      vendor: normalize_string(fetch_form(raw_form, :vendor)),
      model: normalize_string(fetch_form(raw_form, :model)),
      firmware_version: normalize_string(fetch_form(raw_form, :firmware_version)),
      connector_count: normalize_string(fetch_form(raw_form, :connector_count)),
      heartbeat_interval_seconds: normalize_string(fetch_form(raw_form, :heartbeat_interval_seconds)),
      behavior_profile: normalize_string(fetch_form(raw_form, :behavior_profile))
    }
  end

  defp normalize_form(_raw_form), do: default_form()

  defp build_attrs(form, mode) do
    errors =
      %{}
      |> maybe_required(:id, form.id)
      |> maybe_required(:vendor, form.vendor)
      |> maybe_required(:model, form.model)
      |> maybe_required(:firmware_version, form.firmware_version)
      |> maybe_required(:connector_count, form.connector_count)
      |> maybe_required(:heartbeat_interval_seconds, form.heartbeat_interval_seconds)
      |> maybe_required(:behavior_profile, form.behavior_profile)

    errors =
      if mode == :edit do
        Map.delete(errors, :id)
      else
        errors
      end

    with true <- map_size(errors) == 0 || {:error, errors},
         {:ok, connector_count} <- parse_positive_integer(form.connector_count),
         {:ok, heartbeat_interval_seconds} <- parse_positive_integer(form.heartbeat_interval_seconds),
         true <- form.behavior_profile in ["default", "intermittent_disconnects", "faulted"] ||
                   {:error, Map.put(errors, :behavior_profile, "Unsupported behavior profile.")} do
      {:ok,
       %{
         id: form.id,
         vendor: form.vendor,
         model: form.model,
         firmware_version: form.firmware_version,
         connector_count: connector_count,
         heartbeat_interval_seconds: heartbeat_interval_seconds,
         behavior_profile: form.behavior_profile
       }}
    else
      {:error, %{} = validation_errors} -> {:error, validation_errors}
      {:error, _reason} -> {:error, Map.put(errors, :base, "Invalid numeric values.")}
      false -> {:error, Map.put(errors, :base, "Invalid form values.")}
    end
  end

  defp form_from_entry(%ChargePoint{} = entry) do
    %{
      id: entry.id,
      vendor: entry.vendor,
      model: entry.model,
      firmware_version: entry.firmware_version,
      connector_count: Integer.to_string(entry.connector_count),
      heartbeat_interval_seconds: Integer.to_string(entry.heartbeat_interval_seconds),
      behavior_profile: Atom.to_string(entry.behavior_profile)
    }
  end

  defp default_form do
    %{
      id: "",
      vendor: "",
      model: "",
      firmware_version: "",
      connector_count: "1",
      heartbeat_interval_seconds: "60",
      behavior_profile: "default"
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

  defp normalize_string(value), do: value |> to_string() |> String.trim()

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

  defp maybe_clear_selected(%ChargePoint{id: id}, id), do: nil

  defp maybe_clear_selected(selected_entry, _deleted_id), do: selected_entry
end
