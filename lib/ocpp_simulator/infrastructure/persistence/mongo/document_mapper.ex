defmodule OcppSimulator.Infrastructure.Persistence.Mongo.DocumentMapper do
  @moduledoc """
  Converts between domain/application data structures and Mongo documents.
  """

  alias OcppSimulator.Domain.ChargePoints.ChargePoint
  alias OcppSimulator.Domain.Runs.ScenarioRun
  alias OcppSimulator.Domain.Scenarios.Scenario

  @run_states ScenarioRun.states()

  @spec charge_point_to_document(ChargePoint.t()) :: map()
  def charge_point_to_document(%ChargePoint{} = charge_point) do
    %{
      "id" => charge_point.id,
      "vendor" => charge_point.vendor,
      "model" => charge_point.model,
      "firmware_version" => charge_point.firmware_version,
      "connector_count" => charge_point.connector_count,
      "heartbeat_interval_seconds" => charge_point.heartbeat_interval_seconds,
      "behavior_profile" => Atom.to_string(charge_point.behavior_profile)
    }
  end

  @spec charge_point_from_document(map()) :: {:ok, ChargePoint.t()} | {:error, term()}
  def charge_point_from_document(document) when is_map(document) do
    attrs = %{
      id: fetch(document, :id),
      vendor: fetch(document, :vendor),
      model: fetch(document, :model),
      firmware_version: fetch(document, :firmware_version),
      connector_count: fetch(document, :connector_count),
      heartbeat_interval_seconds: fetch(document, :heartbeat_interval_seconds),
      behavior_profile: fetch(document, :behavior_profile)
    }

    ChargePoint.new(attrs)
  end

  @spec target_endpoint_to_document(map()) :: map()
  def target_endpoint_to_document(endpoint) when is_map(endpoint) do
    %{
      "id" => fetch(endpoint, :id),
      "name" => fetch(endpoint, :name),
      "url" => fetch(endpoint, :url),
      "protocol_options" => fetch(endpoint, :protocol_options) || %{},
      "retry_policy" => fetch(endpoint, :retry_policy) || %{},
      "metadata" => fetch(endpoint, :metadata) || %{}
    }
  end

  @spec target_endpoint_from_document(map()) :: {:ok, map()} | {:error, term()}
  def target_endpoint_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, name} <- required_string(document, :name),
         {:ok, url} <- required_string(document, :url),
         {:ok, protocol_options} <- required_map(document, :protocol_options, %{}),
         {:ok, retry_policy} <- required_map(document, :retry_policy, %{}),
         {:ok, metadata} <- required_map(document, :metadata, %{}) do
      {:ok,
       %{
         id: id,
         name: name,
         url: url,
         protocol_options: protocol_options,
         retry_policy: retry_policy,
         metadata: metadata
       }}
    end
  end

  @spec template_to_document(map()) :: map()
  def template_to_document(template) when is_map(template) do
    %{
      "id" => fetch(template, :id),
      "name" => fetch(template, :name),
      "version" => fetch(template, :version),
      "type" => template_type_to_string(fetch(template, :type)),
      "payload_template" => fetch(template, :payload_template) || %{},
      "metadata" => fetch(template, :metadata) || %{}
    }
  end

  @spec template_from_document(map()) :: {:ok, map()} | {:error, term()}
  def template_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, name} <- required_string(document, :name),
         {:ok, version} <- required_string(document, :version),
         {:ok, type} <- normalize_template_type(fetch(document, :type)),
         {:ok, payload_template} <- required_map(document, :payload_template, %{}),
         {:ok, metadata} <- required_map(document, :metadata, %{}) do
      {:ok,
       %{
         id: id,
         name: name,
         version: version,
         type: type,
         payload_template: payload_template,
         metadata: metadata
       }}
    end
  end

  @spec scenario_to_document(Scenario.t()) :: map()
  def scenario_to_document(%Scenario{} = scenario) do
    %{
      "id" => scenario.id,
      "name" => scenario.name,
      "version" => scenario.version,
      "schema_version" => scenario.schema_version,
      "variables" => scenario.variables,
      "variable_scopes" => Enum.map(scenario.variable_scopes, &Atom.to_string/1),
      "validation_policy" => %{
        "strict_ocpp_schema" => scenario.validation_policy.strict_ocpp_schema,
        "strict_state_transitions" => scenario.validation_policy.strict_state_transitions,
        "strict_variable_resolution" => scenario.validation_policy.strict_variable_resolution
      },
      "steps" =>
        Enum.map(scenario.steps, fn step ->
          %{
            "id" => step.id,
            "type" => Atom.to_string(step.type),
            "order" => step.order,
            "payload" => step.payload,
            "delay_ms" => step.delay_ms,
            "loop_count" => step.loop_count,
            "enabled" => step.enabled
          }
        end)
    }
  end

  @spec scenario_from_document(map()) :: {:ok, Scenario.t()} | {:error, term()}
  def scenario_from_document(document) when is_map(document) do
    attrs = %{
      id: fetch(document, :id),
      name: fetch(document, :name),
      version: fetch(document, :version),
      schema_version: fetch(document, :schema_version),
      variables: fetch(document, :variables) || %{},
      variable_scopes: fetch(document, :variable_scopes) || Scenario.default_variable_scopes(),
      validation_policy:
        fetch(document, :validation_policy) || Scenario.validation_policy_defaults(),
      steps: normalize_steps(fetch(document, :steps) || [])
    }

    Scenario.new(attrs)
  end

  @spec scenario_run_to_document(ScenarioRun.t()) :: map()
  def scenario_run_to_document(%ScenarioRun{} = run) do
    %{
      "id" => run.id,
      "scenario_id" => run.scenario_id,
      "scenario_version" => run.scenario_version,
      "state" => Atom.to_string(run.state),
      "frozen_snapshot" => run.frozen_snapshot,
      "metadata" => run.metadata,
      "created_at" => run.created_at
    }
  end

  @spec scenario_run_from_document(map()) :: {:ok, ScenarioRun.t()} | {:error, term()}
  def scenario_run_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, scenario_id} <- required_string(document, :scenario_id),
         {:ok, scenario_version} <- required_string(document, :scenario_version),
         {:ok, state} <- normalize_run_state(fetch(document, :state)),
         {:ok, frozen_snapshot} <- required_map(document, :frozen_snapshot),
         {:ok, metadata} <- required_map(document, :metadata, %{}),
         {:ok, created_at} <- required_datetime(document, :created_at) do
      {:ok,
       %ScenarioRun{
         id: id,
         scenario_id: scenario_id,
         scenario_version: scenario_version,
         state: state,
         frozen_snapshot: frozen_snapshot,
         metadata: metadata,
         created_at: created_at
       }}
    end
  end

  @spec user_to_document(map()) :: map()
  def user_to_document(user) when is_map(user) do
    now = DateTime.utc_now()

    %{
      "id" => fetch(user, :id),
      "email" => fetch(user, :email),
      "role" => role_to_string(fetch(user, :role)),
      "password_hash" => fetch(user, :password_hash),
      "metadata" => fetch(user, :metadata) || %{},
      "updated_at" => normalize_datetime(fetch(user, :updated_at)) || now,
      "created_at" => normalize_datetime(fetch(user, :created_at)) || now
    }
  end

  @spec user_from_document(map()) :: {:ok, map()} | {:error, term()}
  def user_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, email} <- required_string(document, :email),
         {:ok, role} <- required_string(document, :role),
         {:ok, metadata} <- required_map(document, :metadata, %{}) do
      {:ok,
       %{
         id: id,
         email: email,
         role: role,
         password_hash: fetch(document, :password_hash),
         metadata: metadata,
         created_at: normalize_datetime(fetch(document, :created_at)),
         updated_at: normalize_datetime(fetch(document, :updated_at))
       }}
    end
  end

  @spec log_entry_to_document(map()) :: map()
  def log_entry_to_document(log_entry) when is_map(log_entry) do
    %{
      "id" => fetch(log_entry, :id),
      "run_id" => fetch(log_entry, :run_id),
      "session_id" => fetch(log_entry, :session_id),
      "charge_point_id" => fetch(log_entry, :charge_point_id),
      "message_id" => fetch(log_entry, :message_id),
      "severity" => fetch(log_entry, :severity),
      "event_type" => fetch(log_entry, :event_type),
      "payload" => fetch(log_entry, :payload) || %{},
      "timestamp" => normalize_datetime(fetch(log_entry, :timestamp)) || DateTime.utc_now()
    }
  end

  @spec log_entry_from_document(map()) :: {:ok, map()} | {:error, term()}
  def log_entry_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, run_id} <- required_string(document, :run_id),
         {:ok, severity} <- required_string(document, :severity),
         {:ok, event_type} <- required_string(document, :event_type),
         {:ok, payload} <- required_map(document, :payload, %{}),
         {:ok, timestamp} <- required_datetime(document, :timestamp) do
      {:ok,
       %{
         id: id,
         run_id: run_id,
         session_id: fetch(document, :session_id),
         charge_point_id: fetch(document, :charge_point_id),
         message_id: fetch(document, :message_id),
         severity: severity,
         event_type: event_type,
         payload: payload,
         timestamp: timestamp
       }}
    end
  end

  @spec webhook_endpoint_to_document(map()) :: map()
  def webhook_endpoint_to_document(endpoint) when is_map(endpoint) do
    %{
      "id" => fetch(endpoint, :id),
      "name" => fetch(endpoint, :name),
      "url" => fetch(endpoint, :url),
      "events" => fetch(endpoint, :events) || [],
      "retry_policy" => fetch(endpoint, :retry_policy) || %{},
      "secret_ref" => fetch(endpoint, :secret_ref),
      "metadata" => fetch(endpoint, :metadata) || %{}
    }
  end

  @spec webhook_endpoint_from_document(map()) :: {:ok, map()} | {:error, term()}
  def webhook_endpoint_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, name} <- required_string(document, :name),
         {:ok, url} <- required_string(document, :url),
         {:ok, events} <- required_list(document, :events, []),
         {:ok, retry_policy} <- required_map(document, :retry_policy, %{}),
         {:ok, metadata} <- required_map(document, :metadata, %{}) do
      {:ok,
       %{
         id: id,
         name: name,
         url: url,
         events: Enum.map(events, &to_string/1),
         retry_policy: retry_policy,
         secret_ref: fetch(document, :secret_ref),
         metadata: metadata
       }}
    end
  end

  @spec webhook_delivery_to_document(map()) :: map()
  def webhook_delivery_to_document(delivery) when is_map(delivery) do
    now = DateTime.utc_now()

    %{
      "id" => fetch(delivery, :id),
      "run_id" => fetch(delivery, :run_id),
      "event" => fetch(delivery, :event),
      "status" => delivery_status_to_string(fetch(delivery, :status)),
      "attempts" => fetch(delivery, :attempts) || 0,
      "payload" => fetch(delivery, :payload) || %{},
      "response_summary" => fetch(delivery, :response_summary) || %{},
      "last_error" => fetch(delivery, :last_error),
      "metadata" => fetch(delivery, :metadata) || %{},
      "created_at" => normalize_datetime(fetch(delivery, :created_at)) || now,
      "updated_at" => normalize_datetime(fetch(delivery, :updated_at)) || now
    }
  end

  @spec webhook_delivery_from_document(map()) :: {:ok, map()} | {:error, term()}
  def webhook_delivery_from_document(document) when is_map(document) do
    with {:ok, id} <- required_string(document, :id),
         {:ok, run_id} <- required_string(document, :run_id),
         {:ok, event} <- required_string(document, :event),
         {:ok, status} <- normalize_delivery_status(fetch(document, :status)),
         {:ok, attempts} <- required_non_negative_integer(document, :attempts, 0),
         {:ok, payload} <- required_map(document, :payload, %{}),
         {:ok, metadata} <- required_map(document, :metadata, %{}),
         {:ok, created_at} <- required_datetime(document, :created_at),
         {:ok, updated_at} <- required_datetime(document, :updated_at) do
      {:ok,
       %{
         id: id,
         run_id: run_id,
         event: event,
         status: status,
         attempts: attempts,
         payload: payload,
         response_summary: fetch(document, :response_summary) || %{},
         last_error: fetch(document, :last_error),
         metadata: metadata,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  @spec template_type_to_string(term()) :: String.t() | nil
  def template_type_to_string(:action), do: "action"
  def template_type_to_string(:scenario), do: "scenario"
  def template_type_to_string(value) when is_binary(value), do: String.trim(value)
  def template_type_to_string(_value), do: nil

  @spec delivery_status_to_string(term()) :: String.t() | nil
  def delivery_status_to_string(value) when is_atom(value), do: Atom.to_string(value)
  def delivery_status_to_string(value) when is_binary(value), do: String.trim(value)
  def delivery_status_to_string(_value), do: nil

  defp normalize_template_type(value) do
    case template_type_to_string(value) do
      "action" -> {:ok, :action}
      "scenario" -> {:ok, :scenario}
      _ -> {:error, {:invalid_field, :type, :unsupported_template_type}}
    end
  end

  defp normalize_run_state(state) when state in @run_states, do: {:ok, state}

  defp normalize_run_state(state) when is_binary(state) do
    case String.trim(state) do
      "draft" -> {:ok, :draft}
      "queued" -> {:ok, :queued}
      "running" -> {:ok, :running}
      "succeeded" -> {:ok, :succeeded}
      "failed" -> {:ok, :failed}
      "canceled" -> {:ok, :canceled}
      "timed_out" -> {:ok, :timed_out}
      _ -> {:error, {:invalid_field, :state, :unsupported_state}}
    end
  end

  defp normalize_run_state(_state), do: {:error, {:invalid_field, :state, :unsupported_state}}

  defp normalize_delivery_status(value) do
    case delivery_status_to_string(value) do
      "queued" -> {:ok, :queued}
      "delivered" -> {:ok, :delivered}
      "failed" -> {:ok, :failed}
      "retrying" -> {:ok, :retrying}
      _ -> {:error, {:invalid_field, :status, :unsupported_status}}
    end
  end

  defp normalize_steps(steps) when is_list(steps) do
    Enum.map(steps, fn step ->
      if is_map(step) do
        step
      else
        %{}
      end
    end)
  end

  defp normalize_steps(_steps), do: []

  defp required_string(map, key) do
    case fetch(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp required_map(map, key, default \\ nil) do
    case fetch(map, key) do
      nil when is_map(default) -> {:ok, default}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_map}}
    end
  end

  defp required_list(map, key, default) do
    case fetch(map, key) do
      nil when is_list(default) -> {:ok, default}
      value when is_list(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_list}}
    end
  end

  defp required_non_negative_integer(map, key, default) do
    case fetch(map, key) do
      nil when is_integer(default) and default >= 0 -> {:ok, default}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_negative_integer}}
    end
  end

  defp required_datetime(map, key) do
    case normalize_datetime(fetch(map, key)) do
      %DateTime{} = datetime -> {:ok, datetime}
      _ -> {:error, {:invalid_field, key, :must_be_datetime}}
    end
  end

  defp role_to_string(role) when is_atom(role), do: Atom.to_string(role)
  defp role_to_string(role) when is_binary(role), do: role
  defp role_to_string(_role), do: "viewer"

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(%NaiveDateTime{} = naive_datetime),
    do: DateTime.from_naive!(naive_datetime, "Etc/UTC")

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
