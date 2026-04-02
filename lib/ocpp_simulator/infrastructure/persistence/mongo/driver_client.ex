defmodule OcppSimulator.Infrastructure.Persistence.Mongo.DriverClient do
  @moduledoc """
  MongoDB driver-backed implementation of `MongoClient` behavior.
  """

  @behaviour OcppSimulator.Infrastructure.Persistence.Mongo.MongoClient

  @impl true
  def find(topology, collection, filter, opts),
    do: Mongo.find(topology, collection, filter, opts)

  @impl true
  def find_one(topology, collection, filter, opts),
    do: Mongo.find_one(topology, collection, filter, opts)

  @impl true
  def insert_one(topology, collection, document, opts),
    do: Mongo.insert_one(topology, collection, document, opts)

  @impl true
  def update_one(topology, collection, filter, update, opts),
    do: Mongo.update_one(topology, collection, filter, update, opts)

  @impl true
  def count_documents(topology, collection, filter, opts),
    do: Mongo.count_documents(topology, collection, filter, opts)

  @impl true
  def create_indexes(topology, collection, indexes, opts),
    do: Mongo.create_indexes(topology, collection, indexes, opts)
end
