defmodule OcppSimulator.Application.Policies.AuthorizationPolicyTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Application.Policies.AuthorizationPolicy

  test "authorize/2 allows operator to manage charge points and runs" do
    assert :ok = AuthorizationPolicy.authorize(:operator, :manage_charge_points)
    assert :ok = AuthorizationPolicy.authorize("operator", :start_run)
    assert :ok = AuthorizationPolicy.authorize(:admin, :cancel_run)
  end

  test "authorize/2 forbids viewer from management operations" do
    assert {:error, :forbidden} = AuthorizationPolicy.authorize(:viewer, :manage_charge_points)
    assert {:error, :forbidden} = AuthorizationPolicy.authorize(:viewer, :start_run)
    assert {:error, :forbidden} = AuthorizationPolicy.authorize(:viewer, :cancel_run)
  end

  test "authorize/2 returns explicit errors for invalid role or permission" do
    assert {:error, {:invalid_role, "unknown"}} =
             AuthorizationPolicy.authorize("unknown", :view_dashboard)

    assert {:error, {:invalid_permission, :unknown_permission}} =
             AuthorizationPolicy.authorize(:admin, :unknown_permission)
  end
end
