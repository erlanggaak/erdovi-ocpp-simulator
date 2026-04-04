defmodule OcppSimulator.Application.UseCases.ManageScenarios do
  @moduledoc """
  Use-case entrypoints for scenario and template management.
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Domain.Scenarios.Scenario

  @spec create_scenario(module(), map(), term()) :: {:ok, Scenario.t()} | {:error, term()}
  def create_scenario(scenario_repository, attrs, actor_role)
      when is_atom(scenario_repository) and is_map(attrs) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_scenarios),
         {:ok, scenario} <- Scenario.new(attrs),
         {:ok, persisted_scenario} <- invoke(scenario_repository, :insert, [scenario]) do
      {:ok, persisted_scenario}
    end
  end

  def create_scenario(_scenario_repository, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :create_scenario}}

  @spec list_scenarios(module(), term(), map()) :: {:ok, [Scenario.t()]} | {:error, term()}
  def list_scenarios(scenario_repository, actor_role, filters \\ %{})

  def list_scenarios(scenario_repository, actor_role, filters)
      when is_atom(scenario_repository) and is_map(filters) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_scenarios),
         {:ok, scenarios} <- invoke(scenario_repository, :list, [filters]) do
      {:ok, scenarios}
    end
  end

  def list_scenarios(_scenario_repository, _actor_role, _filters),
    do: {:error, {:invalid_arguments, :list_scenarios}}

  @spec get_scenario(module(), String.t(), term()) :: {:ok, Scenario.t()} | {:error, term()}
  def get_scenario(scenario_repository, id, actor_role)
      when is_atom(scenario_repository) and is_binary(id) and id != "" do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_scenarios),
         {:ok, scenario} <- invoke(scenario_repository, :get, [id]) do
      {:ok, scenario}
    end
  end

  def get_scenario(_scenario_repository, _id, _actor_role),
    do: {:error, {:invalid_arguments, :get_scenario}}

  @spec update_scenario(module(), String.t(), map(), term()) :: {:ok, Scenario.t()} | {:error, term()}
  def update_scenario(scenario_repository, id, attrs, actor_role)
      when is_atom(scenario_repository) and is_binary(id) and id != "" and is_map(attrs) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_scenarios),
         {:ok, existing} <- invoke(scenario_repository, :get, [id]),
         existing_snapshot <- Scenario.to_snapshot(existing),
         {:ok, scenario} <- Scenario.new(Map.merge(existing_snapshot, attrs) |> Map.put(:id, id)),
         {:ok, persisted_scenario} <- invoke(scenario_repository, :update, [scenario]) do
      {:ok, persisted_scenario}
    end
  end

  def update_scenario(_scenario_repository, _id, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :update_scenario}}

  @spec delete_scenario(module(), String.t(), term()) :: :ok | {:error, term()}
  def delete_scenario(scenario_repository, id, actor_role)
      when is_atom(scenario_repository) and is_binary(id) and id != "" do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_scenarios),
         result <- invoke(scenario_repository, :delete, [id]) do
      result
    end
  end

  def delete_scenario(_scenario_repository, _id, _actor_role),
    do: {:error, {:invalid_arguments, :delete_scenario}}

  @spec upsert_action_template(module(), map(), term()) :: {:ok, map()} | {:error, term()}
  def upsert_action_template(template_repository, attrs, actor_role)
      when is_atom(template_repository) and is_map(attrs) do
    upsert_template(template_repository, attrs, actor_role, :action)
  end

  @spec upsert_scenario_template(module(), map(), term()) :: {:ok, map()} | {:error, term()}
  def upsert_scenario_template(template_repository, attrs, actor_role)
      when is_atom(template_repository) and is_map(attrs) do
    upsert_template(template_repository, attrs, actor_role, :scenario)
  end

  @spec list_templates(module(), term(), map()) :: {:ok, [map()]} | {:error, term()}
  def list_templates(template_repository, actor_role, filters \\ %{})

  def list_templates(template_repository, actor_role, filters)
      when is_atom(template_repository) and is_map(filters) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_templates),
         {:ok, templates} <- invoke(template_repository, :list, [filters]) do
      {:ok, templates}
    end
  end

  def list_templates(_template_repository, _actor_role, _filters),
    do: {:error, {:invalid_arguments, :list_templates}}

  @spec get_template(module(), String.t(), :action | :scenario, term()) ::
          {:ok, map()} | {:error, term()}
  def get_template(template_repository, id, type, actor_role)
      when is_atom(template_repository) and is_binary(id) and id != "" and type in [:action, :scenario] do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_templates),
         {:ok, template} <- invoke(template_repository, :get, [id, type]) do
      {:ok, template}
    end
  end

  def get_template(_template_repository, _id, _type, _actor_role),
    do: {:error, {:invalid_arguments, :get_template}}

  @spec delete_template(module(), String.t(), :action | :scenario, term()) ::
          :ok | {:error, term()}
  def delete_template(template_repository, id, type, actor_role)
      when is_atom(template_repository) and is_binary(id) and id != "" and type in [:action, :scenario] do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_templates),
         result <- invoke(template_repository, :delete, [id, type]) do
      result
    end
  end

  def delete_template(_template_repository, _id, _type, _actor_role),
    do: {:error, {:invalid_arguments, :delete_template}}

  defp upsert_template(template_repository, attrs, actor_role, type) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_templates),
         {:ok, template} <- build_template(attrs, type),
         {:ok, persisted_template} <- invoke(template_repository, :upsert, [template]) do
      {:ok, persisted_template}
    end
  end

  defp build_template(attrs, type) do
    with {:ok, id} <- fetch_required_string(attrs, :id),
         {:ok, name} <- fetch_required_string(attrs, :name),
         {:ok, version} <- fetch_required_string(attrs, :version),
         {:ok, payload_template} <- fetch_map(attrs, :payload_template, %{}),
         {:ok, metadata} <- fetch_map(attrs, :metadata, %{}) do
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

  defp fetch_required_string(attrs, key) do
    attrs
    |> fetch(key)
    |> case do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp fetch_map(attrs, key, default) do
    attrs
    |> fetch(key)
    |> case do
      nil when is_map(default) -> {:ok, default}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_map}}
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp invoke(module, function, args) when is_atom(module), do: apply(module, function, args)
end
