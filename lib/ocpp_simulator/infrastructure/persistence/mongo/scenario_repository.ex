defmodule OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository do
  @moduledoc """
  MongoDB adapter implementing scenario repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.ScenarioRepository

  alias OcppSimulator.Domain.Scenarios.Scenario
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "scenarios"

  @impl true
  def insert(%Scenario{} = scenario) do
    document = DocumentMapper.scenario_to_document(scenario)

    with {:ok, _result} <- Adapter.insert_one(@collection, document) do
      {:ok, scenario}
    end
  end

  def insert(_scenario), do: {:error, {:invalid_field, :scenario, :must_be_struct}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, scenario} <- DocumentMapper.scenario_from_document(document) do
      {:ok, scenario}
    end
  end

  def get(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def list(filters) when is_map(filters) do
    filter = build_filter(filters)

    with {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"name" => 1, "version" => -1},
             default_page_size: 50,
             max_page_size: 200
           ),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, scenarios} <-
           RepositoryHelpers.map_documents(documents, &DocumentMapper.scenario_from_document/1),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, scenarios)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp build_filter(filters) do
    %{}
    |> RepositoryHelpers.maybe_put_filter("id", optional_string(filters, :id))
    |> RepositoryHelpers.maybe_put_filter("name", optional_string(filters, :name))
    |> RepositoryHelpers.maybe_put_filter("version", optional_string(filters, :version))
  end

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
