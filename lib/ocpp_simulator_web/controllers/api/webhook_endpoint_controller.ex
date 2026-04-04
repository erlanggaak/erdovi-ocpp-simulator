defmodule OcppSimulatorWeb.Api.WebhookEndpointController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulatorWeb.Api.Response

  plug(OcppSimulatorWeb.Auth.RequirePermissionPlug, permission: :api_automation)

  def upsert(conn, params) do
    role = current_role(conn)

    with :ok <- AuthorizationPolicy.authorize(role, :manage_target_endpoints),
         {:ok, endpoint} <- normalize_webhook_endpoint(params),
         {:ok, persisted_endpoint} <- webhook_endpoint_repository().upsert(endpoint) do
      StructuredLogger.info("api.webhook_endpoint.upserted", %{
        persist: true,
        run_id: "system",
        action: "upsert_webhook_endpoint",
        payload: %{endpoint_id: persisted_endpoint.id}
      })

      Response.success(conn, :created, %{
        resource: "webhook_endpoint",
        id: persisted_endpoint.id,
        endpoint: persisted_endpoint
      })
    else
      {:error, reason} -> Response.from_reason(conn, reason)
    end
  end

  def index(conn, params) do
    role = current_role(conn)

    with :ok <- AuthorizationPolicy.authorize(role, :view_target_endpoints),
         {:ok, page} <- webhook_endpoint_repository().list(params) do
      Response.success(conn, :ok, page)
    else
      {:error, reason} -> Response.from_reason(conn, reason)
    end
  end

  defp normalize_webhook_endpoint(params) do
    with {:ok, id} <- required_string(params, :id),
         {:ok, name} <- required_string(params, :name),
         {:ok, url} <- required_string(params, :url),
         :ok <- ensure_http_url(url),
         {:ok, events} <- required_string_list(params, :events),
         {:ok, retry_policy} <- normalize_retry_policy(params),
         {:ok, metadata} <- optional_map(params, :metadata),
         {:ok, secret_ref} <- optional_string(params, :secret_ref) do
      {:ok,
       %{
         id: id,
         name: name,
         url: url,
         events: events,
         retry_policy: retry_policy,
         metadata: metadata,
         secret_ref: secret_ref
       }}
    end
  end

  defp normalize_retry_policy(params) do
    case fetch(params, :retry_policy) do
      nil ->
        {:ok, default_retry_policy()}

      retry_policy when is_map(retry_policy) ->
        with {:ok, max_attempts} <-
               positive_integer(retry_policy, :max_attempts, default_retry_policy().max_attempts),
             {:ok, backoff_ms} <-
               positive_integer(retry_policy, :backoff_ms, default_retry_policy().backoff_ms) do
          {:ok, %{max_attempts: max_attempts, backoff_ms: backoff_ms}}
        end

      _ ->
        {:error, {:invalid_field, :retry_policy, :must_be_map}}
    end
  end

  defp default_retry_policy do
    runtime = Application.get_env(:ocpp_simulator, :runtime, [])

    %{
      max_attempts: runtime[:webhook_delivery_default_max_attempts] || 3,
      backoff_ms: runtime[:webhook_delivery_default_backoff_ms] || 1_000
    }
  end

  defp required_string(params, key) do
    case fetch(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp optional_string(params, key) do
    case fetch(params, key) do
      nil -> {:ok, nil}
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp required_string_list(params, key) do
    case fetch(params, key) do
      values when is_list(values) ->
        normalized_values =
          values
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        if normalized_values == [] do
          {:error, {:invalid_field, key, :must_be_non_empty_string_list}}
        else
          {:ok, normalized_values}
        end

      _ ->
        {:error, {:invalid_field, key, :must_be_non_empty_string_list}}
    end
  end

  defp optional_map(params, key) do
    case fetch(params, key) do
      nil -> {:ok, %{}}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_map}}
    end
  end

  defp ensure_http_url(url) when is_binary(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      :ok
    else
      {:error, {:invalid_field, :url, :must_be_http_or_https_url}}
    end
  rescue
    _ -> {:error, {:invalid_field, :url, :must_be_http_or_https_url}}
  end

  defp positive_integer(params, key, default) do
    case fetch(params, key) do
      nil ->
        {:ok, default}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> {:error, {:invalid_field, key, :must_be_positive_integer}}
        end

      _ ->
        {:error, {:invalid_field, key, :must_be_positive_integer}}
    end
  end

  defp webhook_endpoint_repository do
    Application.get_env(
      :ocpp_simulator,
      :webhook_endpoint_repository,
      OcppSimulator.Infrastructure.Persistence.Mongo.WebhookEndpointRepository
    )
  end

  defp current_role(conn), do: conn.assigns[:current_role] || :viewer
  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
