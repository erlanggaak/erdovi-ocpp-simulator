defmodule OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository do
  @moduledoc """
  MongoDB adapter implementing action/scenario template repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.TemplateRepository

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "action_templates"

  @impl true
  def upsert(template) when is_map(template) do
    now = DateTime.utc_now()
    document = DocumentMapper.template_to_document(template)

    with {:ok, type_string} <- normalize_template_type(document["type"]),
         {:ok, id} <- required_string(document["id"], :id),
         {:ok, _result} <-
           Adapter.update_one(
             @collection,
             %{"id" => id, "type" => type_string},
             %{
               "$set" =>
                 document
                 |> Map.put("type", type_string)
                 |> Map.put("updated_at", now),
               "$setOnInsert" => %{"created_at" => now}
             },
             upsert: true
           ) do
      get(id, type_string)
    end
  end

  def upsert(_template), do: {:error, {:invalid_field, :template, :must_be_map}}

  @impl true
  def get(id, type) when is_binary(id) and id != "" do
    with {:ok, normalized_type} <- normalize_template_type(type),
         {:ok, document} <-
           Adapter.find_one(@collection, %{"id" => id, "type" => normalized_type}),
         {:ok, template} <- DocumentMapper.template_from_document(document) do
      {:ok, template}
    end
  end

  def get(_id, _type), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def delete(id, type) when is_binary(id) and id != "" do
    with {:ok, normalized_type} <- normalize_template_type(type),
         {:ok, result} <-
           Adapter.delete_one(@collection, %{"id" => id, "type" => normalized_type}) do
      if deleted_count(result) > 0 do
        :ok
      else
        {:error, :not_found}
      end
    end
  end

  def delete(_id, _type), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def list(filters) when is_map(filters) do
    with {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"name" => 1, "version" => -1},
             default_page_size: 50,
             max_page_size: 200
           ),
         {:ok, filter} <- build_filter(filters),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, templates} <-
           RepositoryHelpers.map_documents(documents, &DocumentMapper.template_from_document/1),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, templates)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp build_filter(filters) do
    with {:ok, maybe_type} <- optional_template_type(filters) do
      %{}
      |> RepositoryHelpers.maybe_put_filter("id", optional_string(filters, :id))
      |> RepositoryHelpers.maybe_put_filter("name", optional_string(filters, :name))
      |> RepositoryHelpers.maybe_put_filter("type", maybe_type)
      |> then(&{:ok, &1})
    end
  end

  defp optional_template_type(filters) do
    case fetch(filters, :type) do
      nil -> {:ok, nil}
      type -> normalize_template_type(type)
    end
  end

  defp normalize_template_type(type) do
    case DocumentMapper.template_type_to_string(type) do
      "action" -> {:ok, "action"}
      "scenario" -> {:ok, "scenario"}
      _ -> {:error, {:invalid_field, :type, :unsupported_template_type}}
    end
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

  defp deleted_count(result) when is_map(result) do
    Map.get(result, :deleted_count) || Map.get(result, "deleted_count") || 0
  end

  defp deleted_count(_result), do: 0
end
