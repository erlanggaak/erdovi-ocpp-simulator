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

  @type page :: %{
          required(:entries) => [endpoint()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback insert(endpoint()) :: {:ok, endpoint()} | {:error, term()}
  @callback update(endpoint()) :: {:ok, endpoint()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, :not_found | term()}
  @callback get(String.t()) :: {:ok, endpoint()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
