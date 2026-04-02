defmodule OcppSimulator.Infrastructure.Serialization.OcppJson do
  @moduledoc """
  OCPP 1.6J frame encoder/decoder with strict payload validation.
  """

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator

  @spec encode(Message.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(%Message{} = message, opts \\ []) do
    with :ok <- PayloadValidator.validate_message(message, opts),
         {:ok, payload} <- Jason.encode(Message.to_frame(message)) do
      {:ok, payload}
    end
  end

  @spec decode(String.t(), Message.direction(), keyword()) :: {:ok, Message.t()} | {:error, term()}
  def decode(frame_json, direction, opts \\ []) when is_binary(frame_json) do
    with {:ok, frame} <- Jason.decode(frame_json),
         :ok <- ensure_frame_list(frame),
         {:ok, message} <- Message.from_frame(frame, direction),
         :ok <- PayloadValidator.validate_message(message, opts) do
      {:ok, message}
    else
      {:error, %Jason.DecodeError{}} -> {:error, {:invalid_frame, :invalid_json}}
      error -> error
    end
  end

  @spec decode_frame(list(term()), Message.direction(), keyword()) ::
          {:ok, Message.t()} | {:error, term()}
  def decode_frame(frame, direction, opts \\ []) when is_list(frame) do
    with :ok <- ensure_frame_list(frame),
         {:ok, message} <- Message.from_frame(frame, direction),
         :ok <- PayloadValidator.validate_message(message, opts) do
      {:ok, message}
    end
  end

  defp ensure_frame_list(frame) when is_list(frame), do: :ok
  defp ensure_frame_list(_frame), do: {:error, {:invalid_frame, :must_be_array}}
end
