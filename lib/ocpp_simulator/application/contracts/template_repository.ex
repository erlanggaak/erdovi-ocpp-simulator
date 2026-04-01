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

  @callback upsert(template()) :: {:ok, template()} | {:error, term()}
  @callback get(String.t(), template_type()) :: {:ok, template()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, [template()]} | {:error, term()}
end
