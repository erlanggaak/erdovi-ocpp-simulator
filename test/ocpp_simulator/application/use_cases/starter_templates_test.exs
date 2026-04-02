defmodule OcppSimulator.Application.UseCases.StarterTemplatesTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Application.UseCases.StarterTemplates

  defmodule TemplateRepositoryStub do
    def upsert(template), do: {:ok, template}
  end

  test "starter_templates/0 returns three minimally compliant scenario templates" do
    templates = StarterTemplates.starter_templates()

    assert length(templates) == 3
    assert Enum.all?(templates, &(&1.type == :scenario))
    assert Enum.all?(templates, &is_map(&1.payload_template["definition"]))

    template_ids = Enum.map(templates, & &1.id)

    assert "starter-template-normal-transaction" in template_ids
    assert "starter-template-fault-recovery" in template_ids
    assert "starter-template-remote-operations" in template_ids

    send_action_actions =
      templates
      |> Enum.flat_map(fn template ->
        template.payload_template["definition"]["steps"]
      end)
      |> Enum.filter(&(&1["type"] == "send_action"))
      |> Enum.map(&get_in(&1, ["payload", "action"]))

    refute "RemoteStartTransaction" in send_action_actions
    refute "RemoteStopTransaction" in send_action_actions
    refute "TriggerMessage" in send_action_actions
  end

  test "seed_starter_templates/2 enforces template management permission" do
    assert {:error, :forbidden} =
             StarterTemplates.seed_starter_templates(TemplateRepositoryStub, :viewer)

    assert {:ok, templates} =
             StarterTemplates.seed_starter_templates(TemplateRepositoryStub, :operator)

    assert length(templates) == 3
  end
end
