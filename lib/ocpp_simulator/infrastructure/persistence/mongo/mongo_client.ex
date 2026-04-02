defmodule OcppSimulator.Infrastructure.Persistence.Mongo.MongoClient do
  @moduledoc """
  Minimal Mongo client behavior used by persistence adapters.
  """

  @type topology :: term()
  @type collection :: String.t()

  @callback find(topology(), collection(), map(), keyword()) :: Enumerable.t() | {:error, term()}

  @callback find_one(topology(), collection(), map(), keyword()) ::
              map() | nil | {:error, term()}

  @callback insert_one(topology(), collection(), map(), keyword()) ::
              {:ok, term()} | {:error, term()}

  @callback update_one(topology(), collection(), map(), map(), keyword()) ::
              {:ok, term()} | {:error, term()}

  @callback count_documents(topology(), collection(), map(), keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @callback create_indexes(topology(), collection(), [keyword()], keyword()) ::
              :ok | {:error, term()}
end
