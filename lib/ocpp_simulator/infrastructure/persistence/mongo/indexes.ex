defmodule OcppSimulator.Infrastructure.Persistence.Mongo.Indexes do
  @moduledoc """
  Canonical Mongo collection/index definitions for simulator persistence.
  """

  alias OcppSimulator.Infrastructure.Persistence.Mongo.Adapter

  @definitions %{
    "users" => [
      [key: %{"id" => 1}, name: "users_id_unique", unique: true],
      [key: %{"email" => 1}, name: "users_email_unique", unique: true]
    ],
    "charge_points" => [
      [key: %{"id" => 1}, name: "charge_points_id_unique", unique: true],
      [key: %{"vendor" => 1, "model" => 1}, name: "charge_points_vendor_model_idx"]
    ],
    "target_endpoints" => [
      [key: %{"id" => 1}, name: "target_endpoints_id_unique", unique: true],
      [key: %{"url" => 1}, name: "target_endpoints_url_unique", unique: true]
    ],
    "action_templates" => [
      [key: %{"id" => 1, "type" => 1}, name: "templates_id_type_unique", unique: true],
      [
        key: %{"name" => 1, "type" => 1, "version" => -1},
        name: "templates_name_type_version_idx"
      ]
    ],
    "scenarios" => [
      [key: %{"id" => 1}, name: "scenarios_id_unique", unique: true],
      [key: %{"name" => 1, "version" => -1}, name: "scenarios_name_version_idx"]
    ],
    "scenario_runs" => [
      [key: %{"id" => 1}, name: "scenario_runs_id_unique", unique: true],
      [
        key: %{"scenario_id" => 1, "created_at" => -1},
        name: "scenario_runs_history_idx"
      ],
      [key: %{"state" => 1, "created_at" => -1}, name: "scenario_runs_state_idx"]
    ],
    "logs" => [
      [key: %{"id" => 1}, name: "logs_id_unique", unique: true],
      [key: %{"run_id" => 1, "timestamp" => -1}, name: "logs_run_timestamp_idx"],
      [key: %{"session_id" => 1, "timestamp" => -1}, name: "logs_session_timestamp_idx"],
      [
        key: %{"charge_point_id" => 1, "timestamp" => -1},
        name: "logs_charge_point_timestamp_idx"
      ],
      [key: %{"message_id" => 1, "timestamp" => -1}, name: "logs_message_timestamp_idx"]
    ],
    "webhook_endpoints" => [
      [key: %{"id" => 1}, name: "webhook_endpoints_id_unique", unique: true]
    ],
    "webhook_deliveries" => [
      [key: %{"id" => 1}, name: "webhook_deliveries_id_unique", unique: true],
      [
        key: %{"run_id" => 1, "status" => 1, "created_at" => -1},
        name: "webhook_deliveries_run_status_idx"
      ]
    ]
  }

  @spec definitions() :: %{String.t() => [keyword()]}
  def definitions, do: @definitions

  @spec ensure_all() :: :ok | {:error, term()}
  def ensure_all do
    @definitions
    |> Enum.reduce_while(:ok, fn {collection, indexes}, :ok ->
      case Adapter.create_indexes(collection, indexes) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {collection, reason}}}
      end
    end)
  end

  @spec ensure_collection(String.t()) :: :ok | {:error, term()}
  def ensure_collection(collection) when is_binary(collection) do
    case Map.fetch(@definitions, collection) do
      {:ok, indexes} -> Adapter.create_indexes(collection, indexes)
      :error -> {:error, {:unknown_collection, collection}}
    end
  end
end
