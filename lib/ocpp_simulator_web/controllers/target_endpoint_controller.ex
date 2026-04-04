defmodule OcppSimulatorWeb.TargetEndpointController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints

  def create(conn, %{"endpoint" => endpoint_params}) when is_map(endpoint_params) do
    role = conn.assigns[:current_role] || :viewer
    attrs = build_attrs(endpoint_params)

    case ManageTargetEndpoints.create_target_endpoint(target_endpoint_repository(), attrs, role) do
      {:ok, endpoint} ->
        conn
        |> put_flash(:info, "Target endpoint `#{endpoint.id}` was created.")
        |> redirect(to: "/target-endpoints")

      {:error, :forbidden} ->
        conn
        |> put_flash(:error, "Current role is not allowed to create endpoints.")
        |> redirect(to: "/target-endpoints")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Unable to create endpoint: #{inspect(reason)}")
        |> redirect(to: "/target-endpoints")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Endpoint payload is required.")
    |> redirect(to: "/target-endpoints")
  end

  defp target_endpoint_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :target_endpoint_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository
      )

  defp build_attrs(params) when is_map(params) do
    %{
      id: fetch(params, :id),
      name: fetch(params, :name),
      url: normalize_ws_url(fetch(params, :url)),
      retry_policy: %{
        max_attempts: parse_positive_integer(fetch(params, :retry_max_attempts), 3),
        backoff_ms: parse_positive_integer(fetch(params, :retry_backoff_ms), 1_000)
      },
      protocol_options: %{},
      metadata: %{}
    }
  end

  defp parse_positive_integer(value, fallback) when is_integer(fallback) and fallback > 0 do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp normalize_ws_url(value) do
    normalized = to_string(value || "") |> String.trim()

    cond do
      normalized == "" ->
        ""

      String.contains?(normalized, "://") ->
        normalized

      true ->
        "ws://" <> normalized
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
