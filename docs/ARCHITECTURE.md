# Architecture Guide

## Persistence Boundary

MongoDB persistence is implemented only in `lib/ocpp_simulator/infrastructure/persistence/mongo/`.

- Domain rules stay in domain modules (`ChargePoint`, `Scenario`, `ScenarioRun`, etc.).
- Mongo adapters only map values and execute database operations behind application contracts.
- Document conversion is centralized in `DocumentMapper` to avoid persistence rules spreading across repositories.

## Collections

The Mongo adapter currently persists to these collections:

- `users`
- `charge_points`
- `target_endpoints`
- `action_templates`
- `scenarios`
- `scenario_runs`
- `logs`
- `webhook_endpoints`
- `webhook_deliveries`

## Index Conventions

Index definitions are centralized in `OcppSimulator.Infrastructure.Persistence.Mongo.Indexes`.

Required indexes:

- `users`
- `users_id_unique` (`id`, unique)
- `users_email_unique` (`email`, unique)

- `charge_points`
- `charge_points_id_unique` (`id`, unique)
- `charge_points_vendor_model_idx` (`vendor`, `model`)

- `target_endpoints`
- `target_endpoints_id_unique` (`id`, unique)
- `target_endpoints_url_unique` (`url`, unique)

- `action_templates`
- `templates_id_type_unique` (`id`, `type`, unique)
- `templates_name_type_version_idx` (`name`, `type`, `version desc`)

- `scenarios`
- `scenarios_id_unique` (`id`, unique)
- `scenarios_name_version_idx` (`name`, `version desc`)

- `scenario_runs`
- `scenario_runs_id_unique` (`id`, unique)
- `scenario_runs_history_idx` (`scenario_id`, `created_at desc`)
- `scenario_runs_state_idx` (`state`, `created_at desc`)

- `logs`
- `logs_id_unique` (`id`, unique)
- `logs_run_timestamp_idx` (`run_id`, `timestamp desc`)
- `logs_session_timestamp_idx` (`session_id`, `timestamp desc`)
- `logs_charge_point_timestamp_idx` (`charge_point_id`, `timestamp desc`)
- `logs_message_timestamp_idx` (`message_id`, `timestamp desc`)

- `webhook_endpoints`
- `webhook_endpoints_id_unique` (`id`, unique)

- `webhook_deliveries`
- `webhook_deliveries_id_unique` (`id`, unique)
- `webhook_deliveries_run_status_idx` (`run_id`, `status`, `created_at desc`)

## Query Strategy: Paginated Lists

Repository `list/1` and `list_history/1` queries are page-aware and bounded by default:

- Every list returns pagination metadata (`entries`, `page`, `page_size`, `total_entries`, `total_pages`).
- Pagination parameters (`page`, `page_size`) are accepted on every list call.
- `page_size` is capped per repository (`scenario_runs` max `100`, `logs` max `500`, config tables max `200`).
- Sorting is explicit (`created_at` / `timestamp` descending by default).
- Filter + count are executed separately to preserve deterministic metadata.

### Run History

`ScenarioRunRepository.list_history/1` uses:

- optional filters: `run_id`, `scenario_id`, `state|states`, `created_from`, `created_to`
- default sort: `created_at desc`
- indexed access paths through `scenario_runs_history_idx` and `scenario_runs_state_idx`

### Logs Viewer

`LogRepository.list/1` uses:

- correlation filters: `run_id`, `session_id`, `charge_point_id`, `message_id`
- optional qualifiers: `event_type`, `severity`, `from`, `to`
- filter-first enforcement by default (unfiltered scans are rejected unless explicitly allowed)
- default sort: `timestamp desc`

## Scenario Run Processing Sequence

Maintainer reference sequence used by run orchestration:

```text
create_run
-> freeze_snapshot
-> resolve_variables
-> execute_steps
-> persist_step_results
-> finalize_run
-> trigger_webhook
```

Run lifecycle notes:

- `create_run` persists state `queued` with an immutable scenario snapshot.
- `freeze_snapshot` ensures execution uses the run snapshot, not mutable latest scenario state.
- `resolve_variables` applies deterministic scope precedence (`scenario < run < session < step`).
- `execute_steps` enforces step semantics, delay/loop behavior, and strict validation policy defaults.
- `persist_step_results` updates run metadata after each executed step for timeline traceability.
- `finalize_run` transitions state to `succeeded`, `failed`, `canceled`, or `timed_out`.
- `trigger_webhook` dispatches terminal run events through the configured webhook dispatcher.

## Index Bootstrap

At runtime, index bootstrap is started automatically when both flags are enabled:

- `:mongo_autostart`
- `:mongo_index_bootstrap`

To apply all indexes manually, call:

- `OcppSimulator.Infrastructure.Persistence.Mongo.Indexes.ensure_all/0`
- `mix ocpp.mongo.ensure_indexes`

To apply only one collection’s indexes:

- `OcppSimulator.Infrastructure.Persistence.Mongo.Indexes.ensure_collection/1`
- `mix ocpp.mongo.ensure_indexes <collection>`
