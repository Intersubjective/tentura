# Episode closure release — deploy runbook (A24)

Release sequence (one maintenance window; testers only):

1. Stop the web client (maintenance page) and server workers.
2. Apply migrations `m0202`, `m0203`.
3. Apply Hasura metadata without `beacon_review_window` and without any closure table.
4. Start the server (runs pgmer2 upgrade, then `TrustCutoverCase`, then workers).
5. Deploy the web client built with the new GraphQL schema; bump `packages/client/pubspec.yaml` version and the `packages/client/web/index.html` bootstrap cache-buster; raise `kDefaultMinClientVersion` (S/env.dart:79) to the new version (keep `release_client_version_floor_test` green).

## After deploy

- Confirm `trust_cutover_state.status = 'done'`.
- Confirm queue depth near 0.
