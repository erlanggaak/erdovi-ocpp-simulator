defmodule OcppSimulator.Application.Contracts.WebhookEndpointRepository do
  @moduledoc """
  Contract for webhook endpoint configuration persistence.
  """

  @type webhook_endpoint :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:url) => String.t(),
          required(:events) => [String.t()],
          required(:retry_policy) => map(),
          optional(:secret_ref) => String.t() | nil,
          optional(:metadata) => map()
        }

  @type page :: %{
          required(:entries) => [webhook_endpoint()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback upsert(webhook_endpoint()) :: {:ok, webhook_endpoint()} | {:error, term()}
  @callback get(String.t()) :: {:ok, webhook_endpoint()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
