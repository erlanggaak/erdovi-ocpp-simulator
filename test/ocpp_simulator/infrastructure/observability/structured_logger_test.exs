defmodule OcppSimulator.Infrastructure.Observability.StructuredLoggerTest do
  use ExUnit.Case, async: false

  require Logger

  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulator.Infrastructure.Security.SensitiveDataMasker

  defmodule LogRepositoryStub do
    def insert(entry) do
      send(self(), {:log_inserted, entry})
      {:ok, entry}
    end
  end

  setup do
    previous_log_repository = Application.get_env(:ocpp_simulator, :log_repository)
    Application.put_env(:ocpp_simulator, :log_repository, LogRepositoryStub)

    on_exit(fn ->
      if previous_log_repository do
        Application.put_env(:ocpp_simulator, :log_repository, previous_log_repository)
      else
        Application.delete_env(:ocpp_simulator, :log_repository)
      end
    end)

    :ok
  end

  test "persists masked payload with correlation fields" do
    payload = %{
      run_id: "run-log-1",
      session_id: "session-log-1",
      action: "Authorize",
      step_id: "step-1",
      token: "abc.def.ghi",
      secret_ref: "whsec_logger",
      authorization: "Bearer abcdefghijklmnopqrstuvwxyz"
    }

    assert :ok = StructuredLogger.info("scenario.step.executed", payload)

    assert_received {:log_inserted, entry}
    assert entry.run_id == "run-log-1"
    assert entry.session_id == "session-log-1"
    assert entry.action == "Authorize"
    assert entry.step_id == "step-1"
    assert entry.payload[:token] == SensitiveDataMasker.redacted()
    assert entry.payload[:secret_ref] == SensitiveDataMasker.redacted()
    assert entry.payload[:authorization] == SensitiveDataMasker.redacted()
    assert entry.event_type == "scenario.step.executed"
  end

  test "does not leak stale correlation metadata across events" do
    assert :ok =
             StructuredLogger.info("scenario.run.queued", %{
               run_id: "run-a",
               session_id: "session-a"
             })

    assert :ok =
             StructuredLogger.info("scenario.run.queued", %{
               run_id: "run-b"
             })

    metadata = Logger.metadata()
    assert metadata[:run_id] == "run-b"
    assert is_nil(metadata[:session_id])
  end
end
