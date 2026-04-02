defmodule OcppSimulator.Infrastructure.Persistence.Mongo.WebhookDeliveryRepository do
  @moduledoc """
  MongoDB adapter implementing webhook delivery repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.WebhookDeliveryRepository

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "webhook_deliveries"

  @impl true
  def insert(delivery) when is_map(delivery) do
    document = DocumentMapper.webhook_delivery_to_document(delivery)

    with {:ok, normalized_delivery} <- DocumentMapper.webhook_delivery_from_document(document),
         {:ok, _result} <- Adapter.insert_one(@collection, document) do
      {:ok, normalized_delivery}
    end
  end

  def insert(_delivery), do: {:error, {:invalid_field, :delivery, :must_be_map}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, delivery} <- DocumentMapper.webhook_delivery_from_document(document) do
      {:ok, delivery}
    end
  end

  def get(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def update_status(id, status, attrs) when is_binary(id) and id != "" and is_map(attrs) do
    with {:ok, status_string} <- normalize_status(status),
         {:ok, existing} <- get(id),
         {:ok, metadata_patch} <- optional_map(attrs, :metadata),
         {:ok, response_summary_patch} <- optional_map(attrs, :response_summary),
         {:ok, attempts} <- optional_non_negative_integer(attrs, :attempts, existing.attempts) do
      update_payload = %{
        "status" => status_string,
        "attempts" => attempts,
        "metadata" => Map.merge(existing.metadata, metadata_patch),
        "response_summary" => Map.merge(existing.response_summary, response_summary_patch),
        "last_error" => fetch(attrs, :last_error) || existing.last_error,
        "updated_at" => DateTime.utc_now()
      }

      with {:ok, _result} <-
             Adapter.update_one(@collection, %{"id" => id}, %{"$set" => update_payload}) do
        get(id)
      end
    end
  end

  def update_status(_id, _status, _attrs),
    do: {:error, {:invalid_field, :attrs, :must_be_map}}

  @impl true
  def list(filters) when is_map(filters) do
    with {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"created_at" => -1},
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
         {:ok, deliveries} <-
           RepositoryHelpers.map_documents(
             documents,
             &DocumentMapper.webhook_delivery_from_document/1
           ),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, deliveries)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp build_filter(filters) do
    with {:ok, normalized_status} <- optional_status(filters) do
      %{}
      |> RepositoryHelpers.maybe_put_filter("id", optional_string(filters, :id))
      |> RepositoryHelpers.maybe_put_filter("run_id", optional_string(filters, :run_id))
      |> RepositoryHelpers.maybe_put_filter("event", optional_string(filters, :event))
      |> RepositoryHelpers.maybe_put_filter("status", normalized_status)
      |> then(&{:ok, &1})
    end
  end

  defp optional_status(filters) do
    case fetch(filters, :status) do
      nil -> {:ok, nil}
      status -> normalize_status(status)
    end
  end

  defp normalize_status(status) do
    case DocumentMapper.delivery_status_to_string(status) do
      "queued" -> {:ok, "queued"}
      "delivered" -> {:ok, "delivered"}
      "failed" -> {:ok, "failed"}
      "retrying" -> {:ok, "retrying"}
      _ -> {:error, {:invalid_field, :status, :unsupported_status}}
    end
  end

  defp optional_map(attrs, key) do
    case fetch(attrs, key) do
      nil -> {:ok, %{}}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_map}}
    end
  end

  defp optional_non_negative_integer(attrs, key, default) do
    case fetch(attrs, key) do
      nil -> {:ok, default}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_negative_integer}}
    end
  end

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
