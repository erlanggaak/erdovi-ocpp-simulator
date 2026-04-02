defmodule OcppSimulator.Application.Contracts.WebhookDeliveryRepository do
  @moduledoc """
  Contract for webhook delivery lifecycle persistence.
  """

  @type status :: :queued | :delivered | :failed | :retrying

  @type webhook_delivery :: %{
          required(:id) => String.t(),
          required(:run_id) => String.t(),
          required(:event) => String.t(),
          required(:status) => status(),
          required(:attempts) => non_neg_integer(),
          required(:payload) => map(),
          optional(:response_summary) => map(),
          optional(:last_error) => String.t() | nil,
          optional(:metadata) => map(),
          optional(:created_at) => DateTime.t(),
          optional(:updated_at) => DateTime.t()
        }

  @type page :: %{
          required(:entries) => [webhook_delivery()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback insert(webhook_delivery()) :: {:ok, webhook_delivery()} | {:error, term()}
  @callback get(String.t()) :: {:ok, webhook_delivery()} | {:error, :not_found | term()}

  @callback update_status(String.t(), status(), map()) ::
              {:ok, webhook_delivery()} | {:error, term()}

  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
