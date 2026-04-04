# Contributing

Thanks for contributing to the OCPP 1.6J Charge Point Simulator.

## Development Workflow

1. Create a branch from `main`.
2. Implement a focused change set.
3. Run formatter and tests locally.
4. Open a pull request with:
   - scope summary
   - test evidence
   - migration/setup impact
5. Confirm governance files are respected:
   - `CODE_OF_CONDUCT.md`
   - `LICENSE`

## Local Commands

```bash
mix setup
mix format
mix test
```

## Repository Boundaries

The runtime source of truth is under:
- `lib/`
- `config/`
- `docs/`
- `test/` (when present)

The following are migration/planning artifacts and must be excluded from simulator release commits:
- `bin/`
- `prompts/`
- `tasks/`
- legacy prompt-package metadata (`package.json`, `package-lock.json`)

If you use local planning artifacts while developing, keep them out of commits.

## Coding Rules

- Keep domain modules infrastructure-agnostic.
- Depend inward: web/interface -> application -> domain.
- Implement adapters in infrastructure behind contracts.
- Prefer explicit names and small, testable functions.

## Extension Checklist

When adding features, keep this checklist aligned with architecture boundaries:

1. New OCPP action:
   - add/extend schema validation
   - add protocol + orchestration tests
   - update starter templates/docs if action is user-facing.
2. New scenario step type:
   - update `Scenario` validation + `RunScenario` execution semantics
   - maintain visual/JSON round-trip support
   - add actionable UI validation coverage.
3. New persistence adapter:
   - implement application contracts
   - keep domain/application modules unchanged
   - pass repository contract tests.
