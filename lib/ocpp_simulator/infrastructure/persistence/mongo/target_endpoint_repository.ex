defmodule OcppSimulator.Infrastructure.Persistence.Mongo.TargetEndpointRepository do
  @moduledoc """
  MongoDB adapter implementing target endpoint repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.TargetEndpointRepository

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "target_endpoints"

  @impl true
  def insert(endpoint) when is_map(endpoint) do
    document = DocumentMapper.target_endpoint_to_document(endpoint)

    with {:ok, _result} <- Adapter.insert_one(@collection, document),
         {:ok, normalized_endpoint} <- DocumentMapper.target_endpoint_from_document(document) do
      {:ok, normalized_endpoint}
    end
  end

  def insert(_endpoint), do: {:error, {:invalid_field, :endpoint, :must_be_map}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, endpoint} <- DocumentMapper.target_endpoint_from_document(document) do
      {:ok, endpoint}
    end
  end

  def get(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def list(filters) when is_map(filters) do
    filter = build_filter(filters)

    with {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"name" => 1},
             default_page_size: 50,
             max_page_size: 200
           ),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, endpoints} <-
           RepositoryHelpers.map_documents(
             documents,
             &DocumentMapper.target_endpoint_from_document/1
           ),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, endpoints)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp build_filter(filters) do
    %{}
    |> RepositoryHelpers.maybe_put_filter("id", optional_string(filters, :id))
    |> RepositoryHelpers.maybe_put_filter("name", optional_string(filters, :name))
    |> RepositoryHelpers.maybe_put_filter("url", optional_string(filters, :url))
  end

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
