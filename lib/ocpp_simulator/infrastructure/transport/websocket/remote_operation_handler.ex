defmodule OcppSimulator.Infrastructure.Transport.WebSocket.RemoteOperationHandler do
  @moduledoc """
  Handles inbound CSMS remote-operation calls with state-aware strategy routing.
  """

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator

  @supported_actions [
    "RemoteStartTransaction",
    "RemoteStopTransaction",
    "TriggerMessage",
    "Reset",
    "ChangeAvailability"
  ]

  @trigger_messages [
    "BootNotification",
    "DiagnosticsStatusNotification",
    "FirmwareStatusNotification",
    "Heartbeat",
    "MeterValues",
    "StatusNotification"
  ]

  @spec supported_actions() :: [String.t()]
  def supported_actions, do: @supported_actions

  @spec handle_inbound(Message.t(), map()) :: {:ok, Message.t(), map()} | {:error, term()}
  def handle_inbound(%Message{type: :call, direction: :inbound} = request, context)
      when is_map(context) do
    normalized_context = normalize_context(context)

    with :ok <- ensure_supported_action(request.action),
         :ok <- PayloadValidator.validate_message(request, []),
         {:ok, payload, updated_context} <- dispatch(request.action, request.payload, normalized_context),
         {:ok, response} <- Message.new_call_result(request.message_id, payload, :outbound) do
      {:ok, response, updated_context}
    else
      {:error, {:unsupported_remote_action, action}} ->
        build_call_error_response(request.message_id, "NotSupported", "Unsupported remote action", %{
          "action" => action
        }, normalized_context)

      {:error, {:invalid_payload, _action, _reason, _details} = reason} ->
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

  defp dispatch("RemoteStartTransaction", _payload, context) do
    cond do
      context.availability == :inoperative ->
        {:ok, %{"status" => "Rejected"}, context}

      context.transaction_state in [:authorized, :started, :metering] ->
        {:ok, %{"status" => "Rejected"}, context}

      context.charge_point_state in [:available, :preparing] ->
        {:ok, %{"status" => "Accepted"}, %{context | transaction_state: :started, charge_point_state: :preparing}}

      true ->
        {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("RemoteStopTransaction", _payload, context) do
    if context.transaction_state in [:authorized, :started, :metering] do
      {:ok, %{"status" => "Accepted"}, %{context | transaction_state: :stopped, charge_point_state: :finishing}}
    else
      {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("TriggerMessage", payload, context) do
    requested_message = payload["requestedMessage"]

    cond do
      requested_message not in @trigger_messages ->
        {:ok, %{"status" => "NotImplemented"}, context}

      context.availability == :inoperative ->
        {:ok, %{"status" => "Rejected"}, context}

      true ->
        {:ok, %{"status" => "Accepted"}, Map.put(context, :last_triggered_message, requested_message)}
    end
  end

  defp dispatch("Reset", payload, context) do
    case payload["type"] do
      "Hard" ->
        {:ok, %{"status" => "Accepted"}, %{context | charge_point_state: :booting, transaction_state: :none}}

      "Soft" when context.transaction_state in [:authorized, :started, :metering] ->
        {:ok, %{"status" => "Rejected"}, context}

      "Soft" ->
        {:ok, %{"status" => "Accepted"}, %{context | charge_point_state: :booting, transaction_state: :none}}

      _ ->
        {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch("ChangeAvailability", payload, context) do
    case payload["type"] do
      "Inoperative" when context.transaction_state in [:authorized, :started, :metering] ->
        {:ok, %{"status" => "Scheduled"}, %{context | pending_availability: :inoperative}}

      "Inoperative" ->
        {:ok, %{"status" => "Accepted"}, %{context | availability: :inoperative, charge_point_state: :unavailable}}

      "Operative" ->
        updated_state = if context.charge_point_state == :unavailable, do: :available, else: context.charge_point_state
        {:ok, %{"status" => "Accepted"}, %{context | availability: :operative, charge_point_state: updated_state, pending_availability: nil}}

      _ ->
        {:ok, %{"status" => "Rejected"}, context}
    end
  end

  defp dispatch(action, _payload, _context), do: {:error, {:unsupported_remote_action, action}}

  defp ensure_supported_action(action) when action in @supported_actions, do: :ok
  defp ensure_supported_action(action), do: {:error, {:unsupported_remote_action, action}}

  defp normalize_context(context) do
    defaults = %{
      charge_point_state: :available,
      transaction_state: :none,
      availability: :operative,
      pending_availability: nil,
      last_triggered_message: nil
    }

    Map.merge(defaults, context)
  end

  defp build_call_error_response(message_id, code, description, details, context) do
    with {:ok, response} <- Message.new_call_error(message_id, code, description, details, :outbound) do
      {:ok, response, context}
    end
  end
end
