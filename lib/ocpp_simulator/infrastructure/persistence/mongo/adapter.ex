defmodule OcppSimulator.Infrastructure.Persistence.Mongo.Adapter do
  @moduledoc """
  Shared helper functions for Mongo persistence adapters.
  """

  @default_topology OcppSimulator.Infrastructure.Persistence.Mongo.Topology
  @default_client OcppSimulator.Infrastructure.Persistence.Mongo.DriverClient
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger

  @spec insert_one(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def insert_one(collection, document) when is_binary(collection) and is_map(document) do
    result = client_module().insert_one(topology(), collection, document, mongo_options())

    maybe_log(collection, "persistence.insert_one", %{
      collection: collection,
      operation: "insert_one",
      run_id: fetch(document, "run_id"),
      session_id: fetch(document, "session_id"),
      message_id: fetch(document, "message_id"),
      status: operation_status(result)
    })

    result
  end

  @spec find_one(String.t(), map()) :: {:ok, map()} | {:error, :not_found | term()}
  def find_one(collection, filter) when is_binary(collection) and is_map(filter) do
    result = client_module().find_one(topology(), collection, filter, mongo_options())

    maybe_log(collection, "persistence.find_one", %{
      collection: collection,
      operation: "find_one",
      run_id: fetch(filter, "run_id"),
      session_id: fetch(filter, "session_id"),
      message_id: fetch(filter, "message_id"),
      status: operation_status(result)
    })

    case result do
      {:error, reason} -> {:error, reason}
      nil -> {:error, :not_found}
      document when is_map(document) -> {:ok, document}
    end
  end

  @spec find_many(String.t(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_many(collection, filter, opts \\ []) when is_binary(collection) and is_map(filter) do
    result = client_module().find(topology(), collection, filter, mongo_options(opts))

    maybe_log(collection, "persistence.find_many", %{
      collection: collection,
      operation: "find_many",
      run_id: fetch(filter, "run_id"),
      session_id: fetch(filter, "session_id"),
      message_id: fetch(filter, "message_id"),
      status: operation_status(result)
    })

    case result do
      {:error, reason} -> {:error, reason}
      enumerable -> {:ok, Enum.to_list(enumerable)}
    end
  end

  @spec update_one(String.t(), map(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def update_one(collection, filter, update, opts \\ [])
      when is_binary(collection) and is_map(filter) and is_map(update) do
    result =
      client_module().update_one(topology(), collection, filter, update, mongo_options(opts))

    maybe_log(collection, "persistence.update_one", %{
      collection: collection,
      operation: "update_one",
      run_id: fetch(filter, "run_id"),
      session_id: fetch(filter, "session_id"),
      message_id: fetch(filter, "message_id"),
      status: operation_status(result)
    })

    result
  end

  @spec delete_one(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def delete_one(collection, filter, opts \\ []) when is_binary(collection) and is_map(filter) do
    result = client_module().delete_one(topology(), collection, filter, mongo_options(opts))

    maybe_log(collection, "persistence.delete_one", %{
      collection: collection,
      operation: "delete_one",
      run_id: fetch(filter, "run_id"),
      session_id: fetch(filter, "session_id"),
      message_id: fetch(filter, "message_id"),
      status: operation_status(result)
    })

    result
  end

  @spec count_documents(String.t(), map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_documents(collection, filter) when is_binary(collection) and is_map(filter) do
    result = client_module().count_documents(topology(), collection, filter, mongo_options())

    maybe_log(collection, "persistence.count_documents", %{
      collection: collection,
      operation: "count_documents",
      run_id: fetch(filter, "run_id"),
      session_id: fetch(filter, "session_id"),
      message_id: fetch(filter, "message_id"),
      status: operation_status(result),
      persist: false
    })

    result
  end

  @spec create_indexes(String.t(), [keyword()]) :: :ok | {:error, term()}
  def create_indexes(collection, indexes) when is_binary(collection) and is_list(indexes) do
    result = client_module().create_indexes(topology(), collection, indexes, mongo_options())

    maybe_log(collection, "persistence.create_indexes", %{
      collection: collection,
      operation: "create_indexes",
      index_count: length(indexes),
      status: operation_status(result),
      persist: false
    })

    result
  end

  @spec topology() :: term()
  def topology do
    Application.get_env(:ocpp_simulator, :mongo_persistence_topology, @default_topology)
  end

  @spec client_module() :: module()
  def client_module do
    Application.get_env(:ocpp_simulator, :mongo_persistence_client, @default_client)
  end

  @spec mongo_options(keyword()) :: keyword()
  def mongo_options(extra_opts \\ []) do
    database_options =
      case OcppSimulator.mongo_config()[:database] do
        database when is_binary(database) and database != "" -> [database: database]
        _ -> []
      end

    Keyword.merge(database_options, extra_opts)
  end

  defp maybe_log("logs", _event, _payload), do: :ok

  defp maybe_log(_collection, event, payload) do
    StructuredLogger.info(event, payload)
  end

  defp operation_status(:ok), do: "ok"
  defp operation_status({:ok, _}), do: "ok"
  defp operation_status({:error, _}), do: "error"
  defp operation_status(nil), do: "not_found"
  defp operation_status(_), do: "ok"

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) ||
      case safe_existing_atom(key) do
        nil -> nil
        atom_key -> Map.get(map, atom_key)
      end
  rescue
    _ -> nil
  end

  defp fetch(_map, _key), do: nil

  defp safe_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp safe_existing_atom(_key), do: nil
end
