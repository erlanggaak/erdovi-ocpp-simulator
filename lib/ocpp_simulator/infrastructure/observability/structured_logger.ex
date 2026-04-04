defmodule OcppSimulator.Infrastructure.Observability.StructuredLogger do
  @moduledoc """
  Structured logger that masks sensitive data and persists events.
  """

  @behaviour OcppSimulator.Application.Contracts.StructuredLogger

  require Logger

  alias OcppSimulator.Infrastructure.Security.SensitiveDataMasker

  @default_log_repository OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository

  @impl true
  def info(event, payload), do: log(:info, event, payload)

  @impl true
  def warn(event, payload), do: log(:warning, event, payload)

  @impl true
  def error(event, payload), do: log(:error, event, payload)

  defp log(level, event, payload) when is_binary(event) and is_map(payload) do
    masked_payload = SensitiveDataMasker.mask(payload)
    correlation_metadata = correlation_metadata(masked_payload)

    Logger.metadata(correlation_metadata)
    Logger.log(level, fn -> "#{event} #{inspect(masked_payload)}" end)

    if should_persist?(masked_payload) do
      persist_safely(level, event, masked_payload)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp log(_level, _event, _payload), do: :ok

  defp should_persist?(payload) do
    fetch(payload, :persist) != false and fetch(payload, "persist") != false
  end

  defp persist_event(level, event, payload) do
    log_entry = %{
      id: "log-#{System.unique_integer([:positive, :monotonic])}",
      run_id: to_string(fetch(payload, :run_id) || fetch(payload, "run_id") || "system"),
      session_id: fetch(payload, :session_id),
      charge_point_id: fetch(payload, :charge_point_id),
      message_id: fetch(payload, :message_id),
      action: normalize_optional_string(fetch(payload, :action)),
      step_id: normalize_optional_string(fetch(payload, :step_id)),
      severity: severity_to_string(level),
      event_type: event,
      payload: Map.drop(payload, [:persist, "persist"]),
      timestamp: DateTime.utc_now()
    }

    log_repository().insert(log_entry)
  end

  defp persist_safely(level, event, payload) do
    _ = persist_event(level, event, payload)
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp log_repository do
    Application.get_env(:ocpp_simulator, :log_repository, @default_log_repository)
  end

  defp severity_to_string(:warning), do: "warn"
  defp severity_to_string(level), do: Atom.to_string(level)

  defp correlation_metadata(payload) do
    %{
      run_id: normalize_optional_string(fetch(payload, :run_id)),
      session_id: normalize_optional_string(fetch(payload, :session_id)),
      charge_point_id: normalize_optional_string(fetch(payload, :charge_point_id)),
      message_id: normalize_optional_string(fetch(payload, :message_id)),
      action: normalize_optional_string(fetch(payload, :action)),
      step_id: normalize_optional_string(fetch(payload, :step_id))
    }
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp fetch(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp fetch(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      case safe_existing_atom(key) do
        nil -> nil
        atom_key -> Map.get(map, atom_key)
      end
  end

  defp fetch(_map, _key), do: nil

  defp safe_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
