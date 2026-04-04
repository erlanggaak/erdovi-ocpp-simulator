defmodule OcppSimulator.Application.UseCases.ManageChargePoints do
  @moduledoc """
  Use-case entrypoints for charge point management.
  """

  alias OcppSimulator.Application.Policies.AuthorizationPolicy
  alias OcppSimulator.Domain.ChargePoints.ChargePoint

  @spec register_charge_point(module(), map(), term()) ::
          {:ok, ChargePoint.t()} | {:error, term()}
  def register_charge_point(charge_point_repository, attrs, actor_role)
      when is_atom(charge_point_repository) and is_map(attrs) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_charge_points),
         {:ok, charge_point} <- ChargePoint.new(attrs),
         {:ok, persisted_charge_point} <- invoke(charge_point_repository, :insert, [charge_point]) do
      {:ok, persisted_charge_point}
    end
  end

  def register_charge_point(_charge_point_repository, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :register_charge_point}}

  @spec list_charge_points(module(), term(), map()) :: {:ok, [ChargePoint.t()]} | {:error, term()}
  def list_charge_points(charge_point_repository, actor_role, filters \\ %{})

  def list_charge_points(charge_point_repository, actor_role, filters)
      when is_atom(charge_point_repository) and is_map(filters) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_charge_points),
         {:ok, charge_points} <- invoke(charge_point_repository, :list, [filters]) do
      {:ok, charge_points}
    end
  end

  def list_charge_points(_charge_point_repository, _actor_role, _filters),
    do: {:error, {:invalid_arguments, :list_charge_points}}

  @spec get_charge_point(module(), String.t(), term()) :: {:ok, ChargePoint.t()} | {:error, term()}
  def get_charge_point(charge_point_repository, id, actor_role)
      when is_atom(charge_point_repository) and is_binary(id) and id != "" do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :view_charge_points),
         {:ok, charge_point} <- invoke(charge_point_repository, :get, [id]) do
      {:ok, charge_point}
    end
  end

  def get_charge_point(_charge_point_repository, _id, _actor_role),
    do: {:error, {:invalid_arguments, :get_charge_point}}

  @spec update_charge_point(module(), String.t(), map(), term()) ::
          {:ok, ChargePoint.t()} | {:error, term()}
  def update_charge_point(charge_point_repository, id, attrs, actor_role)
      when is_atom(charge_point_repository) and is_binary(id) and id != "" and is_map(attrs) do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_charge_points),
         {:ok, existing} <- invoke(charge_point_repository, :get, [id]),
         existing_attrs <- Map.from_struct(existing),
         {:ok, charge_point} <- ChargePoint.new(Map.merge(existing_attrs, attrs) |> Map.put(:id, id)),
         {:ok, updated_charge_point} <-
           invoke(charge_point_repository, :update, [charge_point]) do
      {:ok, updated_charge_point}
    end
  end

  def update_charge_point(_charge_point_repository, _id, _attrs, _actor_role),
    do: {:error, {:invalid_arguments, :update_charge_point}}

  @spec delete_charge_point(module(), String.t(), term()) :: :ok | {:error, term()}
  def delete_charge_point(charge_point_repository, id, actor_role)
      when is_atom(charge_point_repository) and is_binary(id) and id != "" do
    with :ok <- AuthorizationPolicy.authorize(actor_role, :manage_charge_points),
         result <- invoke(charge_point_repository, :delete, [id]) do
      result
    end
  end

  def delete_charge_point(_charge_point_repository, _id, _actor_role),
    do: {:error, {:invalid_arguments, :delete_charge_point}}

  defp invoke(module, function, args) when is_atom(module), do: apply(module, function, args)
end
