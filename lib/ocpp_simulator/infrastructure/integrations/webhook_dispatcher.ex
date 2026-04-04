defmodule OcppSimulator.Infrastructure.Integrations.WebhookDispatcher do
  @moduledoc """
  Dispatches scenario-run terminal events to configured webhook endpoints with retries.
  """

  @behaviour OcppSimulator.Application.Contracts.WebhookDispatcher

  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Infrastructure.Integrations.HttpClient
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulator.Infrastructure.Security.SensitiveDataMasker

  @default_endpoint_repository OcppSimulator.Infrastructure.Persistence.Mongo.WebhookEndpointRepository
  @default_delivery_repository OcppSimulator.Infrastructure.Persistence.Mongo.WebhookDeliveryRepository
  @default_id_generator OcppSimulator.Infrastructure.Support.IdGenerator

  @event_name_mapping %{
    run_succeeded: "run.succeeded",
    run_failed: "run.failed",
    run_canceled: "run.canceled",
    run_timed_out: "run.timed_out"
  }

  @impl true
  def dispatch_run_event(run_event, %ScenarioRun{} = run, metadata) when is_map(metadata) do
    deps = %{
      delivery_repository: delivery_repository(),
      id_generator: id_generator(),
      http_client: http_client(),
      runtime: runtime_config()
    }

    with {:ok, event_name} <- normalize_event(run_event),
         {:ok, endpoints} <- list_event_endpoints(event_name) do
      endpoints
      |> Enum.each(fn endpoint ->
        _ = schedule_delivery(endpoint, event_name, run, metadata, deps)
      end)

      :ok
    else
      {:error, reason} ->
        StructuredLogger.warn("webhook.dispatch.skipped", %{
          persist: true,
          run_id: run.id,
          event: run_event,
          reason: inspect(reason)
        })

        :ok
    end
  end

  def dispatch_run_event(_run_event, _run, _metadata), do: :ok

  defp schedule_delivery(endpoint, event_name, run, metadata, deps) do
    task_fun = fn -> deliver_to_endpoint(endpoint, event_name, run, metadata, deps) end

    case Task.Supervisor.start_child(OcppSimulator.Application.UseCaseTaskSupervisor, task_fun) do
      {:ok, _pid} ->
        :ok

      {:error, _reason} ->
        # Fall back to lightweight task scheduling if supervisor is unavailable.
        case Task.start(task_fun) do
          {:ok, _pid} ->
            :ok

          {:error, reason} ->
            StructuredLogger.error("webhook.dispatch.schedule_failed", %{
              persist: true,
              run_id: run.id,
              event: event_name,
              endpoint_id: fetch(endpoint, :id),
              reason: inspect(reason)
            })

            :ok
        end
    end
  rescue
    _ ->
      StructuredLogger.error("webhook.dispatch.schedule_failed", %{
        persist: true,
        run_id: run.id,
        event: event_name,
        endpoint_id: fetch(endpoint, :id),
        reason: "unexpected_scheduler_error"
      })

      :ok
  end

  @spec validate_signature(String.t(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def validate_signature(_payload, _signature, nil), do: :ok
  def validate_signature(_payload, _signature, ""), do: :ok

  def validate_signature(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    expected_signature = build_signature(payload, secret)

    if Plug.Crypto.secure_compare(signature, expected_signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def validate_signature(_payload, _signature, _secret), do: {:error, :invalid_signature}

  defp deliver_to_endpoint(endpoint, event_name, run, metadata, deps) do
    delivery_repository = deps.delivery_repository
    runtime = deps.runtime
    payload = build_webhook_payload(endpoint, event_name, run, metadata)

    delivery_id = deps.id_generator.generate("webhook-delivery")

    with {:ok, queued_delivery} <-
           delivery_repository.insert(%{
             id: delivery_id,
             run_id: run.id,
             event: event_name,
             status: :queued,
             attempts: 0,
             payload: payload,
             metadata: %{
               endpoint_id: fetch(endpoint, :id),
               endpoint_name: fetch(endpoint, :name)
             }
           }),
         :ok <- attempt_delivery(endpoint, queued_delivery, payload, runtime, deps) do
      :ok
    else
      {:error, reason} ->
        StructuredLogger.error("webhook.delivery.enqueue_failed", %{
          persist: true,
          run_id: run.id,
          event: event_name,
          endpoint_id: fetch(endpoint, :id),
          reason: inspect(reason)
        })

        :ok
    end
  end

  defp attempt_delivery(endpoint, delivery, payload, runtime, deps) do
    payload_json = Jason.encode!(payload)
    timeout_ms = runtime[:webhook_delivery_timeout_ms] || 5_000
    policy = normalized_retry_policy(endpoint, runtime)

    do_attempt_delivery(endpoint, delivery, payload_json, timeout_ms, policy, 1, deps)
  end

  defp do_attempt_delivery(endpoint, delivery, payload_json, timeout_ms, policy, attempt, deps) do
    signature = maybe_signature(payload_json, fetch(endpoint, :secret_ref))
    headers = build_headers(signature)

    with :ok <- validate_signature(payload_json, signature, fetch(endpoint, :secret_ref)),
         {:ok, response} <-
           deps.http_client.post(fetch(endpoint, :url), payload_json, headers,
             timeout: timeout_ms
           ),
         :ok <- ensure_success_status(response.status),
         {:ok, _updated_delivery} <-
           deps.delivery_repository.update_status(delivery.id, :delivered, %{
             attempts: attempt,
             response_summary: response_summary(response),
             metadata: %{delivered_at: DateTime.utc_now()}
           }) do
      StructuredLogger.info("webhook.delivery.succeeded", %{
        persist: true,
        run_id: delivery.run_id,
        endpoint_id: fetch(endpoint, :id),
        event: delivery.event,
        attempts: attempt,
        status_code: response.status
      })

      :ok
    else
      {:error, reason} ->
        if attempt < policy.max_attempts do
          _ =
            deps.delivery_repository.update_status(delivery.id, :retrying, %{
              attempts: attempt,
              last_error: inspect(reason),
              metadata: %{retry_scheduled_at: DateTime.utc_now()}
            })

          StructuredLogger.warn("webhook.delivery.retrying", %{
            persist: true,
            run_id: delivery.run_id,
            endpoint_id: fetch(endpoint, :id),
            event: delivery.event,
            attempt: attempt,
            next_attempt: attempt + 1,
            reason: inspect(reason)
          })

          Process.sleep(policy.backoff_ms)

          do_attempt_delivery(
            endpoint,
            delivery,
            payload_json,
            timeout_ms,
            policy,
            attempt + 1,
            deps
          )
        else
          _ =
            deps.delivery_repository.update_status(delivery.id, :failed, %{
              attempts: attempt,
              last_error: inspect(reason),
              metadata: %{failed_at: DateTime.utc_now()}
            })

          StructuredLogger.error("webhook.delivery.failed", %{
            persist: true,
            run_id: delivery.run_id,
            endpoint_id: fetch(endpoint, :id),
            event: delivery.event,
            attempts: attempt,
            reason: inspect(reason)
          })

          :ok
        end
    end
  end

  defp normalize_event(run_event) do
    case Map.fetch(@event_name_mapping, run_event) do
      {:ok, event_name} -> {:ok, event_name}
      :error -> {:error, {:unsupported_run_event, run_event}}
    end
  end

  defp normalized_retry_policy(endpoint, runtime) do
    endpoint_policy = fetch(endpoint, :retry_policy) || %{}

    %{
      max_attempts:
        positive_integer(endpoint_policy[:max_attempts] || endpoint_policy["max_attempts"]) ||
          runtime[:webhook_delivery_default_max_attempts] || 3,
      backoff_ms:
        positive_integer(endpoint_policy[:backoff_ms] || endpoint_policy["backoff_ms"]) ||
          runtime[:webhook_delivery_default_backoff_ms] || 1_000
    }
  end

  defp list_event_endpoints(event_name) do
    filters = %{event: event_name, page: 1, page_size: 200}

    with {:ok, page} <- endpoint_repository().list(filters) do
      collect_pages(event_name, page, page.page + 1, page.total_pages)
    end
  end

  defp collect_pages(_event_name, page, current_page, total_pages)
       when current_page > total_pages,
       do: {:ok, page.entries}

  defp collect_pages(event_name, page, current_page, total_pages) do
    with {:ok, next_page} <-
           endpoint_repository().list(%{
             event: event_name,
             page: current_page,
             page_size: page.page_size
           }),
         {:ok, remaining_entries} <-
           collect_pages(event_name, next_page, current_page + 1, total_pages) do
      {:ok, page.entries ++ remaining_entries}
    end
  end

  defp ensure_success_status(status) when status in 200..299, do: :ok
  defp ensure_success_status(status), do: {:error, {:unexpected_status_code, status}}

  defp response_summary(response) do
    %{
      status: response.status,
      headers: SensitiveDataMasker.mask(response.headers),
      body_preview:
        response.body
        |> to_string()
        |> String.slice(0, 500)
    }
  end

  defp build_webhook_payload(endpoint, event_name, run, metadata) do
    %{
      event: event_name,
      endpoint_id: fetch(endpoint, :id),
      run: %{
        id: run.id,
        scenario_id: run.scenario_id,
        scenario_version: run.scenario_version,
        state: run.state,
        created_at: run.created_at,
        metadata: SensitiveDataMasker.mask(run.metadata)
      },
      frozen_snapshot: SensitiveDataMasker.mask(run.frozen_snapshot),
      dispatch_metadata: SensitiveDataMasker.mask(metadata),
      occurred_at: DateTime.utc_now()
    }
  end

  defp maybe_signature(payload_json, secret) when is_binary(secret) and secret != "" do
    build_signature(payload_json, secret)
  end

  defp maybe_signature(_payload_json, _secret), do: ""

  defp build_signature(payload_json, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload_json)
    |> Base.encode16(case: :lower)
  end

  defp build_headers(signature) do
    base_headers = [
      {"content-type", "application/json"},
      {"x-ocpp-webhook-signature-alg", "hmac-sha256"}
    ]

    if signature == "" do
      base_headers
    else
      base_headers ++ [{"x-ocpp-webhook-signature", signature}]
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp endpoint_repository do
    Application.get_env(
      :ocpp_simulator,
      :webhook_endpoint_repository,
      @default_endpoint_repository
    )
  end

  defp delivery_repository do
    Application.get_env(
      :ocpp_simulator,
      :webhook_delivery_repository,
      @default_delivery_repository
    )
  end

  defp id_generator do
    Application.get_env(:ocpp_simulator, :id_generator, @default_id_generator)
  end

  defp http_client do
    Application.get_env(:ocpp_simulator, :webhook_http_client, HttpClient)
  end

  defp runtime_config do
    Application.get_env(:ocpp_simulator, :runtime, [])
  end

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp fetch(_map, _key), do: nil
end
