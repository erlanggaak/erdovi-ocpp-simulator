defmodule OcppSimulator.Infrastructure.Persistence.Mongo.WebhookEndpointRepository do
  @moduledoc """
  MongoDB adapter implementing webhook endpoint repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.WebhookEndpointRepository

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "webhook_endpoints"

  @impl true
  def upsert(endpoint) when is_map(endpoint) do
    now = DateTime.utc_now()
    document = DocumentMapper.webhook_endpoint_to_document(endpoint)

    with {:ok, id} <- required_string(document["id"], :id),
         {:ok, _result} <-
           Adapter.update_one(
             @collection,
             %{"id" => id},
             %{
               "$set" => Map.put(document, "updated_at", now),
               "$setOnInsert" => %{"created_at" => now}
             },
             upsert: true
           ) do
      get(id)
    end
  end

  def upsert(_endpoint), do: {:error, {:invalid_field, :endpoint, :must_be_map}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, endpoint} <- DocumentMapper.webhook_endpoint_from_document(document) do
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
             &DocumentMapper.webhook_endpoint_from_document/1
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
    |> RepositoryHelpers.maybe_put_filter("events", optional_string(filters, :event))
  end

  defp required_string(value, _key) when is_binary(value) and value != "", do: {:ok, value}

  defp required_string(_value, key),
    do: {:error, {:invalid_field, key, :must_be_non_empty_string}}

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
