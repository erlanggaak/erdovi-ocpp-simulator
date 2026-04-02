## Product Requirements Document (PRD)

### 1. Product Overview
Build a production-oriented OCPP 1.6J Charge Point Simulator as a modular monolith using Elixir, Phoenix, LiveView, and MongoDB.

The product simulates virtual charge points over WebSocket, executes realistic OCPP scenarios, and provides a web UI for configuration, scenario authoring, live monitoring, and history review.

The initial users are internal QA and protocol teams, but the repository, architecture, and documentation must be open-source grade from day one.

### 2. Current State
The current workspace contains internal prompt-tooling files, not an OCPP simulator application runtime.

Current observations:
- There is no Elixir/Phoenix project scaffold yet (`mix.exs`, OTP app modules, web interface, and supervision tree are absent).
- There is no domain model, no persistence layer, no WebSocket engine, and no UI runtime.
- There is no existing MongoDB integration.
- There is no contributor-facing documentation set for an application lifecycle (`ARCHITECTURE.md`, `SETUP.md`, `CONTRIBUTING.md`, etc.).
- Existing local files such as `bin/`, `prompts/`, `tasks/`, and the current root `README.md` are internal planning/bootstrap artifacts and should not be part of the final simulator Git repository.

Implication for this PRD:
- This is a greenfield product design.
- The PRD defines the architecture, modules, and delivery plan for a new clean simulator repository.

### 3. Target State
After implementation, the repository contains a deployable single-service Phoenix application with a modular-monolith architecture and clear boundaries:

- `Domain` layer defines core entities, value objects, state models, and behavior contracts.
- `Application` layer orchestrates use cases and scenario execution.
- `Infrastructure` layer implements adapters for MongoDB, WebSocket transport, logging, and external concerns.
- `Interface` layer provides LiveView UI, HTTP endpoints, and presentation logic without business rules.

The system can:
- Manage virtual charge points and target CSMS endpoints.
- Maintain active WebSocket sessions and OCPP message flows.
- Create reusable action and scenario templates with versioning.
- Execute scenario runs with traceability and live console visibility.
- Store and query configurations, templates, runs, and logs from MongoDB through repository abstractions.
- Provide built-in Phoenix authentication flow for user login and role-based access boundaries in UI and run operations.

The repository also ships with:
- Open-source-quality docs and contribution standards.
- Local-first developer experience with Docker Compose.
- Extensibility points for new OCPP actions, scenario step types, and persistence backends.

### 4. User Stories
- As a QA engineer, I want to register many virtual charge points so that I can test CSMS behavior under varied charger configurations.
- As a protocol engineer, I want to run customizable OCPP 1.6J scenarios so that I can validate command handling and transaction flows.
- As a tester, I want reusable action and scenario templates so that I can avoid rewriting common test flows.
- As an operator, I want live session and run monitoring so that I can quickly diagnose failing scenarios.
- As a maintainer, I want logs correlated by run, charge point, and message so that troubleshooting is deterministic.
- As an open-source contributor, I want clear module boundaries and setup guides so that I can add features safely.
- As a future platform engineer, I want persistence and transport adapters behind contracts so that I can swap implementations without domain rewrites.
- As an internal user, I want to sign in securely and operate only permitted features so that simulator usage is controlled.

### 5. Functional Requirements
Included behavior (must do):
- Simulate OCPP 1.6J JSON charge points over WebSocket.
- Support virtual charge point configuration:
  - `chargePointId`, vendor, model, firmware, connector count, heartbeat interval, behavior profile.
- Include authentication and role separation using Phoenix built-in authentication patterns (session/token flow and LiveView authorization hooks).
- Manage target CSMS endpoints and connection profiles (URL, protocol options, retry policy).
- Support plain `ws://` CSMS connectivity in v1.
- WebSocket session manager must support connect, disconnect, reconnect, and session lifecycle tracking.
- Correlate OCPP Call/CallResult/CallError messages by unique message identifiers.
- Enforce strict OCPP 1.6J payload validation for inbound and outbound frames.
- Support multiple virtual charge points and concurrent scenario execution across those charge points with configurable concurrency limits.
- Implement v1 OCPP action coverage:
  - BootNotification
  - Heartbeat
  - StatusNotification
  - Authorize
  - StartTransaction
  - MeterValues
  - StopTransaction
  - RemoteStartTransaction and RemoteStopTransaction
  - Reset
  - ChangeAvailability
  - TriggerMessage
  - Basic configuration management
  - Basic fault scenarios
- Scenario builder must support:
  - Ordered step composition
  - Delays and repeat loops
  - Reusable action templates
  - Reusable scenario templates
  - Payload parameterization and variable substitution
  - Structured visual editing and raw JSON editing for scenario definition
  - Builder layout with step palette, flow canvas/timeline, step inspector, and payload preview
  - Inline field-level validation and run-level validation summary before execution
  - Step-level request/response preview with correlation IDs
  - Starter templates that are minimally OCPP-compliant out of the box
- Support import/export of templates and scenarios.
- Support webhook notifications for scenario run completion and failure events.
- Persist all primary data in MongoDB:
  - charge points
  - target endpoints
  - action templates
  - scenarios
  - scenario runs
  - logs
- Persist a frozen full scenario snapshot on each scenario run for reproducibility.
- LiveView UI must provide:
  - Dashboard
  - Charge point registry
  - Scenario library
  - Template library
  - Scenario builder
  - Live session console
  - Logs viewer
  - Run history
  - Debugging views with per-step timeline, frame details, and error reason panels
- Observability:
  - Structured logs
  - Traceable IDs per scenario run and charge point session
  - Clear error states in UI and service logs
- Open-source quality deliverables:
  - `README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `SETUP.md`, `.env.example`, `LICENSE` (MIT), `CODE_OF_CONDUCT.md`
  - Documentation written in English for v1

Excluded behavior (explicitly not in v1):
- OCPP 2.0.1 or other protocol versions.
- `wss://` and mTLS CSMS transport (planned for a later release).
- Multi-service distributed deployment.
- Multi-tenant enterprise access control model.
- Billing, payment gateway, or production charger device management.
- Hard dependency on Mongo-specific constructs in domain/application layers.

Acceptance criteria:
- A developer can start the app and MongoDB locally via documented commands and run a sample scenario end-to-end.
- At least one realistic transaction flow can be executed and observed from LiveView in real time.
- Scenario runs and logs are queryable in history views after completion.
- Scenario runs persist frozen scenario snapshots and can be replayed with historical data context.
- Repositories are defined as behavior contracts with MongoDB as one adapter implementation.
- Webhook delivery is triggered for run completion and failure, with retry and failure visibility.
- Tests cover domain logic, protocol serialization, scenario execution, repository behavior, and key LiveView flows.
- Builder supports both visual editing and raw JSON editing for the same scenario with schema-safe round trip.
- Execution is blocked when strict OCPP schema validation or state-transition validation fails, with actionable error details shown in UI.

