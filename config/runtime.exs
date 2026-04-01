import Config

parse_positive_int = fn raw, default ->
  case Integer.parse(to_string(raw || "")) do
    {value, ""} when value > 0 -> value
    _ -> default
  end
end

host = System.get_env("PHX_HOST") || "localhost"
port = parse_positive_int.(System.get_env("PORT"), 4000)

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    if(config_env() == :prod,
      do: raise("SECRET_KEY_BASE is required in production"),
      else: "dev-secret-key-base-dev-secret-key-base-dev-secret-key-base-2026"
    )

if System.get_env("PHX_SERVER") do
  config :ocpp_simulator, OcppSimulatorWeb.Endpoint, server: true
end

config :ocpp_simulator, OcppSimulatorWeb.Endpoint,
  url: [host: host, port: port],
  http: [ip: {0, 0, 0, 0}, port: port],
  secret_key_base: secret_key_base

config :ocpp_simulator, :mongo,
  url: System.get_env("MONGO_URL") || "mongodb://localhost:27017/ocpp_simulator_dev",
  pool_size: parse_positive_int.(System.get_env("MONGO_POOL_SIZE"), 10),
  database: System.get_env("MONGO_DATABASE") || "ocpp_simulator_dev"

config :ocpp_simulator, :runtime,
  max_concurrent_runs: parse_positive_int.(System.get_env("MAX_CONCURRENT_RUNS"), 25),
  max_active_sessions: parse_positive_int.(System.get_env("MAX_ACTIVE_SESSIONS"), 200),
  ws_retry_base_delay_ms: parse_positive_int.(System.get_env("WS_RETRY_BASE_DELAY_MS"), 1_000)
