defmodule OcppSimulatorWeb.ChargePointController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ManageChargePoints

  def create(conn, %{"charge_point" => charge_point_params}) when is_map(charge_point_params) do
    role = conn.assigns[:current_role] || :viewer
    attrs = build_attrs(charge_point_params)

    case ManageChargePoints.register_charge_point(charge_point_repository(), attrs, role) do
      {:ok, charge_point} ->
        conn
        |> put_flash(:info, "Charge point `#{charge_point.id}` was created.")
        |> redirect(to: "/charge-points")

      {:error, :forbidden} ->
        conn
        |> put_flash(:error, "Current role is not allowed to create charge points.")
        |> redirect(to: "/charge-points")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Unable to create charge point: #{inspect(reason)}")
        |> redirect(to: "/charge-points")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Charge point payload is required.")
    |> redirect(to: "/charge-points")
  end

  defp charge_point_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :charge_point_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository
      )

  defp build_attrs(params) when is_map(params) do
    %{
      id: fetch(params, :id),
      vendor: fetch(params, :vendor),
      model: fetch(params, :model),
      firmware_version: fetch(params, :firmware_version),
      connector_count: parse_positive_integer(fetch(params, :connector_count), 1),
      heartbeat_interval_seconds:
        parse_positive_integer(fetch(params, :heartbeat_interval_seconds), 60),
      behavior_profile: normalize_behavior_profile(fetch(params, :behavior_profile))
    }
  end

  defp parse_positive_integer(value, fallback) when is_integer(fallback) and fallback > 0 do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp normalize_behavior_profile(value) do
    normalized = to_string(value || "") |> String.trim()

    case normalized do
      "default" -> "default"
      "intermittent_disconnects" -> "intermittent_disconnects"
      "faulted" -> "faulted"
      _ -> "default"
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
