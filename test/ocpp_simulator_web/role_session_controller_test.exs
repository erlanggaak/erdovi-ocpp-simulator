defmodule OcppSimulatorWeb.RoleSessionControllerTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.Controller, only: [fetch_flash: 2]

  alias OcppSimulatorWeb.RoleSessionController

  test "switch stores normalized role and redirects to safe return path" do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> fetch_flash([])
      |> RoleSessionController.switch(%{"role" => "operator", "return_to" => "/runs"})

    assert get_session(conn, "current_role") == "operator"
    assert redirected_to(conn, 302) == "/runs"
  end

  test "switch rejects invalid role and prevents external redirect target" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> fetch_flash([])
      |> RoleSessionController.switch(%{
        "role" => "unknown",
        "return_to" => "https://evil.example/path"
      })

    assert get_session(conn, "current_role") == "viewer"
    assert redirected_to(conn, 302) == "/"
  end
end
