defmodule OcppSimulatorWeb.ScenarioBuilderLive do
  use OcppSimulatorWeb, :live_view

  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Application.UseCases.ScenarioEditor
  alias OcppSimulator.Domain.Scenarios.Scenario

  @semver ~r/^\d+\.\d+\.\d+$/

  @impl true
  def mount(_params, _session, socket) do
    visual_model = default_visual_model()
    raw_json = encode_visual_model(visual_model)
    {field_errors, validation_summary, preview_rows} = validate_visual_model(visual_model)

    {:ok,
     assign(socket,
       page_title: "Scenario Builder",
       mode: "visual",
       visual_model: visual_model,
       raw_json: raw_json,
       steps_json: Jason.encode!(visual_model["steps"]),
       field_errors: field_errors,
       validation_summary: validation_summary,
       preview_rows: preview_rows,
       feedback: nil
     )}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => "raw"}, socket) do
    raw_json = encode_visual_model(socket.assigns.visual_model)

    {:noreply,
     assign(socket,
       mode: "raw",
       raw_json: raw_json,
       feedback: "Switched to raw JSON mode."
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
           steps_json: Jason.encode!(visual_model["steps"]),
           field_errors: field_errors,
           validation_summary: validation_summary,
           preview_rows: preview_rows,
           feedback: "Switched to visual mode."
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           feedback:
             "Cannot switch to visual mode until raw JSON is valid. Reason: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def handle_event("update_visual", %{"scenario" => params}, socket) do
    {visual_model, steps_parse_error} = merge_visual_model(socket.assigns.visual_model, params)
    {field_errors, validation_summary, preview_rows} = validate_visual_model(visual_model)
    field_errors = maybe_put_steps_parse_error(field_errors, steps_parse_error)

    {:noreply,
     assign(socket,
       visual_model: visual_model,
       steps_json: Map.get(params, "steps_json", socket.assigns.steps_json),
       raw_json: encode_visual_model(visual_model),
       field_errors: field_errors,
       validation_summary: validation_summary,
       preview_rows: preview_rows,
       feedback: nil
     )}
  end

  @impl true
  def handle_event("update_raw", %{"scenario" => %{"raw_json" => raw_json}}, socket) do
    {field_errors, validation_summary, preview_rows} = validate_raw_json(raw_json)

    {:noreply,
     assign(socket,
       raw_json: raw_json,
       field_errors: field_errors,
       validation_summary: validation_summary,
       preview_rows: preview_rows,
       feedback: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page-shell">
      <h1><%= @page_title %></h1>
      <p>Dual-mode authoring with shared validation and request/response preview.</p>
      <p :if={@feedback}><%= @feedback %></p>

      <section>
        <button type="button" phx-click="switch_mode" phx-value-mode="visual">Visual Mode</button>
        <button type="button" phx-click="switch_mode" phx-value-mode="raw">Raw JSON Mode</button>
      </section>

      <section :if={@mode == "visual"}>
        <.form for={%{}} as={:scenario} phx-change="update_visual">
          <label>
            Scenario ID
            <input type="text" name="scenario[id]" value={@visual_model["id"]} />
          </label>
          <p :if={@field_errors[:id]}><%= @field_errors[:id] %></p>

          <label>
            Name
            <input type="text" name="scenario[name]" value={@visual_model["name"]} />
          </label>
          <p :if={@field_errors[:name]}><%= @field_errors[:name] %></p>

          <label>
            Version
            <input type="text" name="scenario[version]" value={@visual_model["version"]} />
          </label>
          <p :if={@field_errors[:version]}><%= @field_errors[:version] %></p>

          <label>
            Steps JSON
            <textarea name="scenario[steps_json]" rows="12"><%= @steps_json %></textarea>
          </label>
          <p :if={@field_errors[:steps]}><%= @field_errors[:steps] %></p>
        </.form>
      </section>

      <section :if={@mode == "raw"}>
        <.form for={%{}} as={:scenario} phx-change="update_raw">
          <label>
            Raw Scenario JSON
            <textarea name="scenario[raw_json]" rows="18"><%= @raw_json %></textarea>
          </label>
        </.form>
      </section>

      <section>
        <h2>Run Validation Summary</h2>
        <ul>
          <li :for={item <- @validation_summary}><%= item %></li>
        </ul>
      </section>

      <section>
        <h2>Request/Response Preview</h2>
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
      </section>
    </main>
    """
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
      "steps" => [
        %{
          "id" => "boot",
          "type" => "send_action",
          "order" => 1,
          "payload" => %{"action" => "BootNotification", "chargePointVendor" => "Erdovi"},
          "delay_ms" => 0,
          "loop_count" => 1,
          "enabled" => true
        },
        %{
          "id" => "await_boot",
          "type" => "await_response",
          "order" => 2,
          "payload" => %{"action" => "BootNotification"},
          "delay_ms" => 0,
          "loop_count" => 1,
          "enabled" => true
        }
      ]
    }
  end

  defp merge_visual_model(base, params) when is_map(base) and is_map(params) do
    base_model =
      base
      |> Map.put("id", normalize_string(Map.get(params, "id", base["id"])))
      |> Map.put("name", normalize_string(Map.get(params, "name", base["name"])))
      |> Map.put("version", normalize_string(Map.get(params, "version", base["version"])))

    case parse_steps(Map.get(params, "steps_json", Jason.encode!(base["steps"]))) do
      {:ok, steps} ->
        {Map.put(base_model, "steps", steps), nil}

      {:error, reason} ->
        {base_model, reason}
    end
  end

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

  defp to_validation_summary([]), do: ["Validation passed. Scenario is executable."]

  defp to_validation_summary(errors) when is_list(errors) do
    Enum.map(errors, fn error -> "Pre-run validation error: #{error}" end)
  end

  defp preview_rows(%Scenario{} = scenario) do
    {:ok, plan} = Scenario.execution_plan(scenario)

    plan
    |> Enum.flat_map(fn step ->
      action = step_action(step.payload)
      correlation_id = "corr-#{step.step_id}-#{step.execution_order}"

      case step.step_type do
        :send_action ->
          [
            %{step_id: step.step_id, direction: "request", action: action, correlation_id: correlation_id},
            %{step_id: step.step_id, direction: "response", action: action, correlation_id: correlation_id}
          ]

        :await_response ->
          [
            %{step_id: step.step_id, direction: "await", action: action, correlation_id: correlation_id}
          ]

        _ ->
          []
      end
    end)
  end

  defp step_action(payload) when is_map(payload) do
    Map.get(payload, "action") || Map.get(payload, :action) || "-"
  end

  defp parse_steps(raw_steps_json) do
    case Jason.decode(raw_steps_json) do
      {:ok, steps} when is_list(steps) -> {:ok, steps}
      {:ok, _decoded} -> {:error, :steps_must_be_array}
      {:error, _reason} -> {:error, :invalid_steps_json}
    end
  end

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
  defp maybe_add_steps_error(errors, _steps), do: Map.put(errors, :steps, "Steps must be a JSON array.")

  defp maybe_put_steps_parse_error(field_errors, nil), do: field_errors

  defp maybe_put_steps_parse_error(field_errors, :steps_must_be_array) do
    Map.put(field_errors, :steps, "Steps must decode to a JSON array.")
  end

  defp maybe_put_steps_parse_error(field_errors, :invalid_steps_json) do
    Map.put(field_errors, :steps, "Steps must be valid JSON array format.")
  end

  defp encode_visual_model(visual_model) do
    case ScenarioEditor.visual_to_raw_json(visual_model) do
      {:ok, raw_json} ->
        raw_json

      {:error, _reason} ->
        Jason.encode!(visual_model)
    end
  end

  defp normalize_string(value), do: value |> to_string() |> String.trim()
end
