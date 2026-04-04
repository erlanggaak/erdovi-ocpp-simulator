defmodule OcppSimulator.Domain.Ocpp.PayloadTemplates do
  @moduledoc """
  Builds schema-aligned default OCPP 1.6J payload templates for UI editors.
  """

  @schema_dir Path.expand("../../../../OCPP_1.6_documentation/schemas/json", __DIR__)
  @schema_files @schema_dir
                |> Path.join("*.json")
                |> Path.wildcard()
                |> Enum.reject(&String.ends_with?(&1, "Response.json"))
                |> Enum.sort()

  for schema_path <- @schema_files do
    @external_resource schema_path
  end

  schema_map =
    Enum.reduce(@schema_files, %{}, fn schema_path, acc ->
      schema =
        schema_path
        |> File.read!()
        |> Jason.decode!()

      action = Path.basename(schema_path, ".json")
      Map.put(acc, action, schema)
    end)

  @action_schemas schema_map

  @charge_point_initiated_actions [
    "Authorize",
    "BootNotification",
    "DataTransfer",
    "DiagnosticsStatusNotification",
    "FirmwareStatusNotification",
    "Heartbeat",
    "MeterValues",
    "StartTransaction",
    "StatusNotification",
    "StopTransaction"
  ]

  @central_system_initiated_actions [
    "CancelReservation",
    "ChangeAvailability",
    "ChangeConfiguration",
    "ClearCache",
    "ClearChargingProfile",
    "DataTransfer",
    "GetCompositeSchedule",
    "GetConfiguration",
    "GetDiagnostics",
    "GetLocalListVersion",
    "RemoteStartTransaction",
    "RemoteStopTransaction",
    "ReserveNow",
    "Reset",
    "SendLocalList",
    "SetChargingProfile",
    "TriggerMessage",
    "UnlockConnector",
    "UpdateFirmware"
  ]

  @default_datetime "2026-04-01T00:00:00Z"

  @spec supported_actions() :: [String.t()]
  def supported_actions do
    @action_schemas
    |> Map.keys()
    |> Enum.sort()
  end

  @spec charge_point_initiated_actions() :: [String.t()]
  def charge_point_initiated_actions, do: @charge_point_initiated_actions

  @spec central_system_initiated_actions() :: [String.t()]
  def central_system_initiated_actions, do: @central_system_initiated_actions

  @spec payload_for_action(String.t()) :: map()
  def payload_for_action(action) when is_binary(action) do
    case Map.get(@action_schemas, action) do
      nil -> %{}
      schema -> build_required_object(schema)
    end
  end

  @spec send_action_step_payload(String.t()) :: map()
  def send_action_step_payload(action) when is_binary(action) do
    %{
      "action" => action,
      "payload" => payload_for_action(action)
    }
  end

  defp build_required_object(schema) when is_map(schema) do
    properties = Map.get(schema, "properties", %{})
    required_keys = Map.get(schema, "required", [])

    Enum.reduce(required_keys, %{}, fn key, acc ->
      field_schema = Map.get(properties, key, %{})
      Map.put(acc, key, build_default_value(key, field_schema))
    end)
  end

  defp build_default_value(field_name, schema) when is_map(schema) do
    case Map.get(schema, "enum") do
      [head | _tail] ->
        head

      _ ->
        case Map.get(schema, "type") do
          type when is_list(type) and type != [] ->
            build_default_value(field_name, Map.put(schema, "type", hd(type)))

          "object" ->
            build_required_object(schema)

          "array" ->
            build_default_array_value(field_name, schema)

          "string" ->
            build_default_string_value(field_name, schema)

          "integer" ->
            build_default_integer_value(field_name)

          "number" ->
            build_default_number_value(schema)

          "boolean" ->
            false

          _ ->
            ""
        end
    end
  end

  defp build_default_array_value(field_name, schema) do
    case Map.get(schema, "items") do
      item_schema when is_map(item_schema) ->
        [build_default_value(field_name, item_schema)]

      _ ->
        []
    end
  end

  defp build_default_string_value(field_name, schema) do
    value =
      case Map.get(schema, "format") do
        "date-time" ->
          @default_datetime

        _ ->
          default_string_for_field(field_name)
      end

    case Map.get(schema, "maxLength") do
      max_length when is_integer(max_length) and max_length >= 0 ->
        String.slice(value, 0, max_length)

      _ ->
        value
    end
  end

  defp default_string_for_field("chargePointVendor"), do: "Erdovi"
  defp default_string_for_field("chargePointModel"), do: "Simulator"
  defp default_string_for_field("idTag"), do: "RFID-1"
  defp default_string_for_field("key"), do: "HeartbeatInterval"
  defp default_string_for_field("value"), do: "0"
  defp default_string_for_field("location"), do: "https://example.com/firmware.bin"
  defp default_string_for_field("vendorId"), do: "vendor"
  defp default_string_for_field("messageId"), do: "request-1"
  defp default_string_for_field("data"), do: "{}"
  defp default_string_for_field(_field_name), do: "value"

  defp build_default_integer_value("connectorId"), do: 1
  defp build_default_integer_value("meterStart"), do: 0
  defp build_default_integer_value("meterStop"), do: 0
  defp build_default_integer_value("interval"), do: 60
  defp build_default_integer_value("listVersion"), do: 1
  defp build_default_integer_value("stackLevel"), do: 0
  defp build_default_integer_value("startPeriod"), do: 0
  defp build_default_integer_value("duration"), do: 60
  defp build_default_integer_value("retries"), do: 1
  defp build_default_integer_value("retryInterval"), do: 60
  defp build_default_integer_value("reservationId"), do: 1
  defp build_default_integer_value("transactionId"), do: 1
  defp build_default_integer_value(_field_name), do: 1

  defp build_default_number_value(schema) do
    case Map.get(schema, "multipleOf") do
      divisor when is_number(divisor) and divisor > 0 -> divisor
      _ -> 1.0
    end
  end
end
