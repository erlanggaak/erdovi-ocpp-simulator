defmodule OcppSimulator.Infrastructure.Persistence.Mongo.PaginationFilterTest do
  use ExUnit.Case, async: false

  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository
  alias OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository
  alias OcppSimulator.TestSupport.InMemoryMongoClient

  setup_all do
    original_client = Application.get_env(:ocpp_simulator, :mongo_persistence_client)
    original_topology = Application.get_env(:ocpp_simulator, :mongo_persistence_topology)

    Application.put_env(:ocpp_simulator, :mongo_persistence_client, InMemoryMongoClient)
    Application.put_env(:ocpp_simulator, :mongo_persistence_topology, :in_memory_test_topology)

    on_exit(fn ->
      if original_client do
        Application.put_env(:ocpp_simulator, :mongo_persistence_client, original_client)
      else
        Application.delete_env(:ocpp_simulator, :mongo_persistence_client)
      end

      if original_topology do
        Application.put_env(:ocpp_simulator, :mongo_persistence_topology, original_topology)
      else
        Application.delete_env(:ocpp_simulator, :mongo_persistence_topology)
      end
    end)

    :ok
  end

  setup do
    InMemoryMongoClient.reset!()
    :ok
  end

  test "run history query is paginated, sorted, and bounded" do
    scenario = build_scenario!("scn-history-1")

    [
      {"run-1", ~U[2026-04-01 10:00:00Z]},
      {"run-2", ~U[2026-04-01 10:05:00Z]},
      {"run-3", ~U[2026-04-01 10:10:00Z]}
    ]
    |> Enum.each(fn {run_id, created_at} ->
      run =
        build_run!(run_id, scenario)
        |> Map.put(:created_at, created_at)

      assert {:ok, _} = ScenarioRunRepository.insert(run)
    end)

    assert {:ok, page_1} =
             ScenarioRunRepository.list_history(%{
               scenario_id: "scn-history-1",
               page: 1,
               page_size: 2
             })

    assert page_1.total_entries == 3
    assert page_1.total_pages == 2
    assert Enum.map(page_1.entries, & &1.id) == ["run-3", "run-2"]

    assert {:ok, page_2} =
             ScenarioRunRepository.list_history(%{
               scenario_id: "scn-history-1",
               page: 2,
               page_size: 2
             })

    assert Enum.map(page_2.entries, & &1.id) == ["run-1"]
  end

  test "run history rejects oversized page size" do
    assert {:error, {:invalid_field, :page_size, {:must_be_lte, 100}}} =
             ScenarioRunRepository.list_history(%{page_size: 500})
  end

  test "logs enforce filter-first by default" do
    assert {:error, {:invalid_filters, :at_least_one_filter_required}} =
             LogRepository.list(%{page: 1, page_size: 10})
  end

  test "logs pagination remains bounded when unfiltered access is explicitly allowed" do
    now = ~U[2026-04-01 11:00:00Z]

    assert {:ok, _} =
             LogRepository.insert(%{
               id: "log-a",
               run_id: "run-a",
               session_id: "session-a",
               severity: "info",
               event_type: "protocol",
               payload: %{},
               timestamp: DateTime.add(now, 10, :second)
             })

    assert {:ok, _} =
             LogRepository.insert(%{
               id: "log-b",
               run_id: "run-b",
               session_id: "session-b",
               severity: "warn",
               event_type: "scenario",
               payload: %{},
               timestamp: now
             })

    assert {:ok, page} = LogRepository.list(%{allow_unfiltered: true, page: 1, page_size: 1})

    assert page.total_entries == 2
    assert page.total_pages == 2
    assert length(page.entries) == 1
    assert Enum.at(page.entries, 0).id == "log-a"
  end

  test "history and logs queries stay within baseline latency under larger in-memory datasets" do
    scenario = build_scenario!("scn-perf-1")
    base = ~U[2026-04-02 09:00:00Z]

    Enum.each(1..250, fn index ->
      run =
        build_run!("run-perf-#{index}", scenario)
        |> Map.put(:created_at, DateTime.add(base, index, :second))

      assert {:ok, _} = ScenarioRunRepository.insert(run)
    end)

    Enum.each(1..300, fn index ->
      assert {:ok, _} =
               LogRepository.insert(%{
                 id: "log-perf-#{index}",
                 run_id: if(rem(index, 2) == 0, do: "run-perf-focus", else: "run-perf-other"),
                 session_id: "session-perf-#{index}",
                 severity: "info",
                 event_type: "scenario.run.executed",
                 payload: %{},
                 timestamp: DateTime.add(base, index, :second)
               })
    end)

    started_history = System.monotonic_time(:millisecond)

    assert {:ok, history_page} =
             ScenarioRunRepository.list_history(%{
               scenario_id: "scn-perf-1",
               page: 1,
               page_size: 50
             })

    history_elapsed_ms = System.monotonic_time(:millisecond) - started_history

    assert history_page.total_entries == 250
    assert length(history_page.entries) == 50
    assert history_elapsed_ms < 500

    started_logs = System.monotonic_time(:millisecond)

    assert {:ok, logs_page} =
             LogRepository.list(%{
               run_id: "run-perf-focus",
               page: 1,
               page_size: 50
             })

    logs_elapsed_ms = System.monotonic_time(:millisecond) - started_logs

    assert logs_page.total_entries == 150
    assert length(logs_page.entries) == 50
    assert logs_elapsed_ms < 500
  end

  defp build_scenario!(id) do
    {:ok, scenario} =
      Scenario.new(%{
        id: id,
        name: "Scenario #{id}",
        version: "1.0.0",
        steps: [
          %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}}
        ]
      })

    scenario
  end

  defp build_run!(id, scenario) do
    {:ok, run} =
      ScenarioRun.new(%{
        id: id,
        scenario: scenario,
        state: :queued,
        metadata: %{}
      })

    run
  end
end
