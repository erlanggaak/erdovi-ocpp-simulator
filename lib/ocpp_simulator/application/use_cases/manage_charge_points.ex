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

  defp invoke(module, function, args) when is_atom(module), do: apply(module, function, args)
end
