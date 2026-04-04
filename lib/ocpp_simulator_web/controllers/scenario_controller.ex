defmodule OcppSimulatorWeb.ScenarioController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Domain.Scenarios.Scenario

  def create(conn, %{"scenario" => scenario_params}) when is_map(scenario_params) do
    role = conn.assigns[:current_role] || :viewer
    mode = normalize_mode(fetch(scenario_params, :form_mode))

    with {:ok, attrs} <- build_attrs(scenario_params, mode),
         {:ok, action, scenario} <- persist_scenario(mode, attrs, role) do
      conn
      |> put_flash(
        :info,
        if(action == :created,
          do: "Scenario `#{scenario.id}` was created.",
          else: "Scenario `#{scenario.id}` was updated."
        )
      )
      |> redirect(to: "/scenarios")
    else
      {:error, :forbidden} ->
        conn
        |> put_flash(:error, "Current role is not allowed to save scenarios.")
        |> redirect(to: "/scenarios")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Unable to save scenario: #{inspect(reason)}")
        |> redirect(to: "/scenarios")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Scenario payload is required.")
    |> redirect(to: "/scenarios")
  end

  defp persist_scenario(:edit, attrs, role) do
    case ManageScenarios.update_scenario(scenario_repository(), attrs.id, attrs, role) do
      {:ok, scenario} -> {:ok, :updated, scenario}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_scenario(:create, attrs, role) do
    case ManageScenarios.create_scenario(scenario_repository(), attrs, role) do
      {:ok, scenario} -> {:ok, :created, scenario}
      {:error, reason} -> {:error, reason}
    end
  end

  defp scenario_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :scenario_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.ScenarioRepository
      )

  defp build_attrs(params, mode) when is_map(params) do
    id = normalize_string(fetch(params, :id))
    name = normalize_string(fetch(params, :name))
    version = normalize_string(fetch(params, :version))
    charge_point_id = normalize_string(fetch(params, :charge_point_id))
    target_endpoint_id = normalize_string(fetch(params, :target_endpoint_id))

    required_errors =
      %{}
      |> maybe_required(:id, id)
      |> maybe_required(:name, name)
      |> maybe_required(:version, version)

    required_errors =
      if mode == :edit do
        Map.delete(required_errors, :id)
      else
        required_errors
      end

    with true <- map_size(required_errors) == 0 || {:error, required_errors},
         {:ok, steps} <- parse_steps(params) do
      variables =
        %{}
        |> maybe_put("charge_point_id", charge_point_id)
        |> maybe_put("target_endpoint_id", target_endpoint_id)

      {:ok,
       %{
         id: id,
         name: name,
         version: version,
         schema_version: "1.0",
         variables: variables,
         variable_scopes: Scenario.default_variable_scopes(),
         validation_policy: Scenario.validation_policy_defaults(),
         steps: steps
       }}
    else
      {:error, %{} = errors} -> {:error, errors}
      {:error, reason} -> {:error, reason}
      false -> {:error, {:invalid_field, :scenario, :invalid_payload}}
    end
  end

  defp parse_steps(params) when is_map(params) do
    case fetch(params, :steps_json) do
      nil ->
        case fetch(params, :steps) do
          steps when is_list(steps) -> {:ok, steps}
          _ -> {:error, {:invalid_field, :steps_json, :must_be_json_array}}
        end

      raw_steps_json ->
        case Jason.decode(to_string(raw_steps_json)) do
          {:ok, steps} when is_list(steps) -> {:ok, steps}
          {:ok, _decoded} -> {:error, {:invalid_field, :steps_json, :must_be_json_array}}
          {:error, _reason} -> {:error, {:invalid_field, :steps_json, :must_be_json_array}}
        end
    end
  end

  defp maybe_required(errors, _key, value) when is_binary(value) and value != "", do: errors
  defp maybe_required(errors, key, _value), do: Map.put(errors, key, :required)

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_mode("edit"), do: :edit
  defp normalize_mode(_value), do: :create

  defp normalize_string(nil), do: ""

  defp normalize_string(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
