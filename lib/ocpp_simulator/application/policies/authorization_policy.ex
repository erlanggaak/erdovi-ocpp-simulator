defmodule OcppSimulator.Application.Policies.AuthorizationPolicy do
  @moduledoc """
  Central role-based authorization policy for UI and API operations.
  """

  @roles [:admin, :operator, :viewer]

  @permissions [
    :api_automation,
    :view_dashboard,
    :view_charge_points,
    :manage_charge_points,
    :view_target_endpoints,
    :manage_target_endpoints,
    :view_scenarios,
    :manage_scenarios,
    :view_templates,
    :manage_templates,
    :view_runs,
    :start_run,
    :cancel_run
  ]

  @role_permissions %{
    admin: @permissions,
    operator: [
      :api_automation,
      :view_dashboard,
      :view_charge_points,
      :manage_charge_points,
      :view_target_endpoints,
      :manage_target_endpoints,
      :view_scenarios,
      :manage_scenarios,
      :view_templates,
      :manage_templates,
      :view_runs,
      :start_run,
      :cancel_run
    ],
    viewer: [
      :view_dashboard,
      :view_charge_points,
      :view_target_endpoints,
      :view_scenarios,
      :view_templates,
      :view_runs
    ]
  }

  @type role :: :admin | :operator | :viewer

  @type permission ::
          :api_automation
          | :view_dashboard
          | :view_charge_points
          | :manage_charge_points
          | :view_target_endpoints
          | :manage_target_endpoints
          | :view_scenarios
          | :manage_scenarios
          | :view_templates
          | :manage_templates
          | :view_runs
          | :start_run
          | :cancel_run

  @spec roles() :: [role()]
  def roles, do: @roles

  @spec permissions() :: [permission()]
  def permissions, do: @permissions

  @spec normalize_role(term()) :: {:ok, role()} | {:error, term()}
  def normalize_role(nil), do: {:ok, :viewer}
  def normalize_role(role) when role in @roles, do: {:ok, role}

  def normalize_role(role) when is_binary(role) do
    role
    |> String.trim()
    |> String.downcase()
    |> case do
      "admin" -> {:ok, :admin}
      "operator" -> {:ok, :operator}
      "viewer" -> {:ok, :viewer}
      _ -> {:error, {:invalid_role, role}}
    end
  end

  def normalize_role(role), do: {:error, {:invalid_role, role}}

  @spec authorize(term(), permission()) :: :ok | {:error, term()}
  def authorize(role, permission) do
    with {:ok, normalized_role} <- normalize_role(role),
         :ok <- validate_permission(permission) do
      if permission in Map.fetch!(@role_permissions, normalized_role) do
        :ok
      else
        {:error, :forbidden}
      end
    end
  end

  @spec allowed?(term(), permission()) :: boolean()
  def allowed?(role, permission), do: authorize(role, permission) == :ok

  defp validate_permission(permission) when permission in @permissions, do: :ok
  defp validate_permission(permission), do: {:error, {:invalid_permission, permission}}
end
