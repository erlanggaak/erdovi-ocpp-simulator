defmodule OcppSimulator.Application.Contracts.ChargePointRepository do
  @moduledoc """
  Contract for charge point persistence.
  """

  alias OcppSimulator.Domain.ChargePoints.ChargePoint

  @type page :: %{
          required(:entries) => [ChargePoint.t()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback insert(ChargePoint.t()) :: {:ok, ChargePoint.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, ChargePoint.t()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
