defmodule OcppSimulator.Application.Contracts.StructuredLogger do
  @moduledoc """
  Contract for structured application-layer logging.
  """

  @callback info(String.t(), map()) :: :ok
  @callback warn(String.t(), map()) :: :ok
  @callback error(String.t(), map()) :: :ok
end
