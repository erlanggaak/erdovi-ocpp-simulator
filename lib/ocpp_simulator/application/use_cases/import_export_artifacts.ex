defmodule OcppSimulator.Application.UseCases.ImportExportArtifacts do
  @moduledoc """
  Imports and exports scenarios/templates through application boundaries.
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Domain.Scenarios.Scenario

  @export_schema_version "1.0"

  @spec export_scenarios(module(), term(), map()) :: {:ok, map()} | {:error, term()}
  def export_scenarios(scenario_repository, actor_role, filters \\ %{})

  def export_scenarios(scenario_repository, actor_role, filters)
      when is_atom(scenario_repository) and is_map(filters) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_scenarios),
         {:ok, entries} <- fetch_all_entries(scenario_repository, filters) do
      {:ok,
       %{
         artifact: "scenarios",
         schema_version: @export_schema_version,
         exported_at: DateTime.utc_now(),
         count: length(entries),
         entries: Enum.map(entries, &Scenario.to_snapshot/1)
       }}
    end
  end

  def export_scenarios(_scenario_repository, _actor_role, _filters),
    do: {:error, {:invalid_arguments, :export_scenarios}}

  @spec import_scenarios(module(), term(), map()) :: {:ok, map()} | {:error, term()}
  def import_scenarios(scenario_repository, actor_role, payload)
      when is_atom(scenario_repository) and is_map(payload) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_scenarios),
         {:ok, entries} <- extract_payload_entries(payload),
         {:ok, imported_entries} <- import_scenario_entries(scenario_repository, entries) do
      {:ok,
       %{
         artifact: "scenarios",
         imported_count: length(imported_entries),
         entries: Enum.map(imported_entries, &Scenario.to_snapshot/1)
       }}
    end
  end

  def import_scenarios(_scenario_repository, _actor_role, _payload),
    do: {:error, {:invalid_arguments, :import_scenarios}}

  @spec export_templates(module(), term(), map()) :: {:ok, map()} | {:error, term()}
  def export_templates(template_repository, actor_role, filters \\ %{})

  def export_templates(template_repository, actor_role, filters)
      when is_atom(template_repository) and is_map(filters) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_templates),
         {:ok, entries} <- fetch_all_entries(template_repository, filters) do
      {:ok,
       %{
         artifact: "templates",
         schema_version: @export_schema_version,
         exported_at: DateTime.utc_now(),
         count: length(entries),
         entries: entries
       }}
    end
  end

  def export_templates(_template_repository, _actor_role, _filters),
    do: {:error, {:invalid_arguments, :export_templates}}

  @spec import_templates(module(), term(), map()) :: {:ok, map()} | {:error, term()}
  def import_templates(template_repository, actor_role, payload)
      when is_atom(template_repository) and is_map(payload) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_templates),
         {:ok, entries} <- extract_payload_entries(payload),
         {:ok, imported_entries} <- import_template_entries(template_repository, entries) do
      {:ok,
       %{
         artifact: "templates",
         imported_count: length(imported_entries),
         entries: imported_entries
       }}
    end
  end

  def import_templates(_template_repository, _actor_role, _payload),
    do: {:error, {:invalid_arguments, :import_templates}}

  defp import_scenario_entries(scenario_repository, entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      with {:ok, scenario} <- Scenario.new(entry),
           {:ok, persisted} <- invoke(scenario_repository, :insert, [scenario]) do
        {:cont, {:ok, acc ++ [persisted]}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp import_template_entries(template_repository, entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      with {:ok, template} <- normalize_template(entry),
           {:ok, persisted} <- invoke(template_repository, :upsert, [template]) do
        {:cont, {:ok, acc ++ [persisted]}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_template(entry) when is_map(entry) do
    with {:ok, id} <- fetch_required_string(entry, :id),
         {:ok, name} <- fetch_required_string(entry, :name),
         {:ok, version} <- fetch_required_string(entry, :version),
         {:ok, type} <- normalize_template_type(fetch(entry, :type)),
         {:ok, payload_template} <- fetch_map(entry, :payload_template, %{}),
         {:ok, metadata} <- fetch_map(entry, :metadata, %{}) do
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

  defp normalize_template(_entry),
    do: {:error, {:invalid_field, :entry, :must_be_map}}

  defp normalize_template_type(:action), do: {:ok, :action}
  defp normalize_template_type(:scenario), do: {:ok, :scenario}

  defp normalize_template_type(type) when is_binary(type) do
    case type |> String.trim() |> String.downcase() do
      "action" -> {:ok, :action}
      "scenario" -> {:ok, :scenario}
      _ -> {:error, {:invalid_field, :type, :unsupported_template_type}}
    end
  end

  defp normalize_template_type(_type),
    do: {:error, {:invalid_field, :type, :unsupported_template_type}}

  defp extract_payload_entries(payload) do
    case fetch(payload, :entries) do
      entries when is_list(entries) -> {:ok, entries}
      _ -> {:error, {:invalid_field, :entries, :must_be_list}}
    end
  end

  defp extract_entries(listed) when is_list(listed), do: {:ok, listed}

  defp extract_entries(%{entries: entries}) when is_list(entries), do: {:ok, entries}

  defp extract_entries(_listed),
    do: {:error, {:invalid_field, :repository_response, :missing_entries}}

  defp fetch_all_entries(repository, filters) do
    base_filters =
      filters
      |> Map.drop([:page, "page", :page_size, "page_size"])
      |> Map.put(:page, 1)
      |> Map.put(:page_size, 200)

    with {:ok, listed} <- invoke(repository, :list, [base_filters]),
         {:ok, entries, page, total_pages} <- normalize_page(listed) do
      if page >= total_pages do
        {:ok, entries}
      else
        fetch_remaining_pages(repository, base_filters, page + 1, total_pages, entries)
      end
    end
  end

  defp fetch_remaining_pages(_repository, _base_filters, current_page, total_pages, acc)
       when current_page > total_pages do
    {:ok, acc}
  end

  defp fetch_remaining_pages(repository, base_filters, current_page, total_pages, acc) do
    page_filters = Map.put(base_filters, :page, current_page)

    with {:ok, listed} <- invoke(repository, :list, [page_filters]),
         {:ok, entries, _page, _total_pages} <- normalize_page(listed) do
      fetch_remaining_pages(
        repository,
        base_filters,
        current_page + 1,
        total_pages,
        acc ++ entries
      )
    end
  end

  defp normalize_page(listed) when is_list(listed), do: {:ok, listed, 1, 1}

  defp normalize_page(%{} = listed) do
    with {:ok, entries} <- extract_entries(listed),
         {:ok, page} <- fetch_positive_integer(listed, :page, 1),
         {:ok, total_pages} <- fetch_positive_integer(listed, :total_pages, 1) do
      {:ok, entries, page, total_pages}
    end
  end

  defp normalize_page(_listed),
    do: {:error, {:invalid_field, :repository_response, :missing_entries}}

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

  defp fetch_positive_integer(attrs, key, default) do
    attrs
    |> fetch(key)
    |> case do
      nil when is_integer(default) and default > 0 -> {:ok, default}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_positive_integer}}
    end
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp invoke(module, function, args), do: apply(module, function, args)
end
