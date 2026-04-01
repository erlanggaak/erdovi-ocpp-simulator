defmodule OcppSimulator.Domain.ChargePoints.ChargePoint do
  @moduledoc """
  Charge point aggregate with baseline configuration invariants.
  """

  @behavior_profiles [:default, :intermittent_disconnects, :faulted]

  @enforce_keys [
    :id,
    :vendor,
    :model,
    :firmware_version,
    :connector_count,
    :heartbeat_interval_seconds,
    :behavior_profile
  ]
  defstruct [
    :id,
    :vendor,
    :model,
    :firmware_version,
    :connector_count,
    :heartbeat_interval_seconds,
    :behavior_profile
  ]

  @type behavior_profile :: :default | :intermittent_disconnects | :faulted

  @type t :: %__MODULE__{
          id: String.t(),
          vendor: String.t(),
          model: String.t(),
          firmware_version: String.t(),
          connector_count: pos_integer(),
          heartbeat_interval_seconds: pos_integer(),
          behavior_profile: behavior_profile()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- fetch_required_string(attrs, :id),
         {:ok, vendor} <- fetch_required_string(attrs, :vendor),
         {:ok, model} <- fetch_required_string(attrs, :model),
         {:ok, firmware_version} <- fetch_required_string(attrs, :firmware_version),
         {:ok, connector_count} <- fetch_positive_integer(attrs, :connector_count),
         {:ok, heartbeat_interval_seconds} <-
           fetch_positive_integer(attrs, :heartbeat_interval_seconds, 60),
         {:ok, behavior_profile} <- fetch_behavior_profile(attrs) do
      {:ok,
       %__MODULE__{
         id: id,
         vendor: vendor,
         model: model,
         firmware_version: firmware_version,
         connector_count: connector_count,
         heartbeat_interval_seconds: heartbeat_interval_seconds,
         behavior_profile: behavior_profile
       }}
    end
  end

  def new(_attrs), do: {:error, {:invalid_field, :attrs, :must_be_map}}

  @spec behavior_profiles() :: [behavior_profile()]
  def behavior_profiles, do: @behavior_profiles

  defp fetch_behavior_profile(attrs) do
    case fetch(attrs, :behavior_profile) do
      nil -> {:ok, :default}
      value -> normalize_behavior_profile(value)
    end
  end

  defp normalize_behavior_profile(value) when value in @behavior_profiles, do: {:ok, value}

  defp normalize_behavior_profile(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "default" -> {:ok, :default}
      "intermittent_disconnects" -> {:ok, :intermittent_disconnects}
      "faulted" -> {:ok, :faulted}
      _ -> {:error, {:invalid_field, :behavior_profile, :unsupported_profile}}
    end
  end

  defp normalize_behavior_profile(_value),
    do: {:error, {:invalid_field, :behavior_profile, :must_be_profile_atom_or_string}}

  defp fetch_positive_integer(attrs, key, default \\ nil) do
    attrs
    |> fetch(key)
    |> case do
      nil when is_integer(default) and default > 0 -> {:ok, default}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_positive_integer}}
    end
  end

  defp fetch_required_string(attrs, key) do
    attrs
    |> fetch(key)
    |> case do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
