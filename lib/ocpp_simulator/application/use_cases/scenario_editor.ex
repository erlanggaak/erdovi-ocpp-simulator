defmodule OcppSimulator.Application.UseCases.ScenarioEditor do
  @moduledoc """
  Dual-mode scenario editor conversion rules:
  visual builder model <-> raw JSON document.

  Conversion is schema-safe because both directions normalize through
  `OcppSimulator.Domain.Scenarios.Scenario.new/1`.
  """

  alias OcppSimulator.Domain.Scenarios.Scenario

  @spec visual_to_raw_json(map()) :: {:ok, String.t()} | {:error, term()}
  def visual_to_raw_json(visual_model) when is_map(visual_model) do
    with {:ok, scenario} <- Scenario.new(visual_model),
         {:ok, json} <- Jason.encode(to_visual_model(scenario)) do
      {:ok, json}
    end
  end

  def visual_to_raw_json(_visual_model),
    do: {:error, {:invalid_field, :visual_model, :must_be_map}}

  @spec raw_json_to_visual(String.t() | map()) :: {:ok, map()} | {:error, term()}
  def raw_json_to_visual(raw_json) when is_binary(raw_json) do
    with {:ok, decoded} <- decode_json(raw_json),
         {:ok, scenario} <- Scenario.new(decoded) do
      {:ok, to_visual_model(scenario)}
    end
  end

  def raw_json_to_visual(raw_document) when is_map(raw_document) do
    with {:ok, scenario} <- Scenario.new(raw_document) do
      {:ok, to_visual_model(scenario)}
    end
  end

  def raw_json_to_visual(_raw_document),
    do: {:error, {:invalid_field, :raw_document, :must_be_json_or_map}}

  @spec round_trip_visual(map()) :: {:ok, map()} | {:error, term()}
  def round_trip_visual(visual_model) when is_map(visual_model) do
    with {:ok, raw_json} <- visual_to_raw_json(visual_model),
         {:ok, normalized_visual_model} <- raw_json_to_visual(raw_json) do
      {:ok, normalized_visual_model}
    end
  end

  def round_trip_visual(_visual_model),
    do: {:error, {:invalid_field, :visual_model, :must_be_map}}

  @spec equivalent_definition?(map() | String.t(), map() | String.t()) :: boolean()
  def equivalent_definition?(left, right) do
    with {:ok, left_visual} <- normalize_editor_payload(left),
         {:ok, right_visual} <- normalize_editor_payload(right) do
      left_visual == right_visual
    else
      _ -> false
    end
  end

  @spec starter_visual_model!(String.t(), String.t(), String.t(), map()) :: map()
  def starter_visual_model!(id, name, version, payload) do
    attrs =
      payload
      |> Map.merge(%{"id" => id, "name" => name, "version" => version})

    {:ok, visual_model} = raw_json_to_visual(attrs)
    visual_model
  end

  defp normalize_editor_payload(payload) when is_binary(payload), do: raw_json_to_visual(payload)
  defp normalize_editor_payload(payload) when is_map(payload), do: raw_json_to_visual(payload)
  defp normalize_editor_payload(_payload), do: {:error, :invalid_payload}

  defp to_visual_model(%Scenario{} = scenario) do
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

  defp decode_json(raw_json) do
    case Jason.decode(raw_json) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, %Jason.DecodeError{}} -> {:error, {:invalid_field, :raw_json, :malformed_json}}
    end
  end
end
