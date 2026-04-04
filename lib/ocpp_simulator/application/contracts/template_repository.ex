defmodule OcppSimulator.Application.Contracts.TemplateRepository do
  @moduledoc """
  Contract for action and scenario template persistence.
  """

  @type template_type :: :action | :scenario

  @type template :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:version) => String.t(),
          required(:type) => template_type(),
          required(:payload_template) => map(),
          optional(:metadata) => map()
        }

  @type page :: %{
          required(:entries) => [template()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback upsert(template()) :: {:ok, template()} | {:error, term()}
  @callback delete(String.t(), template_type()) :: :ok | {:error, :not_found | term()}
  @callback get(String.t(), template_type()) :: {:ok, template()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
