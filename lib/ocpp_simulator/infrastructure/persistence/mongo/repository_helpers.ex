defmodule OcppSimulator.Infrastructure.Persistence.Mongo.RepositoryHelpers do
  @moduledoc false

  @spec map_documents([map()], (map() -> {:ok, term()} | {:error, term()})) ::
          {:ok, [term()]} | {:error, term()}
  def map_documents(documents, mapper) when is_list(documents) and is_function(mapper, 1) do
    documents
    |> Enum.reduce_while({:ok, []}, fn document, {:ok, acc} ->
      case mapper.(document) do
        {:ok, mapped} -> {:cont, {:ok, [mapped | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, mapped_documents} -> {:ok, Enum.reverse(mapped_documents)}
      {:error, _reason} = error -> error
    end
  end

  @spec maybe_put_filter(map(), String.t(), term()) :: map()
  def maybe_put_filter(filter, _key, nil), do: filter
  def maybe_put_filter(filter, key, value), do: Map.put(filter, key, value)
end
