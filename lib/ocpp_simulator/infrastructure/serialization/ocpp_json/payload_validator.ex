defmodule OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator do
  @moduledoc """
  Strict OCPP 1.6J payload validation powered by official JSON schemas.
  """

  alias OcppSimulator.Domain.Ocpp.Message

  @schema_dir Path.expand("../../../../../OCPP_1.6_documentation/schemas/json", __DIR__)
  @schema_files @schema_dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()

  for schema_path <- @schema_files do
    @external_resource schema_path
  end

  schema_pairs =
    Enum.reduce(@schema_files, {%{}, %{}}, fn schema_path, {call_schemas, call_result_schemas} ->
      schema =
        schema_path
        |> File.read!()
        |> Jason.decode!()

      base_name = Path.basename(schema_path, ".json")

      if String.ends_with?(base_name, "Response") do
        action = String.replace_suffix(base_name, "Response", "")
        {call_schemas, Map.put(call_result_schemas, action, schema)}
      else
        action = base_name
        {Map.put(call_schemas, action, schema), call_result_schemas}
      end
    end)

  @call_schemas elem(schema_pairs, 0)
  @call_result_schemas elem(schema_pairs, 1)

  @supported_actions Map.keys(@call_schemas) |> Enum.sort()

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

  @call_error_codes [
    "NotImplemented",
    "NotSupported",
    "InternalError",
    "ProtocolError",
    "SecurityError",
    "FormationViolation",
    "PropertyConstraintViolation",
    "OccurenceConstraintViolation",
    "OccurrenceConstraintViolation",
    "TypeConstraintViolation",
    "GenericError"
  ]

  @spec supported_actions() :: [String.t()]
  def supported_actions, do: @supported_actions

  @spec charge_point_initiated_actions() :: [String.t()]
  def charge_point_initiated_actions, do: @charge_point_initiated_actions

  @spec central_system_initiated_actions() :: [String.t()]
  def central_system_initiated_actions, do: @central_system_initiated_actions

  @spec validate_message(Message.t(), keyword()) :: :ok | {:error, term()}
  def validate_message(%Message{type: :call, action: action, payload: payload}, _opts) do
    with :ok <- validate_supported_action(action),
         {:ok, schema} <- fetch_schema(@call_schemas, action, :call) do
      validate_payload(payload, schema, action)
    end
  end

  def validate_message(%Message{type: :call_result, direction: :inbound, payload: payload}, opts) do
    case Keyword.get(opts, :request_action) do
      nil ->
        ensure_map(payload, :payload)

      request_action ->
        validate_call_result_payload(payload, request_action)
    end
  end

  def validate_message(%Message{type: :call_result, payload: payload}, opts) do
    case Keyword.get(opts, :request_action) do
      nil ->
        {:error, {:missing_request_action, :call_result}}

      request_action ->
        validate_call_result_payload(payload, request_action)
    end
  end

  def validate_message(
        %Message{
          type: :call_error,
          error_code: error_code,
          error_description: error_description,
          error_details: error_details
        },
        _opts
      ) do
    with :ok <- validate_non_empty_string(error_code, :error_code),
         :ok <- validate_error_code(error_code),
         :ok <- validate_non_empty_string(error_description, :error_description),
         :ok <- ensure_map(error_details || %{}, :error_details) do
      :ok
    end
  end

  defp validate_call_result_payload(payload, request_action) do
    with :ok <- validate_supported_action(request_action),
         {:ok, schema} <- fetch_schema(@call_result_schemas, request_action, :call_result) do
      validate_payload(payload, schema, request_action)
    end
  end

  defp fetch_schema(schemas, action, context) do
    case Map.fetch(schemas, action) do
      {:ok, schema} -> {:ok, schema}
      :error -> {:error, {:unsupported_action_schema, context, action}}
    end
  end

  defp validate_supported_action(action) do
    if action in @supported_actions do
      :ok
    else
      {:error, {:unsupported_action, action}}
    end
  end

  defp validate_payload(payload, schema, action) do
    with :ok <- ensure_map(payload, :payload),
         normalized <- normalize_payload(payload),
         :ok <- validate_against_schema(normalized, schema, []) do
      :ok
    else
      {:error, {:missing_required_keys, path, missing_fields}} ->
        missing =
          if path == [] do
            missing_fields
          else
            Enum.map(missing_fields, &path_to_string(path ++ [&1]))
          end

        {:error, {:invalid_payload, action, :missing_required_keys, Enum.sort(missing)}}

      {:error, {:unexpected_keys, path, unexpected_fields}} ->
        unexpected =
          if path == [] do
            unexpected_fields
          else
            Enum.map(unexpected_fields, &path_to_string(path ++ [&1]))
          end

        {:error, {:invalid_payload, action, :unexpected_keys, Enum.sort(unexpected)}}

      {:error, {:invalid_field_type, path, descriptor}} ->
        {:error,
         {:invalid_payload, action, :invalid_field_type, path_to_string(path), descriptor}}
    end
  end

  defp validate_error_code(code) do
    if code in @call_error_codes do
      :ok
    else
      {:error, {:invalid_field, :error_code, :unsupported_error_code}}
    end
  end

  defp validate_against_schema(value, schema, path) when is_map(schema) do
    with :ok <- validate_enum_constraint(value, schema, path),
         :ok <- validate_typed_constraints(value, schema, path) do
      :ok
    end
  end

  defp validate_against_schema(_value, _schema, path) do
    {:error, {:invalid_field_type, path, %{schema: :invalid_schema_definition}}}
  end

  defp validate_enum_constraint(value, schema, path) do
    case Map.get(schema, "enum") do
      enum when is_list(enum) ->
        if value in enum do
          :ok
        else
          {:error, {:invalid_field_type, path, %{enum: enum}}}
        end

      _ ->
        :ok
    end
  end

  defp validate_typed_constraints(value, schema, path) do
    case Map.get(schema, "type") do
      nil ->
        :ok

      type when is_list(type) ->
        validate_union_type(value, type, schema, path)

      "object" ->
        validate_object_schema(value, schema, path)

      "array" ->
        validate_array_schema(value, schema, path)

      "string" ->
        validate_string_schema(value, schema, path)

      "integer" ->
        validate_integer_schema(value, schema, path)

      "number" ->
        validate_number_schema(value, schema, path)

      "boolean" ->
        if is_boolean(value), do: :ok, else: invalid_type(path, "boolean")

      "null" ->
        if is_nil(value), do: :ok, else: invalid_type(path, "null")

      other ->
        {:error, {:invalid_field_type, path, %{type: other}}}
    end
  end

  defp validate_union_type(value, union_types, schema, path) do
    if Enum.any?(union_types, fn union_type -> type_matches?(value, union_type) end) do
      :ok
    else
      validate_typed_constraints(value, Map.put(schema, "type", hd(union_types)), path)
    end
  end

  defp type_matches?(value, "object"), do: is_map(value)
  defp type_matches?(value, "array"), do: is_list(value)
  defp type_matches?(value, "string"), do: is_binary(value)
  defp type_matches?(value, "integer"), do: is_integer(value)
  defp type_matches?(value, "number"), do: is_number(value)
  defp type_matches?(value, "boolean"), do: is_boolean(value)
  defp type_matches?(value, "null"), do: is_nil(value)
  defp type_matches?(_value, _type), do: false

  defp validate_object_schema(value, schema, path) do
    if is_map(value) do
      properties = Map.get(schema, "properties", %{})
      required_fields = Map.get(schema, "required", [])

      missing_fields =
        required_fields
        |> Enum.reject(&Map.has_key?(value, &1))
        |> Enum.sort()

      if missing_fields != [] do
        {:error, {:missing_required_keys, path, missing_fields}}
      else
        with :ok <- validate_object_additional_properties(value, properties, schema, path),
             :ok <- validate_object_defined_properties(value, properties, path) do
          :ok
        end
      end
    else
      invalid_type(path, "object")
    end
  end

  defp validate_object_additional_properties(value, properties, schema, path) do
    property_keys = Map.keys(properties)
    additional = Map.get(schema, "additionalProperties", true)

    case additional do
      false ->
        unexpected_keys =
          value
          |> Map.keys()
          |> Enum.reject(&(&1 in property_keys))
          |> Enum.sort()

        if unexpected_keys == [] do
          :ok
        else
          {:error, {:unexpected_keys, path, unexpected_keys}}
        end

      true ->
        :ok

      additional_schema when is_map(additional_schema) ->
        value
        |> Enum.reduce_while(:ok, fn {key, nested_value}, :ok ->
          if key in property_keys do
            {:cont, :ok}
          else
            case validate_against_schema(nested_value, additional_schema, path ++ [key]) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end
        end)

      _ ->
        :ok
    end
  end

  defp validate_object_defined_properties(value, properties, path) do
    properties
    |> Enum.reduce_while(:ok, fn {property_key, property_schema}, :ok ->
      if Map.has_key?(value, property_key) do
        case validate_against_schema(
               Map.fetch!(value, property_key),
               property_schema,
               path ++ [property_key]
             ) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_array_schema(value, schema, path) do
    if is_list(value) do
      case Map.get(schema, "items") do
        nil ->
          :ok

        items_schema ->
          value
          |> Enum.with_index()
          |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
            case validate_against_schema(item, items_schema, path ++ [index]) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
      end
    else
      invalid_type(path, "array")
    end
  end

  defp validate_string_schema(value, schema, path) do
    if is_binary(value) do
      with :ok <- validate_max_length(value, schema, path),
           :ok <- validate_string_format(value, schema, path) do
        :ok
      end
    else
      invalid_type(path, "string")
    end
  end

  defp validate_max_length(value, schema, path) do
    case Map.get(schema, "maxLength") do
      max_length when is_integer(max_length) ->
        if String.length(value) > max_length do
          {:error, {:invalid_field_type, path, %{type: "string", maxLength: max_length}}}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp validate_string_format(value, schema, path) do
    case Map.get(schema, "format") do
      "date-time" ->
        if valid_iso8601_datetime?(value) do
          :ok
        else
          {:error, {:invalid_field_type, path, %{type: "string", format: "date-time"}}}
        end

      _ ->
        :ok
    end
  end

  defp validate_integer_schema(value, schema, path) do
    if is_integer(value) do
      validate_multiple_of(value, schema, path, "integer")
    else
      invalid_type(path, "integer")
    end
  end

  defp validate_number_schema(value, schema, path) do
    if is_number(value) do
      validate_multiple_of(value, schema, path, "number")
    else
      invalid_type(path, "number")
    end
  end

  defp validate_multiple_of(value, schema, path, number_type) do
    case Map.get(schema, "multipleOf") do
      divisor when is_number(divisor) and divisor != 0 ->
        if multiple_of?(value, divisor) do
          :ok
        else
          {:error, {:invalid_field_type, path, %{type: number_type, multipleOf: divisor}}}
        end

      _ ->
        :ok
    end
  end

  defp multiple_of?(value, divisor) do
    quotient = value / divisor
    rounded = Float.round(quotient)
    abs(quotient - rounded) < 1.0e-9
  end

  defp invalid_type(path, expected_type) do
    {:error, {:invalid_field_type, path, %{type: expected_type}}}
  end

  defp valid_iso8601_datetime?(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> true
      _ -> false
    end
  end

  defp valid_iso8601_datetime?(_value), do: false

  defp path_to_string(path) when is_list(path) do
    case Enum.reduce(path, "", &append_path_segment/2) do
      "" -> "payload"
      built -> built
    end
  end

  defp append_path_segment(segment, acc) when is_integer(segment) do
    "#{acc}[#{segment}]"
  end

  defp append_path_segment(segment, ""), do: to_string(segment)
  defp append_path_segment(segment, acc), do: "#{acc}.#{segment}"

  defp normalize_payload(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        cond do
          is_atom(key) -> Atom.to_string(key)
          is_binary(key) -> key
          true -> to_string(key)
        end

      Map.put(acc, normalized_key, normalize_payload(nested_value))
    end)
  end

  defp normalize_payload(value) when is_list(value), do: Enum.map(value, &normalize_payload/1)
  defp normalize_payload(value), do: value

  defp validate_non_empty_string(value, key) do
    if is_binary(value) and value != "" do
      :ok
    else
      {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp ensure_map(value, key) do
    if is_map(value) do
      :ok
    else
      {:error, {:invalid_field, key, :must_be_map}}
    end
  end
end
