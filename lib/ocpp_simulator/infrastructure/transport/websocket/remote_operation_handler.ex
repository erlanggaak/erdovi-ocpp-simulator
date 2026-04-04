defmodule OcppSimulator.Infrastructure.Transport.WebSocket.RemoteOperationHandler do
  @moduledoc """
  Handles inbound CSMS remote-operation calls with state-aware strategy routing.
  """

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator

  @trigger_messages [
    "BootNotification",
    "DiagnosticsStatusNotification",
    "FirmwareStatusNotification",
    "Heartbeat",
    "MeterValues",
    "StatusNotification"
  ]

  @default_configuration %{
    "HeartbeatInterval" => "60",
    "MeterValueSampleInterval" => "60"
  }

  @spec supported_actions() :: [String.t()]
  def supported_actions, do: PayloadValidator.central_system_initiated_actions()

  @spec handle_inbound(Message.t(), map()) :: {:ok, Message.t(), map()} | {:error, term()}
  def handle_inbound(%Message{type: :call, direction: :inbound} = request, context)
      when is_map(context) do
    normalized_context = normalize_context(context)

    with :ok <- ensure_supported_action(request.action),
         :ok <- PayloadValidator.validate_message(request, []),
         {:ok, payload, updated_context} <-
           dispatch(request.action, request.payload, normalized_context),
         {:ok, response} <- Message.new_call_result(request.message_id, payload, :outbound) do
      {:ok, response, updated_context}
    else
      {:error, {:unsupported_remote_action, action}} ->
        build_call_error_response(
          request.message_id,
          "NotSupported",
          "Unsupported remote action",
          %{"action" => action},
          normalized_context
        )

      {:error, {:invalid_payload, _action, _reason, _details} = reason} ->
        build_call_error_response(
          request.message_id,
          "FormationViolation",
          "Remote operation payload is invalid",
          %{"reason" => inspect(reason)},
          normalized_context
        )

      {:error, {:invalid_payload, _action, _reason, _field, _descriptor} = reason} ->
        build_call_error_response(
          request.message_id,
          "FormationViolation",
          "Remote operation payload is invalid",
          %{"reason" => inspect(reason)},
          normalized_context
        )

      {:error, reason} ->
        build_call_error_response(
          request.message_id,
          "InternalError",
          "Remote operation failed",
          %{"reason" => inspect(reason)},
          normalized_context
        )
    end
  end

  def handle_inbound(%Message{}, _context),
    do: {:error, {:invalid_message, :must_be_inbound_call}}

  defp dispatch("CancelReservation", payload, context) do
    reservation_id = payload["reservationId"]

    if Map.has_key?(context.reservations, reservation_id) do
      updated_reservations = Map.delete(context.reservations, reservation_id)
      {:ok, %{"status" => "Accepted"}, %{context | reservations: updated_reservations}}
    else
      {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("ChangeAvailability", payload, context) do
    case payload["type"] do
      "Inoperative" when context.transaction_state in [:authorized, :started, :metering] ->
        {:ok, %{"status" => "Scheduled"}, %{context | pending_availability: :inoperative}}

      "Inoperative" ->
        {:ok, %{"status" => "Accepted"},
         %{context | availability: :inoperative, charge_point_state: :unavailable}}

      "Operative" ->
        updated_state =
          if context.charge_point_state == :unavailable,
            do: :available,
            else: context.charge_point_state

        {:ok, %{"status" => "Accepted"},
         %{
           context
           | availability: :operative,
             charge_point_state: updated_state,
             pending_availability: nil
         }}

      _ ->
        {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("ChangeConfiguration", payload, context) do
    key = payload["key"]
    value = payload["value"]
    updated_configuration = Map.put(context.configuration, key, value)

    {:ok, %{"status" => "Accepted"}, %{context | configuration: updated_configuration}}
  end

  defp dispatch("ClearCache", _payload, context) do
    {:ok, %{"status" => "Accepted"}, %{context | id_tag_cache_cleared: true}}
  end

  defp dispatch("ClearChargingProfile", _payload, context) do
    {:ok, %{"status" => "Accepted"}, %{context | charging_profiles: %{}}}
  end

  defp dispatch("DataTransfer", payload, context) do
    response =
      case payload["data"] do
        value when is_binary(value) and value != "" ->
          %{"status" => "Accepted", "data" => value}

        _ ->
          %{"status" => "Accepted"}
      end

    {:ok, response, context}
  end

  defp dispatch("GetCompositeSchedule", _payload, context) do
    {:ok, %{"status" => "Rejected"}, context}
  end

  defp dispatch("GetConfiguration", payload, context) do
    requested_keys = payload["key"]

    response =
      case requested_keys do
        keys when is_list(keys) and keys != [] ->
          {known_keys, unknown_keys} =
            Enum.split_with(keys, fn key -> Map.has_key?(context.configuration, key) end)

          %{}
          |> maybe_put(
            "configurationKey",
            build_configuration_keys(context.configuration, known_keys),
            known_keys != []
          )
          |> maybe_put("unknownKey", Enum.sort(unknown_keys), unknown_keys != [])

        _ ->
          all_keys = context.configuration |> Map.keys() |> Enum.sort()
          %{"configurationKey" => build_configuration_keys(context.configuration, all_keys)}
      end

    {:ok, response, context}
  end

  defp dispatch("GetDiagnostics", _payload, context) do
    {:ok, %{"fileName" => context.diagnostics_file_name}, context}
  end

  defp dispatch("GetLocalListVersion", _payload, context) do
    {:ok, %{"listVersion" => context.local_list_version}, context}
  end

  defp dispatch("RemoteStartTransaction", _payload, context) do
    cond do
      context.availability == :inoperative ->
        {:ok, %{"status" => "Rejected"}, context}

      context.transaction_state in [:authorized, :started, :metering] ->
        {:ok, %{"status" => "Rejected"}, context}

      context.charge_point_state in [:available, :preparing] ->
        {:ok, %{"status" => "Accepted"},
         %{context | transaction_state: :authorized, charge_point_state: :preparing}}

      true ->
        {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("RemoteStopTransaction", _payload, context) do
    if context.transaction_state in [:authorized, :started, :metering] do
      {:ok, %{"status" => "Accepted"},
       %{context | transaction_state: :stopped, charge_point_state: :finishing}}
    else
      {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("ReserveNow", payload, context) do
    reservation_id = payload["reservationId"]

    cond do
      context.availability == :inoperative ->
        {:ok, %{"status" => "Unavailable"}, context}

      context.transaction_state in [:started, :metering] ->
        {:ok, %{"status" => "Occupied"}, context}

      Map.has_key?(context.reservations, reservation_id) ->
        {:ok, %{"status" => "Rejected"}, context}

      true ->
        updated_reservations = Map.put(context.reservations, reservation_id, payload)
        {:ok, %{"status" => "Accepted"}, %{context | reservations: updated_reservations}}
    end
  end

  defp dispatch("Reset", payload, context) do
    case payload["type"] do
      "Hard" ->
        {:ok, %{"status" => "Accepted"},
         %{context | charge_point_state: :booting, transaction_state: :none}}

      "Soft" when context.transaction_state in [:authorized, :started, :metering] ->
        {:ok, %{"status" => "Rejected"}, context}

      "Soft" ->
        {:ok, %{"status" => "Accepted"},
         %{context | charge_point_state: :booting, transaction_state: :none}}

      _ ->
        {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("SendLocalList", payload, context) do
    incoming_version = payload["listVersion"]

    if incoming_version > context.local_list_version do
      {:ok, %{"status" => "Accepted"}, %{context | local_list_version: incoming_version}}
    else
      {:ok, %{"status" => "VersionMismatch"}, context}
    end
  end

  defp dispatch("SetChargingProfile", payload, context) do
    profile = payload["csChargingProfiles"]
    profile_id = profile["chargingProfileId"]
    updated_profiles = Map.put(context.charging_profiles, profile_id, profile)

    {:ok, %{"status" => "Accepted"}, %{context | charging_profiles: updated_profiles}}
  end

  defp dispatch("TriggerMessage", payload, context) do
    requested_message = payload["requestedMessage"]

    cond do
      requested_message not in @trigger_messages ->
        {:ok, %{"status" => "NotImplemented"}, context}

      context.availability == :inoperative ->
        {:ok, %{"status" => "Rejected"}, context}

      true ->
        {:ok, %{"status" => "Accepted"},
         Map.put(context, :last_triggered_message, requested_message)}
    end
  end

  defp dispatch("UnlockConnector", _payload, context) do
    status =
      if context.transaction_state in [:started, :metering] do
        "UnlockFailed"
      else
        "Unlocked"
      end

    {:ok, %{"status" => status}, context}
  end

  defp dispatch("UpdateFirmware", payload, context) do
    updated_context =
      context
      |> Map.put(:firmware_update_requested, true)
      |> Map.put(:firmware_url, payload["location"])
      |> Map.put(:firmware_retrieve_date, payload["retrieveDate"])

    {:ok, %{}, updated_context}
  end

  defp dispatch(action, _payload, _context), do: {:error, {:unsupported_remote_action, action}}

  defp ensure_supported_action(action) do
    if action in supported_actions() do
      :ok
    else
      {:error, {:unsupported_remote_action, action}}
    end
  end

  defp normalize_context(context) do
    defaults = %{
      charge_point_state: :available,
      transaction_state: :none,
      availability: :operative,
      pending_availability: nil,
      last_triggered_message: nil,
      configuration: @default_configuration,
      reservations: %{},
      charging_profiles: %{},
      local_list_version: 0,
      diagnostics_file_name: "diagnostics.log",
      id_tag_cache_cleared: false,
      firmware_update_requested: false,
      firmware_url: nil,
      firmware_retrieve_date: nil
    }

    defaults
    |> Map.merge(context)
    |> normalize_configuration_map()
  end

  defp normalize_configuration_map(context) do
    configuration =
      context.configuration
      |> case do
        map when is_map(map) -> map
        _ -> @default_configuration
      end
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        normalized_key = if is_binary(key), do: key, else: to_string(key)

        normalized_value =
          cond do
            is_binary(value) -> value
            is_nil(value) -> nil
            true -> to_string(value)
          end

        Map.put(acc, normalized_key, normalized_value)
      end)

    %{context | configuration: configuration}
  end

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  defp build_configuration_keys(configuration, keys) do
    Enum.map(keys, fn key ->
      value = Map.get(configuration, key)

      %{"key" => key, "readonly" => false}
      |> maybe_put("value", value, is_binary(value))
    end)
  end

  defp build_call_error_response(message_id, code, description, details, context) do
    with {:ok, response} <-
           Message.new_call_error(message_id, code, description, details, :outbound) do
      {:ok, response, context}
    end
  end
end
