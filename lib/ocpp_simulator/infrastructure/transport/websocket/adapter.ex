defmodule OcppSimulator.Infrastructure.Transport.WebSocket.Adapter do
  @moduledoc """
  Adapter contract for WebSocket transport operations.
  """

  @callback connect(String.t(), map()) :: :ok | {:error, term()}
  @callback disconnect(String.t(), term()) :: :ok | {:error, term()}
  @callback send_frame(String.t(), String.t()) :: :ok | {:error, term()}
end
