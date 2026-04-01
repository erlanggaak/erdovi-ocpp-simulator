defmodule OcppSimulator.Application.UseCases.ManagementUseCasesTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Application.UseCases.ManageChargePoints
  alias OcppSimulator.Application.UseCases.ManageScenarios
  alias OcppSimulator.Application.UseCases.ManageTargetEndpoints

  defmodule ChargePointRepositoryStub do
    def insert(charge_point), do: {:ok, charge_point}
    def get(_id), do: {:error, :not_found}
    def list(_filters), do: {:ok, []}
  end

  defmodule TargetEndpointRepositoryStub do
    def insert(endpoint), do: {:ok, endpoint}
    def get(_id), do: {:error, :not_found}
    def list(_filters), do: {:ok, []}
  end

  defmodule ScenarioRepositoryStub do
    def insert(scenario), do: {:ok, scenario}
    def get(_id), do: {:error, :not_found}
    def list(_filters), do: {:ok, []}
  end

  defmodule TemplateRepositoryStub do
    def upsert(template), do: {:ok, template}
    def get(_id, _type), do: {:error, :not_found}
    def list(_filters), do: {:ok, []}
  end

  test "register_charge_point/3 creates a charge point through repository contract" do
    attrs = %{
      id: "CP-APP-1",
      vendor: "Erdovi",
      model: "Simulator",
      firmware_version: "1.0.0",
      connector_count: 2,
      heartbeat_interval_seconds: 30
    }

    assert {:ok, charge_point} =
             ManageChargePoints.register_charge_point(ChargePointRepositoryStub, attrs, :operator)

    assert charge_point.id == "CP-APP-1"
  end

  test "register_charge_point/3 rejects unauthorized role" do
    assert {:error, :forbidden} =
             ManageChargePoints.register_charge_point(ChargePointRepositoryStub, %{}, :viewer)
  end

  test "create_target_endpoint/3 enforces plain ws url" do
    attrs = %{id: "ep-1", name: "Primary", url: "wss://secure-host"}

    assert {:error, {:invalid_field, :url, :must_use_plain_ws_scheme}} =
             ManageTargetEndpoints.create_target_endpoint(
               TargetEndpointRepositoryStub,
               attrs,
               :operator
             )
  end

  test "create_scenario/3 builds scenario via domain invariants" do
    attrs = %{
      id: "scn-app-1",
      name: "Boot flow",
      version: "1.0.0",
      steps: [
        %{id: "boot", type: :send_action, order: 1, payload: %{"action" => "BootNotification"}}
      ]
    }

    assert {:ok, scenario} =
             ManageScenarios.create_scenario(ScenarioRepositoryStub, attrs, :operator)

    assert scenario.id == "scn-app-1"
    assert length(scenario.steps) == 1
  end

  test "upsert_action_template/3 is permission-gated" do
    attrs = %{
      id: "tpl-1",
      name: "Boot action",
      version: "1.0.0",
      payload_template: %{"action" => "BootNotification"}
    }

    assert {:error, :forbidden} =
             ManageScenarios.upsert_action_template(TemplateRepositoryStub, attrs, :viewer)

    assert {:ok, template} =
             ManageScenarios.upsert_action_template(TemplateRepositoryStub, attrs, :operator)

    assert template.type == :action
  end
end
