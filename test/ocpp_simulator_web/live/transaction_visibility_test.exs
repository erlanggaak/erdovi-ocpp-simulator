defmodule OcppSimulatorWeb.Live.TransactionVisibilityTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias OcppSimulator.Application.UseCases.RunScenario
  alias OcppSimulator.Domain.Scenarios.Scenario

  @endpoint OcppSimulatorWeb.Endpoint

  defmodule ScenarioRepositoryStub do
    alias OcppSimulator.Domain.Scenarios.Scenario

    def get("scn-e2e-transaction") do
      build_scenario!(
        "scn-e2e-transaction",
        [
          %{
            id: "boot",
            type: :send_action,
            order: 1,
            payload: %{
              "action" => "BootNotification",
              "payload" => %{
                "chargePointVendor" => "Erdovi",
                "chargePointModel" => "Simulator"
              }
            }
          },
          %{
            id: "authorize",
            type: :send_action,
            order: 2,
            payload: %{"action" => "Authorize", "payload" => %{"idTag" => "RFID-1"}}
          },
          %{
            id: "start",
            type: :send_action,
            order: 3,
            payload: %{
              "action" => "StartTransaction",
              "payload" => %{
                "connectorId" => 1,
                "idTag" => "RFID-1",
                "meterStart" => 0,
                "timestamp" => "2026-04-01T10:00:00Z"
              }
            }
          },
          %{
            id: "meter",
            type: :send_action,
            order: 4,
            payload: %{
              "action" => "MeterValues",
              "payload" => %{
                "connectorId" => 1,
                "meterValue" => [
                  %{
                    "timestamp" => "2026-04-01T10:00:30Z",
                    "sampledValue" => [%{"value" => "1.25"}]
                  }
                ],
                "transactionId" => 1
              }
            }
          },
          %{
            id: "stop",
            type: :send_action,
            order: 5,
            payload: %{
              "action" => "StopTransaction",
              "payload" => %{
                "meterStop" => 100,
                "timestamp" => "2026-04-01T10:01:00Z",
                "transactionId" => 1
              }
            }
          }
        ]
      )
    end

    def get("scn-invalid-transition") do
      build_scenario!(
        "scn-invalid-transition",
        [
          %{
            id: "start",
            type: :send_action,
            order: 1,
            payload: %{
              "action" => "StartTransaction",
              "payload" => %{
                "connectorId" => 1,
                "idTag" => "RFID-1",
                "meterStart" => 0,
                "timestamp" => "2026-04-01T10:00:00Z"
              }
            }
          }
        ]
      )
    end

    def get(_id), do: {:error, :not_found}

    defp build_scenario!(id, steps) do
      Scenario.new(%{
        id: id,
        name: "Scenario #{id}",
        version: "1.0.0",
        steps: steps
      })
    end
  end

  defmodule ScenarioRunRepositoryStub do
    alias OcppSimulator.Domain.Runs.ScenarioRun

    @agent_key :task9_run_state_agent

    def insert(%ScenarioRun{} = run) do
      Agent.update(agent_pid(), &Map.put(&1, run.id, run))
      {:ok, run}
    end

    def get(run_id) do
      Agent.get(agent_pid(), fn runs ->
        case Map.fetch(runs, run_id) do
          {:ok, run} -> {:ok, run}
          :error -> {:error, :not_found}
        end
      end)
    end

    def update_state(run_id, state, metadata) do
      Agent.get_and_update(agent_pid(), fn runs ->
        case Map.fetch(runs, run_id) do
          {:ok, run} ->
            updated = %{run | state: state, metadata: Map.merge(run.metadata, metadata)}
            {{:ok, updated}, Map.put(runs, run_id, updated)}

          :error ->
            {{:error, :not_found}, runs}
        end
      end)
    end

    def list_history(filters) do
      page = parse_positive_integer(filters[:page] || filters["page"], 1)
      page_size = parse_positive_integer(filters[:page_size] || filters["page_size"], 25)
      scenario_id = normalize_string(filters[:scenario_id] || filters["scenario_id"])
      state = normalize_state(filters[:state] || filters["state"])
      states = normalize_states(filters[:states] || filters["states"])

      entries =
        agent_pid()
        |> Agent.get(&Map.values/1)
        |> Enum.filter(fn run ->
          scenario_matches?(run, scenario_id) and state_matches?(run, state, states)
        end)
        |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

      total_entries = length(entries)
      total_pages = max(div(total_entries + page_size - 1, page_size), 1)
      offset = (page - 1) * page_size

      paged_entries =
        entries
        |> Enum.drop(offset)
        |> Enum.take(page_size)

      {:ok,
       %{
         entries: paged_entries,
         page: page,
         page_size: page_size,
         total_entries: total_entries,
         total_pages: total_pages
       }}
    end

    defp agent_pid do
      Application.fetch_env!(:ocpp_simulator, @agent_key)
    end

    defp parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

    defp parse_positive_integer(value, default) when is_binary(value) do
      case Integer.parse(value) do
        {parsed, ""} when parsed > 0 -> parsed
        _ -> default
      end
    end

    defp parse_positive_integer(_value, default), do: default

    defp normalize_string(value) when is_binary(value) do
      case String.trim(value) do
        "" -> nil
        trimmed -> trimmed
      end
    end

    defp normalize_string(_value), do: nil

    defp normalize_state(nil), do: nil
    defp normalize_state(""), do: nil
    defp normalize_state(value) when is_atom(value), do: value

    defp normalize_state(value) when is_binary(value) do
      value
      |> String.trim()
      |> String.downcase()
      |> case do
        "" -> nil
        state -> String.to_existing_atom(state)
      end
    rescue
      ArgumentError -> nil
    end

    defp normalize_state(_value), do: nil

    defp normalize_states(nil), do: []

    defp normalize_states(values) when is_list(values) do
      values
      |> Enum.map(&normalize_state/1)
      |> Enum.reject(&is_nil/1)
    end

    defp normalize_states(_values), do: []

    defp scenario_matches?(_run, nil), do: true
    defp scenario_matches?(run, scenario_id), do: run.scenario_id == scenario_id

    defp state_matches?(_run, nil, []), do: true

    defp state_matches?(run, _state, states) when is_list(states) and states != [] do
      run.state in states
    end

    defp state_matches?(run, state, _states), do: run.state == state
  end

  defmodule LogRepositoryStub do
    @agent_key :task9_log_state_agent

    def insert(log_entry) when is_map(log_entry) do
      Agent.update(agent_pid(), fn entries -> [log_entry | entries] end)
      {:ok, log_entry}
    end

    def list(filters) when is_map(filters) do
      page = parse_positive_integer(filters[:page] || filters["page"], 1)
      page_size = parse_positive_integer(filters[:page_size] || filters["page_size"], 50)

      entries =
        agent_pid()
        |> Agent.get(& &1)
        |> Enum.filter(fn entry ->
          filter_match?(entry.run_id, filters[:run_id] || filters["run_id"]) and
            filter_match?(entry.session_id, filters[:session_id] || filters["session_id"]) and
            filter_match?(entry.message_id, filters[:message_id] || filters["message_id"]) and
            filter_match?(entry.severity, filters[:severity] || filters["severity"]) and
            filter_match?(entry.event_type, filters[:event_type] || filters["event_type"])
        end)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

      total_entries = length(entries)
      total_pages = max(div(total_entries + page_size - 1, page_size), 1)
      offset = (page - 1) * page_size

      paged_entries =
        entries
        |> Enum.drop(offset)
        |> Enum.take(page_size)

      {:ok,
       %{
         entries: paged_entries,
         page: page,
         page_size: page_size,
         total_entries: total_entries,
         total_pages: total_pages
       }}
    end

    defp agent_pid do
      Application.fetch_env!(:ocpp_simulator, @agent_key)
    end

    defp parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

    defp parse_positive_integer(value, default) when is_binary(value) do
      case Integer.parse(value) do
        {parsed, ""} when parsed > 0 -> parsed
        _ -> default
      end
    end

    defp parse_positive_integer(_value, default), do: default

    defp filter_match?(_entry_value, nil), do: true
    defp filter_match?(_entry_value, ""), do: true
    defp filter_match?(entry_value, value), do: to_string(entry_value || "") == to_string(value)
  end

  defmodule IdGeneratorStub do
    def generate("run"),
      do: "run-e2e-#{System.unique_integer([:positive, :monotonic])}"

    def generate(namespace),
      do: "#{namespace}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defmodule WebhookDispatcherStub do
    def dispatch_run_event(event, run, _metadata) do
      send(self(), {:webhook_dispatched, event, run.id})
      :ok
    end
  end

  setup do
    {:ok, run_agent} = Agent.start_link(fn -> %{} end)
    {:ok, log_agent} = Agent.start_link(fn -> [] end)

    previous_run_repository = Application.get_env(:ocpp_simulator, :scenario_run_repository)
    previous_log_repository = Application.get_env(:ocpp_simulator, :log_repository)
    previous_run_agent = Application.get_env(:ocpp_simulator, :task9_run_state_agent)
    previous_log_agent = Application.get_env(:ocpp_simulator, :task9_log_state_agent)

    Application.put_env(:ocpp_simulator, :scenario_run_repository, ScenarioRunRepositoryStub)
    Application.put_env(:ocpp_simulator, :log_repository, LogRepositoryStub)
    Application.put_env(:ocpp_simulator, :task9_run_state_agent, run_agent)
    Application.put_env(:ocpp_simulator, :task9_log_state_agent, log_agent)

    on_exit(fn ->
      restore_env(:scenario_run_repository, previous_run_repository)
      restore_env(:log_repository, previous_log_repository)
      restore_env(:task9_run_state_agent, previous_run_agent)
      restore_env(:task9_log_state_agent, previous_log_agent)
    end)

    :ok
  end

  test "realistic transaction lifecycle is visible from queued to succeeded across live interfaces" do
    dependencies = %{
      scenario_repository: ScenarioRepositoryStub,
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub,
      id_generator: IdGeneratorStub
    }

    assert {:ok, queued_run} =
             RunScenario.start_run(dependencies, %{scenario_id: "scn-e2e-transaction"}, :operator)

    assert {:ok, queued_snapshot} = ScenarioRunRepositoryStub.get(queued_run.id)
    assert queued_snapshot.state == :queued

    assert {:ok, queued_history_page} =
             ScenarioRunRepositoryStub.list_history(%{state: :queued, page: 1, page_size: 25})

    assert Enum.any?(queued_history_page.entries, fn entry ->
             entry.id == queued_run.id and entry.state == :queued
           end)

    assert {:ok, completed_run} =
             RunScenario.execute_run(dependencies, queued_run.id, :system)

    assert completed_run.state == :succeeded
    assert {:ok, succeeded_snapshot} = ScenarioRunRepositoryStub.get(queued_run.id)
    assert succeeded_snapshot.state == :succeeded

    queued_run_id = queued_run.id
    assert_receive {:webhook_dispatched, :run_succeeded, ^queued_run_id}

    console_response =
      viewer_conn()
      |> get("/live-console?run_id=#{queued_run.id}")
      |> html_response(200)

    assert console_response =~ "Live Console"
    assert console_response =~ queued_run.id
    assert console_response =~ "scenario.run.executed"

    assert {:ok, history_page} = ScenarioRunRepositoryStub.list_history(%{page: 1, page_size: 25})

    assert Enum.any?(history_page.entries, fn entry ->
             entry.id == queued_run.id and entry.state == :succeeded
           end)

    history_response =
      viewer_conn()
      |> get("/run-history?page_size=25")
      |> html_response(200)

    assert history_response =~ "Run History"
    assert history_response =~ queued_run.id
    assert history_response =~ "succeeded"

    logs_response =
      viewer_conn()
      |> get("/logs?run_id=#{queued_run.id}")
      |> html_response(200)

    assert logs_response =~ queued_run.id
    assert logs_response =~ "scenario.run.executed"
  end

  test "state-transition validation failures surface actionable reason in run history" do
    dependencies = %{
      scenario_repository: ScenarioRepositoryStub,
      scenario_run_repository: ScenarioRunRepositoryStub,
      webhook_dispatcher: WebhookDispatcherStub,
      id_generator: IdGeneratorStub
    }

    assert {:ok, queued_run} =
             RunScenario.start_run(
               dependencies,
               %{scenario_id: "scn-invalid-transition"},
               :operator
             )

    assert {:ok, failed_run} =
             RunScenario.execute_run(dependencies, queued_run.id, :system)

    assert failed_run.state == :failed
    assert match?({:invalid_transition, :none, :started}, failed_run.metadata.failure_reason)
    assert {:ok, stored_failed_run} = ScenarioRunRepositoryStub.get(queued_run.id)
    assert stored_failed_run.state == :failed

    queued_run_id = queued_run.id
    assert_receive {:webhook_dispatched, :run_failed, ^queued_run_id}

    assert {:ok, history_page} = ScenarioRunRepositoryStub.list_history(%{page: 1, page_size: 25})

    assert Enum.any?(history_page.entries, fn entry ->
             failure_reason =
               Map.get(entry.metadata, :failure_reason) ||
                 Map.get(entry.metadata, "failure_reason")

             entry.id == queued_run.id and inspect(failure_reason) =~ "invalid_transition"
           end)

    history_response =
      viewer_conn()
      |> get("/run-history?page_size=25")
      |> html_response(200)

    assert history_response =~ "invalid_transition"
  end

  test "scenario builder shows actionable schema validation errors" do
    {:ok, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.mount(
        %{},
        %{},
        live_socket(%{current_role: :operator})
      )

    {:noreply, socket} =
      OcppSimulatorWeb.ScenarioBuilderLive.handle_event(
        "update_visual",
        %{
          "scenario" => %{
            "id" => "",
            "name" => "",
            "version" => "1.0",
            "steps_json" => "{invalid-json"
          }
        },
        socket
      )

    assert socket.assigns.field_errors[:id] == "Must be a non-empty value."
    assert socket.assigns.field_errors[:name] == "Must be a non-empty value."
    assert socket.assigns.field_errors[:version] =~ "semantic version"
    assert socket.assigns.field_errors[:steps] == "Steps must be valid JSON array format."

    assert Enum.any?(socket.assigns.validation_summary, fn message ->
             String.contains?(message, "Scenario schema validation failed")
           end)
  end

  defp viewer_conn do
    build_conn()
    |> init_test_session(%{"current_role" => "viewer"})
  end

  defp live_socket(assigns) when is_map(assigns) do
    base_assigns =
      %{
        __changed__: %{},
        current_role: :viewer,
        permission_grants: %{}
      }
      |> Map.merge(assigns)

    %Phoenix.LiveView.Socket{assigns: base_assigns}
  end

  defp restore_env(key, nil), do: Application.delete_env(:ocpp_simulator, key)
  defp restore_env(key, value), do: Application.put_env(:ocpp_simulator, key, value)
end
