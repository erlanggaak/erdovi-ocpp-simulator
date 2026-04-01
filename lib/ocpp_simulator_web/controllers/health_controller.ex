defmodule OcppSimulatorWeb.HealthController do
  use OcppSimulatorWeb, :controller

  def show(conn, _params) do
    payload = %{
      status: "ok",
      service: "ocpp_simulator",
      mongo_database: OcppSimulator.mongo_config()[:database]
    }

    if get_format(conn) == "json" do
      json(conn, payload)
    else
      text(conn, "ok")
    end
  end
end
