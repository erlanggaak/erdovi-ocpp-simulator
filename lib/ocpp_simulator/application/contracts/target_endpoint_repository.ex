defmodule OcppSimulator.Application.Contracts.TargetEndpointRepository do
  @moduledoc """
  Contract for target CSMS endpoint persistence.
  """

  @type endpoint :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:url) => String.t(),
          required(:protocol_options) => map(),
          required(:retry_policy) => map(),
          optional(:metadata) => map()
        }

  @callback insert(endpoint()) :: {:ok, endpoint()} | {:error, term()}
  @callback get(String.t()) :: {:ok, endpoint()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, [endpoint()]} | {:error, term()}
end
