defmodule OcppSimulator.Application.Contracts.TransportGateway do
  @moduledoc """
  Contract for transport operations used by scenario execution.
  """

  alias OcppSimulator.Domain.Ocpp.Message

  @callback connect(String.t(), map()) :: :ok | {:error, term()}
  @callback disconnect(String.t()) :: :ok | {:error, term()}
  @callback send_message(String.t(), Message.t()) :: :ok | {:error, term()}
  @callback send_and_await_response(String.t(), Message.t(), pos_integer()) ::
              {:ok, map()} | {:error, term()}
  @callback await_inbound_call(String.t(), String.t(), pos_integer()) ::
              {:ok, Message.t()} | {:error, term()}
end
