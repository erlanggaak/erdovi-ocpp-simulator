defmodule OcppSimulator.Application.Contracts.IdGenerator do
  @moduledoc """
  Contract for deterministic or random ID generation in use-cases.
  """

  @callback generate(atom() | String.t()) :: String.t()
end
