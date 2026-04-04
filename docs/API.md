# Internal API Guide

This document defines the internal JSON API used for automation-triggered runs, artifact import/export, and webhook endpoint configuration.

## Base URL

- Local: `http://localhost:4000/api`

## Authentication and Authorization

- API requests use the same role model as LiveView routes.
- Role is resolved from session (`current_role`) by default.
- `x-ocpp-role` header is ignored unless `allow_untrusted_role_header=true`.
- All API routes are protected by `:api_automation` permission plus action-specific permission checks.

## Standard Response Envelope

Every API response uses this envelope:

```json
{
  "ok": true,
  "data": {},
  "error": null,
  "meta": {
    "request_id": "..."
  }
}
```

Error responses:

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "invalid_field",
    "message": "One or more fields are invalid.",
    "details": {
      "field": "scenario_id",
      "detail": "must_be_non_empty_string"
    }
  },
  "meta": {
    "request_id": "..."
  }
}
```

## Error Code Semantics

- `forbidden`: actor role is not allowed for the action.
- `not_found`: requested resource ID does not exist.
- `invalid_arguments`: request payload shape is invalid.
- `invalid_field`: one field failed validation.
- `pre_run_validation_failed`: scenario run blocked by validation gates.
- `scenario_version_mismatch`: requested scenario version does not match latest persisted version.
- `run_not_executable`: run state does not allow execution.
- `invalid_transition`: requested run transition is invalid.
- `concurrency_limit_reached`: configured concurrent run limit is reached.
- `missing_dependency`: required server dependency is not configured.
- `invalid_request`: fallback error when no specialized mapping exists.

## Routes

### Health

- `GET /health`

### Management

- `POST /charge-points`
- `POST /target-endpoints`
- `POST /scenarios`
- `POST /templates`

### Runs

- `POST /runs`
  - Required: `scenario_id`
  - Optional:
    - `run_id`
    - `scenario_version`
    - `metadata`
    - `execute_after_start` (`true|false`)
    - `timeout_ms` (used only when `execute_after_start=true`)
- `POST /runs/:id/cancel`

### Artifacts

- `GET /scenarios/export`
- `POST /scenarios/import`
- `GET /templates/export`
- `POST /templates/import`
- `POST /templates/starter`

### Webhooks

- `GET /webhooks/endpoints`
- `POST /webhooks/endpoints`
  - Required fields:
    - `id`
    - `name`
    - `url` (`http://` or `https://`)
    - `events` (non-empty list of strings)
  - Optional fields:
    - `retry_policy.max_attempts`
    - `retry_policy.backoff_ms`
    - `metadata`
    - `secret_ref`

## Webhook Delivery Behavior

- Terminal run events dispatched:
  - `run.succeeded`
  - `run.failed`
  - `run.canceled`
  - `run.timed_out`
- Delivery lifecycle is persisted in `webhook_deliveries`:
  - `queued -> retrying -> delivered|failed`
- Retry and backoff use endpoint policy with runtime defaults fallback.
- Requests are signed with HMAC-SHA256 when `secret_ref` is provided:
  - `x-ocpp-webhook-signature-alg: hmac-sha256`
  - `x-ocpp-webhook-signature: <hex signature>`
