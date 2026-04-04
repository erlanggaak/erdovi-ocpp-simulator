defmodule OcppSimulator.Infrastructure.Persistence.Mongo.QueryBuilder do
  @moduledoc """
  Filter and pagination helpers for Mongo-backed read paths.
  """

  @default_page_size 25
  @max_page_size 100

  @type pagination :: %{
          page: pos_integer(),
          page_size: pos_integer(),
          skip: non_neg_integer(),
          sort: map()
        }

  @spec pagination(map(), keyword()) :: {:ok, pagination()} | {:error, term()}
  def pagination(filters, opts \\ []) when is_map(filters) do
    default_page = Keyword.get(opts, :default_page, 1)
    default_page_size = Keyword.get(opts, :default_page_size, @default_page_size)
    max_page_size = Keyword.get(opts, :max_page_size, @max_page_size)
    default_sort = Keyword.get(opts, :default_sort, %{"created_at" => -1})

    with {:ok, page} <- fetch_positive_integer(filters, :page, default_page),
         {:ok, page_size} <- fetch_positive_integer(filters, :page_size, default_page_size),
         :ok <- ensure_page_size(page_size, max_page_size),
         {:ok, sort} <- normalize_sort(fetch(filters, :sort) || default_sort) do
      {:ok,
       %{
         page: page,
         page_size: page_size,
         skip: (page - 1) * page_size,
         sort: sort
       }}
    end
  end

  @spec pagination_metadata(non_neg_integer(), pagination()) :: map()
  def pagination_metadata(total_entries, %{page: page, page_size: page_size})
      when is_integer(total_entries) and total_entries >= 0 do
    total_pages =
      case total_entries do
        0 -> 0
        _ -> ceil(total_entries / page_size)
      end

    %{
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @spec run_history_filter(map()) :: {:ok, map()} | {:error, term()}
  def run_history_filter(filters) when is_map(filters) do
    with {:ok, run_id} <- optional_string(filters, :run_id),
         {:ok, scenario_id} <- optional_string(filters, :scenario_id),
         {:ok, state_filter} <-
           normalize_state_filter(fetch(filters, :state), fetch(filters, :states)),
         {:ok, created_range} <-
           datetime_range_filter(filters, :created_from, :created_to, "created_at") do
      %{}
      |> maybe_put("id", run_id)
      |> maybe_put("scenario_id", scenario_id)
      |> maybe_put("state", state_filter)
      |> maybe_put("created_at", created_range)
      |> then(&{:ok, &1})
    end
  end

  @spec log_filter(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def log_filter(filters, opts \\ []) when is_map(filters) do
    require_filter = Keyword.get(opts, :require_filter, true)

    with {:ok, run_id} <- optional_string(filters, :run_id),
         {:ok, session_id} <- optional_string(filters, :session_id),
         {:ok, charge_point_id} <- optional_string(filters, :charge_point_id),
         {:ok, message_id} <- optional_string(filters, :message_id),
         {:ok, action} <- optional_string(filters, :action),
         {:ok, step_id} <- optional_string(filters, :step_id),
         {:ok, event_type} <- optional_string(filters, :event_type),
         {:ok, severity} <- optional_string(filters, :severity),
         {:ok, timestamp_range} <- datetime_range_filter(filters, :from, :to, "timestamp") do
      filter =
        %{}
        |> maybe_put("run_id", run_id)
        |> maybe_put("session_id", session_id)
        |> maybe_put("charge_point_id", charge_point_id)
        |> maybe_put("message_id", message_id)
        |> maybe_put("action", action)
        |> maybe_put("step_id", step_id)
        |> maybe_put("event_type", event_type)
        |> maybe_put("severity", severity)
        |> maybe_put("timestamp", timestamp_range)

      if require_filter and map_size(filter) == 0 do
        {:error, {:invalid_filters, :at_least_one_filter_required}}
      else
        {:ok, filter}
      end
    end
  end

  @spec apply_pagination_options(keyword(), pagination()) :: keyword()
  def apply_pagination_options(opts, %{page_size: page_size, skip: skip, sort: sort})
      when is_list(opts) do
    opts
    |> Keyword.put(:limit, page_size)
    |> Keyword.put(:skip, skip)
    |> Keyword.put(:sort, sort)
  end

  defp normalize_state_filter(nil, nil), do: {:ok, nil}

  defp normalize_state_filter(state, states) do
    state_values =
      []
      |> maybe_append_state(state)
      |> maybe_append_states(states)
      |> Enum.uniq()

    case state_values do
      [] -> {:ok, nil}
      [single_state] -> {:ok, single_state}
      many_states -> {:ok, %{"$in" => many_states}}
    end
  rescue
    ArgumentError -> {:error, {:invalid_field, :state, :must_be_atom_or_string_or_list}}
  end

  defp maybe_append_state(values, nil), do: values

  defp maybe_append_state(values, state) do
    values ++ [normalize_state(state)]
  end

  defp maybe_append_states(values, nil), do: values

  defp maybe_append_states(values, states) when is_list(states) do
    values ++ Enum.map(states, &normalize_state/1)
  end

  defp maybe_append_states(_values, _states), do: raise(ArgumentError)

  defp normalize_state(state) when is_atom(state), do: Atom.to_string(state)

  defp normalize_state(state) when is_binary(state) do
    state
    |> String.trim()
    |> case do
      "" -> raise(ArgumentError)
      normalized -> normalized
    end
  end

  defp normalize_state(_state), do: raise(ArgumentError)

  defp datetime_range_filter(filters, from_key, to_key, field_name) do
    with {:ok, from_value} <- optional_datetime(filters, from_key),
         {:ok, to_value} <- optional_datetime(filters, to_key) do
      case {from_value, to_value} do
        {nil, nil} -> {:ok, nil}
        {from_datetime, nil} -> {:ok, %{"$gte" => from_datetime}}
        {nil, to_datetime} -> {:ok, %{"$lte" => to_datetime}}
        {from_datetime, to_datetime} -> {:ok, %{"$gte" => from_datetime, "$lte" => to_datetime}}
      end
    else
      {:error, reason} ->
        {:error, {:invalid_field, field_name, reason}}
    end
  end

  defp optional_datetime(filters, key) do
    case fetch(filters, key) do
      nil -> {:ok, nil}
      value -> normalize_datetime(value)
    end
  end

  defp normalize_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp normalize_datetime(%NaiveDateTime{} = naive_datetime),
    do: {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :must_be_iso8601_datetime}
    end
  end

  defp normalize_datetime(_value), do: {:error, :must_be_datetime_or_iso8601}

  defp optional_string(filters, key) do
    case fetch(filters, key) do
      nil ->
        {:ok, nil}

      value when is_atom(value) ->
        {:ok, Atom.to_string(value)}

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:ok, nil}
          normalized -> {:ok, normalized}
        end

      _ ->
        {:error, {:invalid_field, key, :must_be_string_or_atom}}
    end
  end

  defp fetch_positive_integer(filters, key, default) do
    case fetch(filters, key) do
      nil ->
        {:ok, default}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> {:ok, integer}
          _ -> {:error, {:invalid_field, key, :must_be_positive_integer}}
        end

      _ ->
        {:error, {:invalid_field, key, :must_be_positive_integer}}
    end
  end

  defp ensure_page_size(page_size, max_page_size) when page_size <= max_page_size, do: :ok

  defp ensure_page_size(_page_size, max_page_size),
    do: {:error, {:invalid_field, :page_size, {:must_be_lte, max_page_size}}}

  defp normalize_sort(sort) when is_map(sort) do
    sort
    |> Enum.reduce_while({:ok, %{}}, fn {key, direction}, {:ok, acc} ->
      with {:ok, normalized_key} <- normalize_sort_key(key),
           {:ok, normalized_direction} <- normalize_sort_direction(direction) do
        {:cont, {:ok, Map.put(acc, normalized_key, normalized_direction)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_sort(sort) when is_list(sort) do
    sort
    |> Enum.into(%{}, fn
      {key, direction} -> {key, direction}
      invalid -> raise ArgumentError, "invalid sort entry: #{inspect(invalid)}"
    end)
    |> normalize_sort()
  rescue
    ArgumentError -> {:error, {:invalid_field, :sort, :must_be_map_or_keyword}}
  end

  defp normalize_sort(_sort), do: {:error, {:invalid_field, :sort, :must_be_map_or_keyword}}

  defp normalize_sort_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> {:error, {:invalid_field, :sort, :key_must_be_non_empty_string}}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_sort_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_sort_key(_key), do: {:error, {:invalid_field, :sort, :unsupported_sort_key_type}}

  defp normalize_sort_direction(1), do: {:ok, 1}
  defp normalize_sort_direction(-1), do: {:ok, -1}
  defp normalize_sort_direction(:asc), do: {:ok, 1}
  defp normalize_sort_direction(:desc), do: {:ok, -1}

  defp normalize_sort_direction(direction) when is_binary(direction) do
    case String.downcase(String.trim(direction)) do
      "asc" -> {:ok, 1}
      "desc" -> {:ok, -1}
      "1" -> {:ok, 1}
      "-1" -> {:ok, -1}
      _ -> {:error, {:invalid_field, :sort, :direction_must_be_asc_or_desc}}
    end
  end

  defp normalize_sort_direction(_direction),
    do: {:error, {:invalid_field, :sort, :direction_must_be_asc_or_desc}}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
