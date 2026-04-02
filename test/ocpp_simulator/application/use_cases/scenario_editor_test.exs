defmodule OcppSimulator.Application.UseCases.ScenarioEditorTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Application.UseCases.ScenarioEditor

  test "visual_to_raw_json/1 and raw_json_to_visual/1 preserve normalized scenario definition" do
    visual_model = %{
      "id" => "scn-editor-1",
      "name" => "Editor Flow",
      "version" => "1.0.0",
      "steps" => [
        %{"id" => "wait", "type" => "wait", "order" => 2, "delay_ms" => 100},
        %{
          "id" => "boot",
          "type" => "send_action",
          "order" => 1,
          "payload" => %{"action" => "BootNotification"}
        }
      ]
    }

    assert {:ok, raw_json} = ScenarioEditor.visual_to_raw_json(visual_model)
    assert {:ok, normalized_visual_model} = ScenarioEditor.raw_json_to_visual(raw_json)

    assert Enum.map(normalized_visual_model["steps"], & &1["id"]) == ["boot", "wait"]
    assert normalized_visual_model["validation_policy"]["strict_ocpp_schema"] == true
  end

  test "round_trip_visual/1 guarantees schema-safe normalization" do
    visual_model = %{
      id: "scn-editor-2",
      name: "Round Trip",
      version: "1.0.0",
      variable_scopes: ["scenario", "run", "session", "step"],
      steps: [
        %{id: "boot", type: "send_action", payload: %{"action" => "Heartbeat"}}
      ]
    }

    assert {:ok, normalized_visual_model} = ScenarioEditor.round_trip_visual(visual_model)

    assert normalized_visual_model["id"] == "scn-editor-2"

    assert normalized_visual_model["steps"] == [
             %{
               "delay_ms" => 0,
               "enabled" => true,
               "id" => "boot",
               "loop_count" => 1,
               "order" => 1,
               "payload" => %{"action" => "Heartbeat"},
               "type" => "send_action"
             }
           ]
  end

  test "raw_json_to_visual/1 returns malformed_json error for invalid JSON input" do
    assert {:error, {:invalid_field, :raw_json, :malformed_json}} =
             ScenarioEditor.raw_json_to_visual("{\"invalid\":")
  end
end
