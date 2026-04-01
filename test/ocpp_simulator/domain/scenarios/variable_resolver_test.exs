defmodule OcppSimulator.Domain.Scenarios.VariableResolverTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Scenarios.VariableResolver

  test "resolve/2 applies deterministic scope precedence scenario < run < session < step" do
    template = %{
      "token" => "{{token}}",
      "session_id" => "{{session.id}}",
      "label" => "cp-{{charge_point_id}}"
    }

    scopes = %{
      scenario: %{"token" => "scenario-token", "charge_point_id" => "CP-001"},
      run: %{"token" => "run-token"},
      session: %{"token" => "session-token", "session" => %{"id" => "session-1"}},
      step: %{"token" => "step-token"}
    }

    assert {:ok, resolved} = VariableResolver.resolve(template, scopes)
    assert resolved["token"] == "step-token"
    assert resolved["session_id"] == "session-1"
    assert resolved["label"] == "cp-CP-001"
  end

  test "resolve/2 keeps non-string values when template is exact placeholder" do
    assert {:ok, resolved} =
             VariableResolver.resolve(%{"connector" => "{{connector_id}}"}, %{
               scenario: %{"connector_id" => 2}
             })

    assert resolved["connector"] == 2
  end

  test "resolve/2 returns error when variable is missing" do
    assert {:error, {:missing_variable, "unknown_key"}} =
             VariableResolver.resolve("{{unknown_key}}", %{})
  end

  test "resolve/2 returns validation error for unsupported scope key types" do
    assert {:error,
            {:invalid_field, :scenario, {:invalid_field, :scope_key, :unsupported_scope_key_type}}} =
             VariableResolver.resolve("{{foo}}", %{scenario: %{{:bad, :key} => "value"}})
  end

  test "resolve/2 returns error when interpolated value is not json-encodable" do
    complex_value = fn -> :ok end

    assert {:error, {:invalid_field, :variable_value, :not_json_encodable}} =
             VariableResolver.resolve("payload={{complex}}", %{
               scenario: %{"complex" => complex_value}
             })
  end
end
