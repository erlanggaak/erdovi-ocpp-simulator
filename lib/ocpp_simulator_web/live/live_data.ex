defmodule OcppSimulatorWeb.Live.LiveData do
  @moduledoc false

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  @spec normalize_role(term()) :: AuthorizationPolicy.role()
  def normalize_role(role) do
    case AuthorizationPolicy.normalize_role(role) do
      {:ok, normalized_role} -> normalized_role
      {:error, _reason} -> :viewer
    end
  end

  @spec can?(Phoenix.LiveView.Socket.t() | map(), atom()) :: boolean()
  def can?(%Phoenix.LiveView.Socket{} = socket, permission) do
    grants = socket.assigns[:permission_grants] || %{}
    Map.get(grants, permission, false)
  end

  def can?(%{} = assigns, permission) do
    cond do
      Map.has_key?(assigns, permission) ->
        Map.get(assigns, permission, false)

      true ->
        grants = Map.get(assigns, :permission_grants, %{})
        Map.get(grants, permission, false)
    end
  end

  @spec repository(atom(), module()) :: module()
  def repository(config_key, default_module) do
    Application.get_env(:ocpp_simulator, config_key, default_module)
  end

  @spec fetch(map(), atom()) :: term()
  def fetch(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  @spec parse_positive_integer(map(), atom(), pos_integer()) :: pos_integer()
  def parse_positive_integer(params, key, default) when is_integer(default) and default > 0 do
    case fetch(params, key) do
      nil ->
        default

      raw ->
        case Integer.parse(to_string(raw)) do
          {value, ""} when value > 0 -> value
          _ -> default
        end
    end
  end

  @spec normalize_filter(map(), atom()) :: String.t() | nil
  def normalize_filter(params, key) do
    params
    |> fetch(key)
    |> case do
      nil ->
        nil

      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          normalized -> normalized
        end

      value when is_atom(value) ->
        value
        |> Atom.to_string()
        |> normalize_filter_value()

      _ ->
        nil
    end
  end

  defp normalize_filter_value(""), do: nil
  defp normalize_filter_value(value), do: value

  @spec compact_filters(map()) :: map()
  def compact_filters(filters) when is_map(filters) do
    filters
    |> Enum.reject(fn {_key, value} ->
      is_nil(value) or value == ""
    end)
    |> Map.new()
  end
end
