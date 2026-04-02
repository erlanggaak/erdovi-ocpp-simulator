defmodule OcppSimulator.Infrastructure.Persistence.Mongo.LogRepository do
  @moduledoc """
  MongoDB adapter implementing structured log repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.LogRepository

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "logs"

  @impl true
  def insert(log_entry) when is_map(log_entry) do
    document = DocumentMapper.log_entry_to_document(log_entry)

    with {:ok, normalized_log_entry} <- DocumentMapper.log_entry_from_document(document),
         {:ok, _result} <- Adapter.insert_one(@collection, document) do
      {:ok, normalized_log_entry}
    end
  end

  def insert(_log_entry), do: {:error, {:invalid_field, :log_entry, :must_be_map}}

  @impl true
  def list(filters) when is_map(filters) do
    allow_unfiltered = fetch(filters, :allow_unfiltered) == true

    with {:ok, filter} <- QueryBuilder.log_filter(filters, require_filter: not allow_unfiltered),
         {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"timestamp" => -1},
             default_page_size: 100,
             max_page_size: 500
           ),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, entries} <-
           RepositoryHelpers.map_documents(documents, &DocumentMapper.log_entry_from_document/1),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, entries)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
