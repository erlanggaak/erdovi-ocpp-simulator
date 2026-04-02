defmodule OcppSimulator.Infrastructure.Persistence.Mongo.Adapter do
  @moduledoc """
  Shared helper functions for Mongo persistence adapters.
  """

  @default_topology OcppSimulator.Infrastructure.Persistence.Mongo.Topology
  @default_client OcppSimulator.Infrastructure.Persistence.Mongo.DriverClient

  @spec insert_one(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def insert_one(collection, document) when is_binary(collection) and is_map(document) do
    client_module().insert_one(topology(), collection, document, mongo_options())
  end

  @spec find_one(String.t(), map()) :: {:ok, map()} | {:error, :not_found | term()}
  def find_one(collection, filter) when is_binary(collection) and is_map(filter) do
    case client_module().find_one(topology(), collection, filter, mongo_options()) do
      {:error, reason} -> {:error, reason}
      nil -> {:error, :not_found}
      document when is_map(document) -> {:ok, document}
    end
  end

  @spec find_many(String.t(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_many(collection, filter, opts \\ []) when is_binary(collection) and is_map(filter) do
    case client_module().find(topology(), collection, filter, mongo_options(opts)) do
      {:error, reason} -> {:error, reason}
      enumerable -> {:ok, Enum.to_list(enumerable)}
    end
  end

  @spec update_one(String.t(), map(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def update_one(collection, filter, update, opts \\ [])
      when is_binary(collection) and is_map(filter) and is_map(update) do
    client_module().update_one(topology(), collection, filter, update, mongo_options(opts))
  end

  @spec count_documents(String.t(), map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_documents(collection, filter) when is_binary(collection) and is_map(filter) do
    client_module().count_documents(topology(), collection, filter, mongo_options())
  end

  @spec create_indexes(String.t(), [keyword()]) :: :ok | {:error, term()}
  def create_indexes(collection, indexes) when is_binary(collection) and is_list(indexes) do
    client_module().create_indexes(topology(), collection, indexes, mongo_options())
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
end
