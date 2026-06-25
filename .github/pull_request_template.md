## Summary

<!-- What changed and why -->

## Test plan

- [ ] Server unit tests (PR CI): `cd packages/server && dart test --exclude-tags pg`
- [ ] Client tests: `cd packages/client && flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env`
- [ ] **Postgres integration** (`@Tags(['pg'])`): **not** run in PR CI — use locally:
  ```bash
  docker compose up -d meritrank postgres
  cd packages/server && dart test --tags pg
  ```
  Nightly workflow [pg-integration-nightly.yml](.github/workflows/pg-integration-nightly.yml) runs these on `main` (03:00 UTC) and via **workflow_dispatch**.

## Coverage backlog

If this PR closes an item from [`docs/test-coverage-misses.md`](../docs/test-coverage-misses.md), note the ID (e.g. COV-042) in the summary and set `status: done` in that file.
