# OCPP 1.6J Charge Point Simulator

Production-oriented OCPP 1.6J simulator built with Elixir, Phoenix, LiveView, and MongoDB.

## Current Scope

This repository currently includes:
- Phoenix + LiveView bootstrap runtime
- MongoDB-connected local development setup
- Modular-monolith layer skeleton (`domain`, `application`, `infrastructure`, `web`)
- Initial contributor and setup documentation

## Quick Start

1. Copy environment template:
   ```bash
   cp .env.example .env
   ```
2. Start MongoDB:
   ```bash
   docker compose up -d mongo
   ```
3. Install dependencies and run app:
   ```bash
   mix setup
   set -a
   source .env
   set +a
   mix phx.server
   ```

Visit `http://localhost:4000`.

## Documentation

- `docs/SETUP.md` — local bootstrap and run flow
- `CONTRIBUTING.md` — contribution workflow and repository boundaries

## Repository Transition Boundaries

This repository is transitioning from internal planning scaffolding to the simulator runtime. Legacy planning artifacts must not be part of released simulator commits:
- `bin/`
- `prompts/`
- `tasks/`
- old prompt-package metadata files

Boundary rules are enforced in `.gitignore` and `CONTRIBUTING.md`.

Planning/task files are used only for local development workflow and are intentionally excluded from final Git history.
