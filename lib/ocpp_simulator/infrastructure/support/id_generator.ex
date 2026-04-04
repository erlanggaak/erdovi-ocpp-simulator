defmodule OcppSimulator.Infrastructure.Support.IdGenerator do
  @moduledoc """
  Default unique ID generator for run/log/delivery identifiers.
  """

  @behaviour OcppSimulator.Application.Contracts.IdGenerator

  @impl true
  def generate(namespace) when is_atom(namespace), do: generate(Atom.to_string(namespace))

  def generate(namespace) when is_binary(namespace) do
    prefix =
      namespace
      |> String.trim()
      |> case do
        "" -> "id"
        value -> value
      end

    suffix = System.unique_integer([:positive, :monotonic])
    "#{prefix}-#{suffix}"
  end
end
