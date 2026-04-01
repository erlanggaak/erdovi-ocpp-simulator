defmodule OcppSimulator.Application.Contracts.Clock do
  @moduledoc """
  Contract for retrieving current wall-clock UTC time.
  """

  @callback utc_now() :: DateTime.t()
end
