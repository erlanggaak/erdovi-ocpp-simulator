defmodule OcppSimulator.TestSupport.InMemoryMongoClient do
  @moduledoc false

  @behaviour OcppSimulator.Infrastructure.Persistence.Mongo.MongoClient

  @agent __MODULE__

  @spec ensure_started() :: :ok
  def ensure_started do
    case Process.whereis(@agent) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> %{collections: %{}, indexes: %{}} end, name: @agent)
        :ok

      _pid ->
        :ok
    end
  end

  @spec reset!() :: :ok
  def reset! do
    ensure_started()
    Agent.update(@agent, fn _ -> %{collections: %{}, indexes: %{}} end)
  end

  @spec indexes_for(String.t()) :: [keyword()]
  def indexes_for(collection) when is_binary(collection) do
    ensure_started()
    Agent.get(@agent, fn state -> get_in(state, [:indexes, collection]) || [] end)
  end

  @impl true
  def find(_topology, collection, filter, opts) do
    ensure_started()

    Agent.get(@agent, fn state ->
      state
      |> collection_documents(collection)
      |> Enum.filter(&matches_filter?(&1, filter))
      |> apply_sort(Keyword.get(opts, :sort))
      |> apply_skip(Keyword.get(opts, :skip, 0))
      |> apply_limit(Keyword.get(opts, :limit))
    end)
  end

  @impl true
  def find_one(_topology, collection, filter, opts) do
    ensure_started()

    Agent.get(@agent, fn state ->
      state
      |> collection_documents(collection)
      |> Enum.filter(&matches_filter?(&1, filter))
      |> apply_sort(Keyword.get(opts, :sort))
      |> List.first()
    end)
  end

  @impl true
  def insert_one(_topology, collection, document, _opts) do
    ensure_started()

    Agent.get_and_update(@agent, fn state ->
      documents = collection_documents(state, collection)
      id = fetch(document, "id")

      if duplicate_id?(documents, id) do
        {{:error, :duplicate_key}, state}
      else
        new_state = put_collection_documents(state, collection, [document | documents])
        {{:ok, %{inserted_id: id}}, new_state}
      end
    end)
  end

  @impl true
  def update_one(_topology, collection, filter, update, opts) do
    ensure_started()

    Agent.get_and_update(@agent, fn state ->
      documents = collection_documents(state, collection)

      case pop_first_match(documents, filter) do
        {:ok, matched_document, remaining_documents} ->
          updated_document = apply_update(matched_document, update)
          new_documents = [updated_document | remaining_documents]
          new_state = put_collection_documents(state, collection, new_documents)

          {{:ok, %{matched_count: 1, modified_count: 1}}, new_state}

        :not_found ->
          if Keyword.get(opts, :upsert, false) do
            inserted_document = build_upsert_document(filter, update)
            id = fetch(inserted_document, "id")

            if duplicate_id?(documents, id) do
              {{:error, :duplicate_key}, state}
            else
              new_state = put_collection_documents(state, collection, [inserted_document | documents])
              {{:ok, %{matched_count: 0, modified_count: 0, upserted_id: id}}, new_state}
            end
          else
            {{:ok, %{matched_count: 0, modified_count: 0}}, state}
          end
      end
    end)
  end

  @impl true
  def count_documents(_topology, collection, filter, _opts) do
    ensure_started()

    total =
      Agent.get(@agent, fn state ->
        state
        |> collection_documents(collection)
        |> Enum.count(&matches_filter?(&1, filter))
      end)

    {:ok, total}
  end

  @impl true
  def create_indexes(_topology, collection, indexes, _opts) do
    ensure_started()

    Agent.update(@agent, fn state ->
      update_in(state, [:indexes], fn existing ->
        Map.put(existing, collection, indexes)
      end)
    end)

    :ok
  end

  defp collection_documents(state, collection) do
    get_in(state, [:collections, collection]) || []
  end

  defp put_collection_documents(state, collection, documents) do
    put_in(state, [:collections, collection], documents)
  end

  defp duplicate_id?(_documents, nil), do: false

  defp duplicate_id?(documents, id) do
    Enum.any?(documents, fn document -> fetch(document, "id") == id end)
  end

  defp pop_first_match(documents, filter) do
    index = Enum.find_index(documents, &matches_filter?(&1, filter))

    if is_integer(index) do
      {matched_document, remaining_documents} = List.pop_at(documents, index)
      {:ok, matched_document, remaining_documents}
    else
      :not_found
    end
  end

  defp apply_update(document, update) do
    set_payload = fetch(update, "$set") || %{}
    Map.merge(document, stringify_keys(set_payload))
  end

  defp build_upsert_document(filter, update) do
    equality_fields =
      filter
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        if is_map(value) do
          acc
        else
          Map.put(acc, to_string(key), value)
        end
      end)

    set_on_insert_payload = stringify_keys(fetch(update, "$setOnInsert") || %{})
    set_payload = stringify_keys(fetch(update, "$set") || %{})

    equality_fields
    |> Map.merge(set_on_insert_payload)
    |> Map.merge(set_payload)
  end

  defp matches_filter?(_document, filter) when filter == %{}, do: true

  defp matches_filter?(document, filter) when is_map(filter) do
    Enum.all?(filter, fn {key, expected_value} ->
      actual_value = fetch(document, key)
      matches_condition?(actual_value, expected_value)
    end)
  end

  defp matches_filter?(_document, _filter), do: true

  defp matches_condition?(actual_value, expected_value) when is_map(expected_value) do
    Enum.all?(expected_value, fn {operator, operand} ->
      case to_string(operator) do
        "$in" when is_list(operand) -> actual_value in operand
        "$gte" -> compare_values(actual_value, operand) in [:eq, :gt]
        "$lte" -> compare_values(actual_value, operand) in [:eq, :lt]
        _ -> false
      end
    end)
  end

  defp matches_condition?(actual_value, expected_value) when is_list(actual_value),
    do: expected_value in actual_value

  defp matches_condition?(actual_value, expected_value), do: actual_value == expected_value

  defp apply_sort(documents, nil), do: documents

  defp apply_sort(documents, sort) do
    sort_fields = normalize_sort(sort)

    Enum.sort(documents, fn left, right ->
      compare_documents(left, right, sort_fields) != :gt
    end)
  end

  defp normalize_sort(sort) when is_map(sort) do
    Enum.map(sort, fn {key, direction} -> {to_string(key), normalize_sort_direction(direction)} end)
  end

  defp normalize_sort(sort) when is_list(sort) do
    Enum.map(sort, fn {key, direction} -> {to_string(key), normalize_sort_direction(direction)} end)
  end

  defp normalize_sort(_sort), do: []

  defp normalize_sort_direction(1), do: 1
  defp normalize_sort_direction(-1), do: -1
  defp normalize_sort_direction(:asc), do: 1
  defp normalize_sort_direction(:desc), do: -1
  defp normalize_sort_direction("asc"), do: 1
  defp normalize_sort_direction("desc"), do: -1
  defp normalize_sort_direction("1"), do: 1
  defp normalize_sort_direction("-1"), do: -1
  defp normalize_sort_direction(_direction), do: 1

  defp compare_documents(_left, _right, []), do: :eq

  defp compare_documents(left, right, [{key, direction} | rest]) do
    comparison = compare_values(fetch(left, key), fetch(right, key))

    case comparison do
      :eq -> compare_documents(left, right, rest)
      :lt -> if(direction == 1, do: :lt, else: :gt)
      :gt -> if(direction == 1, do: :gt, else: :lt)
    end
  end

  defp compare_values(left, right) do
    cond do
      is_nil(left) and is_nil(right) ->
        :eq

      is_nil(left) ->
        :lt

      is_nil(right) ->
        :gt

      match?(%DateTime{}, left) and match?(%DateTime{}, right) ->
        DateTime.compare(left, right)

      true ->
        left_cmp = comparable(left)
        right_cmp = comparable(right)

        cond do
          left_cmp < right_cmp -> :lt
          left_cmp > right_cmp -> :gt
          true -> :eq
        end
    end
  end

  defp comparable(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp comparable(value) when is_binary(value), do: value
  defp comparable(value) when is_number(value), do: value
  defp comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp comparable(value), do: inspect(value)

  defp apply_skip(documents, skip) when is_integer(skip) and skip > 0, do: Enum.drop(documents, skip)
  defp apply_skip(documents, _skip), do: documents

  defp apply_limit(documents, limit) when is_integer(limit) and limit >= 0, do: Enum.take(documents, limit)
  defp apply_limit(documents, _limit), do: documents

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