### 6. Technical Design (High-Level)
This section intentionally provides architecture and design detail without implementation code.

Architecture overview:
- Style: modular monolith with strict layer boundaries.
- Runtime: single Phoenix application process with supervised subsystems.
- Logical modules:
  - OCPP engine
  - Scenario engine
  - Charge point session manager
  - Template and configuration management
  - Identity and access control
  - Notification and integration hooks
  - Run tracking and observability
- Dependency direction:
  - Interface -> Application -> Domain
  - Infrastructure depends inward through behaviors only
  - Domain has zero direct dependency on Infrastructure or Phoenix

Component interactions:
- LiveView UI authenticates users and enforces role checks before dispatching use-case intent.
- Use cases load and persist state via repository behaviors.
- Use cases dispatch scenario actions to OCPP execution services.
- OCPP transport adapter manages WebSocket I/O and emits message events.
- Run event service dispatches completion/failure webhook notifications.
- Event/log service stores correlated run/session/message logs.

Data flow and processing logic:
- Scenario execution flow:
  - User selects scenario + charge point(s) + endpoint.
  - Application creates `scenario_run` with correlation IDs.
  - Scenario engine resolves templates and variables.
  - Step executor dispatches OCPP actions in sequence with delay/loop semantics.
  - WebSocket manager transmits frames and awaits correlated responses.
  - State machine updates charge point/session/transaction states.
  - Structured logs and metrics are persisted for each step transition.
  - Frozen full scenario snapshot is stored with run metadata for reproducibility.
  - Run final state is marked succeeded, failed, canceled, or timed out.
  - Completion/failure notification is sent through configured webhooks.
- Inbound command flow (example remote control):
  - WebSocket receives CSMS command frame.
  - OCPP parser validates action and schema with strict conformance rules.
  - Action strategy executes according to charge point current state.
  - Result frame is generated by message factory and returned.
  - State/log repositories are updated.

