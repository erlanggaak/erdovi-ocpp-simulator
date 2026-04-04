defmodule OcppSimulatorWeb.TemplateController do
  use OcppSimulatorWeb, :controller

  alias OcppSimulator.Application.UseCases.ManageScenarios

  def create(conn, %{"template" => template_params}) when is_map(template_params) do
    role = conn.assigns[:current_role] || :viewer

    with {:ok, attrs, type} <- build_attrs(template_params),
         {:ok, template} <- persist_template(type, attrs, role) do
      conn
      |> put_flash(:info, "Template `#{template.id}` was saved.")
      |> redirect(to: "/templates")
    else
      {:error, :forbidden} ->
        conn
        |> put_flash(:error, "Current role is not allowed to save templates.")
        |> redirect(to: "/templates")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Unable to save template: #{inspect(reason)}")
        |> redirect(to: "/templates")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Template payload is required.")
    |> redirect(to: "/templates")
  end

  defp persist_template(:action, attrs, role),
    do: ManageScenarios.upsert_action_template(template_repository(), attrs, role)

  defp persist_template(:scenario, attrs, role),
    do: ManageScenarios.upsert_scenario_template(template_repository(), attrs, role)

  defp template_repository,
    do:
      Application.get_env(
        :ocpp_simulator,
        :template_repository,
        OcppSimulator.Infrastructure.Persistence.Mongo.TemplateRepository
      )

  defp build_attrs(params) when is_map(params) do
    with {:ok, type} <- normalize_template_type(fetch(params, :type)),
         {:ok, payload_template} <- parse_payload_template(params) do
      source_scenario_id = normalize_string(fetch(params, :source_scenario_id))

      metadata =
        %{}
        |> maybe_put("source_scenario_id", source_scenario_id)

      {:ok,
       %{
         id: normalize_string(fetch(params, :id)),
         name: normalize_string(fetch(params, :name)),
         version: normalize_string(fetch(params, :version)),
         payload_template: payload_template,
         metadata: metadata
       }, type}
    end
  end

  defp parse_payload_template(params) when is_map(params) do
    case fetch(params, :payload_template_json) do
      nil ->
        case fetch(params, :payload_template) do
          payload when is_map(payload) -> {:ok, payload}
          _ -> {:error, {:invalid_field, :payload_template_json, :must_be_json_object}}
        end

      raw_json ->
        case Jason.decode(to_string(raw_json)) do
          {:ok, payload} when is_map(payload) ->
            {:ok, payload}

          {:ok, _decoded} ->
            {:error, {:invalid_field, :payload_template_json, :must_be_json_object}}

          {:error, _reason} ->
            {:error, {:invalid_field, :payload_template_json, :must_be_json_object}}
        end
    end
  end

  defp normalize_template_type(:action), do: {:ok, :action}
  defp normalize_template_type(:scenario), do: {:ok, :scenario}
  defp normalize_template_type("action"), do: {:ok, :action}
  defp normalize_template_type("scenario"), do: {:ok, :scenario}
  defp normalize_template_type(_value), do: {:error, {:invalid_field, :type, :unsupported_template_type}}

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_string(nil), do: ""

  defp normalize_string(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
