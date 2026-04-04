defmodule OcppSimulator.Infrastructure.Security.SensitiveDataMasker do
  @moduledoc """
  Masks sensitive fields from logs and API payloads.
  """

  @redacted "[REDACTED]"

  @sensitive_key_fragments [
    "password",
    "secret",
    "token",
    "api_key",
    "apikey",
    "authorization",
    "credential",
    "cookie",
    "private_key",
    "client_secret",
    "secret_ref"
  ]

  @spec mask(term()) :: term()
  def mask(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_key(key)

      masked_value =
        if sensitive_key?(normalized_key) do
          @redacted
        else
          mask(nested_value)
        end

      Map.put(acc, key, masked_value)
    end)
  end

  def mask(value) when is_list(value), do: Enum.map(value, &mask/1)
  def mask({left, right}), do: {mask(left), mask(right)}
  def mask(value) when is_binary(value), do: maybe_mask_token_like_value(value)
  def mask(value), do: value

  @spec redacted() :: String.t()
  def redacted, do: @redacted

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
  defp normalize_key(key), do: key |> to_string() |> String.downcase()

  defp sensitive_key?(normalized_key) do
    Enum.any?(@sensitive_key_fragments, &String.contains?(normalized_key, &1))
  end

  defp maybe_mask_token_like_value(value) do
    normalized = String.trim(value)

    cond do
      normalized == "" ->
        value

      String.starts_with?(String.downcase(normalized), "bearer ") ->
        @redacted

      token_like?(normalized) ->
        @redacted

      true ->
        value
    end
  end

  defp token_like?(value) do
    String.length(value) >= 24 and
      String.match?(value, ~r/^[A-Za-z0-9+\/\._=-]+$/) and
      String.contains?(value, ".")
  end
end
