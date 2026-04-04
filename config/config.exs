import Config

config :ocpp_simulator,
  namespace: OcppSimulator,
  generators: [timestamp_type: :utc_datetime]

config :ocpp_simulator, OcppSimulatorWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: OcppSimulatorWeb.ErrorHTML, json: OcppSimulatorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OcppSimulator.PubSub,
  live_view: [signing_salt: "CHANGE_ME_LIVE_VIEW_SALT"]

config :phoenix, :json_library, Jason

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :run_id, :session_id, :charge_point_id, :message_id]

config :ocpp_simulator, :runtime,
  max_concurrent_runs: 25,
  max_active_sessions: 200,
  ws_retry_base_delay_ms: 1_000,
  ws_max_reconnect_attempts: 3,
  ws_outbound_max_queue_size: 200,
  ws_outbound_max_in_flight: 8,
  ws_outbound_max_retry_attempts: 3,
  ws_outbound_retry_base_delay_ms: 200,
  webhook_delivery_timeout_ms: 5_000,
  webhook_delivery_default_max_attempts: 3,
  webhook_delivery_default_backoff_ms: 1_000

config :ocpp_simulator, :mongo,
  url: "mongodb://localhost:27017/ocpp_simulator_dev",
  pool_size: 10,
  database: "ocpp_simulator_dev"

config :ocpp_simulator,
  mongo_autostart: config_env() != :test,
  mongo_index_bootstrap: config_env() != :test,
  mongo_index_bootstrap_retry_ms: 5_000

config :ocpp_simulator, :allow_untrusted_role_header, false

config :ocpp_simulator,
       :ocpp_transport_adapter,
       OcppSimulator.Infrastructure.Transport.WebSocket.TcpAdapter

config :ocpp_simulator, :id_generator, OcppSimulator.Infrastructure.Support.IdGenerator

config :ocpp_simulator,
       :structured_logger,
       OcppSimulator.Infrastructure.Observability.StructuredLogger

config :ocpp_simulator,
       :webhook_dispatcher,
       OcppSimulator.Infrastructure.Integrations.WebhookDispatcher
