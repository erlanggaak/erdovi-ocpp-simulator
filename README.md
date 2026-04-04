# OCPP 1.6J Charge Point Simulator

Production-oriented OCPP 1.6J simulator built with Elixir, Phoenix, LiveView, and MongoDB.

## Current Scope

This repository currently includes:
- Phoenix + LiveView simulator runtime
- MongoDB-connected local development setup
- Modular-monolith architecture (`domain`, `application`, `infrastructure`, `web`)
- Scenario orchestration, transport/session handling, and internal API coverage
- Contributor and governance documentation for open-source collaboration

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
- `docs/ARCHITECTURE.md` — module boundaries and extension points
- `docs/API.md` — internal automation API contract
- `CONTRIBUTING.md` — contribution workflow and repository boundaries
- `CODE_OF_CONDUCT.md` — community participation standards
- `LICENSE` — MIT license terms

## Quality Gates

Run all checks locally before opening a pull request:

```bash
mix format
mix test
```

Focused end-to-end and reliability checks:

```bash
mix test test/ocpp_simulator_web/live/transaction_visibility_test.exs
mix test test/ocpp_simulator/infrastructure/integrations/webhook_dispatcher_test.exs
```

## Extension Guides

Use these architecture-backed extension paths for new capabilities:

1. Add new OCPP actions:
   Update payload schema validation (`PayloadValidator`), message/action handling, and protocol tests.
2. Add new scenario step types:
   Extend scenario normalization/execution semantics (`Scenario`, `RunScenario`) and scenario-builder coverage.
3. Add new persistence adapters:
   Implement application contracts first, then wire adapter modules via runtime config without changing domain rules.

Detailed guidance lives in `docs/ARCHITECTURE.md` and `CONTRIBUTING.md`.

## Repository Transition Boundaries

This repository is transitioning from internal planning scaffolding to the simulator runtime. Legacy planning artifacts must not be part of released simulator commits:
- `bin/`
- `prompts/`
- `tasks/`
- old prompt-package metadata files

Boundary rules are enforced in `.gitignore` and `CONTRIBUTING.md`.

Planning/task files are used only for local development workflow and are intentionally excluded from final Git history.
