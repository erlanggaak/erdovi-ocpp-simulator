defmodule OcppSimulator.Application.UseCases.ImportExportArtifactsTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Application.UseCases.ImportExportArtifacts
  alias OcppSimulator.Domain.Scenarios.Scenario

  defmodule ScenarioRepositoryStub do
    def list(_filters) do
      {:ok,
       %{entries: [build_scenario!()], page: 1, page_size: 50, total_entries: 1, total_pages: 1}}
    end

    def insert(scenario), do: {:ok, scenario}

    defp build_scenario! do
      {:ok, scenario} =
        Scenario.new(%{
          id: "scn-export-1",
          name: "Export Scenario",
          version: "1.0.0",
          steps: [
            %{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}
          ]
        })

      scenario
    end
  end

  defmodule TemplateRepositoryStub do
    def list(_filters) do
      {:ok,
       %{
         entries: [
           %{
             id: "tpl-export-1",
             name: "Template Export",
             version: "1.0.0",
             type: :action,
             payload_template: %{"action" => "Heartbeat"},
             metadata: %{}
           }
         ],
         page: 1,
         page_size: 50,
         total_entries: 1,
         total_pages: 1
       }}
    end

    def upsert(template), do: {:ok, template}
  end

  defmodule PaginatedScenarioRepositoryStub do
    alias OcppSimulator.Domain.Scenarios.Scenario

    def list(filters) do
      page = Map.get(filters, :page, 1)

      scenario_1 = build_scenario!("scn-export-page-1")
      scenario_2 = build_scenario!("scn-export-page-2")

      case page do
        1 ->
          {:ok,
           %{
             entries: [scenario_1],
             page: 1,
             page_size: 1,
             total_entries: 2,
             total_pages: 2
           }}

        2 ->
          {:ok,
           %{
             entries: [scenario_2],
             page: 2,
             page_size: 1,
             total_entries: 2,
             total_pages: 2
           }}
      end
    end

    def insert(scenario), do: {:ok, scenario}

    defp build_scenario!(id) do
      {:ok, scenario} =
        Scenario.new(%{
          id: id,
          name: "Export Scenario #{id}",
          version: "1.0.0",
          steps: [
            %{id: "boot", type: :send_action, payload: %{"action" => "BootNotification"}}
          ]
        })

      scenario
    end
  end

  defmodule PaginatedTemplateRepositoryStub do
    def list(filters) do
      page = Map.get(filters, :page, 1)

      case page do
        1 ->
          {:ok,
           %{
             entries: [
               %{
                 id: "tpl-export-page-1",
                 name: "Template Export 1",
                 version: "1.0.0",
                 type: :action,
                 payload_template: %{"action" => "Heartbeat"},
                 metadata: %{}
               }
             ],
             page: 1,
             page_size: 1,
             total_entries: 2,
             total_pages: 2
           }}

        2 ->
          {:ok,
           %{
             entries: [
               %{
                 id: "tpl-export-page-2",
                 name: "Template Export 2",
                 version: "1.0.0",
                 type: :scenario,
                 payload_template: %{"definition" => %{"steps" => []}},
                 metadata: %{}
               }
             ],
             page: 2,
             page_size: 1,
             total_entries: 2,
             total_pages: 2
           }}
      end
    end

    def upsert(template), do: {:ok, template}
  end

  test "export_scenarios/3 returns schema-versioned scenario bundle" do
    assert {:ok, bundle} =
             ImportExportArtifacts.export_scenarios(ScenarioRepositoryStub, :operator, %{})

    assert bundle.artifact == "scenarios"
    assert bundle.schema_version == "1.0"
    assert bundle.count == 1
    assert Enum.at(bundle.entries, 0).id == "scn-export-1"
  end

  test "export_scenarios/3 iterates through all pages and exports complete dataset" do
    assert {:ok, bundle} =
             ImportExportArtifacts.export_scenarios(
               PaginatedScenarioRepositoryStub,
               :operator,
               %{}
             )

    assert bundle.count == 2
    assert Enum.map(bundle.entries, & &1.id) == ["scn-export-page-1", "scn-export-page-2"]
  end

  test "import_scenarios/3 validates and imports entries" do
    payload = %{
      entries: [
        %{
          id: "scn-import-1",
          name: "Imported Scenario",
          version: "1.0.0",
          steps: [
            %{id: "boot", type: "send_action", payload: %{"action" => "BootNotification"}}
          ]
        }
      ]
    }

    assert {:ok, result} =
             ImportExportArtifacts.import_scenarios(ScenarioRepositoryStub, :operator, payload)

    assert result.imported_count == 1
    assert Enum.at(result.entries, 0).id == "scn-import-1"
  end

  test "export_templates/3 and import_templates/3 handle template artifacts" do
    assert {:ok, bundle} =
             ImportExportArtifacts.export_templates(TemplateRepositoryStub, :operator, %{})

    assert bundle.artifact == "templates"
    assert bundle.count == 1

    import_payload = %{
      entries: [
        %{
          id: "tpl-import-1",
          name: "Imported Template",
          version: "1.0.0",
          type: "scenario",
          payload_template: %{"definition" => %{"steps" => []}},
          metadata: %{"starter" => false}
        }
      ]
    }

    assert {:ok, result} =
             ImportExportArtifacts.import_templates(
               TemplateRepositoryStub,
               :operator,
               import_payload
             )

    assert result.imported_count == 1
    assert Enum.at(result.entries, 0).id == "tpl-import-1"
    assert Enum.at(result.entries, 0).type == :scenario
  end

  test "export_templates/3 iterates through all pages and exports complete dataset" do
    assert {:ok, bundle} =
             ImportExportArtifacts.export_templates(
               PaginatedTemplateRepositoryStub,
               :operator,
               %{}
             )

    assert bundle.count == 2
    assert Enum.map(bundle.entries, & &1.id) == ["tpl-export-page-1", "tpl-export-page-2"]
  end
end
