defmodule OcppSimulator.Application.Contracts.ChargePointRepository do
  @moduledoc """
  Contract for charge point persistence.
  """

  alias OcppSimulator.Domain.ChargePoints.ChargePoint

  @callback insert(ChargePoint.t()) :: {:ok, ChargePoint.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, ChargePoint.t()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, [ChargePoint.t()]} | {:error, term()}
end
