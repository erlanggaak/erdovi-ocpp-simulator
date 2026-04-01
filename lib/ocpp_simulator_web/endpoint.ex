defmodule OcppSimulatorWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ocpp_simulator

  @session_options [
    store: :cookie,
    key: "_ocpp_simulator_key",
    signing_salt: "CHANGE_ME_SESSION_SALT",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(OcppSimulatorWeb.Router)
end
