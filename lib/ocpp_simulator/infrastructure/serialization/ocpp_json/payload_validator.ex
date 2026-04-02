defmodule OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator do
  @moduledoc """
  Strict OCPP 1.6J payload validation for supported v1 actions.
  """

  alias OcppSimulator.Domain.Ocpp.Message

  @id_tag_status_values ["Accepted", "Blocked", "Expired", "Invalid", "ConcurrentTx"]

  @sampled_value_schema %{
    required: [
      {"value", :string}
    ],
    optional: [
      {"context", :string},
      {"format", :string},
      {"measurand", :string},
      {"phase", :string},
      {"location", :string},
      {"unit", :string}
    ]
  }

  @meter_value_entry_schema %{
    required: [
      {"timestamp", :string},
      {"sampledValue", {:list, {:shape, @sampled_value_schema}}}
    ],
    optional: []
  }

  @id_tag_info_schema %{
    required: [
      {"status", {:enum, @id_tag_status_values}}
    ],
    optional: [
      {"expiryDate", :string},
      {"parentIdTag", :string}
    ]
  }

  @configuration_key_schema %{
    required: [
      {"key", :string},
      {"readonly", :boolean}
    ],
    optional: [
      {"value", :string}
    ]
  }

  @call_error_codes [
    "NotImplemented",
    "NotSupported",
    "InternalError",
    "ProtocolError",
    "SecurityError",
    "FormationViolation",
    "PropertyConstraintViolation",
    "OccurenceConstraintViolation",
    "TypeConstraintViolation",
    "GenericError"
  ]

  @trigger_messages [
    "BootNotification",
    "DiagnosticsStatusNotification",
    "FirmwareStatusNotification",
    "Heartbeat",
    "MeterValues",
    "StatusNotification"
  ]

  @call_schemas %{
    "BootNotification" => %{
      required: [
        {"chargePointVendor", :string},
        {"chargePointModel", :string}
      ],
      optional: [
        {"chargeBoxSerialNumber", :string},
        {"chargePointSerialNumber", :string},
        {"firmwareVersion", :string},
        {"iccid", :string},
        {"imsi", :string},
        {"meterType", :string},
        {"meterSerialNumber", :string}
      ]
    },
    "Heartbeat" => %{required: [], optional: []},
    "StatusNotification" => %{
      required: [
        {"connectorId", :non_neg_integer},
        {"status", :string},
        {"errorCode", :string}
      ],
      optional: [
        {"info", :string},
        {"timestamp", :string},
        {"vendorId", :string},
        {"vendorErrorCode", :string}
      ]
    },
    "Authorize" => %{
      required: [
        {"idTag", :string}
      ],
      optional: []
    },
    "StartTransaction" => %{
      required: [
        {"connectorId", :positive_integer},
        {"idTag", :string},
        {"meterStart", :integer},
        {"timestamp", :string}
      ],
      optional: [
        {"reservationId", :integer}
      ]
    },
    "MeterValues" => %{
      required: [
        {"connectorId", :positive_integer},
        {"meterValue", {:list, {:shape, @meter_value_entry_schema}}}
      ],
      optional: [
        {"transactionId", :integer}
      ]
    },
    "StopTransaction" => %{
      required: [
        {"meterStop", :integer},
        {"timestamp", :string},
        {"transactionId", :integer}
      ],
      optional: [
        {"idTag", :string},
        {"reason", :string},
        {"transactionData", {:list, {:shape, @meter_value_entry_schema}}}
      ]
    },
    "RemoteStartTransaction" => %{
      required: [
        {"idTag", :string}
      ],
      optional: [
        {"connectorId", :positive_integer}
      ]
    },
    "RemoteStopTransaction" => %{
      required: [
        {"transactionId", :integer}
      ],
      optional: []
    },
    "Reset" => %{
      required: [
        {"type", {:enum, ["Hard", "Soft"]}}
      ],
      optional: []
    },
    "ChangeAvailability" => %{
      required: [
        {"connectorId", :non_neg_integer},
        {"type", {:enum, ["Inoperative", "Operative"]}}
      ],
      optional: []
    },
    "TriggerMessage" => %{
      required: [
        {"requestedMessage", {:enum, @trigger_messages}}
      ],
      optional: [
        {"connectorId", :non_neg_integer}
      ]
    },
    "ChangeConfiguration" => %{
      required: [
        {"key", :string},
        {"value", :string}
      ],
      optional: []
    },
    "GetConfiguration" => %{
      required: [],
      optional: [
        {"key", {:list, :string}}
      ]
    }
  }

  @call_result_schemas %{
    "BootNotification" => %{
      required: [
        {"status", {:enum, ["Accepted", "Pending", "Rejected"]}},
        {"currentTime", :string},
        {"interval", :positive_integer}
      ],
      optional: []
    },
    "Heartbeat" => %{
      required: [
        {"currentTime", :string}
      ],
      optional: []
    },
    "StatusNotification" => %{required: [], optional: []},
    "Authorize" => %{
      required: [
        {"idTagInfo", {:shape, @id_tag_info_schema}}
      ],
      optional: []
    },
    "StartTransaction" => %{
      required: [
        {"transactionId", :integer},
        {"idTagInfo", {:shape, @id_tag_info_schema}}
      ],
      optional: []
    },
    "MeterValues" => %{required: [], optional: []},
    "StopTransaction" => %{
      required: [],
      optional: [
        {"idTagInfo", {:shape, @id_tag_info_schema}}
      ]
    },
    "RemoteStartTransaction" => %{
      required: [
        {"status", {:enum, ["Accepted", "Rejected"]}}
      ],
      optional: []
    },
    "RemoteStopTransaction" => %{
      required: [
        {"status", {:enum, ["Accepted", "Rejected"]}}
      ],
      optional: []
    },
    "Reset" => %{
      required: [
        {"status", {:enum, ["Accepted", "Rejected"]}}
      ],
      optional: []
    },
    "ChangeAvailability" => %{
      required: [
        {"status", {:enum, ["Accepted", "Rejected", "Scheduled"]}}
      ],
      optional: []
    },
    "TriggerMessage" => %{
      required: [
        {"status", {:enum, ["Accepted", "Rejected", "NotImplemented"]}}
      ],
      optional: []
    },
    "ChangeConfiguration" => %{
      required: [
        {"status", {:enum, ["Accepted", "Rejected", "RebootRequired", "NotSupported"]}}
      ],
      optional: []
    },
    "GetConfiguration" => %{
      required: [],
      optional: [
        {"configurationKey", {:list, {:shape, @configuration_key_schema}}},
        {"unknownKey", {:list, :string}}
      ]
    }
  }

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
    if Message.supported_action?(action) do
      :ok
    else
      {:error, {:unsupported_action, action}}
    end
  end

  defp validate_payload(payload, schema, action) do
    with :ok <- ensure_map(payload, :payload),
         normalized <- normalize_map_keys(payload),
         :ok <- validate_required_keys(normalized, schema.required, action),
         :ok <- validate_unexpected_keys(normalized, schema, action),
         :ok <- validate_types(normalized, schema, action) do
      :ok
    end
  end

  defp validate_required_keys(payload, required_fields, action) do
    missing =
      required_fields
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&Map.has_key?(payload, &1))

    if missing == [] do
      :ok
    else
      {:error, {:invalid_payload, action, :missing_required_keys, Enum.sort(missing)}}
    end
  end

  defp validate_unexpected_keys(payload, schema, action) do
    allowed_keys =
      schema.required
      |> Kernel.++(schema.optional)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    unexpected =
      payload
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed_keys, &1))
      |> Enum.sort()

    if unexpected == [] do
      :ok
    else
      {:error, {:invalid_payload, action, :unexpected_keys, unexpected}}
    end
  end

  defp validate_types(payload, schema, action) do
    schema.required
    |> Kernel.++(schema.optional)
    |> Enum.reduce_while(:ok, fn {field, descriptor}, :ok ->
      if Map.has_key?(payload, field) do
        value = Map.fetch!(payload, field)

        if valid_type?(value, descriptor) do
          {:cont, :ok}
        else
          {:halt, {:error, {:invalid_payload, action, :invalid_field_type, field, descriptor}}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_error_code(code) do
    if code in @call_error_codes do
      :ok
    else
      {:error, {:invalid_field, :error_code, :unsupported_error_code}}
    end
  end

  defp valid_type?(value, :string), do: is_binary(value) and value != ""
  defp valid_type?(value, :integer), do: is_integer(value)
  defp valid_type?(value, :boolean), do: is_boolean(value)
  defp valid_type?(value, :non_neg_integer), do: is_integer(value) and value >= 0
  defp valid_type?(value, :positive_integer), do: is_integer(value) and value > 0
  defp valid_type?(value, :map), do: is_map(value)

  defp valid_type?(value, {:enum, allowed_values}) when is_binary(value),
    do: value in allowed_values

  defp valid_type?(value, {:list, descriptor}) when is_list(value),
    do: Enum.all?(value, &valid_type?(&1, descriptor))

  defp valid_type?(value, {:shape, %{required: required, optional: optional}}) when is_map(value) do
    normalized = normalize_map_keys(value)
    valid_shape?(normalized, required, optional)
  end

  defp valid_type?(_value, _descriptor), do: false

  defp valid_shape?(payload, required_fields, optional_fields) do
    allowed_keys =
      required_fields
      |> Kernel.++(optional_fields)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    required_valid? =
      Enum.all?(required_fields, fn {field, descriptor} ->
        Map.has_key?(payload, field) and valid_type?(Map.fetch!(payload, field), descriptor)
      end)

    optional_valid? =
      Enum.all?(optional_fields, fn {field, descriptor} ->
        not Map.has_key?(payload, field) or valid_type?(Map.fetch!(payload, field), descriptor)
      end)

    unexpected_valid? =
      payload
      |> Map.keys()
      |> Enum.all?(&MapSet.member?(allowed_keys, &1))

    required_valid? and optional_valid? and unexpected_valid?
  end

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

  defp normalize_map_keys(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: key
      Map.put(acc, normalized_key, value)
    end)
  end
end
