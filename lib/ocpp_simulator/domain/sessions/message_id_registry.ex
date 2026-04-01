defmodule OcppSimulator.Domain.Sessions.MessageIdRegistry do
  @moduledoc """
  Enforces per-session uniqueness for OCPP message IDs.
  """

  @enforce_keys [:session_id, :used_ids]
  defstruct [:session_id, :used_ids]

  @type t :: %__MODULE__{
          session_id: String.t(),
          used_ids: MapSet.t(String.t())
        }

  @spec new(String.t()) :: {:ok, t()} | {:error, term()}
  def new(session_id) when is_binary(session_id) and session_id != "" do
    {:ok, %__MODULE__{session_id: session_id, used_ids: MapSet.new()}}
  end

  def new(_session_id), do: {:error, {:invalid_field, :session_id, :must_be_non_empty_string}}

  @spec register(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def register(%__MODULE__{} = registry, message_id)
      when is_binary(message_id) and message_id != "" do
    if MapSet.member?(registry.used_ids, message_id) do
      {:error, {:duplicate_message_id, message_id}}
    else
      {:ok, %{registry | used_ids: MapSet.put(registry.used_ids, message_id)}}
    end
  end

  def register(%__MODULE__{}, _message_id),
    do: {:error, {:invalid_field, :message_id, :must_be_non_empty_string}}

  @spec registered?(t(), String.t()) :: boolean()
  def registered?(%__MODULE__{} = registry, message_id) when is_binary(message_id) do
    MapSet.member?(registry.used_ids, message_id)
  end

  def registered?(%__MODULE__{}, _message_id), do: false
end
