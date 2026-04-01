defmodule OcppSimulatorWeb.RouterAuthorizationTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint OcppSimulatorWeb.Endpoint

  test "management live route redirects unauthorized viewer" do
    conn =
      build_conn()
      |> get("/charge-points")

    assert redirected_to(conn, 302) == "/"
  end

  test "management live route allows operator from session role" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> get("/charge-points")

    assert html_response(conn, 200) =~ "Charge Points"
  end

  test "api run start denies viewer role" do
    conn =
      build_conn()
      |> post("/api/runs", %{})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "api run start allows operator role from session" do
    conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/runs", %{})

    assert %{"data" => %{"resource" => "run", "status" => "accepted"}} = json_response(conn, 202)
  end

  test "api run start ignores untrusted role header by default" do
    conn =
      build_conn()
      |> put_req_header("x-ocpp-role", "operator")
      |> post("/api/runs", %{})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
  end

  test "api management endpoints enforce role permissions" do
    operator_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "operator"})
      |> post("/api/charge-points", %{})

    assert %{"data" => %{"resource" => "charge_point"}} = json_response(operator_conn, 202)

    viewer_conn =
      build_conn()
      |> init_test_session(%{"current_role" => "viewer"})
      |> post("/api/charge-points", %{})

    assert %{"error" => %{"code" => "forbidden"}} = json_response(viewer_conn, 403)
  end
end
