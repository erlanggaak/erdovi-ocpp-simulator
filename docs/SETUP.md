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
