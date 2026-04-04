defmodule OcppSimulator.Infrastructure.Persistence.Mongo.ChargePointRepository do
  @moduledoc """
  MongoDB adapter implementing charge point repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.ChargePointRepository

  alias OcppSimulator.Domain.ChargePoints.ChargePoint
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "charge_points"

  @impl true
  def insert(%ChargePoint{} = charge_point) do
    document = DocumentMapper.charge_point_to_document(charge_point)

    with {:ok, _result} <- Adapter.insert_one(@collection, document) do
      {:ok, charge_point}
    end
  end

  def insert(_charge_point), do: {:error, {:invalid_field, :charge_point, :must_be_struct}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, charge_point} <- DocumentMapper.charge_point_from_document(document) do
      {:ok, charge_point}
    end
  end

  def get(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def update(%ChargePoint{} = charge_point) do
    document = DocumentMapper.charge_point_to_document(charge_point)

    with {:ok, _result} <-
           Adapter.update_one(
             @collection,
             %{"id" => charge_point.id},
             %{"$set" => document}
           ) do
      get(charge_point.id)
    end
  end

  def update(_charge_point), do: {:error, {:invalid_field, :charge_point, :must_be_struct}}

  @impl true
  def delete(id) when is_binary(id) and id != "" do
    with {:ok, result} <- Adapter.delete_one(@collection, %{"id" => id}) do
      if deleted_count(result) > 0 do
        :ok
      else
        {:error, :not_found}
      end
    end
  end

  def delete(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def list(filters) when is_map(filters) do
    filter = build_filter(filters)

    with {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"id" => 1},
             default_page_size: 50,
             max_page_size: 200
           ),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, charge_points} <-
           RepositoryHelpers.map_documents(
             documents,
             &DocumentMapper.charge_point_from_document/1
           ),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, charge_points)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp build_filter(filters) do
    %{}
    |> RepositoryHelpers.maybe_put_filter("id", optional_string(filters, :id))
    |> RepositoryHelpers.maybe_put_filter("vendor", optional_string(filters, :vendor))
    |> RepositoryHelpers.maybe_put_filter("model", optional_string(filters, :model))
    |> RepositoryHelpers.maybe_put_filter(
      "behavior_profile",
      optional_string(filters, :behavior_profile)
    )
  end

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp deleted_count(result) when is_map(result) do
    Map.get(result, :deleted_count) || Map.get(result, "deleted_count") || 0
  end

  defp deleted_count(_result), do: 0
end
