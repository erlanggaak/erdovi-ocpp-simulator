defmodule OcppSimulator.Infrastructure.Integrations.WebhookDispatcherTest do
  use ExUnit.Case, async: false

  @results_key :webhook_dispatcher_test_http_results

  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Infrastructure.Integrations.WebhookDispatcher

  defmodule WebhookEndpointRepositoryStub do
    def list(_filters) do
      {:ok,
       %{
         entries: [
           %{
             id: "wh-endpoint-1",
             name: "QA Webhook",
             url: "https://example.test/webhook",
             events: ["run.succeeded", "run.failed"],
             retry_policy: %{max_attempts: 2, backoff_ms: 1},
             secret_ref: "whsec_test",
             metadata: %{}
           }
         ],
         page: 1,
         page_size: 50,
         total_entries: 1,
         total_pages: 1
       }}
    end
  end

  defmodule WebhookDeliveryRepositoryStub do
    def insert(delivery) do
      notify({:delivery_insert, delivery})
      {:ok, delivery}
    end

    def update_status(id, status, attrs) do
      notify({:delivery_update_status, id, status, attrs})
      {:ok, Map.merge(%{id: id, status: status}, attrs)}
    end

    defp notify(message) do
      if pid = Process.whereis(:webhook_dispatcher_test_listener) do
        send(pid, message)
      else
        send(self(), message)
      end
    end
  end

  defmodule HttpClientStub do
    def post(url, body, headers, _opts) do
      notify({:webhook_http_post, url, body, headers})

      [next_result | remaining_results] =
        :persistent_term.get(
          OcppSimulator.Infrastructure.Integrations.WebhookDispatcherTest.http_results_key(),
          [{:ok, ok_response()}]
        )

      :persistent_term.put(
        OcppSimulator.Infrastructure.Integrations.WebhookDispatcherTest.http_results_key(),
        remaining_results
      )

      case next_result do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, reason}
        response when is_map(response) -> {:ok, response}
      end
    end

    defp ok_response do
      %{status: 200, headers: [{"content-type", "application/json"}], body: "{\"ok\":true}"}
    end

    defp notify(message) do
      if pid = Process.whereis(:webhook_dispatcher_test_listener) do
        send(pid, message)
      else
        send(self(), message)
      end
    end
  end

  defmodule IdGeneratorStub do
    def generate(namespace) do
      count = Process.get({:id_counter, namespace}, 0) + 1
      Process.put({:id_counter, namespace}, count)
      "#{namespace}-#{count}"
    end
  end

  setup do
    previous_endpoint_repository =
      Application.get_env(:ocpp_simulator, :webhook_endpoint_repository)

    previous_delivery_repository =
      Application.get_env(:ocpp_simulator, :webhook_delivery_repository)

    previous_http_client = Application.get_env(:ocpp_simulator, :webhook_http_client)
    previous_id_generator = Application.get_env(:ocpp_simulator, :id_generator)
    previous_runtime = Application.get_env(:ocpp_simulator, :runtime)

    Application.put_env(
      :ocpp_simulator,
      :webhook_endpoint_repository,
      WebhookEndpointRepositoryStub
    )

    Application.put_env(
      :ocpp_simulator,
      :webhook_delivery_repository,
      WebhookDeliveryRepositoryStub
    )

    Application.put_env(:ocpp_simulator, :webhook_http_client, HttpClientStub)
    Application.put_env(:ocpp_simulator, :id_generator, IdGeneratorStub)

    Application.put_env(:ocpp_simulator, :runtime,
      webhook_delivery_timeout_ms: 100,
      webhook_delivery_default_max_attempts: 2,
      webhook_delivery_default_backoff_ms: 1
    )

    Process.register(self(), :webhook_dispatcher_test_listener)
    :persistent_term.put(@results_key, [{:ok, %{status: 200, headers: [], body: "ok"}}])

    on_exit(fn ->
      restore_env(:webhook_endpoint_repository, previous_endpoint_repository)
      restore_env(:webhook_delivery_repository, previous_delivery_repository)
      restore_env(:webhook_http_client, previous_http_client)
      restore_env(:id_generator, previous_id_generator)
      restore_env(:runtime, previous_runtime)

      if Process.whereis(:webhook_dispatcher_test_listener) == self() do
        Process.unregister(:webhook_dispatcher_test_listener)
      end

      :persistent_term.erase(@results_key)
    end)

    :ok
  end

  test "dispatch_run_event/3 delivers webhook and persists delivered status" do
    :persistent_term.put(@results_key, [{:ok, %{status: 200, headers: [], body: "ok"}}])

    assert :ok =
             WebhookDispatcher.dispatch_run_event(:run_succeeded, sample_run(), %{source: "test"})

    assert_receive {:delivery_insert, %{status: :queued, event: "run.succeeded"}}, 500
    assert_receive {:webhook_http_post, "https://example.test/webhook", _body, headers}, 500

    assert Enum.any?(headers, fn {name, _value} ->
             String.downcase(name) == "x-ocpp-webhook-signature"
           end)

    assert_receive {:delivery_update_status, _id, :delivered, %{attempts: 1}}, 500
  end

  test "dispatch_run_event/3 retries and marks delivery failed after retry budget" do
    :persistent_term.put(@results_key, [{:error, :timeout}, {:error, :timeout}])

    assert :ok =
             WebhookDispatcher.dispatch_run_event(:run_failed, sample_run(), %{source: "test"})

    assert_receive {:delivery_insert, %{status: :queued, event: "run.failed"}}, 500

    assert_receive {:delivery_update_status, _id, :retrying, %{attempts: 1, last_error: error}},
                   500

    assert error =~ ":timeout"

    assert_receive {:delivery_update_status, _id, :failed,
                    %{attempts: 2, last_error: final_error}},
                   500

    assert final_error =~ ":timeout"
  end

  test "validate_signature/3 accepts valid signatures and rejects mismatches" do
    payload = ~s({"event":"run.succeeded"})
    secret = "whsec_test"

    valid_signature =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    assert :ok = WebhookDispatcher.validate_signature(payload, valid_signature, secret)

    assert {:error, :invalid_signature} =
             WebhookDispatcher.validate_signature(payload, valid_signature <> "x", secret)
  end

  test "dispatch_run_event/3 redacts secret-like fields in persisted payload and outbound body" do
    :persistent_term.put(@results_key, [{:ok, %{status: 200, headers: [], body: "ok"}}])

    assert :ok =
             WebhookDispatcher.dispatch_run_event(
               :run_succeeded,
               sample_run(),
               %{
                 "source" => "test",
                 "secret_ref" => "whsec_dispatch",
                 "authorization" => "Bearer token"
               }
             )

    assert_receive {:delivery_insert, %{payload: payload}}, 500

    assert payload.run.metadata["token"] == "[REDACTED]"
    assert payload.dispatch_metadata["secret_ref"] == "[REDACTED]"
    assert payload.dispatch_metadata["authorization"] == "[REDACTED]"

    assert_receive {:webhook_http_post, "https://example.test/webhook", body, _headers}, 500
    assert body =~ "[REDACTED]"
    refute body =~ "abc.def.ghi"
    refute body =~ "whsec_dispatch"
  end

  defp sample_run do
    {:ok, scenario} =
      Scenario.new(%{
        id: "scenario-wh-1",
        name: "Webhook Scenario",
        version: "1.0.0",
        steps: [%{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}]
      })

    {:ok, run} =
      ScenarioRun.new(%{
        id: "run-wh-1",
        scenario: scenario,
        state: :succeeded,
        metadata: %{"token" => "abc.def.ghi"}
      })

    run
  end

  defp restore_env(key, nil), do: Application.delete_env(:ocpp_simulator, key)
  defp restore_env(key, value), do: Application.put_env(:ocpp_simulator, key, value)

  def http_results_key, do: @results_key
end
