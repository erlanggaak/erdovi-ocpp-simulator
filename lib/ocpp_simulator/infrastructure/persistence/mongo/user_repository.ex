defmodule OcppSimulator.Infrastructure.Persistence.Mongo.UserRepository do
  @moduledoc """
  MongoDB adapter implementing user repository contract.
  """

  @behaviour OcppSimulator.Application.Contracts.UserRepository

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "users"

  @impl true
  def upsert(user) when is_map(user) do
    now = DateTime.utc_now()
    document = DocumentMapper.user_to_document(user)

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

  def upsert(_user), do: {:error, {:invalid_field, :user, :must_be_map}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, user} <- DocumentMapper.user_from_document(document) do
      {:ok, user}
    end
  end

  def get(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def get_by_email(email) when is_binary(email) and email != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"email" => email}),
         {:ok, user} <- DocumentMapper.user_from_document(document) do
      {:ok, user}
    end
  end

  def get_by_email(_email), do: {:error, {:invalid_field, :email, :must_be_non_empty_string}}

  @impl true
  def list(filters) when is_map(filters) do
    filter = build_filter(filters)

    with {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"email" => 1},
             default_page_size: 50,
             max_page_size: 200
           ),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, users} <-
           RepositoryHelpers.map_documents(documents, &DocumentMapper.user_from_document/1),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, users)}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp build_filter(filters) do
    %{}
    |> RepositoryHelpers.maybe_put_filter("id", optional_string(filters, :id))
    |> RepositoryHelpers.maybe_put_filter("email", optional_string(filters, :email))
    |> RepositoryHelpers.maybe_put_filter("role", optional_role(filters))
  end

  defp optional_role(filters) do
    case fetch(filters, :role) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp required_string(value, _key) when is_binary(value) and value != "", do: {:ok, value}

  defp required_string(_value, key),
    do: {:error, {:invalid_field, key, :must_be_non_empty_string}}

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