Module structure (output expectation #2):
- Proposed high-level structure:
  - `/lib/ocpp_simulator/domain`
  - `/lib/ocpp_simulator/application`
  - `/lib/ocpp_simulator/infrastructure`
  - `/lib/ocpp_simulator/interface`
  - `/lib/ocpp_simulator_web` (Phoenix web boundary)
  - `/test` mirrors domain/application/infrastructure/interface
  - `/docs` for architecture, setup, examples, contribution guide
  - `/priv/repo` only for Phoenix defaults unrelated to Mongo persistence concerns
- Domain submodules:
  - `accounts`
  - `charge_points`
  - `sessions`
  - `ocpp`
  - `scenarios`
  - `templates`
  - `runs`
  - `notifications`
  - `logs`
- Application submodules:
  - `use_cases`
  - `services`
  - `policies`
  - `contracts` (behaviors)
- Infrastructure submodules:
  - `persistence/mongo`
  - `transport/websocket`
  - `serialization/ocpp_json`
  - `observability/logging`
- Interface submodules:
  - `live/auth`
  - `live/dashboard`
  - `live/charge_points`
  - `live/scenarios`
  - `live/templates`
  - `live/sessions`
  - `live/logs`

Domain model (output expectation #3):
- Core entities:
  - `User`
  - `RoleAssignment`
  - `ChargePoint`
  - `Connector`
  - `TargetEndpoint`
  - `Session`
  - `Scenario`
  - `ScenarioStep`
  - `ActionTemplate`
  - `ScenarioTemplate`
  - `ScenarioRun`
  - `RunStepExecution`
  - `WebhookEndpoint`
  - `WebhookDelivery`
  - `OcppMessage`
  - `LogEntry`
- Value objects:
  - IDs (`ChargePointId`, `RunId`, `MessageId`)
  - `OcppAction`
  - `Role`
  - `ConnectionPolicy`
  - `RetryPolicy`
  - `HeartbeatConfig`
  - `PayloadVariables`
- Domain services:
  - Scenario variable resolver
  - OCPP message validator
  - Correlation and timeout policy
- Business invariants:
  - Scenario step order is deterministic.
  - Message IDs are unique per session.
  - Transaction lifecycle transitions are valid.
  - A run references immutable scenario/template versions.

MongoDB schema design (output expectation #4):
- Collections:
  - `users`
  - `charge_points`
  - `target_endpoints`
  - `action_templates`
  - `scenarios`
  - `scenario_runs`
  - `webhook_endpoints`
  - `webhook_deliveries`
  - `logs`
- Conceptual document design:
  - `users`: identity fields + credential hash + role membership + audit timestamps.
  - `charge_points`: identity + hardware profile + behavior defaults + connector metadata.
  - `target_endpoints`: endpoint URL + TLS/retry config + tags.
  - `action_templates`: action type + payload template + variable definitions + version metadata.
  - `scenarios`: ordered step definitions + references to action templates + loop/delay + version metadata.
  - `scenario_runs`: full frozen scenario snapshot + source version reference + runtime state + step results + timing + actor metadata.
  - `webhook_endpoints`: target URL + event filters + retry policy + secret metadata.
  - `webhook_deliveries`: webhook event payload + delivery attempts + final status + response summary.
  - `logs`: correlation IDs + severity + event type + structured payload + timestamp.
- Indexing guidance:
  - Unique index on user email or username.
  - Unique index on charge point ID.
  - Compound indexes for run history by scenario ID and created time.
  - Compound indexes for logs by run ID, session ID, and timestamp.
  - Compound indexes for webhook deliveries by run ID and delivery status.
  - Index for active sessions/state filters.
- Versioning model:
  - Templates and scenarios include semantic revision fields.
  - Scenario runs persist resolved version references and mandatory frozen snapshots.

Repository abstraction (critical for extensibility):
- Define behavior contracts in application/domain-facing modules.
- MongoDB adapter implements behavior contracts.
- Alternative adapters (for example PostgreSQL, in-memory) can be added without domain changes.

Scenario DSL (output expectation #5):
- Definition:
  - DSL means Domain-Specific Language for scenario/test-case authoring.
- Representation:
  - Persisted as JSON documents with explicit schema version.
  - Editable in both structured form UI and raw JSON mode.
- Conceptual grammar:
  - Scenario metadata (name, purpose, tags, version)
  - Variables (defaults and runtime overrides)
  - Steps (type, action, payload-template-ref, delay, loop, conditions)
  - Error policy (stop, continue, retry)
  - Validation policy (strict OCPP conformance enabled by default in v1)
- Step types:
  - `send_action`
  - `await_response`
  - `wait`
  - `loop`
  - `set_variable`
  - `assert_state`
- Variable substitution:
  - Scoped by run, session, and step outputs.
  - Deterministic resolution order to prevent ambiguous payload values.

State machines (output expectation #6):
- Charge point state:
  - `offline -> connecting -> booting -> available -> preparing -> charging -> finishing -> available`
  - Fault and unavailable transitions allowed from operational states.
- Session state:
  - `idle -> connected -> active -> reconnecting -> disconnected -> terminated`
- Transaction state:
  - `none -> authorized -> started -> metering -> stopped`
- Scenario run state:
  - `draft -> queued -> running -> succeeded | failed | canceled | timed_out`
- Rules:
  - Invalid transitions are rejected and logged.
  - State transition events carry correlation IDs.

API and interface design considerations:
- Primary UI interaction through LiveView events and routes.
- Internal JSON API namespace for automation, import/export, and webhook configuration.
- WebSocket subsystem for OCPP transport only, separate from LiveView sockets.
- Standardized response envelope for UI-triggered run operations.
- Scenario builder UX contract:
  - left panel: step palette and template picker
  - center panel: ordered timeline/canvas with add, reorder, clone, and disable step actions
  - right panel: step inspector with action-specific fields, variable helper, and validation messages
  - bottom panel: raw JSON editor and generated OCPP frame preview

Security considerations:
- No hardcoded credentials.
- Environment-driven secrets and endpoint settings.
- Authentication and role-based authorization are mandatory in v1.
- Input validation for scenario payload templates and variable values.
- Strict OCPP 1.6J schema validation for inbound and outbound payloads is mandatory in v1.
- Safe logging defaults with sensitive-field masking policy.

Performance considerations:
- Supervised connection pools and bounded concurrency per run.
- Backpressure-aware message handling and retry strategies.
- Pagination and filter-first query patterns for logs and run history.
- Practical limits for number of simultaneous virtual charge points and concurrent scenario runs in one node, with limits configurable by environment.

Observability design:
- Structured logging fields:
  - `run_id`, `session_id`, `charge_point_id`, `message_id`, `action`, `step_id`, `severity`, `timestamp`
- Event taxonomy:
  - connection events
  - protocol events
  - scenario engine events
  - authentication and authorization events
  - webhook delivery events
  - persistence events
  - UI-triggered run events
- Traceability:
  - Every scenario step and protocol frame links to run/session context.
  - UI exposes run timeline and per-step trace so users can diagnose failures without external tooling.

Implementation plan (output expectation #7):
- Phase 1: Project scaffold and baseline docs.
- Phase 2: Domain model, auth model, and behavior contracts.
- Phase 3: MongoDB repositories and persistence adapter tests.
- Phase 4: WebSocket transport and OCPP frame engine.
- Phase 5: Scenario DSL, builder, and run executor.
- Phase 6: LiveView screens for auth, management, and monitoring.
- Phase 7: Core action support, import/export, webhook events, and fault scenarios.
- Phase 8: Hardening, observability, and OSS readiness pass.

Code skeleton (output expectation #8):
- Target skeleton is module-level, not implementation-level:
  - Domain modules for entities, authentication roles, state machines, and invariants.
  - Application use-case modules for create/update/run/cancel flows.
  - Infrastructure adapters for MongoDB repositories, WebSocket transport, and webhook delivery.
  - Interface modules for LiveView pages and reusable UI components.
  - Shared contracts (behaviors) for repositories, transport, clock, ID generation, and logging.

Key examples (output expectation #9):
- Example scenario template:
  - BootNotification -> Heartbeat loop -> Authorize -> StartTransaction -> MeterValues loop -> StopTransaction
- Example fault scenario:
  - Normal boot -> intermittent disconnect -> reconnect -> TriggerMessage -> recovery validation
- Example remote operation:
  - Receive `RemoteStartTransaction` while available -> run state transition -> emit StartTransaction sequence.

Test strategy (output expectation #10):
- Unit tests:
  - Domain invariants, state transitions, variable substitution.
- Auth tests:
  - Login/session flow and role-based authorization checks in LiveView routes/actions.
- Protocol tests:
  - OCPP 1.6J message encoding/decoding and correlation handling.
  - JSON schema conformance tests for each supported OCPP action payload.
- Application tests:
  - Scenario orchestration, retry logic, timeout behavior, and pre-run validation gate behavior.
- Repository tests:
  - Contract tests for repositories plus MongoDB adapter integration tests.
- LiveView tests:
  - Critical user flows for scenario creation, dual-mode editor (visual and JSON), run launch, and live monitoring.
- End-to-end integration tests:
  - Representative scenarios with mocked or controlled CSMS endpoints.
- Notification tests:
  - Webhook trigger conditions, signature validation, retry behavior, and failure handling.
- Non-functional tests:
  - Concurrency smoke tests and log traceability assertions.

Integration points with existing repository:
- Simulator implementation should start from a clean repository/application scaffold.
- Internal tooling artifacts in this workspace (`bin/`, `prompts/`, `tasks/`, current root `README.md`) are planning aids and must be excluded from the final simulator Git repository.

### 7. Relevant Files to Review
- `tasks/2026-04-01-ocpp-16j-charge-point-simulator.md` — Authoritative PRD for v1 product scope and architecture.
- `prompts/prd-creator.md` — Internal planning template used to structure this PRD (not part of final simulator repo).
- `/` — No runtime source files yet; product implementation starts from an empty codebase scaffold.
- `prompts/task-breakdown.md` (ADDED FOR CONTEXT) — Task breakdown prompt rules used to structure this implementation plan.
- `README.md` (ADDED FOR CONTEXT) — Repository workflow guidance for PRD, breakdown, and execution sequencing.
- `mix.exs` (NEW) — Elixir/Phoenix project manifest and dependency baseline.
- `config/config.exs` (NEW) — Shared application configuration and module wiring defaults.
- `config/runtime.exs` (NEW) — Runtime configuration for environment-driven settings and limits.
- `.env.example` (NEW) — Local environment variable template.
- `docker-compose.yml` (NEW) — Local MongoDB and app runtime dependencies for development.
- `lib/ocpp_simulator/application.ex` (NEW) — OTP supervision tree root and subsystem startup order.
- `lib/ocpp_simulator/domain/charge_points/charge_point.ex` (NEW) — Charge point entity and behavior profile invariants.
- `lib/ocpp_simulator/domain/sessions/session_state_machine.ex` (NEW) — Session lifecycle transitions and transition guards.
- `lib/ocpp_simulator/domain/transactions/transaction_state_machine.ex` (NEW) — Transaction lifecycle transitions and invariants.
- `lib/ocpp_simulator/domain/scenarios/scenario.ex` (NEW) — Scenario aggregate model and step ordering rules.
- `lib/ocpp_simulator/domain/runs/scenario_run.ex` (NEW) — Scenario run aggregate and immutable snapshot metadata.
- `lib/ocpp_simulator/domain/ocpp/message.ex` (NEW) — OCPP message model and correlation identifiers.
- `lib/ocpp_simulator/domain/scenarios/variable_resolver.ex` (NEW) — Deterministic variable resolution service with scope precedence (`scenario < run < session < step`).
- `lib/ocpp_simulator/domain/ocpp/correlation_policy.ex` (NEW) — Outbound-call correlation tracking and timeout policy service.
- `lib/ocpp_simulator/domain/sessions/message_id_registry.ex` (NEW) — Per-session unique OCPP message-ID enforcement service.
- `lib/ocpp_simulator/application/contracts/` (NEW) — Behavior contracts for repositories, transport, and integration adapters.
- `lib/ocpp_simulator/application/use_cases/run_scenario.ex` (NEW) — Scenario execution orchestration use case.
- `.gitignore` (NEW) — Repository hygiene and exclusion rules for non-runtime artifacts.
- `lib/ocpp_simulator/application/use_cases/manage_target_endpoints.ex` (NEW) — Target CSMS endpoint and connection profile management use case.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/` (NEW) — MongoDB adapters for persistence contracts.
- `lib/ocpp_simulator/infrastructure/transport/websocket/session_manager.ex` (NEW) — WebSocket session lifecycle orchestration.
- `lib/ocpp_simulator/infrastructure/transport/websocket/outbound_queue.ex` (NEW) — Backpressure-aware outbound message queue and retry coordination.
- `lib/ocpp_simulator/infrastructure/serialization/ocpp_json/` (NEW) — OCPP frame serialization and strict schema validation.
- `lib/ocpp_simulator/infrastructure/integrations/webhook_dispatcher.ex` (NEW) — Webhook delivery orchestration with retry policies.
- `lib/ocpp_simulator/infrastructure/security/sensitive_data_masker.ex` (NEW) — Sensitive-field masking policy for logs and UI-safe error payloads.
- `lib/ocpp_simulator_web/router.ex` (NEW) — HTTP and LiveView route wiring with auth boundaries.
- `lib/ocpp_simulator_web/controllers/api/` (NEW) — Internal JSON API namespace for automation, import/export, and webhook configuration.
- `lib/ocpp_simulator_web/live/scenario_builder_live.ex` (NEW) — Dual-mode scenario authoring UI (visual + raw JSON).
- `lib/ocpp_simulator_web/live/live_console_live.ex` (NEW) — Live monitoring console and frame timeline view.
- `lib/ocpp_simulator_web/live/run_history_live.ex` (NEW) — Run history and replay entry views.
- `lib/ocpp_simulator_web/live/logs_live.ex` (NEW) — Logs viewer UI with filter, pagination, and correlation drill-down.
- `lib/ocpp_simulator_web/live/target_endpoints_live.ex` (NEW) — Target endpoint and connection profile management UI.
- `test/ocpp_simulator/` (NEW) — Domain, application, protocol, and infrastructure tests.
- `test/test_helper.exs` (NEW) — ExUnit bootstrap entrypoint.
- `test/ocpp_simulator/domain/charge_points/charge_point_test.exs` (NEW) — Charge point aggregate invariants coverage.
- `test/ocpp_simulator/domain/scenarios/scenario_test.exs` (NEW) — Scenario deterministic ordering and validation coverage.
- `test/ocpp_simulator/domain/scenarios/variable_resolver_test.exs` (NEW) — Variable scope precedence and placeholder resolution coverage.
- `test/ocpp_simulator/domain/runs/scenario_run_test.exs` (NEW) — Snapshot immutability and version-lock checks.
- `test/ocpp_simulator/domain/ocpp/message_and_correlation_policy_test.exs` (NEW) — OCPP frame mapping and correlation timeout policy coverage.
- `test/ocpp_simulator/domain/sessions/session_state_machine_test.exs` (NEW) — Session lifecycle and message-ID uniqueness coverage.
- `test/ocpp_simulator/domain/transactions/transaction_state_machine_test.exs` (NEW) — Transaction lifecycle transition invariants coverage.
- `test/ocpp_simulator_web/live/` (NEW) — Critical LiveView flow tests.
- `test/ocpp_simulator_web/controllers/api/` (NEW) — Internal JSON API behavior and envelope tests.
- `docs/ARCHITECTURE.md` (NEW) — Module boundaries, dependency direction, and extensibility guidance.
- `docs/SETUP.md` (NEW) — Local setup and run instructions.
- `docs/API.md` (NEW) — Internal JSON API contract and response envelope conventions.
- `CONTRIBUTING.md` (NEW) — Contributor workflow and development conventions.
- `CODE_OF_CONDUCT.md` (NEW) — OSS behavior standards.
- `LICENSE` (NEW) — MIT license file.
- `prompts/task-executor.md` (ADDED FOR CONTEXT) — Execution constraints and PRD update rules applied for this implementation batch.
- `package.json` (ADDED FOR CONTEXT) — Legacy prompt-package metadata reviewed during repository transition cleanup.
- `package-lock.json` (ADDED FOR CONTEXT) — Legacy dependency lock metadata reviewed during repository transition cleanup.
- `mix.lock` (NEW) — Dependency lockfile generated after fetching Elixir dependencies for deterministic test/runtime resolution.
- `lib/ocpp_simulator.ex` (NEW) — Root runtime configuration accessor used by bootstrap modules.
- `lib/ocpp_simulator/domain/boundary.ex` (NEW) — Domain layer namespace marker for modular-monolith boundaries.
- `lib/ocpp_simulator/domain/supervisor.ex` (NEW) — Domain boundary supervisor for startup ordering.
- `lib/ocpp_simulator/application/boundary.ex` (NEW) — Application layer namespace marker for orchestration boundary setup.
- `lib/ocpp_simulator/application/supervisor.ex` (NEW) — Application-layer task supervision boundary.
- `lib/ocpp_simulator/infrastructure/boundary.ex` (NEW) — Infrastructure layer namespace marker for adapter boundaries.
- `lib/ocpp_simulator/infrastructure/supervisor.ex` (NEW) — Infrastructure supervision boundary for adapter processes.
- `lib/ocpp_simulator_web.ex` (NEW) — Shared web macros and verified route helpers.
- `lib/ocpp_simulator_web/endpoint.ex` (NEW) — Phoenix endpoint wiring for HTTP and LiveView sockets.
- `lib/ocpp_simulator_web/telemetry.ex` (NEW) — Telemetry poller and baseline runtime metrics emission.
- `lib/ocpp_simulator_web/error_html.ex` (NEW) — HTML error rendering module.
- `lib/ocpp_simulator_web/error_json.ex` (NEW) — JSON error rendering module.
- `lib/ocpp_simulator_web/controllers/health_controller.ex` (NEW) — Health endpoints for browser and API pipelines.
- `lib/ocpp_simulator_web/live/dashboard_live.ex` (NEW) — Bootstrap LiveView dashboard shell for runtime verification.
- `lib/ocpp_simulator/application/contracts/charge_point_repository.ex` (NEW) — Charge point repository behavior contract for replaceable persistence adapters.
- `lib/ocpp_simulator/application/contracts/target_endpoint_repository.ex` (NEW) — Target endpoint repository behavior contract for connection profile storage.
- `lib/ocpp_simulator/application/contracts/scenario_repository.ex` (NEW) — Scenario repository behavior contract for lifecycle orchestration.
- `lib/ocpp_simulator/application/contracts/template_repository.ex` (NEW) — Action/scenario template repository behavior contract for reusable artifacts.
- `lib/ocpp_simulator/application/contracts/scenario_run_repository.ex` (NEW) — Scenario run repository behavior contract for queued/running/terminal lifecycle persistence.
- `lib/ocpp_simulator/application/contracts/transport_gateway.ex` (NEW) — Transport behavior contract for WebSocket session connect/disconnect/send operations.
- `lib/ocpp_simulator/application/contracts/webhook_dispatcher.ex` (NEW) — Webhook delivery behavior contract for terminal run events.
- `lib/ocpp_simulator/application/contracts/id_generator.ex` (NEW) — Cross-cutting utility contract for run/message ID generation.
- `lib/ocpp_simulator/application/contracts/clock.ex` (NEW) — Cross-cutting utility contract for UTC clock access.
- `lib/ocpp_simulator/application/contracts/structured_logger.ex` (NEW) — Cross-cutting utility contract for structured application logging.
- `lib/ocpp_simulator/application/policies/authorization_policy.ex` (NEW) — Central role/permission matrix for LiveView, use-case, and API authorization boundaries.
- `lib/ocpp_simulator/application/use_cases/manage_charge_points.ex` (NEW) — Charge point management use-case entrypoints with authorization + aggregate validation.
- `lib/ocpp_simulator/application/use_cases/manage_scenarios.ex` (NEW) — Scenario/template management use-case entrypoints with authorization + domain validation.
- `lib/ocpp_simulator_web/auth/current_role_plug.ex` (NEW) — Session/header role extraction plug used by browser/API pipelines.
- `lib/ocpp_simulator_web/auth/require_permission_plug.ex` (NEW) — Reusable permission-enforcement plug for API boundary protection.
- `lib/ocpp_simulator_web/auth/live_authorization.ex` (NEW) — LiveView `on_mount` authorization hook for management route gating.
- `lib/ocpp_simulator_web/controllers/api/management_controller.ex` (NEW) — Internal API management operations with role checks aligned to LiveView permissions.
- `lib/ocpp_simulator_web/controllers/api/run_controller.ex` (NEW) — Internal API run start/cancel operations with role checks aligned to use-case permissions.
- `lib/ocpp_simulator_web/live/charge_points_live.ex` (NEW) — Authorization-gated charge point management LiveView shell.
- `lib/ocpp_simulator_web/live/target_endpoints_live.ex` (NEW) — Authorization-gated target endpoint management LiveView shell.
- `lib/ocpp_simulator_web/live/scenarios_live.ex` (NEW) — Authorization-gated scenario management LiveView shell.
- `lib/ocpp_simulator_web/live/templates_live.ex` (NEW) — Authorization-gated template management LiveView shell.
- `lib/ocpp_simulator_web/live/run_operations_live.ex` (NEW) — Authorization-gated run operations LiveView shell.
- `test/ocpp_simulator/application/policies/authorization_policy_test.exs` (NEW) — Role/permission matrix behavior tests.
- `test/ocpp_simulator/application/use_cases/management_use_cases_test.exs` (NEW) — Charge point/endpoint/scenario/template use-case authorization + validation tests.
- `test/ocpp_simulator/application/use_cases/run_scenario_test.exs` (NEW) — Run orchestration tests for pre-run validation gating, snapshot persistence, and terminal webhook dispatch.
- `test/ocpp_simulator_web/router_authorization_test.exs` (NEW) — Router/API authorization boundary tests for browser session roles and API header roles.
- `lib/ocpp_simulator/application/contracts/log_repository.ex` (NEW) — Log repository behavior contract for paginated/filter-first log retrieval.
- `lib/ocpp_simulator/application/contracts/user_repository.ex` (NEW) — User repository behavior contract for account persistence.
- `lib/ocpp_simulator/application/contracts/webhook_endpoint_repository.ex` (NEW) — Webhook endpoint repository behavior contract for endpoint configuration storage.
- `lib/ocpp_simulator/application/contracts/webhook_delivery_repository.ex` (NEW) — Webhook delivery repository behavior contract for delivery lifecycle persistence.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/mongo_client.ex` (NEW) — Mongo operation behavior abstraction used by adapters.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/driver_client.ex` (NEW) — Default MongoDB driver-backed implementation of persistence client behavior.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/adapter.ex` (NEW) — Shared Mongo adapter helpers for connection options and CRUD primitives.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/document_mapper.ex` (NEW) — Isolated document/domain mapping logic for repository adapters.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/query_builder.ex` (NEW) — Pagination and filter builders for bounded run-history/log queries.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/indexes.ex` (NEW) — Collection index registry and index bootstrap helpers.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/repository_helpers.ex` (NEW) — Shared mapper/repository utility helpers.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/charge_point_repository.ex` (NEW) — Mongo adapter implementing charge point repository contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/target_endpoint_repository.ex` (NEW) — Mongo adapter implementing target endpoint repository contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/template_repository.ex` (NEW) — Mongo adapter implementing action/scenario template repository contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/scenario_repository.ex` (NEW) — Mongo adapter implementing scenario repository contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/scenario_run_repository.ex` (NEW) — Mongo adapter implementing run lifecycle + history pagination contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/user_repository.ex` (NEW) — Mongo adapter implementing user repository contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/log_repository.ex` (NEW) — Mongo adapter implementing log repository with filter-first pagination.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/webhook_endpoint_repository.ex` (NEW) — Mongo adapter implementing webhook endpoint repository contract.
- `lib/ocpp_simulator/infrastructure/persistence/mongo/webhook_delivery_repository.ex` (NEW) — Mongo adapter implementing webhook delivery repository contract.
- `test/ocpp_simulator/infrastructure/persistence/mongo/repositories_test.exs` (NEW) — Contract-level adapter integration coverage for Mongo repositories and index bootstrap.
- `test/ocpp_simulator/infrastructure/persistence/mongo/pagination_filter_test.exs` (NEW) — Run history/log pagination and filter-first behavior coverage.
- `test_support/in_memory_mongo_client.ex` (NEW) — In-memory Mongo client test double used by persistence adapter tests.
- `lib/ocpp_simulator/infrastructure/serialization/ocpp_json.ex` (NEW) — OCPP JSON frame encoder/decoder boundary used by transport and protocol tests.
- `lib/ocpp_simulator/infrastructure/serialization/ocpp_json/payload_validator.ex` (NEW) — Strict OCPP 1.6J payload schema validation for supported v1 actions.
- `lib/ocpp_simulator/infrastructure/transport/websocket/adapter.ex` (NEW) — Transport adapter behavior contract for connect/disconnect/frame send operations.
- `lib/ocpp_simulator/infrastructure/transport/websocket/noop_adapter.ex` (NEW) — Safe default transport adapter when no runtime WebSocket adapter is configured.
- `lib/ocpp_simulator/infrastructure/transport/websocket/remote_operation_handler.ex` (NEW) — State-aware inbound CSMS remote-operation strategy handler with correlated responses.
- `test/ocpp_simulator/infrastructure/serialization/ocpp_json_test.exs` (NEW) — Protocol coverage for strict serialization/deserialization, v1 action payload validation, and fault-frame behavior.
- `test/ocpp_simulator/infrastructure/transport/websocket/outbound_queue_test.exs` (NEW) — Backpressure, retry, and drop-behavior coverage for outbound queue dispatch.
- `test/ocpp_simulator/infrastructure/transport/websocket/session_manager_test.exs` (NEW) — Session lifecycle, reconnect retry, correlation, and inbound remote-command flow coverage.
- `test/ocpp_simulator/infrastructure/transport/websocket/remote_operation_handler_test.exs` (NEW) — Remote operation strategy acceptance/rejection and call-error behavior coverage.
- `lib/ocpp_simulator/application/use_cases/scenario_editor.ex` (NEW) — Dual-mode scenario editor conversion + round-trip normalization rules.
- `lib/ocpp_simulator/application/use_cases/starter_templates.ex` (NEW) — Starter scenario template catalog and seeding use case.
- `lib/ocpp_simulator/application/use_cases/import_export_artifacts.ex` (NEW) — Scenario/template import-export use case boundaries.
- `lib/ocpp_simulator_web/controllers/api/artifact_controller.ex` (NEW) — API interface boundary for scenario/template import-export and starter template seeding.
- `test/ocpp_simulator/application/use_cases/scenario_editor_test.exs` (NEW) — Round-trip conversion and schema-safe editor normalization coverage.
- `test/ocpp_simulator/application/use_cases/starter_templates_test.exs` (NEW) — Starter template catalog + permission-gated seeding coverage.
- `test/ocpp_simulator/application/use_cases/import_export_artifacts_test.exs` (NEW) — Scenario/template bundle import-export behavior coverage.
- `lib/ocpp_simulator_web/live/live_data.ex` (NEW) — Shared LiveView data helper for role checks, repository lookup, and normalized filter parsing used by Task 7 screens.

### 8. Open Questions / Concerns
All previously listed questions are resolved in this revision.

- No blocking open questions at this time.

### Task Breakdown
<task>

# Task 1 — Bootstrap project foundation and runtime skeleton
- [x] Task 1.1
Create the baseline Phoenix + LiveView project structure and dependency setup in `mix.exs`, `config/config.exs`, `config/runtime.exs`, `.env.example`, and `docker-compose.yml` so local development can start with MongoDB and application runtime services.

- [x] Task 1.2
Establish the modular-monolith directory layout and supervised startup boundaries in `lib/ocpp_simulator/application.ex`, `lib/ocpp_simulator/domain/`, `lib/ocpp_simulator/application/`, `lib/ocpp_simulator/infrastructure/`, and `lib/ocpp_simulator_web/`.

- [x] Task 1.3
Document bootstrap and local run flow in `docs/SETUP.md` to satisfy the acceptance criterion that developers can start the app and MongoDB locally.

- [x] Task 1.4
Define and execute repository transition boundaries in `.gitignore`, `README.md`, and `CONTRIBUTING.md` so planning artifacts (`bin/`, `prompts/`, `tasks/`, legacy bootstrap content) are excluded from the final simulator repository.

# Task 2 — Define domain entities, value objects, and state invariants
- [x] Task 2.1
Define core domain aggregates and value objects for charge points, sessions, scenarios, runs, and OCPP messages in `lib/ocpp_simulator/domain/charge_points/charge_point.ex`, `lib/ocpp_simulator/domain/scenarios/scenario.ex`, `lib/ocpp_simulator/domain/runs/scenario_run.ex`, and `lib/ocpp_simulator/domain/ocpp/message.ex`.

- [x] Task 2.2
Implement explicit lifecycle transitions and invalid-transition rejection in `lib/ocpp_simulator/domain/sessions/session_state_machine.ex` and `lib/ocpp_simulator/domain/transactions/transaction_state_machine.ex`, including correlation metadata on state transition events.

- [x] Task 2.3
Capture scenario version immutability and deterministic step ordering rules in domain modules so run snapshots remain reproducible across template/scenario revisions.

- [x] Task 2.4
Define and enforce domain-level services for variable resolution order, message correlation/timeout policy, and unique message-ID constraints per session.

# Task 3 — Build application contracts, use cases, and policy boundaries
- [x] Task 3.1
Create infra-agnostic behavior contracts in `lib/ocpp_simulator/application/contracts/` for repositories, transport, webhook delivery, and cross-cutting utilities so MongoDB and WebSocket adapters remain replaceable.

- [x] Task 3.2
Implement use-case entrypoints for charge point management, target endpoint/profile management, scenario/template management, and run lifecycle orchestration in `lib/ocpp_simulator/application/use_cases/`, including pre-run validation gating and frozen snapshot persistence requirements.

- [x] Task 3.3
Define authorization policy checks tied to run operations and management screens, and enforce them through `lib/ocpp_simulator_web/router.ex` and interface-layer auth hooks.

- [x] Task 3.4
Apply the same authorization boundaries to internal JSON API operations so automation endpoints follow role-based permissions consistent with LiveView flows.

# Task 4 — Implement MongoDB persistence adapter behind contracts
- [x] Task 4.1
Implement MongoDB adapters in `lib/ocpp_simulator/infrastructure/persistence/mongo/` for users, charge points, endpoints, templates, scenarios, runs, logs, webhook endpoints, and webhook deliveries while keeping mapping logic isolated from domain rules.

- [x] Task 4.2
Apply collection index and query strategy requirements for history views, logs viewer filters, and traceability use cases, then document collection/index conventions in `docs/ARCHITECTURE.md`.

- [x] Task 4.3
Add repository contract and adapter integration tests in `test/ocpp_simulator/` to verify persistence correctness and behavior-level compatibility.

- [x] Task 4.4
Implement and verify pagination/filter-first query patterns for run history and logs retrieval to prevent unbounded read patterns in monitoring screens.

# Task 5 — Implement OCPP 1.6J transport, correlation, and strict schema validation
- [x] Task 5.1
Implement WebSocket session lifecycle management in `lib/ocpp_simulator/infrastructure/transport/websocket/session_manager.ex` covering connect, disconnect, reconnect, retries, and lifecycle state synchronization.

- [x] Task 5.2
Implement strict OCPP frame serialization/deserialization and payload validation in `lib/ocpp_simulator/infrastructure/serialization/ocpp_json/` and `lib/ocpp_simulator/domain/ocpp/message.ex`, including Call/CallResult/CallError correlation by unique message IDs.

- [x] Task 5.3
Implement inbound remote-operation handling flow for CSMS commands (`RemoteStartTransaction`, `RemoteStopTransaction`, `TriggerMessage`, `Reset`, `ChangeAvailability`) with state-aware action strategy and correlated response emission.

- [x] Task 5.4
Implement backpressure-aware outbound message handling and retry coordination in `lib/ocpp_simulator/infrastructure/transport/websocket/outbound_queue.ex` to support bounded concurrency under load.

- [x] Task 5.5
Implement v1 action support coverage and protocol behavior tests in `test/ocpp_simulator/` for BootNotification, Heartbeat, StatusNotification, Authorize, StartTransaction, MeterValues, StopTransaction, remote control actions, reset, availability changes, trigger message, basic configuration management, and basic fault scenarios.

# Task 6 — Deliver scenario DSL, template lifecycle, and execution orchestration
- [x] Task 6.1
Define schema-versioned scenario/template structures and step semantics in `lib/ocpp_simulator/domain/scenarios/scenario.ex` with explicit support for ordered steps, delays, loops, variable substitution scopes, and strict validation policy defaults.

- [x] Task 6.2
Implement scenario run orchestration in `lib/ocpp_simulator/application/use_cases/run_scenario.ex` to handle queueing, execution, cancellation, timeout, step-level result persistence, terminal run states, and execution blocking when strict schema/state-transition validation fails.

- [x] Task 6.3
Implement dual-mode editor round-trip rules (visual builder model <-> raw JSON) with schema-safe conversion guarantees for the same scenario definition.

- [x] Task 6.4
Create and ship minimally OCPP-compliant starter templates for normal transaction, fault recovery, and remote-operation scenarios.

- [x] Task 6.5
Implement import/export capabilities for templates and scenarios through application and interface boundaries so reusable artifacts can move between environments.

- [x] Task 6.6
Clarify end-to-end run processing sequence for maintainers:
`(pseudo-code) create_run -> freeze_snapshot -> resolve_variables -> execute_steps -> persist_step_results -> finalize_run -> trigger_webhook`

# Task 7 — Build LiveView UI for management, authoring, and monitoring
- [x] Task 7.1
Implement authenticated LiveView route structure and role-aware access behavior in `lib/ocpp_simulator_web/router.ex` and auth-related LiveView modules.

- [x] Task 7.2
Implement management screens for dashboard, charge point registry, scenario library, and template library in `lib/ocpp_simulator_web/live/` with consistent filtering and state feedback.

- [x] Task 7.3
Implement target endpoint and connection profile management UI in `lib/ocpp_simulator_web/live/target_endpoints_live.ex`, including retry policy settings and validation messages.

- [x] Task 7.4
Implement `lib/ocpp_simulator_web/live/scenario_builder_live.ex` for dual-mode authoring (visual editor plus raw JSON editor), field-level validation, run-level validation summary, and request/response preview with correlation IDs.

- [x] Task 7.5
Implement `lib/ocpp_simulator_web/live/live_console_live.ex` and `lib/ocpp_simulator_web/live/run_history_live.ex` to provide live timeline diagnostics, frame detail panels, error reason visibility, and historical run replay entry points.

- [x] Task 7.6
Implement `lib/ocpp_simulator_web/live/logs_live.ex` as a dedicated logs viewer with pagination, filter-first search, and correlation-ID drill-down across run/session/message context.

# Task 8 — Deliver internal API, observability, security hardening, and webhook reliability
- [ ] Task 8.1
Implement internal JSON API endpoints in `lib/ocpp_simulator_web/controllers/api/` for automation-triggered runs, import/export flows, and webhook endpoint configuration, with a standardized response envelope and actionable error schema documented in `docs/API.md`.

- [ ] Task 8.2
Implement structured event logging and correlation fields across scenario, protocol, session, auth, and persistence events with storage support in `lib/ocpp_simulator/infrastructure/persistence/mongo/`.

- [ ] Task 8.3
Implement sensitive-data masking defaults in `lib/ocpp_simulator/infrastructure/security/sensitive_data_masker.ex` and ensure logs/error payloads avoid exposing secrets, credentials, and token-like values.

- [ ] Task 8.4
Implement webhook endpoint configuration and delivery processing in `lib/ocpp_simulator/infrastructure/integrations/webhook_dispatcher.ex`, including retries, failure tracking, completion/failure triggers, and request signature validation.

- [ ] Task 8.5
Expose and document configurable concurrency limits, retry/backoff policy, connection pool/backpressure controls, and performance-related runtime controls through `config/runtime.exs` and `docs/SETUP.md`.

# Task 9 — Complete quality gates, tests, and OSS-grade documentation
- [ ] Task 9.1
Implement comprehensive test coverage in `test/ocpp_simulator/` and `test/ocpp_simulator_web/live/` across domain invariants, protocol handling, orchestration behavior, repository adapters, auth boundaries, and critical UI flows.

- [ ] Task 9.2
Add end-to-end integration coverage for at least one realistic transaction scenario proving real-time visibility and post-run historical queryability from LiveView interfaces.

- [ ] Task 9.3
Add explicit test cases for schema-safe visual/JSON round trip, validation-gated execution blocking, and actionable UI error display when schema/state-transition checks fail.

- [ ] Task 9.4
Add webhook reliability/security tests for retry behavior, failure visibility, signature validation, and secret-handling safety in logging.

- [ ] Task 9.5
Add non-functional tests for bounded concurrency, WebSocket backpressure behavior, and logs/history pagination performance baselines.

- [ ] Task 9.6
Produce OSS documentation and governance files in `README.md`, `docs/ARCHITECTURE.md`, `docs/SETUP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, and `LICENSE`, including extension guidance for new OCPP actions, step types, and persistence adapters.

</task>

### Changes Summary
- Implemented Task `2.1` domain aggregates/value objects for charge points, scenarios, scenario runs, and OCPP messages with explicit constructor validation and OCPP frame conversion rules.
- Implemented Task `2.2` explicit session and transaction lifecycle state machines that reject invalid transitions and emit transition events carrying correlation metadata.
- Implemented Task `2.3` deterministic scenario step normalization plus scenario-run frozen snapshot/version guards (`ensure_scenario_version/2`, `verify_snapshot/2`) to preserve reproducibility.
- Implemented Task `2.4` domain services for deterministic variable resolution order, outbound call correlation + timeout policy, and per-session message-ID uniqueness enforcement.
- Added focused ExUnit coverage for all implemented invariants/services and validated with `mix test` (`20` tests passing).
- Assumption: installing Hex/dependencies and generating `mix.lock` in this environment is acceptable to enable compile/test verification.
- Implemented Task `3.1` by introducing infra-agnostic application contracts for repositories, transport gateway, webhook delivery, and cross-cutting utilities (`id_generator`, `clock`, `structured_logger`).
- Implemented Task `3.2` by adding use-case entrypoints for charge points, target endpoints, scenarios/templates, and run lifecycle orchestration with explicit pre-run validation gating and snapshot persistence via `ScenarioRun.new/1`.
- Implemented Task `3.3` by adding a centralized authorization policy and enforcing role-gated management screens through router `live_session` boundaries plus a LiveView `on_mount` auth hook.
- Implemented Task `3.4` by enforcing equivalent role boundaries in internal JSON API operations using shared role resolution/permission checks and API role-protected controllers.
- Added focused Task 3 test coverage (application policy/use-cases + router/API authorization) and validated with `mix test` (`43` tests passing).
- Assumption: until full Phoenix auth flows are delivered in later tasks, role context is sourced from session key `current_role` (browser) or header `x-ocpp-role` (API) for boundary enforcement.
- Implemented Task `4.1` by adding Mongo persistence adapters for users, charge points, target endpoints, templates, scenarios, scenario runs, logs, webhook endpoints, and webhook deliveries, with conversion logic isolated in `DocumentMapper`.
- Implemented Task `4.2` by codifying collection/index conventions in `lib/ocpp_simulator/infrastructure/persistence/mongo/indexes.ex` and documenting index/query strategy in `docs/ARCHITECTURE.md`.
- Implemented Task `4.3` by adding repository-contract integration tests in `test/ocpp_simulator/infrastructure/persistence/mongo/repositories_test.exs` using an in-memory Mongo test client.
- Implemented Task `4.4` by adding bounded pagination + filter-first query paths for run history/log retrieval (`ScenarioRunRepository.list_history/1`, `LogRepository.list/1`) with dedicated coverage in `test/ocpp_simulator/infrastructure/persistence/mongo/pagination_filter_test.exs`.
- Validation: full test suite passes with `mix test` (`59` tests passing).
- Assumption: persistence adapter tests run against an in-memory Mongo client double (`test_support/in_memory_mongo_client.ex`) to validate contract behavior without requiring an external MongoDB instance during CI/local test runs.
- Implemented Task `5.1` with a supervised WebSocket session manager that handles connect/disconnect/reconnect flows, retry scheduling with exponential backoff, lifecycle synchronization via the domain session state machine, and correlation-timeout expiration helpers.
- Implemented Task `5.2` by adding strict OCPP JSON codec + payload validator modules and extending domain OCPP messages with supported-action metadata and correlation helper predicates for call/response matching.
- Implemented Task `5.3` by adding inbound CSMS remote-operation strategy handling (`RemoteStartTransaction`, `RemoteStopTransaction`, `TriggerMessage`, `Reset`, `ChangeAvailability`) that emits correlated `CallResult`/`CallError` responses with state-aware accept/reject behavior.
- Implemented Task `5.4` by introducing a bounded outbound queue worker with in-flight limits, backpressure rejection, async dispatch, retry coordination, and terminal drop accounting when retry budgets are exhausted.
- Implemented Task `5.5` with focused protocol/transport coverage in new tests for v1 action payload validation, fault/call-error behavior, remote-operation strategy outcomes, outbound queue backpressure/retry semantics, and session lifecycle + correlation flows.
- Validation: full test suite passes with `mix test` (`82` tests passing, `1` skipped).
- Assumption: runtime WebSocket I/O remains adapter-driven for now (`transport adapter` behavior + default `NoopAdapter`), enabling protocol/session verification without introducing a concrete network client in this task batch.
- Implemented Task `6.1` by extending the scenario aggregate with schema-versioned template payload helpers, explicit variable scope ordering, strict validation policy defaults, and step-type semantics checks (ordered steps, delays, loops, supported actions).
- Implemented Task `6.2` by extending run orchestration with `execute_run/4` to process queued/running lifecycle, resolve variables per step, enforce strict schema/state-transition validation gates, persist step-level results, handle timeout/cancellation, and finalize terminal states with webhook dispatch.
- Implemented Task `6.3` by adding dual-mode editor conversion in `ScenarioEditor` (`visual <-> raw JSON`) with round-trip normalization through domain schema validation.
- Implemented Task `6.4` by adding a starter template catalog + seed use case that ships minimally OCPP-compliant scenario templates for normal transaction, fault recovery, and remote-operation flows.
- Implemented Task `6.5` by adding scenario/template import-export use cases and API interface routes/controllers for export/import + starter-template seeding.
- Implemented Task `6.6` by documenting and aligning the run-processing sequence (`create_run -> freeze_snapshot -> resolve_variables -> execute_steps -> persist_step_results -> finalize_run -> trigger_webhook`) in architecture docs and run-use-case module docs.
- Added focused Task 6 tests for scenario semantics, execution orchestration outcomes, editor round-trip guarantees, starter template coverage, artifact import/export behavior, and API routing/authorization behavior for artifact endpoints.
- Validation: full test suite passes with `mix test` (`104` tests passing, `1` skipped).
- Assumption: strict OCPP schema checks in run execution are currently applied to `send_action` steps, using nested `payload` when provided (or action-level payload fields when nested payload is omitted).
- Implemented Task `7.1` by refactoring LiveView route sessions to explicit view/manage boundaries and extending `LiveAuthorization` to assign role grants used for role-aware UI behavior.
- Implemented Task `7.2` by replacing placeholder dashboard/registry/library LiveViews with data-backed screens (`DashboardLive`, `ChargePointsLive`, `ScenariosLive`, `TemplatesLive`) that provide consistent filter forms, result feedback, and role-aware management affordances.
- Implemented Task `7.3` by extending `TargetEndpointsLive` with endpoint/profile filters plus managed create form validation (including retry max attempts/backoff settings and `ws://` URL validation).
- Implemented Task `7.4` with a new `ScenarioBuilderLive` supporting visual/raw authoring mode switching, top-level field validation, run-level validation summary via domain/use-case checks, and request/response correlation preview rows.
- Implemented Task `7.5` with new `LiveConsoleLive` and `RunHistoryLive` pages providing timeline diagnostics, frame-detail/error-reason visibility, pagination, and replay entry actions.
- Implemented Task `7.6` with new `LogsLive` filter-first viewer enforcing search criteria before query execution, paginated result browsing, and correlation drill-down shortcuts.
- Added focused Task 7 web routing/authorization coverage in `test/ocpp_simulator_web/router_authorization_test.exs`, including scenario-builder role gating, management-screen rendering, and monitoring route behavior.
- Validation: full test suite passes with `mix test` (`113` tests passing, `1` skipped).
- Assumption: until full user identity/session auth flows are implemented, `current_role` in session remains the authenticated role source for LiveView route and UI permission behavior.
