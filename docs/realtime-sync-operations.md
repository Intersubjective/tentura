# Realtime synchronization operations

This runbook covers the `entity_changes` PG LISTEN/WebSocket path and client
catch-up behavior. The protocol inventory is machine-readable in
[`contracts/realtime-entity-contract.json`](contracts/realtime-entity-contract.json);
architecture and PG tests enforce it.

## What healthy looks like

- A committed state-bearing mutation emits a bounded PG envelope for every
  affected account, including the actor, with no private content.
- Every worker has its own PG LISTEN connection and fans out only to its local
  authenticated sessions.
- Connected projections silently converge within 1.5 seconds p95 locally or on
  staging. Reconnect/resume catch-up converges within 3 seconds p95.
- A semantic mutation starts at most one fetch per active projection, with at
  most one queued rerun. Existing content stays visible during background sync.
- A brief disconnect is invisible. After two seconds the client shows the
  non-blocking live-updates-paused banner; it clears after authentication.

## Actor echo compatibility switch

`REALTIME_ACTOR_ECHO_ENABLED` defaults to `true`, so every active session of an
actor's account receives the same invalidation and converges across tabs and
devices. Set it to `false` only as a compatibility rollback.

The switch is deliberately narrow: filtering requires a non-null
`actor_user_id`, which is populated by server-mediated writes using
`TenturaDb.withMutatingUser`. Direct Hasura mutations do not set that PostgreSQL
GUC and continue to echo to the actor even when the switch is `false`. Therefore
`false` is not a global actor-echo disable; it temporarily creates asymmetric
convergence and should not be treated as a steady-state configuration.

## Stable server log fields

Realtime logs use a searchable `realtime_event` marker and contain counts, not
recipient IDs or payload content.

| Marker | Useful fields | Meaning |
|---|---|---|
| `realtime_event=fanout` | `kind`, `recipients`, `direct_sessions`, `frames`, `actor_echo` | one validated PG envelope was routed |
| `realtime_event=malformed_payload` | `reason` | invalid envelope was dropped |
| `realtime_event=payload_failure` | `error` | PG payload could not be decoded/routed |
| `realtime_event=listener_error` / `listener_closed` | — | worker lost its LISTEN connection |
| `realtime_event=reconnect_scheduled` | `delay_ms`, `attempt` | listener backoff |
| `realtime_event=reconnected` | `sequence` | listener recovered |
| `realtime_event=listener_recovered` | `sequence`, `sessions`, `isolate` | isolate-local catch-up broadcast |
| `attention_event=receipt_created` | `event_type`, `recipients`, `occurrence_at` | one attention occurrence was persisted |
| `attention_event=head_refresh_latency` | `latency_ms`, `receipt_created_at` | QA-only client head refresh measurement |

Local log queries:

```bash
rg 'realtime_event=' /tmp/tentura-api.log
rg 'attention_event=' /tmp/tentura-api.log
rg 'realtime_event=(listener_error|reconnect_failed|payload_failure)' /tmp/tentura-api.log
rg 'realtime_event=fanout.*frames=0' /tmp/tentura-api.log
rg 'realtime_event=fanout.*kind=(relationship|profile)' /tmp/tentura-api.log
```

For container logs, replace the file with `docker compose logs --since=30m api`.
In Sentry Discover/Logs, use the same terms, for example
`message:"realtime_event=fanout"` grouped by parsed `kind`, or
`message:"realtime_event=reconnect_failed"` grouped by release/environment.

## Dashboards and alerts

Create three log-derived dashboards per environment:

1. **Delivery:** fanout envelopes and frames by kind; `frames=0` ratio; malformed
   and payload-failure counts; p95 mutation-to-visible timing from integration
   artifacts.
2. **Recovery:** listener errors, reconnect attempts/failures, recovery sequence,
   sessions notified, and client reconnect/catch-up duration.
3. **Database transport pressure:** notification queue usage, sustained NOTIFY
   commit-lock waiters, and p95 write-transaction commit latency.

Alert when any of these holds for five minutes:

- listener recovery does not follow an error/closure within 30 seconds;
- malformed/payload failures exceed 1% of fanout envelopes;
- connected convergence p95 exceeds 1.5 seconds or reconnect convergence p95
  exceeds 3 seconds (receipt commit → Updates card visible; see Updates delivery
  budget);
- duplicate stable IDs/effects appear in the multi-client test;
- PostgreSQL notification queue usage reaches 0.25 (warning) or 0.50 (critical).

Sample the queue on every database instance:

```sql
SELECT pg_notification_queue_usage();
```

Queue exhaustion can fail the transaction at commit. Treat rising usage as a
database incident; do not swallow it in trigger exception handling.

## Local verification

