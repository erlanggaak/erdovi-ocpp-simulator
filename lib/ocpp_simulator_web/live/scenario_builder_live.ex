defmodule OcppSimulatorWeb.ScenarioBuilderLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Application.UseCases.ScenarioEditor
  alias OcppSimulator.Domain.Ocpp.PayloadTemplates
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Domain.Sessions.SessionStateMachine
  alias OcppSimulator.Domain.Transactions.TransactionStateMachine
  alias OcppSimulatorWeb.Live.LiveData
  alias OcppSimulatorWeb.Live.UITheme

  @semver ~r/^\d+\.\d+\.\d+$/
  @step_types Enum.map(Scenario.supported_step_types(), &Atom.to_string/1)

  @impl true
  def mount(_params, _session, socket) do
    visual_model = default_visual_model()
    raw_json = encode_visual_model(visual_model)
    {field_errors, validation_summary, preview_rows} = validate_visual_model(visual_model)

    {:ok,
     assign(socket,
       current_role: socket.assigns[:current_role] || :operator,
       current_path: "/scenario-builder",
       page_title: "Scenario Builder",
       mode: "visual",
       visual_model: visual_model,
       raw_json: raw_json,
       field_errors: field_errors,
       validation_summary: validation_summary,
       preview_rows: preview_rows,
       feedback: nil,
       step_types: @step_types,
       ocpp_send_actions: PayloadTemplates.charge_point_initiated_actions(),
       ocpp_await_actions: PayloadTemplates.central_system_initiated_actions(),
       session_states: Enum.map(SessionStateMachine.states(), &Atom.to_string/1),
       transaction_states: Enum.map(TransactionStateMachine.states(), &Atom.to_string/1)
     )}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) when mode in ["json", "raw"] do
    raw_json = encode_visual_model(socket.assigns.visual_model)

    {:noreply,
     assign(socket,
       mode: "json",
       raw_json: raw_json,
       feedback: "Switched to JSON mode."
     )}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => "visual"}, socket) do
    case ScenarioEditor.raw_json_to_visual(socket.assigns.raw_json) do
      {:ok, visual_model} ->
        {field_errors, validation_summary, preview_rows} = validate_visual_model(visual_model)

        {:noreply,
         assign(socket,
           mode: "visual",
           visual_model: visual_model,
           raw_json: encode_visual_model(visual_model),
           field_errors: field_errors,
           validation_summary: validation_summary,
           preview_rows: preview_rows,
           feedback: "Switched to visual mode."
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           mode: "json",
           field_errors:
             Map.put(socket.assigns.field_errors, :raw_json, raw_json_error_message(reason)),
           feedback:
             "Cannot switch to visual mode until raw JSON is valid. Reason: #{inspect(reason)}"
         )}
    end
  end

  def handle_event("switch_mode", _params, socket) do
    {:noreply, assign(socket, feedback: "Unknown editor mode requested.")}
  end

  @impl true
  def handle_event("update_header", %{"scenario" => params}, socket) do
    visual_model =
      socket.assigns.visual_model
      |> Map.put("id", normalize_string(Map.get(params, "id", socket.assigns.visual_model["id"])))
      |> Map.put(
        "name",
        normalize_string(Map.get(params, "name", socket.assigns.visual_model["name"]))
      )
      |> Map.put(
        "version",
        normalize_string(Map.get(params, "version", socket.assigns.visual_model["version"]))
      )

    {:noreply, apply_visual_model(socket, visual_model)}
  end

  @impl true
  def handle_event("update_visual", %{"scenario" => params}, socket) do
    base_model =
      socket.assigns.visual_model
      |> Map.put("id", normalize_string(Map.get(params, "id", socket.assigns.visual_model["id"])))
      |> Map.put(
        "name",
        normalize_string(Map.get(params, "name", socket.assigns.visual_model["name"]))
      )
      |> Map.put(
        "version",
        normalize_string(Map.get(params, "version", socket.assigns.visual_model["version"]))
      )

    {visual_model, parse_error} =
      case Map.get(params, "steps_json") do
        nil ->
          {base_model, nil}

        raw_steps_json when is_binary(raw_steps_json) ->
          case Jason.decode(raw_steps_json) do
            {:ok, steps} when is_list(steps) ->
              {Map.put(base_model, "steps", steps), nil}

            {:ok, _decoded} ->
              {base_model, "Steps must decode to a JSON array."}

            {:error, _reason} ->
              {base_model, "Steps must be valid JSON array format."}
          end
      end

    next_socket = apply_visual_model(socket, visual_model)

    next_socket =
      case parse_error do
        nil ->
          next_socket

        message ->
          assign(next_socket,
            field_errors: Map.put(next_socket.assigns.field_errors, :steps, message)
          )
      end

    {:noreply, next_socket}
  end

  @impl true
  def handle_event("add_step", _params, socket) do
    steps = socket.assigns.visual_model["steps"] || []
    next_order = length(steps) + 1
    next_step = default_step(next_order)

    visual_model =
      socket.assigns.visual_model
      |> Map.put("steps", steps ++ [next_step])

    {:noreply, apply_visual_model(socket, visual_model)}
  end

  @impl true
  def handle_event("move_step", %{"index" => raw_index, "direction" => direction}, socket) do
    steps = socket.assigns.visual_model["steps"] || []
    index = parse_index(raw_index)

    moved_steps =
      case {direction, index} do
        {"up", idx} when idx > 0 and idx < length(steps) -> swap_steps(steps, idx, idx - 1)
        {"down", idx} when idx >= 0 and idx < length(steps) - 1 -> swap_steps(steps, idx, idx + 1)
        _ -> steps
      end

    visual_model = socket.assigns.visual_model |> Map.put("steps", reindex_steps(moved_steps))

    {:noreply, apply_visual_model(socket, visual_model)}
  end

  @impl true
  def handle_event("remove_step", %{"index" => raw_index}, socket) do
    steps = socket.assigns.visual_model["steps"] || []
    index = parse_index(raw_index)

    remaining_steps =
      steps
      |> Enum.with_index()
      |> Enum.reject(fn {_step, idx} -> idx == index end)
      |> Enum.map(fn {step, _idx} -> step end)
      |> reindex_steps()

    visual_model = socket.assigns.visual_model |> Map.put("steps", remaining_steps)

    {:noreply, apply_visual_model(socket, visual_model)}
  end

  @impl true
  def handle_event("update_step", %{"index" => raw_index, "step" => step_params}, socket) do
    steps = socket.assigns.visual_model["steps"] || []
    index = parse_index(raw_index)

    case Enum.fetch(steps, index) do
      {:ok, existing_step} ->
        {updated_step, step_error} = merge_step(existing_step, step_params)

        updated_steps = List.replace_at(steps, index, updated_step) |> reindex_steps()

        visual_model = socket.assigns.visual_model |> Map.put("steps", updated_steps)
        next_socket = apply_visual_model(socket, visual_model)

        next_socket =
          case step_error do
            nil ->
              assign(next_socket,
                field_errors: Map.delete(next_socket.assigns.field_errors, {:step, index})
              )

            message ->
              assign(next_socket,
                field_errors: Map.put(next_socket.assigns.field_errors, {:step, index}, message)
              )
          end

        {:noreply, next_socket}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_raw", %{"scenario" => %{"raw_json" => raw_json}}, socket) do
    case ScenarioEditor.raw_json_to_visual(raw_json) do
      {:ok, visual_model} ->
        {field_errors, validation_summary, preview_rows} = validate_visual_model(visual_model)

        {:noreply,
         assign(socket,
           raw_json: raw_json,
           visual_model: visual_model,
           field_errors: Map.delete(field_errors, :raw_json),
           validation_summary: validation_summary,
           preview_rows: preview_rows,
           feedback: nil
         )}

      {:error, reason} ->
        {field_errors, validation_summary, preview_rows} = validate_raw_json(raw_json)

        {:noreply,
         assign(socket,
           raw_json: raw_json,
           field_errors: Map.put(field_errors, :raw_json, raw_json_error_message(reason)),
           validation_summary: validation_summary,
           preview_rows: preview_rows,
           feedback: nil
         )}
    end
  end

  @impl true
  def handle_event("save_scenario", _params, socket) do
    role = socket.assigns.current_role

    with {:ok, visual_model} <- visual_model_for_save(socket),
         {:ok, {action, saved_scenario}} <- persist_scenario(visual_model, role) do
      normalized_visual_model = normalize_saved_scenario(saved_scenario, visual_model)
      next_socket = apply_visual_model(socket, normalized_visual_model)

      {:noreply,
       assign(next_socket,
         feedback:
           if(action == :created,
             do: "Scenario `#{saved_scenario.id}` was created successfully.",
             else: "Scenario `#{saved_scenario.id}` was updated successfully."
           )
       )}
    else
      {:error, {:raw_json_invalid, reason}} ->
        {:noreply,
         assign(socket,
           mode: "json",
           field_errors:
             Map.put(socket.assigns.field_errors, :raw_json, raw_json_error_message(reason)),
           feedback: "Cannot save scenario until raw JSON is valid. Reason: #{inspect(reason)}"
         )}

      {:error, {:invalid_scenario, reason}} ->
        {:noreply,
         assign(socket,
           feedback: "Cannot save scenario because schema validation failed: #{inspect(reason)}"
         )}

      {:error, :forbidden} ->
        {:noreply,
         assign(socket,
           feedback: "Current role is not allowed to save scenario definitions."
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           feedback: "Unable to save scenario: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      title={@page_title}
      subtitle="Dual-mode authoring dengan visual steps interaktif + JSON schema-safe."
      current_path={@current_path}
      current_role={@current_role}
      notice={@feedback}
      flash={@flash}
    >
      <section class="sim-section">
        <div class="sim-actions">
          <button
            type="button"
            phx-click="switch_mode"
            phx-value-mode="visual"
            class={["sim-mode-toggle", if(@mode == "visual", do: "active")]}
          >
            Visual Mode
          </button>
          <button
            type="button"
            phx-click="switch_mode"
            phx-value-mode="json"
            class={["sim-mode-toggle", if(@mode == "json", do: "active")]}
          >
            JSON Mode
          </button>
        </div>
      </section>

      <section class="sim-section" :if={@mode == "visual"}>
        <h2>Scenario Header</h2>
        <.form for={%{}} as={:scenario} phx-change="update_header">
          <div class="sim-form-grid">
            <label>
              Scenario ID
              <input type="text" name="scenario[id]" value={@visual_model["id"]} />
              <p :if={@field_errors[:id]} class="sim-error-text"><%= @field_errors[:id] %></p>
            </label>

            <label>
              Name
              <input type="text" name="scenario[name]" value={@visual_model["name"]} />
              <p :if={@field_errors[:name]} class="sim-error-text"><%= @field_errors[:name] %></p>
            </label>

            <label>
              Version
              <input type="text" name="scenario[version]" value={@visual_model["version"]} />
              <p :if={@field_errors[:version]} class="sim-error-text"><%= @field_errors[:version] %></p>
            </label>
          </div>
        </.form>
      </section>

      <section class="sim-section" :if={@mode == "visual"}>
        <div class="sim-row-between">
          <h2>Steps</h2>
          <button type="button" phx-click="add_step">Add Step</button>
        </div>

        <p :if={@field_errors[:steps]} class="sim-error-text"><%= @field_errors[:steps] %></p>

        <div class="sim-step-list">
          <article
            :for={{step, index} <- Enum.with_index(@visual_model["steps"] || [])}
            class="sim-step-card"
          >
            <header class="sim-row-between">
              <strong>Step <%= index + 1 %> - <%= step["id"] %></strong>
              <div class="sim-actions">
                <button type="button" phx-click="move_step" phx-value-index={index} phx-value-direction="up">
                  Move Up
                </button>
                <button
                  type="button"
                  phx-click="move_step"
                  phx-value-index={index}
                  phx-value-direction="down"
                >
                  Move Down
                </button>
                <button
                  type="button"
                  phx-click="remove_step"
                  phx-value-index={index}
                  class="sim-button-danger"
                >
                  Remove
                </button>
              </div>
            </header>

            <.form for={%{}} as={:step} phx-change="update_step">
              <input type="hidden" name="index" value={index} />
              <div class="sim-form-grid">
                <label>
                  Step ID
                  <input type="text" name="step[id]" value={step["id"]} />
                </label>
                <label>
                  Type
                  <select name="step[type]" value={step["type"]}>
                    <option :for={type <- @step_types} value={type} selected={step["type"] == type}>
                      <%= type %>
                    </option>
                  </select>
                </label>
                <label>
                  Delay (ms)
                  <input type="number" min="0" name="step[delay_ms]" value={step["delay_ms"] || 0} />
                </label>
                <label>
                  Loop Count
                  <input type="number" min="1" name="step[loop_count]" value={step["loop_count"] || 1} />
                </label>
                <label class="sim-checkbox-row">
                  <input type="hidden" name="step[enabled]" value="false" />
                  <input type="checkbox" name="step[enabled]" value="true" checked={truthy?(step["enabled"])} />
                  Enabled
                </label>
              </div>

              <div class="sim-form-grid" :if={step["type"] in ["send_action", "await_response"]}>
                <label>
                  Action
                  <select name="step[action]" value={step_action(step)}>
                    <option value="" selected={step_action(step) in [nil, ""]}>-- none --</option>
                    <option
                      :for={action <- action_options(step["type"], @ocpp_send_actions, @ocpp_await_actions)}
                      value={action}
                      selected={step_action(step) == action}
                    >
                      <%= action %>
                    </option>
                  </select>
                </label>
              </div>

              <div class="sim-form-grid" :if={step["type"] == "assert_state"}>
                <label>
                  Machine
                  <select name="step[machine]" value={step_machine(step)}>
                    <option value="session" selected={step_machine(step) == "session"}>session</option>
                    <option value="transaction" selected={step_machine(step) == "transaction"}>transaction</option>
                  </select>
                </label>
                <label>
                  Expected State
                  <select name="step[state]" value={step_state(step)}>
                    <option
                      :for={state <- state_options(step_machine(step), @session_states, @transaction_states)}
                      value={state}
                      selected={step_state(step) == state}
                    >
                      <%= state %>
                    </option>
                  </select>
                </label>
              </div>

              <div class="sim-form-grid" :if={step["type"] == "set_variable"}>
                <label>
                  Variable Name
                  <input type="text" name="step[var_name]" value={step_variable_name(step)} />
                </label>
                <label>
                  Variable Value
                  <input type="text" name="step[var_value]" value={step_variable_value(step)} />
                </label>
              </div>

              <label>
                Payload JSON (advanced)
                <textarea name="step[payload_json]" rows="5"><%= Jason.encode!(step["payload"] || %{}, pretty: true) %></textarea>
              </label>
              <p :if={@field_errors[{:step, index}]} class="sim-error-text">
                <%= @field_errors[{:step, index}] %>
              </p>
            </.form>
          </article>
        </div>
      </section>

      <section class="sim-section" :if={@mode == "json"}>
        <.form for={%{}} as={:scenario} phx-change="update_raw">
          <label>
            Raw Scenario JSON
            <textarea name="scenario[raw_json]" rows="18"><%= @raw_json %></textarea>
          </label>
          <p :if={@field_errors[:raw_json]} class="sim-error-text"><%= @field_errors[:raw_json] %></p>
        </.form>
      </section>

      <section class="sim-section">
        <div class="sim-actions">
          <button type="button" phx-click="save_scenario">Save Scenario</button>
          <.link navigate={~p"/scenarios"} class="sim-button-secondary">Open Scenario Library</.link>
        </div>
      </section>

      <section class="sim-section">
        <h2>Run Validation Summary</h2>
        <ul>
          <li :for={item <- @validation_summary}><%= item %></li>
        </ul>
      </section>

      <section class="sim-section">
        <h2>Request/Response Preview</h2>
        <div class="sim-table-wrap">
          <table>
            <thead>
              <tr>
                <th>Step</th>
                <th>Direction</th>
                <th>Action</th>
                <th>Correlation ID</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @preview_rows}>
                <td><%= row.step_id %></td>
                <td><%= row.direction %></td>
                <td><%= row.action %></td>
                <td><%= row.correlation_id %></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </.page>
    """
  end

  defp page(assigns), do: UITheme.page(assigns)

  defp scenario_repository do
    LiveData.repository(
      :scenario_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
    )
  end

  defp default_visual_model do
    %{
      "id" => "scenario-builder-preview",
      "name" => "Scenario Builder Preview",
      "version" => "1.0.0",
      "schema_version" => "1.0",
      "variables" => %{},
      "variable_scopes" => ["scenario", "run", "session", "step"],
      "validation_policy" => %{
        "strict_ocpp_schema" => true,
        "strict_state_transitions" => true,
        "strict_variable_resolution" => true
      },
      "steps" => [default_step(1), default_await_step(2)]
    }
  end

  defp default_step(order) do
    %{
      "id" => "step_#{order}",
      "type" => "send_action",
      "order" => order,
      "payload" => PayloadTemplates.send_action_step_payload("BootNotification"),
      "delay_ms" => 0,
      "loop_count" => 1,
      "enabled" => true
    }
  end

  defp default_await_step(order) do
    %{
      "id" => "step_#{order}",
      "type" => "await_response",
      "order" => order,
      "payload" => %{"action" => "RemoteStartTransaction", "timeout_ms" => 30_000},
      "delay_ms" => 0,
      "loop_count" => 1,
      "enabled" => true
    }
  end

  defp apply_visual_model(socket, visual_model) do
    {field_errors, validation_summary, preview_rows} = validate_visual_model(visual_model)

    assign(socket,
      visual_model: visual_model,
      raw_json: encode_visual_model(visual_model),
      field_errors: field_errors,
      validation_summary: validation_summary,
      preview_rows: preview_rows,
      feedback: nil
    )
  end

  defp merge_step(existing_step, step_params)
       when is_map(existing_step) and is_map(step_params) do
    payload_json =
      Map.get(step_params, "payload_json", Jason.encode!(existing_step["payload"] || %{}))

    {payload_map, payload_error} =
      case Jason.decode(payload_json) do
        {:ok, payload} when is_map(payload) ->
          {payload, nil}

        {:ok, _decoded} ->
          {existing_step["payload"] || %{}, "Payload JSON must decode to object."}

        {:error, _reason} ->
          {existing_step["payload"] || %{}, "Payload JSON is invalid."}
      end

    type = normalize_step_type(Map.get(step_params, "type", existing_step["type"]))
    existing_action = extract_payload(existing_step, "action")
    selected_action = normalize_optional_string(Map.get(step_params, "action"))

    payload_map =
      payload_map
      |> normalize_step_payload(type, selected_action, existing_action)
      |> maybe_put("action", selected_action)
      |> maybe_put("machine", normalize_optional_string(Map.get(step_params, "machine")))
      |> maybe_put("state", normalize_optional_string(Map.get(step_params, "state")))
      |> maybe_put("name", normalize_optional_string(Map.get(step_params, "var_name")))
      |> maybe_put("value", normalize_optional_string(Map.get(step_params, "var_value")))

    updated_step =
      existing_step
      |> Map.put("id", normalize_string(Map.get(step_params, "id", existing_step["id"])))
      |> Map.put("type", type)
      |> Map.put(
        "delay_ms",
        parse_non_negative_integer(
          Map.get(step_params, "delay_ms"),
          existing_step["delay_ms"] || 0
        )
      )
      |> Map.put(
        "loop_count",
        parse_positive_integer(
          Map.get(step_params, "loop_count"),
          existing_step["loop_count"] || 1
        )
      )
      |> Map.put("enabled", truthy?(Map.get(step_params, "enabled", existing_step["enabled"])))
      |> Map.put("payload", payload_map)

    {updated_step, payload_error}
  end

  defp swap_steps(steps, left, right) when is_list(steps) do
    left_value = Enum.at(steps, left)
    right_value = Enum.at(steps, right)

    steps
    |> List.replace_at(left, right_value)
    |> List.replace_at(right, left_value)
  end

  defp reindex_steps(steps) when is_list(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} -> Map.put(step, "order", idx) end)
  end

  defp step_action(step), do: extract_payload(step, "action")
  defp step_machine(step), do: extract_payload(step, "machine") || "session"
  defp step_state(step), do: extract_payload(step, "state")
  defp step_variable_name(step), do: extract_payload(step, "name")
  defp step_variable_value(step), do: extract_payload(step, "value")

  defp extract_payload(step, key) when is_map(step) do
    step
    |> Map.get("payload", %{})
    |> Map.get(key)
  end

  defp state_options("transaction", _session_states, transaction_states), do: transaction_states
  defp state_options(_machine, session_states, _transaction_states), do: session_states

  defp action_options("send_action", send_actions, _await_actions), do: send_actions
  defp action_options("await_response", _send_actions, await_actions), do: await_actions
  defp action_options(_step_type, send_actions, _await_actions), do: send_actions

  defp validate_raw_json(raw_json) do
    with {:ok, visual_model} <- ScenarioEditor.raw_json_to_visual(raw_json) do
      validate_visual_model(visual_model)
    else
      {:error, reason} ->
        {%{}, ["Raw JSON validation failed: #{inspect(reason)}"], []}
    end
  end

  defp validate_visual_model(visual_model) do
    field_errors = field_errors(visual_model)

    case Scenario.new(visual_model) do
      {:ok, scenario} ->
        run_errors = RunScenario.pre_run_validation_errors(scenario)
        validation_summary = to_validation_summary(run_errors)
        preview_rows = preview_rows(scenario)
        {field_errors, validation_summary, preview_rows}

      {:error, reason} ->
        {field_errors, ["Scenario schema validation failed: #{inspect(reason)}"], []}
    end
  end

  defp visual_model_for_save(socket) do
    case socket.assigns.mode do
      "json" ->
        case ScenarioEditor.raw_json_to_visual(socket.assigns.raw_json) do
          {:ok, visual_model} -> validate_scenario_payload(visual_model)
          {:error, reason} -> {:error, {:raw_json_invalid, reason}}
        end

      _ ->
        validate_scenario_payload(socket.assigns.visual_model)
    end
  end

  defp validate_scenario_payload(visual_model) when is_map(visual_model) do
    case Scenario.new(visual_model) do
      {:ok, _scenario} -> {:ok, visual_model}
      {:error, reason} -> {:error, {:invalid_scenario, reason}}
    end
  end

  defp validate_scenario_payload(_visual_model),
    do: {:error, {:invalid_scenario, :invalid_payload}}

  defp persist_scenario(visual_model, role) when is_map(visual_model) do
    id = normalize_string(Map.get(visual_model, "id"))

    save_result =
      case ManageScenarios.get_scenario(scenario_repository(), id, role) do
        {:ok, _existing} ->
          case ManageScenarios.update_scenario(scenario_repository(), id, visual_model, role) do
            {:ok, scenario} -> {:ok, {:updated, scenario}}
            {:error, reason} -> {:error, reason}
          end

        {:error, :not_found} ->
          case ManageScenarios.create_scenario(scenario_repository(), visual_model, role) do
            {:ok, scenario} -> {:ok, {:created, scenario}}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end

    save_result
  end

  defp normalize_saved_scenario(%Scenario{} = scenario, fallback_visual_model) do
    snapshot = Scenario.to_snapshot(scenario)

    case ScenarioEditor.raw_json_to_visual(snapshot) do
      {:ok, visual_model} -> visual_model
      {:error, _reason} -> fallback_visual_model
    end
  end

  defp to_validation_summary([]), do: ["Validation passed. Scenario is executable."]

  defp to_validation_summary(errors) when is_list(errors) do
    Enum.map(errors, fn error -> "Pre-run validation error: #{error}" end)
  end

  defp preview_rows(%Scenario{} = scenario) do
    {:ok, plan} = Scenario.execution_plan(scenario)

    plan
    |> Enum.flat_map(fn step ->
      action = payload_action(step.payload)
      correlation_id = "corr-#{step.step_id}-#{step.execution_order}"

      case step.step_type do
        :send_action ->
          [
            %{
              step_id: step.step_id,
              direction: "request",
              action: action,
              correlation_id: correlation_id
            },
            %{
              step_id: step.step_id,
              direction: "response",
              action: action,
              correlation_id: correlation_id
            }
          ]

        :await_response ->
          [
            %{
              step_id: step.step_id,
              direction: "await",
              action: action,
              correlation_id: correlation_id
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp payload_action(payload) when is_map(payload) do
    Map.get(payload, "action") || Map.get(payload, :action) || "-"
  end

  defp normalize_step_payload(payload_map, "send_action", selected_action, existing_action)
       when is_map(payload_map) do
    action = selected_action || existing_action || "BootNotification"

    if selected_action && selected_action != existing_action do
      PayloadTemplates.send_action_step_payload(action)
    else
      payload_map
      |> Map.put("action", action)
      |> Map.put_new("payload", PayloadTemplates.payload_for_action(action))
    end
  end

  defp normalize_step_payload(payload_map, "await_response", selected_action, _existing_action)
       when is_map(payload_map) do
    action = selected_action || Map.get(payload_map, "action") || "RemoteStartTransaction"
    Map.put(payload_map, "action", action)
  end

  defp normalize_step_payload(payload_map, _type, _selected_action, _existing_action),
    do: payload_map

  defp field_errors(visual_model) when is_map(visual_model) do
    %{}
    |> maybe_add_required_error(:id, visual_model["id"])
    |> maybe_add_required_error(:name, visual_model["name"])
    |> maybe_add_semver_error(visual_model["version"])
    |> maybe_add_steps_error(visual_model["steps"])
  end

  defp maybe_add_required_error(errors, key, value) do
    if is_binary(value) and String.trim(value) != "" do
      errors
    else
      Map.put(errors, key, "Must be a non-empty value.")
    end
  end

  defp maybe_add_semver_error(errors, value) do
    normalized = normalize_string(value)

    if Regex.match?(@semver, normalized) do
      errors
    else
      Map.put(errors, :version, "Must use semantic version format (e.g. 1.0.0).")
    end
  end

  defp maybe_add_steps_error(errors, steps) when is_list(steps), do: errors

  defp maybe_add_steps_error(errors, _steps),
    do: Map.put(errors, :steps, "Steps must be a JSON array.")

  defp encode_visual_model(visual_model) do
    case ScenarioEditor.visual_to_raw_json(visual_model) do
      {:ok, raw_json} ->
        raw_json

      {:error, _reason} ->
        Jason.encode!(visual_model)
    end
  end

  defp raw_json_error_message(reason) do
    "JSON document is invalid for scenario schema: #{inspect(reason)}"
  end

  defp normalize_step_type(value) when value in @step_types, do: value

  defp normalize_step_type(value) do
    value
    |> normalize_string()
    |> case do
      "" -> "send_action"
      other when other in @step_types -> other
      _ -> "send_action"
    end
  end

  defp normalize_string(value), do: value |> to_string() |> String.trim()

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_index(raw_index) do
    case Integer.parse(to_string(raw_index || "")) do
      {value, ""} when value >= 0 -> value
      _ -> -1
    end
  end

  defp parse_positive_integer(raw, default) do
    case Integer.parse(to_string(raw || "")) do
      {value, ""} when value > 0 -> value
      _ -> default
    end
  end

  defp parse_non_negative_integer(raw, default) do
    case Integer.parse(to_string(raw || "")) do
      {value, ""} when value >= 0 -> value
      _ -> default
    end
  end

  defp truthy?(value) when value in [true, "true", "1", "on", 1], do: true
  defp truthy?(_value), do: false
end
