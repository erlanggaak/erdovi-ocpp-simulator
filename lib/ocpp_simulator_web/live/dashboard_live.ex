defmodule OcppSimulatorWeb.DashboardLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageChargePoints
  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints
  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Application.UseCases.StarterTemplates
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @role_order [:viewer, :operator, :admin]

  @impl true
  def mount(_params, session, socket) do
    role =
      socket.assigns[:current_role] || LiveData.normalize_role(Map.get(session, "current_role"))

    socket =
      socket
      |> assign(
        current_role: role,
        permission_grants: socket.assigns[:permission_grants] || %{},
        role_order: @role_order,
        current_path: "/dashboard",
        page_title: "Simulator Control Center",
        notice: nil,
        data_warning: nil,
        max_concurrent_runs: OcppSimulator.runtime_config()[:max_concurrent_runs],
        max_active_sessions: OcppSimulator.runtime_config()[:max_active_sessions],
        stats: %{},
        scenarios: [],
        templates: [],
        charge_points: [],
        target_endpoints: [],
        runs: [],
        logs: [],
        logs_run_id: "",
        scenario_form: default_scenario_form(),
        run_form: default_run_form(),
        charge_point_form: default_charge_point_form(),
        endpoint_form: default_endpoint_form()
      )
      |> refresh_dashboard_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    {:noreply, refresh_dashboard_data(socket, notice: "Dashboard data refreshed.")}
  end

  @impl true
  def handle_event("create_scenario", %{"scenario" => raw_form}, socket) do
    role = socket.assigns.current_role
    scenario_form = normalize_scenario_form(raw_form)

    with {:ok, attrs} <- build_scenario_attrs(scenario_form),
         {:ok, scenario} <- ManageScenarios.create_scenario(scenario_repository(), attrs, role) do
      socket =
        assign(socket,
          scenario_form: default_scenario_form(),
          run_form: Map.put(socket.assigns.run_form, :scenario_id, scenario.id)
        )

      {:noreply,
       refresh_dashboard_data(socket,
         notice:
           "Scenario `#{scenario.id}` created. You can run it from the Run Orchestrator card."
       )}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(scenario_form: scenario_form)
         |> refresh_dashboard_data(notice: "Scenario creation failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_run", %{"run" => raw_form}, socket) do
    role = socket.assigns.current_role
    run_form = normalize_run_form(raw_form)

    with {:ok, run_attrs} <- build_start_run_attrs(run_form),
         {:ok, run} <- RunScenario.start_run(start_dependencies(), run_attrs, role),
         {:ok, execution_message} <- maybe_execute_run_after_start(run.id, role, run_form) do
      {:noreply,
       socket
       |> assign(run_form: run_form)
       |> refresh_dashboard_data(
         notice: "Run `#{run.id}` queued. #{execution_message}",
         logs_run_id: run.id
       )}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(run_form: run_form)
         |> refresh_dashboard_data(notice: "Run request failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("create_charge_point", %{"charge_point" => raw_form}, socket) do
    role = socket.assigns.current_role
    charge_point_form = normalize_charge_point_form(raw_form)

    with {:ok, attrs} <- build_charge_point_attrs(charge_point_form),
         {:ok, charge_point} <-
           ManageChargePoints.register_charge_point(charge_point_repository(), attrs, role) do
      {:noreply,
       socket
       |> assign(charge_point_form: default_charge_point_form())
       |> refresh_dashboard_data(notice: "Charge point `#{charge_point.id}` created.")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(charge_point_form: charge_point_form)
         |> refresh_dashboard_data(notice: "Charge point creation failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("create_endpoint", %{"endpoint" => raw_form}, socket) do
    role = socket.assigns.current_role
    endpoint_form = normalize_endpoint_form(raw_form)

    with {:ok, attrs} <- build_endpoint_attrs(endpoint_form),
         {:ok, endpoint} <-
           ManageTargetEndpoints.create_target_endpoint(target_endpoint_repository(), attrs, role) do
      {:noreply,
       socket
       |> assign(endpoint_form: default_endpoint_form())
       |> refresh_dashboard_data(notice: "Target endpoint `#{endpoint.id}` created.")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(endpoint_form: endpoint_form)
         |> refresh_dashboard_data(notice: "Endpoint creation failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("seed_templates", _params, socket) do
    role = socket.assigns.current_role

    case StarterTemplates.seed_starter_templates(template_repository(), role) do
      {:ok, templates} ->
        {:noreply,
         refresh_dashboard_data(socket,
           notice: "Starter templates seeded (#{length(templates)} templates)."
         )}

      {:error, reason} ->
        {:noreply,
         refresh_dashboard_data(socket,
           notice: "Starter template seed failed: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def handle_event("load_logs_for_run", %{"run_id" => run_id}, socket) do
    normalized_run_id = normalize_string(run_id)

    {:noreply,
     refresh_dashboard_data(socket,
       notice: "Loaded logs for run `#{normalized_run_id}`.",
       logs_run_id: normalized_run_id
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Build scenario, trigger run, dan monitor hasil dari satu workspace interaktif."
      current_path={@current_path}
      current_role={@current_role}
      flash={@flash}
    >
      <div class="dashboard-canvas">
      <section class="hero-panel">
        <div>
          <p class="eyebrow">OCPP 1.6J Simulator</p>
          <h1><%= @page_title %></h1>
          <p class="subtitle">
            Build scenario, trigger run, and monitor result from one interactive workspace.
          </p>
        </div>
        <div class="metric-grid">
          <article class="metric-card">
            <span>Current Role</span>
            <strong><%= role_label(@current_role) %></strong>
          </article>
          <article class="metric-card">
            <span>Max Concurrent Runs</span>
            <strong><%= @max_concurrent_runs %></strong>
          </article>
          <article class="metric-card">
            <span>Max Active Sessions</span>
            <strong><%= @max_active_sessions %></strong>
          </article>
          <article class="metric-card">
            <span>Total Scenarios</span>
            <strong><%= @stats.scenarios %></strong>
          </article>
        </div>
      </section>

      <section class="role-switcher card">
        <h2>Login As</h2>
        <p>
          Session role menentukan akses fitur. Pilih role lalu dashboard akan reload dengan permission yang sesuai.
        </p>
        <div class="role-actions">
          <%= for role <- @role_order do %>
            <form method="post" action={~p"/session/role"}>
              <input type="hidden" name="_csrf_token" value={csrf_token_value()} />
              <input type="hidden" name="return_to" value="/dashboard" />
              <input type="hidden" name="role" value={role} />
              <button class={["role-btn", if(@current_role == role, do: "active")]} type="submit">
                <span><%= role_label(role) %></span>
                <small><%= role_hint(role) %></small>
              </button>
            </form>
          <% end %>
        </div>
      </section>

      <p :if={@notice} class="notice"><%= @notice %></p>
      <p :if={@data_warning} class="warning"><%= @data_warning %></p>

      <section class="grid two-col">
        <article class="card">
          <header>
            <h2>Scenario Builder</h2>
            <p>Buat scenario dari JSON steps secara langsung.</p>
          </header>
          <.form
            for={%{}}
            as={:scenario}
            phx-submit="create_scenario"
            action={~p"/scenarios"}
            method="post"
          >
            <label>
              Scenario ID
              <input type="text" name="scenario[id]" value={@scenario_form.id} placeholder="scn-fast-charge" />
            </label>
            <label>
              Name
              <input type="text" name="scenario[name]" value={@scenario_form.name} placeholder="Fast Charge Flow" />
            </label>
            <label>
              Version
              <input type="text" name="scenario[version]" value={@scenario_form.version} placeholder="1.0.0" />
            </label>
            <label>
              Steps JSON
              <textarea name="scenario[steps_json]" rows="10"><%= @scenario_form.steps_json %></textarea>
            </label>
            <button type="submit" disabled={!LiveData.can?(@permission_grants, :manage_scenarios)}>
              Save Scenario
            </button>
          </.form>
          <p class="inline-link">
            <.link navigate={~p"/scenario-builder"}>Open advanced visual/raw scenario builder</.link>
          </p>
        </article>

        <article class="card">
          <header>
            <h2>Run Orchestrator</h2>
            <p>Queue run dan optionally execute langsung.</p>
          </header>
          <.form
            for={%{}}
            as={:run}
            phx-submit="start_run"
            action={~p"/runs"}
            method="post"
          >
            <label>
              Scenario ID
              <input type="text" name="run[scenario_id]" value={@run_form.scenario_id} placeholder="scn-fast-charge" />
            </label>
            <label class="checkbox-row">
              <input
                type="checkbox"
                name="run[execute_after_start]"
                value="true"
                checked={@run_form.execute_after_start == "true"}
              />
              Execute immediately after queued
            </label>
            <label>
              Timeout (ms)
              <input type="number" min="1" name="run[timeout_ms]" value={@run_form.timeout_ms} />
            </label>
            <button type="submit" disabled={!LiveData.can?(@permission_grants, :start_run)}>
              Start Run
            </button>
          </.form>
          <div class="row-actions">
            <button
              type="button"
              phx-click="seed_templates"
              disabled={!LiveData.can?(@permission_grants, :manage_templates)}
            >
              Seed Starter Templates
            </button>
            <button type="button" phx-click="refresh_data">Refresh Dashboard Data</button>
          </div>
          <p class="inline-link">
            <.link navigate={~p"/runs"}>Open run operations page</.link>
          </p>
        </article>
      </section>

      <section class="grid two-col">
        <article class="card">
          <header>
            <h2>Charge Points</h2>
            <p>Daftarkan charge point profile untuk simulasi.</p>
          </header>
          <.form
            for={%{}}
            as={:charge_point}
            phx-submit="create_charge_point"
            action={~p"/charge-points"}
            method="post"
          >
            <label>
              ID
              <input type="text" name="charge_point[id]" value={@charge_point_form.id} />
            </label>
            <label>
              Vendor
              <input type="text" name="charge_point[vendor]" value={@charge_point_form.vendor} />
            </label>
            <label>
              Model
              <input type="text" name="charge_point[model]" value={@charge_point_form.model} />
            </label>
            <label>
              Firmware Version
              <input
                type="text"
                name="charge_point[firmware_version]"
                value={@charge_point_form.firmware_version}
              />
            </label>
            <label>
              Connector Count
              <input
                type="number"
                min="1"
                name="charge_point[connector_count]"
                value={@charge_point_form.connector_count}
              />
            </label>
            <label>
              Heartbeat (seconds)
              <input
                type="number"
                min="1"
                name="charge_point[heartbeat_interval_seconds]"
                value={@charge_point_form.heartbeat_interval_seconds}
              />
            </label>
            <label>
              Behavior Profile
              <select name="charge_point[behavior_profile]" value={@charge_point_form.behavior_profile}>
                <option value="default">default</option>
                <option value="intermittent_disconnects">intermittent_disconnects</option>
                <option value="faulted">faulted</option>
              </select>
            </label>
            <button type="submit" disabled={!LiveData.can?(@permission_grants, :manage_charge_points)}>
              Create Charge Point
            </button>
          </.form>
          <p class="inline-link"><.link navigate={~p"/charge-points"}>Open charge point registry</.link></p>
        </article>

        <article class="card">
          <header>
            <h2>Target Endpoints</h2>
            <p>Set endpoint WS CSMS target dan retry policy.</p>
          </header>
          <.form
            for={%{}}
            as={:endpoint}
            phx-submit="create_endpoint"
            action={~p"/target-endpoints"}
            method="post"
          >
            <label>
              Endpoint ID
              <input type="text" name="endpoint[id]" value={@endpoint_form.id} />
            </label>
            <label>
              Name
              <input type="text" name="endpoint[name]" value={@endpoint_form.name} />
            </label>
            <label>
              URL (`ws://`)
              <input type="text" name="endpoint[url]" value={@endpoint_form.url} />
            </label>
            <label>
              Retry Max Attempts
              <input
                type="number"
                min="1"
                name="endpoint[retry_max_attempts]"
                value={@endpoint_form.retry_max_attempts}
              />
            </label>
            <label>
              Retry Backoff (ms)
              <input
                type="number"
                min="1"
                name="endpoint[retry_backoff_ms]"
                value={@endpoint_form.retry_backoff_ms}
              />
            </label>
            <button
              type="submit"
              disabled={!LiveData.can?(@permission_grants, :manage_target_endpoints)}
            >
              Create Endpoint
            </button>
          </.form>
          <p class="inline-link">
            <.link navigate={~p"/target-endpoints"}>Open endpoint management page</.link>
          </p>
        </article>
      </section>

      <section class="grid two-col">
        <article class="card table-card">
          <header>
            <h2>Recent Scenarios</h2>
            <p>Scenario terbaru dari repository.</p>
          </header>
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Version</th>
                <th>Steps</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={scenario <- @scenarios}>
                <td><%= scenario.id %></td>
                <td><%= scenario.name %></td>
                <td><%= scenario.version %></td>
                <td><%= length(scenario.steps) %></td>
              </tr>
              <tr :if={Enum.empty?(@scenarios)}>
                <td colspan="4">No scenarios available.</td>
              </tr>
            </tbody>
          </table>
          <p class="inline-link"><.link navigate={~p"/scenarios"}>Open scenario library</.link></p>
        </article>

        <article class="card table-card">
          <header>
            <h2>Recent Runs</h2>
            <p>Monitor state run dan lompat ke console/log.</p>
          </header>
          <table>
            <thead>
              <tr>
                <th>Run ID</th>
                <th>State</th>
                <th>Scenario</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={run <- @runs}>
                <td><%= run.id %></td>
                <td>
                  <span class={"state-pill state-#{run.state}"}><%= run.state %></span>
                </td>
                <td><%= run.scenario_id %></td>
                <td>
                  <div class="row-actions compact">
                    <button type="button" phx-click="load_logs_for_run" phx-value-run_id={run.id}>
                      Load Logs
                    </button>
                    <.link navigate={~p"/live-console?run_id=#{run.id}"}>Console</.link>
                  </div>
                </td>
              </tr>
              <tr :if={Enum.empty?(@runs)}>
                <td colspan="4">No runs available.</td>
              </tr>
            </tbody>
          </table>
          <p class="inline-link"><.link navigate={~p"/run-history"}>Open run history</.link></p>
        </article>
      </section>

      <section class="grid two-col">
        <article class="card table-card">
          <header>
            <h2>Logs for Run</h2>
            <p>
              Filter aktif: <strong><%= if @logs_run_id == "", do: "(none)", else: @logs_run_id %></strong>
            </p>
          </header>
          <table>
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Severity</th>
                <th>Event</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @logs}>
                <td><%= entry.timestamp %></td>
                <td><%= entry.severity %></td>
                <td><%= entry.event_type %></td>
              </tr>
              <tr :if={Enum.empty?(@logs)}>
                <td colspan="3">No logs loaded. Pick a run from "Recent Runs".</td>
              </tr>
            </tbody>
          </table>
          <p class="inline-link"><.link navigate={~p"/logs?run_id=#{@logs_run_id}"}>Open full log viewer</.link></p>
        </article>

        <article class="card table-card">
          <header>
            <h2>Templates & Endpoints Snapshot</h2>
            <p>Ringkasan artefak reusable + endpoint target.</p>
          </header>
          <div class="split-columns">
            <div>
              <h3>Templates</h3>
              <ul>
                <li :for={template <- @templates}>
                  <strong><%= template.id %></strong> (<%= template.type %>)
                </li>
                <li :if={Enum.empty?(@templates)}>No templates available.</li>
              </ul>
            </div>
            <div>
              <h3>Target Endpoints</h3>
              <ul>
                <li :for={endpoint <- @target_endpoints}>
                  <strong><%= endpoint.id %></strong> -> <%= endpoint.url %>
                </li>
                <li :if={Enum.empty?(@target_endpoints)}>No endpoints available.</li>
              </ul>
            </div>
          </div>
          <p class="inline-link">
            <.link navigate={~p"/templates"}>Open template library</.link>
            <span> · </span>
            <.link navigate={~p"/target-endpoints"}>Open endpoint library</.link>
          </p>
        </article>
      </section>
      </div>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)

  defp refresh_dashboard_data(socket, opts \\ []) do
    role = socket.assigns.current_role
    logs_run_id = Keyword.get(opts, :logs_run_id, socket.assigns.logs_run_id)

    {stats, stats_issue} = load_stats()
    {scenarios, scenarios_issue} = load_scenarios(role)
    {templates, templates_issue} = load_templates(role)
    {charge_points, charge_points_issue} = load_charge_points(role)
    {target_endpoints, target_endpoints_issue} = load_target_endpoints(role)
    {runs, runs_issue} = load_runs()
    {logs, logs_issue} = load_logs(logs_run_id)

    data_warning =
      [
        issue_message("stats", stats_issue),
        issue_message("scenarios", scenarios_issue),
        issue_message("templates", templates_issue),
        issue_message("charge points", charge_points_issue),
        issue_message("target endpoints", target_endpoints_issue),
        issue_message("runs", runs_issue),
        issue_message("logs", logs_issue)
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        issues -> Enum.join(issues, " | ")
      end

    assign(socket,
      notice: Keyword.get(opts, :notice, socket.assigns.notice),
      data_warning: data_warning,
      stats: stats,
      scenarios: scenarios,
      templates: templates,
      charge_points: charge_points,
      target_endpoints: target_endpoints,
      runs: runs,
      logs: logs,
      logs_run_id: logs_run_id
    )
  end

  defp load_stats do
    stats = %{
      charge_points: count_entries(charge_point_repository(), :list),
      scenarios: count_entries(scenario_repository(), :list),
      templates: count_entries(template_repository(), :list),
      runs: count_entries(scenario_run_repository(), :list_history)
    }

    issue =
      if Enum.any?(Map.values(stats), &(&1 == :error)) do
        "Some metrics are unavailable"
      else
        nil
      end

    normalized =
      Enum.into(stats, %{}, fn {key, value} ->
        case value do
          :error -> {key, "unavailable"}
          _ -> {key, value}
        end
      end)

    {normalized, issue}
  end

  defp load_scenarios(role) do
    case ManageScenarios.list_scenarios(scenario_repository(), role, %{page: 1, page_size: 8}) do
      {:ok, %{entries: entries}} when is_list(entries) -> {entries, nil}
      {:ok, entries} when is_list(entries) -> {entries, nil}
      {:error, reason} -> {[], inspect(reason)}
    end
  rescue
    error -> {[], Exception.message(error)}
  end

  defp load_templates(role) do
    case ManageScenarios.list_templates(template_repository(), role, %{page: 1, page_size: 8}) do
      {:ok, %{entries: entries}} when is_list(entries) -> {entries, nil}
      {:ok, entries} when is_list(entries) -> {entries, nil}
      {:error, reason} -> {[], inspect(reason)}
    end
  rescue
    error -> {[], Exception.message(error)}
  end

  defp load_charge_points(role) do
    case ManageChargePoints.list_charge_points(charge_point_repository(), role, %{
           page: 1,
           page_size: 8
         }) do
      {:ok, %{entries: entries}} when is_list(entries) -> {entries, nil}
      {:ok, entries} when is_list(entries) -> {entries, nil}
      {:error, reason} -> {[], inspect(reason)}
    end
  rescue
    error -> {[], Exception.message(error)}
  end

  defp load_target_endpoints(role) do
    case ManageTargetEndpoints.list_target_endpoints(
           target_endpoint_repository(),
           role,
           %{page: 1, page_size: 8}
         ) do
      {:ok, %{entries: entries}} when is_list(entries) -> {entries, nil}
      {:ok, entries} when is_list(entries) -> {entries, nil}
      {:error, reason} -> {[], inspect(reason)}
    end
  rescue
    error -> {[], Exception.message(error)}
  end

  defp load_runs do
    case scenario_run_repository().list_history(%{page: 1, page_size: 8}) do
      {:ok, %{entries: entries}} when is_list(entries) -> {entries, nil}
      {:error, reason} -> {[], inspect(reason)}
    end
  rescue
    error -> {[], Exception.message(error)}
  end

  defp load_logs(""), do: {[], nil}

  defp load_logs(run_id) do
    case log_repository().list(%{run_id: run_id, page: 1, page_size: 12}) do
      {:ok, %{entries: entries}} when is_list(entries) -> {entries, nil}
      {:error, reason} -> {[], inspect(reason)}
    end
  rescue
    error -> {[], Exception.message(error)}
  end

  defp issue_message(_label, nil), do: nil
  defp issue_message(label, message), do: "#{label}: #{message}"

  defp maybe_execute_run_after_start(run_id, role, run_form) do
    if truthy?(run_form.execute_after_start) do
      opts =
        case parse_positive_integer(run_form.timeout_ms) do
          {:ok, timeout_ms} -> %{timeout_ms: timeout_ms}
          {:error, _reason} -> %{}
        end

      case RunScenario.execute_run(execute_dependencies(), run_id, role, opts) do
        {:ok, run} -> {:ok, "Execution finished with state `#{run.state}`."}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, "Execution not requested (queued only)."}
    end
  end

  defp build_start_run_attrs(run_form) do
    scenario_id = normalize_string(run_form.scenario_id)

    if scenario_id == "" do
      {:error, {:invalid_field, :scenario_id, :must_be_non_empty_string}}
    else
      {:ok,
       %{
         scenario_id: scenario_id,
         metadata: %{"source" => "dashboard"}
       }}
    end
  end

  defp build_scenario_attrs(scenario_form) do
    with {:ok, steps} <- parse_steps_json(scenario_form.steps_json) do
      {:ok,
       %{
         id: normalize_string(scenario_form.id),
         name: normalize_string(scenario_form.name),
         version: normalize_string(scenario_form.version),
         schema_version: "1.0",
         variables: %{},
         variable_scopes: Scenario.default_variable_scopes(),
         validation_policy: Scenario.validation_policy_defaults(),
         steps: steps
       }}
    end
  end

  defp build_charge_point_attrs(charge_point_form) do
    with {:ok, connector_count} <- parse_positive_integer(charge_point_form.connector_count),
         {:ok, heartbeat_interval_seconds} <-
           parse_positive_integer(charge_point_form.heartbeat_interval_seconds) do
      {:ok,
       %{
         id: normalize_string(charge_point_form.id),
         vendor: normalize_string(charge_point_form.vendor),
         model: normalize_string(charge_point_form.model),
         firmware_version: normalize_string(charge_point_form.firmware_version),
         connector_count: connector_count,
         heartbeat_interval_seconds: heartbeat_interval_seconds,
         behavior_profile: normalize_string(charge_point_form.behavior_profile)
       }}
    end
  end

  defp build_endpoint_attrs(endpoint_form) do
    with {:ok, retry_max_attempts} <- parse_positive_integer(endpoint_form.retry_max_attempts),
         {:ok, retry_backoff_ms} <- parse_positive_integer(endpoint_form.retry_backoff_ms) do
      {:ok,
       %{
         id: normalize_string(endpoint_form.id),
         name: normalize_string(endpoint_form.name),
         url: normalize_string(endpoint_form.url),
         retry_policy: %{
           max_attempts: retry_max_attempts,
           backoff_ms: retry_backoff_ms
         },
         protocol_options: %{},
         metadata: %{}
       }}
    end
  end

  defp parse_steps_json(raw_json) when is_binary(raw_json) do
    case Jason.decode(raw_json) do
      {:ok, steps} when is_list(steps) -> {:ok, steps}
      {:ok, _decoded} -> {:error, {:invalid_field, :steps_json, :must_decode_to_array}}
      {:error, reason} -> {:error, {:invalid_field, :steps_json, inspect(reason)}}
    end
  end

  defp parse_steps_json(_raw_json), do: {:error, {:invalid_field, :steps_json, :must_be_string}}

  defp parse_positive_integer(raw) do
    case Integer.parse(to_string(raw || "")) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, {:invalid_field, :integer, :must_be_positive_integer}}
    end
  end

  defp normalize_scenario_form(raw_form) do
    %{
      id: fetch_form(raw_form, :id) |> normalize_string(),
      name: fetch_form(raw_form, :name) |> normalize_string(),
      version: fetch_form(raw_form, :version) |> normalize_string(),
      steps_json: fetch_form(raw_form, :steps_json) |> normalize_multiline()
    }
  end

  defp normalize_run_form(raw_form) do
    %{
      scenario_id: fetch_form(raw_form, :scenario_id) |> normalize_string(),
      execute_after_start:
        if(truthy?(fetch_form(raw_form, :execute_after_start)), do: "true", else: "false"),
      timeout_ms: fetch_form(raw_form, :timeout_ms) |> normalize_string()
    }
  end

  defp normalize_charge_point_form(raw_form) do
    %{
      id: fetch_form(raw_form, :id) |> normalize_string(),
      vendor: fetch_form(raw_form, :vendor) |> normalize_string(),
      model: fetch_form(raw_form, :model) |> normalize_string(),
      firmware_version: fetch_form(raw_form, :firmware_version) |> normalize_string(),
      connector_count: fetch_form(raw_form, :connector_count) |> normalize_string(),
      heartbeat_interval_seconds:
        fetch_form(raw_form, :heartbeat_interval_seconds) |> normalize_string(),
      behavior_profile: fetch_form(raw_form, :behavior_profile) |> normalize_string()
    }
  end

  defp normalize_endpoint_form(raw_form) do
    %{
      id: fetch_form(raw_form, :id) |> normalize_string(),
      name: fetch_form(raw_form, :name) |> normalize_string(),
      url: fetch_form(raw_form, :url) |> normalize_string(),
      retry_max_attempts: fetch_form(raw_form, :retry_max_attempts) |> normalize_string(),
      retry_backoff_ms: fetch_form(raw_form, :retry_backoff_ms) |> normalize_string()
    }
  end

  defp fetch_form(form, key) do
    if is_map(form) do
      Map.get(form, Atom.to_string(key), Map.get(form, key, ""))
    else
      ""
    end
  end

  defp default_scenario_form do
    %{
      id: "scn-normal-transaction",
      name: "Normal Transaction",
      version: "1.0.0",
      steps_json:
        Jason.encode!(
          [
            %{
              "id" => "boot",
              "type" => "send_action",
              "order" => 1,
              "payload" => %{
                "action" => "BootNotification",
                "payload" => %{
                  "chargePointVendor" => "Erdovi",
                  "chargePointModel" => "Simulator"
                }
              }
            },
            %{
              "id" => "authorize",
              "type" => "send_action",
              "order" => 2,
              "payload" => %{"action" => "Authorize", "payload" => %{"idTag" => "RFID-1"}}
            },
            %{
              "id" => "heartbeat",
              "type" => "send_action",
              "order" => 3,
              "payload" => %{"action" => "Heartbeat", "payload" => %{}}
            }
          ],
          pretty: true
        )
    }
  end

  defp default_run_form do
    %{
      scenario_id: "",
      execute_after_start: "true",
      timeout_ms: "15000"
    }
  end

  defp default_charge_point_form do
    %{
      id: "cp-alpha-01",
      vendor: "Erdovi",
      model: "AC-120",
      firmware_version: "1.0.0",
      connector_count: "2",
      heartbeat_interval_seconds: "60",
      behavior_profile: "default"
    }
  end

  defp default_endpoint_form do
    %{
      id: "endpoint-local-dev",
      name: "Local CSMS",
      url: "ws://localhost:9000/ocpp",
      retry_max_attempts: "3",
      retry_backoff_ms: "1000"
    }
  end

  defp role_label(:admin), do: "Admin"
  defp role_label(:operator), do: "Operator"
  defp role_label(:viewer), do: "Viewer"
  defp role_label(other), do: to_string(other)

  defp role_hint(:admin), do: "full control"
  defp role_hint(:operator), do: "manage + run"
  defp role_hint(:viewer), do: "read-only"
  defp role_hint(_other), do: "custom"

  defp truthy?(value) when value in [true, "true", "1", "on", 1], do: true
  defp truthy?(_value), do: false

  defp normalize_string(value), do: value |> to_string() |> String.trim()
  defp normalize_multiline(value), do: value |> to_string() |> String.trim() |> Kernel.<>("\n")

  defp count_entries(repository, list_function) do
    case apply(repository, list_function, [%{page: 1, page_size: 1, allow_unfiltered: true}]) do
      {:ok, %{total_entries: total_entries}} when is_integer(total_entries) -> total_entries
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp start_dependencies do
    %{
      scenario_repository: scenario_repository(),
      scenario_run_repository: scenario_run_repository(),
      id_generator: id_generator(),
      webhook_dispatcher: webhook_dispatcher()
    }
  end

  defp execute_dependencies do
    %{
      scenario_run_repository: scenario_run_repository(),
      webhook_dispatcher: webhook_dispatcher(),
      charge_point_repository: charge_point_repository(),
      target_endpoint_repository: target_endpoint_repository(),
      transport_gateway:
        LiveData.repository(
          :transport_gateway,
          OcppSimulator.Infrastructure.Transport.WebSocket.SessionManager
        )
    }
  end

  defp csrf_token_value, do: Plug.CSRFProtection.get_csrf_token()

  defp charge_point_repository do
    LiveData.repository(
      :charge_point_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
    )
  end

  defp scenario_repository do
    LiveData.repository(
      :scenario_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
    )
  end

  defp template_repository do
    LiveData.repository(
      :template_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
    )
  end

  defp target_endpoint_repository do
    LiveData.repository(
      :target_endpoint_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
    )
  end

  defp scenario_run_repository do
    LiveData.repository(
      :scenario_run_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
    )
  end

  defp log_repository do
    LiveData.repository(
      :log_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository
    )
  end

  defp id_generator do
    LiveData.repository(:id_generator, OcppSimulator.Infrastructure.Support.IdGenerator)
  end

  defp webhook_dispatcher do
    LiveData.repository(
      :webhook_dispatcher,
      OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
    )
  end
end