Prerequisites and runner ownership are detailed in
[`local-integration-tests.md`](local-integration-tests.md). Use the repository
commands so QA endpoints, ChromeDriver, and cleanup stay scoped correctly.

```bash
# Layer and protocol contracts
cd packages/server && dart test test/architecture/realtime_entity_contract_test.dart
cd packages/server && dart test --tags pg test/data/database/realtime_notification_migration_test.dart
cd packages/client && flutter test test/architecture/realtime_entity_contract_test.dart
cd packages/client && flutter test test/data/service/invalidation_service_test.dart

# Existing real single-client journeys
bash scripts/run_client_integration_web_local.sh

# Simultaneous author/helper sessions plus forced missed-event recovery
bash scripts/run_realtime_multiclient_web_local.sh
```

For interactive browser diagnosis, use the normal local Caddy origin
`https://dev.lvh.me:9443` so auth-cookie behavior matches the supported setup.
Inspect semantics/DOM text and browser/server logs; do not reload or navigate
away to manufacture convergence. The automated runner owns a separate
Flutter-driver origin as documented in `local-integration-tests.md`.

The multi-client runner must pass five consecutive times before release and
must fail when live delivery/catch-up is deliberately disabled. It keeps failure
screenshots, browser console, server log, and timing artifacts; successful runs
do not retain screenshots.

## Updates T-07 Budget Evidence

The server migration proof in
`packages/server/test/data/database/realtime_notification_migration_test.dart`
acknowledges 1, 50, and 500 `notification_outbox` rows in separate SQL statements.
Each statement emits exactly one account-scoped `notification` envelope. This prevents
the old row-trigger fan-out during bulk acknowledgement.

`ATTENTION_V1_SHADOW_ENABLED=true` enables transition-only server telemetry for legacy
Notification Center reads. It compares the same guarded legacy page against the
authorized attention page, reports expected `authorization`, `new_class`, and `mute`
deltas separately, and emits `attention_event=shadow_mismatch` only for unexplained or
dual-read-axis divergence. Logs contain aggregate counts only.

The client half of the budget, at most one in-flight attention refresh plus one queued
rerun per open client, is implemented and measured with the `AttentionCase` in T-08.
Do not treat the PG-only result as client convergence proof.

## Updates delivery budget

This is the same budget as connected/reconnect convergence above — one target,
not a second one. Measure **receipt commit → Updates card visible** (creation to
render), including the attention receipt leg after the `entity_changes` hint.

| Path | p95 target | Measurement |
|---|---|---|
| Connected convergence | ≤ 1.5 s | `attention_event=head_refresh_latency` in QA builds (`QA_INTEGRATION_TEST_MODE=true`); multiclient `proof.json` in release |
| Reconnect catch-up | ≤ 3 s | same, after forced miss + reconnect in the multiclient runner |

Server-side receipt creation logs `attention_event=receipt_created` with
`event_type`, `recipients` (count only), and `occurrence_at`. Realtime logs and
attention telemetry contain counts and timestamps only — never recipient IDs,
titles, bodies, or excerpts.

When refresh fails, the Updates feed keeps existing items visible and shows a
non-blocking retry banner. A sustained WebSocket outage is covered separately by
the live-updates-paused banner (`RealtimeStatusPresenter`); do not duplicate that
for disconnects.

**#102 gate evidence** (2026-08-05, revision `5835f427`, five consecutive runs):
`packages/client/reports/realtime-multiclient/updates-102-20260805/proof.json` —
`my_work_102_delivery_ms` p95 **590 ms**, `my_work_102_qa_head_refresh_latency_ms`
p95 **223 ms**, `attention_reconnect_catch_up_ms` p95 **304 ms** (budgets 1500 ms /
3000 ms). Negative proofs (`live`, `catch_up`) failed as expected when delivery
was deliberately disabled.

## Incident triage

1. Confirm the HTTP mutation committed and identify its canonical wire kind in
   the manifest.
2. Check for `fanout` on every worker. No envelope points to the trigger or
   recipient query; an envelope with zero frames points to session targeting.
3. Check `actor_echo`. A false value is the compatibility kill switch and may
   intentionally exclude all sessions of the actor account for server-mediated
   mutations; Hasura mutations without `actor_user_id` remain echoed.
4. Check listener recovery markers and `pg_notification_queue_usage()`.
5. Confirm the client authenticated a new connection epoch and emitted catch-up.
6. For Updates: check `attention_event=receipt_created` on the API worker, then
   `attention_event=head_refresh_latency` (QA) or multiclient timing artifacts;
   confirm connected p95 ≤ 1.5 s and reconnect catch-up p95 ≤ 3 s.
7. Verify the affected Cubit kept its existing snapshot and did not discard a
   newer generation for a stale response.
8. If the feed is stale but the socket is healthy, check for a refresh failure
   banner (HTTP/GraphQL fetch error), not the live-updates-paused banner.
