defmodule OcppSimulator.Domain.Ocpp.Message do
  @moduledoc """
  OCPP 1.6J message value object with strict frame conversion rules.
  """

  @supported_actions [
    "BootNotification",
    "Heartbeat",
    "StatusNotification",
    "Authorize",
    "StartTransaction",
    "MeterValues",
    "StopTransaction",
    "RemoteStartTransaction",
    "RemoteStopTransaction",
    "Reset",
    "ChangeAvailability",
    "TriggerMessage",
    "ChangeConfiguration",
    "GetConfiguration"
  ]

  @enforce_keys [:type, :message_id, :payload]
  defstruct [
    :type,
    :message_id,
    :action,
    :payload,
    :error_code,
    :error_description,
    :error_details,
    :direction
  ]

  @type type :: :call | :call_result | :call_error
  @type direction :: :inbound | :outbound

  @type t :: %__MODULE__{
          type: type(),
          message_id: String.t(),
          action: String.t() | nil,
          payload: map(),
          error_code: String.t() | nil,
          error_description: String.t() | nil,
          error_details: map() | nil,
          direction: direction() | nil
        }

  @spec new_call(String.t(), String.t(), map(), direction() | nil) ::
          {:ok, t()} | {:error, term()}
  def new_call(message_id, action, payload \\ %{}, direction \\ nil) do
    with :ok <- validate_message_id(message_id),
         :ok <- validate_non_empty_string(action, :action),
         :ok <- validate_map(payload, :payload),
         :ok <- validate_direction(direction) do
      {:ok,
       %__MODULE__{
         type: :call,
         message_id: message_id,
         action: action,
         payload: payload,
         error_code: nil,
         error_description: nil,
         error_details: nil,
         direction: direction
       }}
    end
  end

  @spec new_call_result(String.t(), map(), direction() | nil) :: {:ok, t()} | {:error, term()}
  def new_call_result(message_id, payload \\ %{}, direction \\ nil) do
    with :ok <- validate_message_id(message_id),
         :ok <- validate_map(payload, :payload),
         :ok <- validate_direction(direction) do
      {:ok,
       %__MODULE__{
         type: :call_result,
         message_id: message_id,
         action: nil,
         payload: payload,
         error_code: nil,
         error_description: nil,
         error_details: nil,
         direction: direction
       }}
    end
  end

  @spec new_call_error(String.t(), String.t(), String.t(), map(), direction() | nil) ::
          {:ok, t()} | {:error, term()}
  def new_call_error(
        message_id,
        error_code,
        error_description,
        error_details \\ %{},
        direction \\ nil
      ) do
    with :ok <- validate_message_id(message_id),
         :ok <- validate_non_empty_string(error_code, :error_code),
         :ok <- validate_non_empty_string(error_description, :error_description),
         :ok <- validate_map(error_details, :error_details),
         :ok <- validate_direction(direction) do
      {:ok,
       %__MODULE__{
         type: :call_error,
         message_id: message_id,
         action: nil,
         payload: %{},
         error_code: error_code,
         error_description: error_description,
         error_details: error_details,
         direction: direction
       }}
    end
  end

  @spec to_frame(t()) :: [term()]
  def to_frame(%__MODULE__{type: :call} = message),
    do: [2, message.message_id, message.action, message.payload]

  def to_frame(%__MODULE__{type: :call_result} = message),
    do: [3, message.message_id, message.payload]

  def to_frame(%__MODULE__{type: :call_error} = message),
    do: [
      4,
      message.message_id,
      message.error_code,
      message.error_description,
      message.error_details || %{}
    ]

  @spec from_frame([term()], direction() | nil) :: {:ok, t()} | {:error, term()}
  def from_frame(frame, direction \\ nil)

  def from_frame([2, message_id, action, payload], direction),
    do: new_call(message_id, action, payload, direction)

  def from_frame([3, message_id, payload], direction),
    do: new_call_result(message_id, payload, direction)

  def from_frame([4, message_id, error_code, error_description, error_details], direction),
    do: new_call_error(message_id, error_code, error_description, error_details, direction)

  def from_frame(_frame, _direction),
    do: {:error, {:invalid_frame, :unsupported_shape}}

  @spec call?(t()) :: boolean()
  def call?(%__MODULE__{type: :call}), do: true
  def call?(%__MODULE__{}), do: false

  @spec response?(t()) :: boolean()
  def response?(%__MODULE__{type: type}) when type in [:call_result, :call_error], do: true
  def response?(%__MODULE__{}), do: false

  @spec correlates?(t(), t()) :: boolean()
  def correlates?(%__MODULE__{type: :call, message_id: message_id}, %__MODULE__{
        message_id: message_id,
        type: response_type
      })
      when response_type in [:call_result, :call_error],
      do: true

  def correlates?(%__MODULE__{}, %__MODULE__{}), do: false

  @spec supported_actions() :: [String.t()]
  def supported_actions, do: @supported_actions

  @spec supported_action?(String.t()) :: boolean()
  def supported_action?(action) when is_binary(action), do: action in @supported_actions
  def supported_action?(_action), do: false

  defp validate_message_id(value), do: validate_non_empty_string(value, :message_id)

  defp validate_non_empty_string(value, key) do
    if is_binary(value) and value != "" do
      :ok
    else
      {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp validate_map(value, key) do
    if is_map(value) do
      :ok
    else
      {:error, {:invalid_field, key, :must_be_map}}
    end
  end

  defp validate_direction(nil), do: :ok
  defp validate_direction(:inbound), do: :ok
  defp validate_direction(:outbound), do: :ok

  defp validate_direction(_value),
    do: {:error, {:invalid_field, :direction, :must_be_inbound_or_outbound}}
end
