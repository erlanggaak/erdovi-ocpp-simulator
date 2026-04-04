# Setup Guide

This document covers local bootstrap for the OCPP 1.6J Charge Point Simulator.

## Prerequisites

- Elixir `~> 1.17`
- Erlang/OTP `27`
- Docker and Docker Compose

## 1. Prepare Environment

1. Copy runtime variables:
   ```bash
   cp .env.example .env
   ```
2. Set `SECRET_KEY_BASE` in `.env` for your machine.

You can generate a value with:
```bash
mix phx.gen.secret
```

## 2. Start MongoDB (Docker)

```bash
docker compose up -d mongo
```

Verify MongoDB is healthy:
```bash
docker compose ps
```

## 3. Start the Phoenix App on Host

```bash
mix setup
set -a
source .env
set +a
mix phx.server
```

Alternative one-liner:
```bash
mix setup
env $(grep -v '^#' .env | xargs) mix phx.server
```

App endpoints:
- `http://localhost:4000/` — bootstrap LiveView dashboard
- `http://localhost:4000/health` — health endpoint
- `http://localhost:4000/api/health` — API health endpoint
- `http://localhost:4000/api/*` — internal automation API (see `docs/API.md`)

## 4. Start Full Stack in Docker

```bash
docker compose up --build
```

This starts:
- `mongo` on `27017`
- `app` on `4000`

## 5. Stop Services

```bash
docker compose down
```

To reset MongoDB data:
```bash
docker compose down -v
```

## Notes

- Current bootstrap focuses on runtime skeleton and bounded layer startup.
- Domain/application/infrastructure modules are intentionally minimal in this phase and will be expanded in later tasks.

## Runtime Controls

You can tune performance and reliability behavior with environment variables:

- `MAX_CONCURRENT_RUNS` — maximum queued+running runs allowed before API starts rejecting new runs.
- `MAX_ACTIVE_SESSIONS` — maximum active WebSocket session entries in memory.
- `WS_RETRY_BASE_DELAY_MS` — base delay for session reconnect backoff.
- `WS_MAX_RECONNECT_ATTEMPTS` — reconnect attempt cap per session.
- `WS_OUTBOUND_MAX_QUEUE_SIZE` — outbound queue capacity per session.
- `WS_OUTBOUND_MAX_IN_FLIGHT` — max concurrent outbound sends per session queue.
- `WS_OUTBOUND_MAX_RETRY_ATTEMPTS` — outbound message resend attempt cap.
- `WS_OUTBOUND_RETRY_BASE_DELAY_MS` — base delay for outbound queue retry backoff.
- `WEBHOOK_DELIVERY_TIMEOUT_MS` — HTTP timeout for webhook deliveries.
- `WEBHOOK_DELIVERY_DEFAULT_MAX_ATTEMPTS` — default webhook retry attempts when endpoint policy omits it.
- `WEBHOOK_DELIVERY_DEFAULT_BACKOFF_MS` — default webhook retry backoff when endpoint policy omits it.
- `MONGO_POOL_SIZE` — MongoDB connection pool size.

## Quality Gate Commands

Run these commands before opening a PR:

```bash
mix format
mix test
```

Focused Task 9 quality checks:

```bash
mix test test/ocpp_simulator_web/live/transaction_visibility_test.exs
mix test test/ocpp_simulator/application/use_cases/run_scenario_test.exs
mix test test/ocpp_simulator/infrastructure/transport/websocket/outbound_queue_test.exs
mix test test/ocpp_simulator/infrastructure/persistence/mongo/pagination_filter_test.exs
mix test test/ocpp_simulator/infrastructure/integrations/webhook_dispatcher_test.exs
```
