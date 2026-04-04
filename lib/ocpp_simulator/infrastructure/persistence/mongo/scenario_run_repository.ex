defmodule OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRunRepository do
  @moduledoc """
  MongoDB adapter implementing scenario run persistence contract.
  """

  @behaviour OcppSimulator.Application.Contracts.ScenarioRunRepository

  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter
  alias OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper
  alias OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder
  alias OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers

  @collection "scenario_runs"
  @run_states ScenarioRun.states()

  @impl true
  def insert(%ScenarioRun{} = scenario_run) do
    document = DocumentMapper.scenario_run_to_document(scenario_run)

    with {:ok, _result} <- Adapter.insert_one(@collection, document) do
      {:ok, scenario_run}
    end
  end

  def insert(_scenario_run), do: {:error, {:invalid_field, :scenario_run, :must_be_struct}}

  @impl true
  def get(id) when is_binary(id) and id != "" do
    with {:ok, document} <- Adapter.find_one(@collection, %{"id" => id}),
         {:ok, scenario_run} <- DocumentMapper.scenario_run_from_document(document) do
      {:ok, scenario_run}
    end
  end

  def get(_id), do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  @impl true
  def update_state(id, state, metadata) when is_binary(id) and id != "" and is_map(metadata) do
    with {:ok, normalized_state} <- normalize_state(state),
         {:ok, existing_run} <- get(id),
         merged_metadata <-
           existing_run.metadata
           |> normalize_metadata_for_storage()
           |> Map.merge(normalize_metadata_for_storage(metadata)),
         {:ok, _result} <-
           Adapter.update_one(
             @collection,
             %{"id" => id},
             %{
               "$set" => %{
                 "state" => normalized_state,
                 "metadata" => merged_metadata,
                 "updated_at" => DateTime.utc_now()
               }
             }
           ) do
      get(id)
    end
  end

  def update_state(id, _state, _metadata) when not is_binary(id) or id == "",
    do: {:error, {:invalid_field, :id, :must_be_non_empty_string}}

  def update_state(_id, _state, metadata) when not is_map(metadata),
    do: {:error, {:invalid_field, :metadata, :must_be_map}}

  @impl true
  def list_history(filters) when is_map(filters) do
    with {:ok, filter} <- QueryBuilder.run_history_filter(filters),
         {:ok, pagination} <-
           QueryBuilder.pagination(filters,
             default_sort: %{"created_at" => -1},
             default_page_size: 25,
             max_page_size: 100
           ),
         {:ok, documents} <-
           Adapter.find_many(
             @collection,
             filter,
             QueryBuilder.apply_pagination_options([], pagination)
           ),
         {:ok, entries} <-
           RepositoryHelpers.map_documents(
             documents,
             &DocumentMapper.scenario_run_from_document/1
           ),
         {:ok, total_entries} <- Adapter.count_documents(@collection, filter) do
      {:ok,
       QueryBuilder.pagination_metadata(total_entries, pagination)
       |> Map.put(:entries, entries)}
    end
  end

  def list_history(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  @spec list(map()) :: {:ok, [ScenarioRun.t()]} | {:error, term()}
  def list(filters) when is_map(filters) do
    with {:ok, %{entries: entries}} <- list_history(filters) do
      {:ok, entries}
    end
  end

  def list(_filters), do: {:error, {:invalid_field, :filters, :must_be_map}}

  defp normalize_metadata_for_storage(%DateTime{} = datetime), do: datetime
  defp normalize_metadata_for_storage(%NaiveDateTime{} = naive_datetime), do: naive_datetime

  defp normalize_metadata_for_storage(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_metadata_for_storage()
  end

  defp normalize_metadata_for_storage(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_metadata_for_storage(metadata) when is_map(metadata) do
    metadata
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, normalize_metadata_key(key), normalize_metadata_for_storage(value))
    end)
  end

  defp normalize_metadata_for_storage(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&normalize_metadata_for_storage/1)

  defp normalize_metadata_for_storage(list) when is_list(list),
    do: Enum.map(list, &normalize_metadata_for_storage/1)

  defp normalize_metadata_for_storage(value), do: value

  defp normalize_metadata_key(key) when is_binary(key), do: key
  defp normalize_metadata_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_metadata_key(key), do: to_string(key)

  defp normalize_state(state) when state in @run_states, do: {:ok, Atom.to_string(state)}

  defp normalize_state(state) when is_binary(state) do
    normalized = String.trim(state)

    case normalized do
      "draft" -> {:ok, "draft"}
      "queued" -> {:ok, "queued"}
      "running" -> {:ok, "running"}
      "succeeded" -> {:ok, "succeeded"}
      "failed" -> {:ok, "failed"}
      "canceled" -> {:ok, "canceled"}
      "timed_out" -> {:ok, "timed_out"}
      _ -> {:error, {:invalid_field, :state, :unsupported_state}}
    end
  end

  defp normalize_state(_state), do: {:error, {:invalid_field, :state, :unsupported_state}}
end
