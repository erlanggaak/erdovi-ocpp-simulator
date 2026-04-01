defmodule OcppSimulator.Application.UseCases.ManageTargetEndpoints do
  @moduledoc """
  Use-case entrypoints for target endpoint and connection profile management.
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  @spec create_target_endpoint(module(), map(), term()) :: {:ok, map()} | {:error, term()}
  def create_target_endpoint(target_endpoint_repository, attrs, actor_role)
      when is_atom(target_endpoint_repository) and is_map(attrs) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_target_endpoints),
         {:ok, endpoint} <- build_endpoint(attrs),
         {:ok, persisted_endpoint} <- invoke(target_endpoint_repository, :insert, [endpoint]) do
      {:ok, persisted_endpoint}
    end
  end

  def create_target_endpoint(_target_endpoint_repository, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :create_target_endpoint}}

  @spec list_target_endpoints(module(), term(), map()) :: {:ok, [map()]} | {:error, term()}
  def list_target_endpoints(target_endpoint_repository, actor_role, filters \\ %{})

  def list_target_endpoints(target_endpoint_repository, actor_role, filters)
      when is_atom(target_endpoint_repository) and is_map(filters) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_target_endpoints),
         {:ok, endpoints} <- invoke(target_endpoint_repository, :list, [filters]) do
      {:ok, endpoints}
    end
  end

  def list_target_endpoints(_target_endpoint_repository, _actor_role, _filters),
    do: {:error, {:invalid_arguments, :list_target_endpoints}}

  defp build_endpoint(attrs) when is_map(attrs) do
    with {:ok, id} <- fetch_required_string(attrs, :id),
         {:ok, name} <- fetch_required_string(attrs, :name),
         {:ok, url} <- fetch_required_string(attrs, :url),
         :ok <- ensure_ws_url(url),
         {:ok, protocol_options} <- fetch_map(attrs, :protocol_options, %{}),
         {:ok, retry_policy} <-
           fetch_map(attrs, :retry_policy, %{max_attempts: 3, backoff_ms: 1_000}),
         {:ok, metadata} <- fetch_map(attrs, :metadata, %{}) do
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

  defp ensure_ws_url("ws://" <> _rest), do: :ok
  defp ensure_ws_url(_url), do: {:error, {:invalid_field, :url, :must_use_plain_ws_scheme}}

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
