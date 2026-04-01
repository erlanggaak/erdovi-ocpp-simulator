defmodule OcppSimulator.Domain.Scenarios.VariableResolver do
  @moduledoc """
  Resolves scenario variables with a deterministic scope precedence:
  scenario < run < session < step.
  """

  @resolution_order [:scenario, :run, :session, :step]
  @placeholder ~r/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/
  @exact_placeholder ~r/^\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}$/

  @spec resolution_order() :: [atom()]
  def resolution_order, do: @resolution_order

  @spec resolve(term(), map() | keyword()) :: {:ok, term()} | {:error, term()}
  def resolve(template, scopes) when is_list(scopes),
    do: resolve(template, Enum.into(scopes, %{}))

  def resolve(template, scopes) when is_map(scopes) do
    with {:ok, context} <- build_context(scopes) do
      resolve_term(template, context)
    end
  end

  def resolve(_template, _scopes),
    do: {:error, {:invalid_field, :scopes, :must_be_map_or_keyword}}

  defp build_context(scopes) do
    @resolution_order
    |> Enum.reduce_while({:ok, %{}}, fn scope, {:ok, context} ->
      value = Map.get(scopes, scope, Map.get(scopes, Atom.to_string(scope), %{}))

      case normalize_scope(scope, value) do
        {:ok, normalized_scope} ->
          {:cont, {:ok, deep_merge(context, normalized_scope)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_scope(_scope, nil), do: {:ok, %{}}

  defp normalize_scope(scope, value) when is_map(value) do
    case normalize_map_keys(value) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, reason} -> {:error, {:invalid_field, scope, reason}}
    end
  end

  defp normalize_scope(scope, _value),
    do: {:error, {:invalid_field, scope, :scope_must_be_map_or_nil}}

  defp resolve_term(value, _context) when is_number(value) or is_boolean(value) or is_nil(value),
    do: {:ok, value}

  defp resolve_term(value, context) when is_binary(value), do: resolve_string(value, context)

  defp resolve_term(value, context) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case resolve_term(item, context) do
        {:ok, resolved_item} -> {:cont, {:ok, [resolved_item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved_items} -> {:ok, Enum.reverse(resolved_items)}
      error -> error
    end
  end

  defp resolve_term(value, context) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {key, item}, {:ok, acc} ->
      case resolve_term(item, context) do
        {:ok, resolved_item} -> {:cont, {:ok, Map.put(acc, key, resolved_item)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_term(value, _context), do: {:ok, value}

  defp resolve_string(value, context) do
    case Regex.run(@exact_placeholder, value, capture: :all_but_first) do
      [variable_name] ->
        fetch_variable(context, variable_name)

      _ ->
        replace_placeholders(value, context)
    end
  end

  defp replace_placeholders(value, context) do
    try do
      replaced =
        Regex.replace(@placeholder, value, fn _match, variable_name ->
          with {:ok, resolved_value} <- fetch_variable(context, variable_name),
               {:ok, rendered_value} <- stringify(resolved_value) do
            rendered_value
          else
            {:error, reason} ->
              throw({:resolve_error, reason})
          end
        end)

      {:ok, replaced}
    catch
      {:resolve_error, reason} -> {:error, reason}
    end
  end

  defp fetch_variable(context, variable_name) do
    path = String.split(variable_name, ".", trim: true)

    case fetch_path(context, path) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_variable, variable_name}}
    end
  end

  defp fetch_path(context, []), do: {:ok, context}

  defp fetch_path(context, [segment | rest]) when is_map(context) do
    case Map.fetch(context, segment) do
      {:ok, value} -> fetch_path(value, rest)
      :error -> :error
    end
  end

  defp fetch_path(_context, _path), do: :error

  defp normalize_map_keys(value) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {key, nested_value}, {:ok, acc} ->
      with {:ok, key_string} <- normalize_key(key),
           {:ok, normalized_nested} <- normalize_map_keys(nested_value) do
        {:cont, {:ok, Map.put(acc, key_string, normalized_nested)}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_map_keys(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn nested_value, {:ok, acc} ->
      case normalize_map_keys(nested_value) do
        {:ok, normalized_nested} ->
          {:cont, {:ok, [normalized_nested | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_values} -> {:ok, Enum.reverse(normalized_values)}
      {:error, _} = error -> error
    end
  end

  defp normalize_map_keys(value), do: {:ok, value}

  defp normalize_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_key(key) when is_integer(key), do: {:ok, Integer.to_string(key)}
  defp normalize_key(key) when is_float(key), do: {:ok, Float.to_string(key)}
  defp normalize_key(true), do: {:ok, "true"}
  defp normalize_key(false), do: {:ok, "false"}

  defp normalize_key(_key),
    do: {:error, {:invalid_field, :scope_key, :unsupported_scope_key_type}}

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp stringify(value) when is_binary(value), do: {:ok, value}
  defp stringify(value) when is_number(value) or is_boolean(value), do: {:ok, to_string(value)}
  defp stringify(nil), do: {:ok, ""}

  defp stringify(value) do
    case Jason.encode(value) do
      {:ok, encoded_value} -> {:ok, encoded_value}
      {:error, _reason} -> {:error, {:invalid_field, :variable_value, :not_json_encodable}}
    end
  end
end
