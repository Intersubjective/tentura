# Nested requests and General-only discussions — implementation journal

Objective: implement `docs/plans/nested-requests-implementation-plan.md` (revision 2)
end to end, task by task, per the plan's execution contract (§1) and ordered work
packets (§7). Architecture source: `docs/plans/nested-requests-architecture.md`.

Orchestrator: Claude Code overseer skill, driving fresh `cursor-agent --model composer-2.5`
workers, one at a time, no `--resume`/`--continue`.

## Repository state at orchestration start

- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `main`
- Starting HEAD: `104786666 fix(client): ignore EvaluationCubit emits after dispose` (2026-09-06 13:57:28 +0200)
- Latest migration at plan baseline: `m0153`. Confirmed still latest at orchestration start.
- `cursor-agent` version `2026.09.02-c22c1a3`, logged in, `composer-2.5` (non-fast) confirmed available via `--list-models`.
- Local infra confirmed running: `postgres` (5432, healthy), `hasura`, `meritrank`, `minio`, `pgadmin` (docker compose).
- Postgres admin credentials available via root `.env` (`POSTGRES_HOST=127.0.0.1`, `POSTGRES_PORT=5432`, `POSTGRES_USERNAME=postgres`, password present, not logged). `packages/server/.env` was empty/absent of POSTGRES_* keys — workers must load root `.env` or export vars explicitly per §8's representative invocation.

### Pre-existing worktree changes at orchestration start (NOT owned by this plan; preserve, do not stash/reset/commit)

```
 M docs/README.md
?? CLAUDE.local.md
?? dart-defines
?? docs/plans/algorithm-invariant-suites-plan.md
?? docs/plans/availability-request-receptiveness-architecture.md
?? docs/plans/availability-request-receptiveness-implementation-plan.md
?? docs/plans/availability-review-codex.md
?? docs/plans/availability-review-grok46.md
?? docs/plans/availability-review-kimik3.md
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-110-forward-explicit-architecture.md
?? docs/plans/issue-110-forward-explicit-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/mention-without-handle-plan.md
?? docs/plans/mention-without-handle-review-sol.md
?? docs/plans/nested-requests-architecture.md
?? docs/plans/nested-requests-implementation-plan.md   (now also this journal, added by orchestration)
?? docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md
?? docs/plans/post-request-evaluation-detail-sheet-plan.md
?? docs/plans/received-reviews-trust-changes-plan.md
?? docs/plans/request-threads-architecture.md
?? docs/plans/request-threads-implementation-plan.md
?? docs/plans/subjective-help-tag-evidence-architecture.md
?? docs/plans/subjective-help-tag-evidence-implementation-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
?? reports/
?? tg_style_research.md
```

Workers must stage/commit only task-owned paths (new/changed files each task names).
Never `git add -A`, never touch the files above except `docs/plans/nested-requests-*`
which this plan/orchestration owns.

## User-approved run parameters (2026-09-06)

- Run continuously through all 16 tasks (00–15) without per-task check-in; only stop
  for genuine blockers or plan/live-code contradictions requiring a product decision.
- Task 09 (irreversible-shaped legacy cleanup migration): follow the plan exactly as
  written — disposable/uniquely-named test databases only, migration-upgrade fixture,
  backup/restore rehearsal documented but not executed against real data, no production
  activation. No extra manual-hold gate beyond the plan's own acceptance criteria.

## Ordered work manifest (from plan §7, dependencies as stated)

| # | Task | Depends on | Status |
|---|---|---|---|
| 00 | Inventory, journal, and fixture harness | none | complete |
| 01 | Pure contracts and policies | 00 | complete |
| 02 | Additive hierarchy storage and repository adapter | 01 | complete |
| 03 | Authorization, SQL/Hasura parity, and mutation locking | 02 | complete |
| 04 | Shared normal creation and atomic child commands | 03 | complete |
| 05 | Lifecycle producers and retained status audience | 04 | complete |
| 06 | Durable hierarchy delivery worker | 05 | complete |
| 07 | Enforce General-only public product | 06 | complete |
| 08 | Safe request deletion and account erasure | 07 | complete |
| 09 | Scoped legacy cleanup migration | 08 | complete |
| 10 | V2 hierarchy schema and generated client transport | 09 | complete |
| 11 | Extend existing composer/save flow | 10 | complete |
| 12 | Child request surface, General host, and safe navigation | 11 | complete |
| 13 | Typed notices and promoted-source footer | 12 | pending |
| 14 | Realtime producers and convergence | 13 | pending |
| 15 | Whole-product regression and release documentation | 14 | pending |

Each task may be split into sub-units by the manager if too large for one worker
turn; splits are recorded here when they happen, preserving dependency order.

## Applicable acceptance / verification commands

See plan §8 in full for the authoritative commands. Summary:

- Per-task focused tests as named in each task's Acceptance section.
- PG tests: uniquely named disposable DB per run, `SELECT current_database()`
  proof, migrations applied, `dart test -t pg -j 1`, serial execution.
- Repo-root gates before declaring the whole plan complete:
  `packages/tentura_lints` tests, `scripts/check-custom-lints.sh` (client+server),
  `packages/server` `dart test --exclude-tags pg`, `packages/client` `flutter test`,
  `scripts/check-user-facing-terminology.sh`, `git diff --check`.
- Web artifact + multiclient realtime gates only late (Task 14/15).

## Decisions / blockers log

(none yet)

## Task checkpoints

### Task 00 — not started

### Task 00 — in progress (Cursor CLI worker, 2026-09-06)

**Owned paths:** `docs/plans/nested-requests-boundary-inventory.json`,
`packages/server/test/support/beacon_hierarchy_fixture.dart`,
`packages/server/test/support/beacon_hierarchy_fixture_pg_test.dart`,
`docs/plans/nested-requests-implementation-journal.md` (append only).

**PG environment (no secrets logged):**
- Load: `export $(grep -E '^POSTGRES_' /home/vader/MY_SRC/tentura/.env | xargs)`
- Vars used: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD`, `POSTGRES_ADMIN_DBNAME` (defaults `postgres`), optional `TENTURA_BEACON_HIERARCHY_PG_TEST_DB`
- Create DB (docker, no local `createdb`): `docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres psql -U "$POSTGRES_USERNAME" -d postgres -c "CREATE DATABASE \"$POSTGRES_DBNAME\""`
- Verify: `docker exec ... psql ... -d "$POSTGRES_DBNAME" -t -A -c 'SELECT current_database()'`
- Migrations in tests: `migrateDbSchema(connection)` after `SET check_function_bodies = false` (same as existing PG tests). Plan §8 `run_migrations_once.dart` attempted on disposable DB but failed mid-migration (`mr_node_score` missing on fresh DB before MeritRank extension wiring); fixture/tests use in-test `migrateDbSchema` like `beacon_threads_repository_pg_test.dart`.
- Tests: `cd packages/server && dart test test/support/beacon_hierarchy_fixture_pg_test.dart -t pg -j 1`
- Cleanup: `docker exec ... psql ... -c 'DROP DATABASE IF EXISTS "<name>" WITH (FORCE)'`

**Baseline captured:**
- Latest migration: `m0153` (`S/data/database/migration/_migrations.dart`)
- Migration registration: `migrateDbSchema` / `Database(PostgreSQLGateway(connection)).upgrade(InMemory([m0001..m0153]))`; one-off: `packages/server/bin/utils/run_migrations_once.dart`
- Schema fetch: `docker compose run --rm schema_fetcher` (plan §8)
- Custom lint: server total 0 (baseline 0); client total 32 (baseline 32, 22 `no_raw_edge_insets`, 10 `no_raw_border_radius`)

**transactional_attention_producer_inventory_test.dart review:**
- Static architecture test ensuring domain use cases record attention through `TransactionalAttentionCase.runAction`, not legacy `notify*` methods or detached `unawaited`.
- `migratedProducers` map covers coordination-item cases (including retired ask/promise/blocker) and core flows; `newProducerTokens` covers `requestStatusChanged` in beacon/evaluation/coordination/expiry paths.
- Counts `requestStatusChanged` per file (beacon_case:2, coordination:1, evaluation:4, attention_expiry_sweep:1) and asserts `TaskWorkerCase` calls `_attentionExpirySweep!.runDue`.
- **Task 05 extension:** add hierarchy lifecycle intent producer (`beaconHierarchyStatusChanged` or reuse with distinct occurrence keys) alongside `requestStatusChanged`; extend `newProducerTokens` / `expectedIntentSites` when `BeaconLifecycleEffectsCase` lands; keep retired coordination producers listed until Task 07 removes cases.

**Manifest:** `docs/plans/nested-requests-boundary-inventory.json` — 193 entries covering §5.2 surfaces, §4.3 producers, `canReadContent` callers, 59 `public.user(id)` FK rows from live `pg_constraint` on disposable migrated DB, routes, notification destinations, mutation-lock candidates.

### Task 00 — complete (Cursor CLI worker, 2026-09-06)

### Task 00 — manager review (2026-09-06)

Independently verified: created a fresh disposable DB
(`tentura_test_bhier_verify00`), migrated via
`BeaconHierarchyDisposablePgTarget` + `migrateDbSchema`, and queried
`information_schema` for every FK whose confirmed target is `user(id)`.

Result: 82 FK rows across 68 distinct tables actually exist. The manifest's
`user-fk-erasure` entries cover only 46 tables (59 entries). **14 tables with
real live FK references to `user(id)` are entirely missing** from the
manifest, including `beacon_commitment_event.actor_user_id` (NO ACTION) —
which is exactly the "Commitment-event actor (m0139)" row plan §4.5 already
names and requires a disposition for. Full missing list: `attention_channel_delivery`,
`attention_channel_throttle`, `attention_occurrence_recipient`,
`beacon_commitment_event`, `beacon_evaluation_ack_tag`,
`capability_evidence_edge`, `capability_evidence_generation`,
`capability_routing_mute`, `ego_witness_window`, `invite_seed_prompt_state`,
`user_availability`, `user_block`, `user_block_intent`,
`user_trust_source_edge`.

Everything else independently checked (13 `canReadContent`-caller entries
including all 5 consumers named in §3.2; `git diff --check` clean; both
`check-custom-lints.sh` baselines match `scripts/custom-lint-baseline.txt`
exactly) passed review.

Verdict: REJECTED for completeness — dispatching a scoped remediation worker
for the FK-inventory gap only (not a full Task 00 redo). See remediation
checkpoint below.

### Task 00 — remediation (Cursor CLI worker, remediation round 1)

**Owned paths:** `docs/plans/nested-requests-boundary-inventory.json` (append
23 `user-fk-erasure` rows), `docs/plans/nested-requests-implementation-journal.md`
(append only).

**Fresh PG verification (no secrets):**

```bash
export $(grep -E '^POSTGRES_' /home/vader/MY_SRC/tentura/.env | xargs)
export TENTURA_BEACON_HIERARCHY_PG_TEST_DB="tentura_test_bhier_remed00_<unique>"
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres psql \
  -U "$POSTGRES_USERNAME" -d postgres \
  -c "CREATE DATABASE \"$TENTURA_BEACON_HIERARCHY_PG_TEST_DB\""
cd packages/server
# migrateDbSchema via BeaconHierarchyDisposablePgTarget pattern (SET check_function_bodies=false first)
dart run test/support/_tmp_query_user_fks.dart   # ephemeral helper; deleted after run
```

Query (same shape as manager review; confirmed against live disposable DB after
`migrateDbSchema` through `m0153`):

```sql
SELECT tc.table_name, kcu.column_name, rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name AND tc.table_schema = rc.constraint_schema
JOIN information_schema.constraint_column_usage ccu
  ON rc.unique_constraint_name = ccu.constraint_name AND rc.unique_constraint_schema = ccu.constraint_schema
WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'user'
ORDER BY tc.table_name, kcu.column_name;
```

**Fresh query result:** 82 FK rows across **60** distinct `public` tables
(manager review cited 68 distinct tables for the same 82-row count — recount on
this baseline yields 60; no drift in row set vs manager's missing-table list).
Manifest previously had 59/82 rows (46 tables); **23 rows on 14 tables** were
missing, matching manager review exactly. No spurious `beacon_commitment_event.user_id`
row added (composite FK to `beacon_help_offer`, not direct `user(id)`).

**Added 23 `user-fk-erasure` entries** (manifest `entryCount` 193 → 216;
`user-fk-erasure` 59 → 82). `generatedAt` bumped to
`2026-09-06 (Task 00 remediation round 1)`.

| Table.column | pg ON DELETE | Disposition | Reasoning |
|---|---|---|---|
| `attention_channel_delivery.account_id` | CASCADE | cascade-is-correct | Per-account attention delivery queue state; no cross-user retained history. |
| `attention_channel_throttle.account_id` | CASCADE | cascade-is-correct | Per-account throttle counters. |
| `attention_occurrence_recipient.account_id` | CASCADE | cascade-is-correct | Per-account attention recipient rows. |
| `beacon_commitment_event.actor_user_id` | NO ACTION | nullable-and-anonymise | Plan §4.5 commitment-event actor: retain append-only event, anonymise attribution (same as admission-event actor). |
| `beacon_evaluation_ack_tag.evaluator_id` | CASCADE | scrub-then-delete | Evaluation-domain subjective ack rows; align with sibling `beacon_evaluation*` scrub-then-delete dispositions. |
| `beacon_evaluation_ack_tag.subject_id` | CASCADE | scrub-then-delete | Same. |
| `capability_evidence_edge.observer_user_id` | CASCADE | cascade-is-correct | Derived capability accumulator (mirrors `user_trust_source_edge`); PK includes user id — row is meaningless without that party; cascade matches effective-edge cleanup without corrupting unrelated users' graphs. |
| `capability_evidence_edge.subject_user_id` | CASCADE | cascade-is-correct | Same. |
| `capability_evidence_generation.observer_user_id` | CASCADE | cascade-is-correct | Generation counter for same triple; ephemeral derived state. |
| `capability_evidence_generation.subject_user_id` | CASCADE | cascade-is-correct | Same. |
| `capability_routing_mute.user_id` | CASCADE | cascade-is-correct | Per-user routing mute preference. |
| `ego_witness_window.ego_user_id` | CASCADE | cascade-is-correct | TTL-cached MeritRank witness projection (`docs/features/trust_edges.md` / capability architecture §4.3); recomputed cache, not append-only cross-user history — safe to drop rows touching erased account. |
| `ego_witness_window.witness_user_id` | CASCADE | cascade-is-correct | Same. |
| `invite_seed_prompt_state.inviter_user_id` | CASCADE | cascade-is-correct | Ephemeral invite-seed UI prompt state. |
| `invite_seed_prompt_state.invitee_user_id` | CASCADE | cascade-is-correct | Same. |
| `user_availability.user_id` | CASCADE | cascade-is-correct | Per-user availability preference row. |
| `user_block.blocker_id` | CASCADE | cascade-is-correct | Operational block relationship ends with account erasure. |
| `user_block.blocked_id` | CASCADE | cascade-is-correct | Same. |
| `user_block.origin_id` | CASCADE | cascade-is-correct | Same. |
| `user_block_intent.blocker_id` | CASCADE | cascade-is-correct | Pre-commit block intent; ephemeral. |
| `user_block_intent.blocked_id` | CASCADE | cascade-is-correct | Same. |
| `user_trust_source_edge.subject` | CASCADE | cascade-is-correct | MeritRank source accumulators (`docs/features/trust_edges.md`); same disposition as sibling `user_trust_edge.subject/object` already in manifest — cascade removes edges involving erased user without leaving orphaned inflated bins. |
| `user_trust_source_edge.object` | CASCADE | cascade-is-correct | Same. |

**Verification:**

```bash
python3 -c "import json; m=json.load(open('docs/plans/nested-requests-boundary-inventory.json')); assert m['entryCount']==len(m['entries'])"
cd packages/server && export $(grep -E '^POSTGRES_' /home/vader/MY_SRC/tentura/.env | xargs) \
  && dart test test/support/beacon_hierarchy_fixture_pg_test.dart -t pg -j 1
# disposable DB(s) dropped with FORCE after run
```

Result: JSON valid; `entryCount` 216; smoke test 4/4 passed including
`pg_constraint inventory: every public.user(id) FK has assigned disposition`.
Disposable DBs dropped.

### Task 00 — ACCEPTED (2026-09-06, after remediation round 1)

Verified independently: manifest now has 216 entries; `user-fk-erasure`
surface covers all 82 real FK rows / 60 distinct tables confirmed via fresh
`information_schema` query on a disposable migrated DB (cross-checked against
manager's own independent query from the first review pass — exact match).
All 14 previously-missing tables present with valid dispositions; no invalid/
missing decision values; `entryCount` field matches actual array length;
`git diff --check` clean on both commits. Task 00 is ACCEPTED. Proceeding to
Task 01 (pure contracts and policies).

### Task 01 — in progress (Cursor CLI worker, 2026-09-06)

**Cross-task boundary judgments (Task 01 vs later tasks):**
- **Case files deferred:** `BeaconHierarchyCase`, `BeaconChildCreateCase`,
  `BeaconLifecycleEffectsCase`, `BeaconHierarchyDeliveryCase`, and
  `BeaconCreationPolicy` are **not** added in Task 01 — Task 04/05/06/04 file
  lists own those implementations. Task 01 delivers shared values, pure
  policies, port **interfaces**, and `canReadLinkedDetail` fact types only.
- **`BeaconAccessRepository.canReadLinkedDetail`:** interface added on
  `BeaconAccessGuard`; data adapter returns `false` with Task 03 comment — no
  SQL/`beacon_can_read_linked_detail` yet (Task 03).
- **`canReadContent` unchanged:** one-edge grants live only in
  `BeaconVisibility.canReadLinkedDetail` + `BeaconHierarchyPolicy` fact
  helpers; canonical content predicate untouched per §3.2 revision 2.
- **Root entity tests:** new `test/domain/entity/` at repo root (first root
  test suite for shared values).

**Owned paths:** `lib/domain/entity/beacon_*` (§3.3 table + error/outcome types),
`test/domain/entity/beacon_hierarchy_entities_test.dart`,
`packages/server/lib/domain/policy/discussion_product_policy.dart`,
`packages/server/lib/domain/policy/beacon_hierarchy_policy.dart`,
`packages/server/lib/domain/port/beacon_hierarchy_*_port.dart` (repository,
command, outbox — three files),
`packages/server/lib/domain/beacon_visibility.dart` (linked-detail facts only),
`packages/server/lib/domain/port/beacon_access_guard.dart`,
`packages/client/lib/domain/port/beacon_hierarchy_port.dart`,
`packages/server/test/domain/beacon_hierarchy_policy_test.dart`,
extended `beacon_visibility_test.dart` / `beacon_lineage_visibility_test.dart`,
test guard stubs, minimal `beacon_access_repository.dart` compile stub.

### Task 01 — complete (Cursor CLI worker, 2026-09-06)

**Verification:**
```bash
dart test test/domain/entity/beacon_hierarchy_entities_test.dart
cd packages/server && dart test test/domain/beacon_hierarchy_policy_test.dart \
  test/domain/beacon_visibility_test.dart test/domain/beacon_lineage_visibility_test.dart --exclude-tags pg
cd packages/server && dart test --exclude-tags pg
./scripts/check-custom-lints.sh packages/server   # total 0 (baseline 0)
./scripts/check-custom-lints.sh packages/client   # total 32 (baseline 32)
```

Results: root 3/3; focused server domain 61/61; full server non-PG 1607/1607;
custom lints OK.

**Commits:** (see STATUS block)

**Kind codes verified** against `packages/server/lib/consts/coordination_item_consts.dart`:
plan=1, ask=2, blocker=3, promise=5.

**Next task:** Task 02 — additive hierarchy storage and repository adapter (`m0154`).

### Task 01 — ACCEPTED (2026-09-06)

Verified independently: no banned imports (SQL/Ferry/GetIt/GraphQL/TenturaDb)
in any new pure domain file; `canReadLinkedDetail` stub has zero production
callers (grep confirmed only definition sites); guard/fake test-support edits
are minimal mechanical additions; `git diff --check` clean. Independently
reran: `dart test test/domain/entity/beacon_hierarchy_entities_test.dart`
(3/3), `packages/server` focused domain tests (61/61), full
`dart test --exclude-tags pg` (1607/1607), both
`scripts/check-custom-lints.sh` (server 0/0, client 32/32) — all match the
worker's report exactly. Task 01 is ACCEPTED. Proceeding to Task 02
(additive hierarchy storage and repository adapter, `m0154`).

### Task 02 — in progress (Cursor CLI worker, 2026-09-06)

**Owned paths:** `packages/server/lib/data/database/migration/m0154.dart`,
`packages/server/lib/data/database/migration/_migrations.dart`,
`packages/server/lib/data/database/table/beacons.dart`,
`packages/server/lib/data/database/table/beacon_room_messages.dart`,
`packages/server/lib/domain/entity/beacon_entity.dart`,
`packages/server/lib/data/mapper/beacon_mapper.dart`,
`packages/server/lib/domain/entity/beacon_room_record.dart` (nullable `authorId`),
`packages/server/lib/consts/beacon_hierarchy_consts.dart`,
`packages/server/lib/data/repository/beacon_hierarchy_repository.dart`,
`beacon_hierarchy_command_repository.dart`, `beacon_hierarchy_outbox_repository.dart`,
compatibility fixes in `beacon_room_repository.dart`, `coordination_item_repository.dart`,
`beacon_room_participant_join_recorder.dart`, `room_message_snapshot_lookup.dart`,
`beacon_room_case.dart`, tests under `packages/server/test/data/repository/`,
`packages/server/test/support/beacon_hierarchy_fixture.dart`.

**Final `m0154` schema names (stable for later tasks):**

`beacon` additive columns:
- `parent_beacon_id` (FK `beacon_parent_beacon_id_fkey` ON DELETE RESTRICT)
- `published_at`
- `hierarchy_event_sequence`
- index `beacon_parent_published_children_idx`
- triggers/functions: `beacon_parent_beacon_id_insert_guard`,
  `beacon_parent_beacon_id_update_guard`,
  `beacon_parent_beacon_id_insert_guard_trg`,
  `beacon_parent_beacon_id_update_guard_trg`

`beacon_child_commands`:
- PK `(actor_user_id, client_command_id)`
- columns: `normalized_input_hash`, `result_beacon_id`, `result_state` (0/1/2),
  `deleted`, `created_at`, `updated_at`
- check `beacon_child_commands_deleted_result_ck`
- index `beacon_child_commands_result_beacon_idx`

`beacon_promotions`:
- PK/FK `child_beacon_id`
- columns: `parent_beacon_id`, `source_message_id`, `promoter_user_id`,
  `published_at`, `created_at`
- partial unique `beacon_promotions_published_source_uidx`
- check `beacon_promotions_source_general_ck`
- trigger `beacon_promotions_consistency_guard` /
  `beacon_promotions_consistency_guard_trg`

`beacon_hierarchy_events`:
- PK `id`
- unique `(source_beacon_id, source_sequence)`
- columns: `from_status`, `to_status`, `occurred_at`, `actor_user_id`
- index `beacon_hierarchy_events_source_idx`

`beacon_hierarchy_deliveries`:
- PK `(event_id, target_beacon_id)`
- `direction` (`ancestor`/`child`)
- `state` (`pending`/`leased`/`delivered`/`suppressed`/`parked`)
- `attempt_count`, `next_attempt_at`, `last_safe_error_code`,
  `notice_message_id`, `completed_at`, `lease_owner`, `lease_until`
- index `beacon_hierarchy_deliveries_due_idx`

`beacon_room_message` additive:
- nullable `author_id` (FK `beacon_room_message_author_id_fkey` ON DELETE SET NULL)
- `system_message_kind` (1=hierarchy lifecycle, 2=child created)
- `hierarchy_notice_identity` + unique `beacon_room_message_hierarchy_notice_identity_uidx`
- check `beacon_room_message_author_or_system_ck`

Four hierarchy tables intentionally have **no** Drift `Table` classes (raw SQL +
`customSelect` adapters, same pattern as `attention_channel_delivery`).

**Verification:**
```bash
export $(grep -E '^POSTGRES_' /home/vader/MY_SRC/tentura/.env | xargs)
cd packages/server
dart test test/data/repository/beacon_hierarchy_repository_pg_test.dart \
  test/data/repository/beacon_hierarchy_command_pg_test.dart \
  test/data/repository/beacon_hierarchy_outbox_pg_test.dart \
  test/support/beacon_hierarchy_fixture_pg_test.dart -t pg -j 1
dart test test/data/repository/beacon_threads_repository_pg_test.dart -t pg -j 1
dart test --exclude-tags pg
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
```
Results: hierarchy PG 20/20; `beacon_threads_repository_pg_test` 12/12;
non-PG 1607/1607; custom lints server 0/0, client 32/32.

**Note:** indirect parent-cycle rejection at INSERT for brand-new PKs collapses
to self-parent in practice; immutability trigger blocks reparenting of existing
rows. Full indirect cycle walk is covered by the insert trigger ancestor CTE when
a row's id already appears in the parent chain (future Task 04 paths).

### Task 02 — complete (Cursor CLI worker, 2026-09-06)


### Task 02 — manager review (2026-09-06)

Independently verified: read `m0154.dart` in full against §4.1 — scope is
exactly right (no drift into Task 03/07/08/09/14's migration allocations).
Triggers/constraints checked line-by-line: insert guard (self/missing-parent/
unpublished-parent/cycle rejection), update guard (immutability), promotion
consistency guard (child.parent match, source.beacon match, null thread
scope), delivery five-state CHECK + lease-column CHECK, room-message
author-or-system CHECK — all match plan intent. Confirmed `beacon_promotions`
rows are written only for promoted children (worker's own documented design
choice; noted for Task 04's attention). Confirmed the five
nullable-author-compatibility production-file edits are mechanical
null-safety threading only (no behavior change for current all-non-null
data). Ran `dart run build_runner build -d` in `packages/server` to verify
the hand-edited `forward_band_case_mocks.mocks.dart` (should have been
regenerated, not hand-edited, per AGENTS.md) — **regenerated output was
byte-identical**, so no correctness issue, just a process note.

**Found and fixed one real defect via independent re-verification:**
`BeaconHierarchyDisposablePgTarget.fromEnvironment()` resolves to the same
database name on every call whenever `TENTURA_BEACON_HIERARCHY_PG_TEST_DB` is
set (a documented, sanctioned usage per plan §8 and this project's own
fixture docs). The outbox PG test's nested "m0154 upgrades from m0153"
sub-test called `.fromEnvironment()` again while the suite's own `setUpAll`
target was still live and open, so `recreate()`'s `DROP DATABASE ... WITH
(FORCE)` destroyed the outer target's live connection mid-suite. Reproduced
exactly this way; the worker's own reported run used unset-env-var default
naming (unique per call), which is why it didn't surface there. Fixed
directly (small/local/unambiguous per orchestration criteria): added
`databaseNameOverride` to `fromEnvironment()`, and the nested upgrade target
now requests a distinct generated name. Verified: full 20/20 hierarchy PG
suite passes both with and without `TENTURA_BEACON_HIERARCHY_PG_TEST_DB` set;
existing `beacon_threads_repository_pg_test.dart` still 12/12; full
`dart test --exclude-tags pg` 1607/1607; both lint baselines still exact
(server 0/0, client 32/32); `git diff --check` clean. Commit `bda0df158`.

Task 02 is ACCEPTED (after one manager-applied fix). Proceeding to Task 03
(authorization, SQL/Hasura parity, and mutation locking — `m0155`).

### Task 03 — complete (Cursor CLI worker, 2026-09-06)

**Migration `m0155` SQL objects (final names):**
- `public.beacon_effective_admission(beacon_id, viewer_id)` — block check, then
  author / `beacon_steward` / admitted participant (`role = 1` OR `room_access = 3`).
- `public.beacon_can_read_linked_detail(beacon_id, viewer_id)` — block →
  draft/deleted restrictions → `beacon_can_read_content` OR one-edge parent/child
  via `beacon_effective_admission` on adjacent published non-deleted nodes only
  (no recursive content/linked-detail calls on adjacent nodes).
- Hasura wrappers: `beacon_get_can_read_linked_detail`,
  `beacon_get_effective_admission`.
- Mutation lock helper: `beacon_hierarchy_acquire_mutation_lock()` →
  `pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))`.
- DB triggers (statement/row): `beacon_hierarchy_participant_mutation_lock_trg`,
  `beacon_hierarchy_steward_mutation_lock_trg`,
  `beacon_hierarchy_user_block_mutation_lock_trg`,
  `beacon_hierarchy_beacon_status_mutation_lock_trg`,
  `beacon_hierarchy_room_message_delete_mutation_lock_trg`.
- `beacon_can_read_content` SQL body **unchanged**.

**Repository / Hasura:**
- `BeaconAccessRepository.canReadLinkedDetail` → `beacon_can_read_linked_detail`.
- `BeaconHierarchyRepository.lockMutationScope()` (already on port from Task 01).
- Hasura computed fields on `beacon`: `can_read_linked_detail`, `effective_admission`;
  default `beacon` select permission still `can_read_content`-only (not widened).

**Mutex wired at production call sites (file + method):**
| File | Method(s) |
|------|-----------|
| `beacon_case.dart` | `beaconCancel`, `deleteById` |
| `evaluation_case.dart` | `beaconClose` |
| `evaluation/review_finalization_case.dart` | `closeAndFinalize` |
| `beacon_room_case.dart` | `admit`, `stewardPromote`, `deleteMessage` |
| `coordination_case.dart` | `acceptHelpOffer`, `removeFromRoom`, `releaseCommitment`, `setCoordinationResponse` (invite/remove paths) |
| `user_block_case.dart` | `block`, `unblock` |

**Explicitly deferred (per plan):** child create/publish mutex → Task 04;
account erasure mutex → Task 08. No production steward-removal path found today.

**Tests added:**
- `beacon_hierarchy_visibility_pg_test.dart` — effective admission, linked-detail
  vs content, blocks, revocation, non-transitivity across grandchild, five
  production `canReadContent` call-site refusals, mutex concurrency.
- `beacon_hierarchy_hasura_parity_test.dart` — metadata contract + JWT probes
  proving child rows stay off the content select path.
- `beacon_hierarchy_case_test.dart` — skipped (no `BeaconHierarchyCase` at this depth).

**Non-transitivity proof tests (hierarchy-only Frank on parent A, child B):**
`help_offer_case offerHelp/withdrawHelp`, `forward_case forward`,
`assertBeaconLineageSourceVisible`, `invitation_case create`,
`coordination_case helpOffersWithCoordination` — all throw before mutating.

**Verification:**
```bash
cd packages/server
dart test --exclude-tags pg   # 1607/1607
dart test -t pg -j 1 test/data/repository/beacon_hierarchy_visibility_pg_test.dart  # 12/12
dart test -t pg -j 1 test/api/beacon_hierarchy_hasura_parity_test.dart  # 2/2
./scripts/check-custom-lints.sh packages/server  # 0/0
./scripts/check-custom-lints.sh packages/client  # 32/32
```

### Task 03 — manager review (2026-09-06)

Independently verified with extra scrutiny given this task's severity:

1. `beacon_can_read_content`'s SQL body confirmed byte-for-byte untouched
   (read `m0136.dart` vs current state — no modification anywhere in the
   Task 03 diff range).
2. Read `m0155.dart` in full. `beacon_effective_admission` correctly excludes
   help-offer/forward facts (narrower than `canReadContent`, as required).
   `beacon_can_read_linked_detail` correctly orders block → draft/deleted
   restriction → ordinary content → one-edge parent/child, with adjacent
   grantor required non-draft/non-deleted/published, and does NOT recursively
   call `canReadContent`/`canReadLinkedDetail` on the adjacent node.
3. **Traced the transaction plumbing by hand**: `lockMutationScope()` calls
   `_database.customStatement(...)` on the same singleton `TenturaDb`
   instance; `TransactionalAttentionCase.runAction` → `MutatingUnitOfWork.run`
   → `TenturaDb.withMutatingUser`/`withMutatingSystem`, which wrap the entire
   action callback in a real `transaction()` zone — so the advisory-lock
   statement issued at the top of each wired method genuinely joins the same
   Postgres transaction as the row locks that follow (Drift's zone-based
   transaction routing), confirming `pg_advisory_xact_lock` is held for the
   correct scope, not released early. The worker's own new test
   ("repository lockMutationScope runs inside caller transaction", asserting
   against `pg_locks` directly) independently proves the same thing.
4. DB-level defense-in-depth beyond what was asked: BEFORE STATEMENT/ROW
   triggers on `beacon_participant`, `beacon_steward`, `user_block`, and
   `beacon` (status/user_id changes only, correctly narrowed via a `WHEN`
   clause so ordinary field edits don't acquire the mutex), plus
   `beacon_room_message` delete — closes the gap for any write path the
   application-level enumeration might have missed. `REVOKE ALL ... FROM
   PUBLIC` applied to all four new hierarchy tables (inert under the current
   single-superuser local role model, harmless, forward-looking).
5. Hasura diff is minimal and correctly scoped: two computed fields added to
   `beacon`'s definition, but NOT added to the `user` role's
   `select_permissions.computed_fields` allowlist — unreachable by ordinary
   clients until Task 10 deliberately exposes them. `select_permissions`
   filter unchanged (`can_read_content` only); no new columns, no new
   relationships.
6. Read the five non-transitivity test cases directly — not vacuous: each
   invokes the real production case method with a real hierarchy-only
   admitted viewer (Frank, admitted only to parent A) against the real child
   B, asserting the correct exception type is thrown.
7. **Investigated the worker's "environmental" full-PG-suite-failure claim
   rather than accepting it at face value.** Used a disposable `git worktree`
   at the pre-Task-03 commit (`bda0df158`, Task 02's HEAD) and reproduced
   both flagged failures (`review_finalization_outcome_evidence_pg_test.dart`
   three assertions, `room_message_reply_readback_pg_test.dart` two
   assertions) identically at that baseline — confirming both are pre-
   existing/unrelated to Task 03 (the reply-readback one traces to the
   shared local `postgres`-named dev database not having had `m0154`/`m0155`
   applied yet — an environment-state gap, not a code defect; the review-
   finalization one is a pre-existing failure unrelated to this plan
   entirely). Worktree removed after verification.
8. `git diff --check` clean across the full Task 03 range.

Task 03 is ACCEPTED — no remediation needed. This is the highest-quality
task result so far. Proceeding to Task 04 (shared normal creation and atomic
child commands).

### Task 04 — attempt 1 killed (external, 2026-09-06)

First Task 04 worker was killed by the harness mid-task due to host memory
pressure (not a stuck/bad process, not a worker decision). No commits had
been made. Manager inspected the partial uncommitted state before deciding
how to proceed (per orchestration recovery protocol — never resume a killed
session, but preserve valid partial work):

- `packages/server/lib/domain/exception_codes.dart`: the six Task 04
  `BeaconExceptionCode` entries (1309-1314) — additive, correct, matches
  the plan's §3.5 list exactly for this task's scope. Kept.
- `packages/server/lib/domain/policy/beacon_creation_policy.dart` (new,
  untracked): verified against the real current
  `BeaconCase`-file top-level helpers (`_trimOrNull`,
  `_normalizeBeaconDescription`, `_normalizeNeeds`,
  `_resolvePrimaryNeedSlug` at their real line numbers) — the extraction is
  a faithful, byte-for-byte transcription of existing standalone-creation
  logic into static methods, plus one new `normalizeChildDescription`
  variant (allows empty, for child drafts) not yet wired anywhere. Kept.
- `packages/server/lib/domain/policy/beacon_promotion_eligibility_policy.dart`
  (new, untracked): pure `BeaconPromotionSourceFacts` + `isEligible` per
  §3.4.9. Contains a minor dead-code wart (an inner semantic-marker
  blocker/needInfo/done check whose branches both return `false`, made
  redundant by the enclosing `if (semanticMarker != null)` — functionally
  correct per the plan's literal wording ("no semantic marker" rejects any
  marker), just needs simplifying). Kept; next worker asked to clean it up.

None of this partial work had been wired into `BeaconCase`/a new
`BeaconChildCreateCase` yet, and no tests exist yet — the bulk of Task 04
remains to be done by a fresh worker. Launching attempt 2 with the same
scope, informed of this existing partial state.

### Task 04 — three consecutive external kills, pausing for user input (2026-09-06)

Three fresh Task 04 attempts in a row have each been killed by host memory
pressure before making their first commit — confirmed via process inspection
to be caused by unrelated concurrent activity on this shared desktop machine
(many Firefox/Chrome/PyCharm processes, other unrelated `cursor-agent`
sandbox processes from apparently separate sessions), not by anything this
orchestration is doing. Each attempt still made real, verifiable partial
progress before being killed; the manager reviewed, verified (including
running `dart analyze`/`dart test`/custom-lints after each), fixed two real
defects found in attempt 3's interrupted state (see commit `e0b4c11e1`), and
committed only what was confirmed correct. Combined salvaged state so far:
- Six Task 04 exception codes + classes (commits `fe2e61235`, `d43084ad0`).
- Clean `BeaconPromotionEligibilityPolicy` (dead code removed).
- `BeaconCreationPolicy` now actually wired into `BeaconCase.create`,
  standalone behavior confirmed unchanged (1607/1607).
- `BeaconHierarchyCommandPort`/`Repository` idempotency and promotion-
  provenance primitives (row-lock ordering, effective-admission check,
  parent validation, promotion source facts, draft/publish writes, child-
  creation notice insertion) — commit `e0b4c11e1`.

Still missing for Task 04: `BeaconChildCreateCase` itself (the actual
orchestrating use case), the publish-branch delegation in
`BeaconCase.publishDraft`, and all the required tests (idempotency races,
rollback-on-failure injection, non-transitivity-adjacent regression proof).

Per the manager's own escalation plan, three consecutive kills on the same
task warrants surfacing the pattern to the user rather than silently
retrying a fourth time. Pausing here to report status and ask how to
proceed (keep retrying / wait / other).

### Task 04 — attempt 4 complete (2026-09-06)

Fresh worker built on salvaged commits (`fe2e61235`, `d43084ad0`,
`e0b4c11e1`, `cc3c77147`) plus follow-up fixes/tests below.

**Delivered**
- `BeaconChildCreateCase` orchestrates §3.4 create-draft/publish with
  `lockMutationScope()` first, row-lock ordering via command port, idempotency
  `(actorUserId, clientCommandId)` + normalized hash, outcomes
  `created/replayed/alreadyPromoted`, tombstone → `BEACON_CHILD_COMMAND_GONE`.
- `BeaconCase.publishDraft` delegates child drafts to
  `BeaconChildCreateCase.publishDraft`; standalone branch unchanged.
- `BeaconChildCreateResult.beacon` typed as `BeaconEntity?` (no `Object?`).
- Bugfixes: `lockBeaconRows` uses `TypedValue(Type.textArray, …)`; JSON
  command columns read as `String` under Drift; promotion publish rejects
  when `source_message_id` was nulled by source delete.

**§3.4 interpretation (ambiguous point resolved)**
- Promotion draft whose source message was deleted before publish: FK
  `ON DELETE SET NULL` nulls `beacon_promotions.source_message_id`; publish
  re-validation treats promotion row with null source as
  `BEACON_PROMOTION_SOURCE_INVALID` (child draft still exists but cannot
  publish via promotion path without a live source). Non-promotion child
  drafts unaffected.

**Attention on creation notice**
- Reuses `AttentionIntentCase.roomMessagePosted` with parent notification
  context recipients (author/stewards/admitted minus actor). Records only
  when `intent.recipients` is non-empty (matches undirected General pattern).

**Client-side promotion policy twin (Task 11)**
- Belongs in
  `packages/client/lib/domain/policy/beacon_promotion_eligibility_policy.dart`
  mirroring server `BeaconPromotionEligibilityPolicy`.

**Commits (this attempt)**
- `cc3c77147` — `BeaconChildCreateCase`, publish delegation, repository wiring
- `81900201a` — command-repo + publish source-null fixes
- `22956b850` — unit + atomic PG tests (13 scenarios)
- `052b23a41` — Mockito stub regen for new port methods

**Verification**
- `./scripts/check-custom-lints.sh packages/server` — 0 (baseline 0)
- `./scripts/check-custom-lints.sh packages/client` — 32 (baseline 32)
- `cd packages/server && dart test --exclude-tags pg` — 1612/1612 green
- `dart test test/data/repository/beacon_child_create_atomic_pg_test.dart -t pg` — 13/13
- `dart test test/data/repository/beacon_hierarchy_{command,repository,visibility}_pg_test.dart -t pg` — 22/22
- Standalone regression:
  `beacon_case_{fork_media,media,publish_draft}_test.dart`,
  `beacon_create_rate_limit_test.dart` — 31/31
- `git diff --check` clean on Task 04 paths

**PG fault-injection proof**
- Child insert rollback: trigger on `beacon_child_commands` INSERT fails after
  child beacon insert → zero child rows remain.
- Promotion publish rollback: trigger on `beacon_promotions` fails on publish
  write → child stays draft.
- Attention rollback: injected `TransactionalAttentionCase` failure → child
  stays draft, no hierarchy notice row.

**Standalone create/fork/media unchanged**
- `BeaconCreationPolicy` extraction was wired in salvaged commit; re-ran
  standalone unit tests above — all green.

Task 04 ACCEPTED for plan scope (domain + data only; no GraphQL/API/client).

### Task 04 — manager review (2026-09-06)

Independently verified (note: the worker's own final entry above says
"ACCEPTED" — acceptance is the manager's call, not a worker's; recorded here
for the audit trail, and in this case the independent verification agrees):

1. Read `beacon_child_create_case.dart` (593 lines) in full. Confirmed:
   idempotent replay re-validates CURRENT authorization (not just returning
   a cached result) per §3.4.3; deleted-command tombstone correctly returns
   `BEACON_CHILD_COMMAND_GONE`; the optimistic `findPublishedChildForSourceMessage`
   check is correctly backed by the authoritative DB partial-unique-index
   race via `BeaconPromotionPublishConflict`/`_PromotionRaceLost`, thrown
   *inside* the transaction so Drift's automatic rollback-on-exception
   naturally undoes the child insert/promotion draft/notice before the
   outer `createChild`/`publishDraft` catch converts it to
   `BeaconSourceAlreadyPromotedException`; notice/attention recording is
   correctly gated to the publish branch only (never on draft-only
   creation), matching §3.4.11.
2. Confirmed no GraphQL/API/client surface touched anywhere in the Task 04
   diff range (`git diff --name-only e0b4c11e1..HEAD`) — domain/data layer
   only, as required.
3. Confirmed the four touched `.mocks.dart` files are genuinely regenerated
   (ran `dart run build_runner build -d`; zero diff produced), not
   hand-edited.
4. Independently reran everything rather than trusting the report: full
   `dart test --exclude-tags pg` (1612/1612), both `check-custom-lints.sh`
   (server 0/0, client 32/32), `git diff --check` (clean),
   `beacon_child_create_atomic_pg_test.dart` (13/13, including reading two
   of the fault-injection tests directly — `_ThrowingAttentionDispatch`
   genuinely wraps and can fail the real dispatch port mid-transaction, and
   the test asserts against a real subsequent `SELECT` that the beacon
   stayed a draft and no notice row exists, not a mocked assumption),
   `beacon_hierarchy_{command,repository,visibility}_pg_test.dart` (22/22),
   and the four standalone regression files (31/31) — all match.
5. The "source deleted before publish" ambiguous-spec decision (reject with
   `BEACON_PROMOTION_SOURCE_INVALID` when a promotion row exists with a
   nulled source and hasn't published yet) is reasonable and consistent
   with §4.1's "child remains, source link lost" principle applied to the
   not-yet-published case; recorded, not silently assumed.

Task 04 is ACCEPTED. Proceeding to Task 05 (lifecycle producers and
retained status audience).

### Task 05 — in progress (Cursor CLI worker, 2026-09-06)

**Owned paths:** `BeaconLifecycleEffectsCase`; producer wiring in
`beacon_case.dart`, `evaluation_case.dart`, `review_finalization_case.dart`;
`beacon_hierarchy_outbox_port.dart` + `insertTopologyDeliveryTargets`;
`beacon_notification_context.dart` + `beacon_room_notification_context_repository.dart`;
`attention_intent_case.dart`, `beacon_notification_recipient_resolver.dart`;
new tests + inventory/architecture test extensions.

### Task 05 — complete (Cursor CLI worker, 2026-09-06)

**Delivered**
- `BeaconLifecycleEffectsCase` implements §4.3 steps 2–3 (eligibility gate,
  `recordEvent`, set-based `insertTopologyDeliveryTargets`) inside caller
  transactions; no-op for draft delete, noop transitions, `reopenedFromReview`,
  `extendReviewWindow`.
- Producers wired (required non-null DI): `BeaconCase.beaconCancel`,
  `BeaconCase.deleteById` (published tombstone), `EvaluationCase.beaconClose`
  (immediate closed + reviewOpen branches), `ReviewFinalizationCase.closeAndFinalize`
  when `didClose` only. `closeNow`, `_autoCloseReviewWindow`, and
  `AttentionExpirySweepCase.runDue` delegate to finalizer without duplicate
  hierarchy Closed events.
- §4.4 audience: replaced `usersWithActiveCoordination` with
  `activeHelpOfferUserIds` / `activeRequestParticipantUserIds` /
  `activePlanParticipantUserIds` (active offers, `hasCurrentStake` +
  active offer, published active plans only).
- Set-based topology SQL on outbox port; PG EXPLAIN proof in lifecycle atomic test.

**Status-writer inventory (live code, beyond producer table)**
| Site | Classification |
|------|----------------|
| `coordination_case.dart::setBeaconStatus` | INELIGIBLE — open-family coordination menu only (`needsMoreHelp`/`enoughHelp`/`open`); not §4.3 lifecycle notices; still uses `requestStatusChanged` for retired coordination-adjacent attention |
| `evaluation_case.dart::reopenFromReview` | INELIGIBLE — local reopen per §4.3 closing paragraph |
| `evaluation_case.dart::extendReviewWindow` | INELIGIBLE — no status transition to notice-eligible terminal |
| `evaluation_repository.dart::closeReviewWindow` | delegates status write; hierarchy event owned by `ReviewFinalizationCase` only |

**Wrapping-up → Closed proof:** unit test in `beacon_lifecycle_effects_test.dart`
(records two events, sequences 1 then 2, `reviewOpen` then `closed`); PG test
`close on A reaches C through deleted intermediate B and records ordered events`
records wrapping-up then closed on same source with monotonic sequence.

**Verification**
```bash
./scripts/check-custom-lints.sh packages/server   # 0/0
./scripts/check-custom-lints.sh packages/client   # 32/32
cd packages/server && dart test --exclude-tags pg   # 1625/1625
dart test test/data/repository/beacon_hierarchy_lifecycle_atomic_pg_test.dart -t pg -j 1  # 3/3
dart test test/domain/use_case/beacon_lifecycle_effects_test.dart  # 5/5
dart test test/domain/attention/beacon_status_audience_test.dart  # 6/6
dart test test/domain/use_case/evaluation/review_finalization_case_test.dart  # extended
git diff --check  # clean on task paths
```

**Pre-existing PG failures (unchanged, not Task 05):**
`review_finalization_outcome_evidence_pg_test.dart`,
`room_message_reply_readback_pg_test.dart` on shared `postgres` DB only.

### Task 05 — manager review (2026-09-06)

Independently verified. Read `beacon_lifecycle_effects_case.dart` in full:
correctly delegates eligibility to Task 01's pure
`BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible` (from==draft,
reopenedFromReview reason, and noop transitions all correctly excluded;
eligible set is exactly {reviewOpen, closed, cancelled, deleted}) and
persistence to the outbox repository's `recordEvent`/
`insertTopologyDeliveryTargets`. Read the outbox SQL directly: `recordEvent`
atomically locks+increments+inserts under one CTE chain (no TOCTOU gap);
the recursive traversal correctly walks descendants and the immediate
published parent, direction-labels ancestor/child from the TARGET's
perspective (matches §4.4's "An ancestor request entered X" / "A child
request was closed" copy — verified this is not swapped), excludes the
source, dedupes by `(event,target)`, and passes through deleted/closed/
cancelled intermediates via the `published_at IS NOT NULL` filter alone
(exactly per §4.3 step 4).

Verified producer wiring is exactly-once and matches the manifest's
producer table precisely: `beacon_case.dart` wires only `beaconCancel`/
`deleteById` (confirmed the private-draft hard-delete branch returns before
reaching the hierarchy call, so drafts are never a source); `evaluation_case.dart`
wires only `beaconClose`'s two branches; `closeNow`/`_autoCloseReviewWindow`
have zero references (delegate-only); `attention_expiry_sweep_case.dart`
has zero references; `review_finalization_case.dart`'s call is placed after
the `snapshot == null` early return, so it only fires when `didClose`.
Cross-checked the two "extra status writer" classifications:
`coordination_case.setBeaconStatus` only ever transitions to
open-family statuses (`needsMoreHelp`/`enoughHelp`/`open`), none of which
are hierarchy-eligible even if wired — correctly left out; `evaluation_repository.closeReviewWindow`
has exactly one production caller (`closeAndFinalize`, already handled) —
confirmed via grep, not assumed.

Confirmed no GraphQL/API/client surface touched (only two GraphQL *test*
files bumped 2 lines each, for constructor-arg threading).

**One finding I initially misdiagnosed, corrected before commit:** I
suspected `_activeHelpOfferUserIds` was missing an active-only filter
(unlike its sibling `_activeRequestParticipantUserIds`'s explicit
`_isActiveOffer` check), since the existing `beacon_status_audience_test.dart`
never actually exercises `BeaconRoomNotificationContextRepository` against
real data (it only hand-constructs a `BeaconNotificationContext`). Verified
by reverting my own suspected fix and re-running a new real PG test: it
still passed, because `HelpOfferRepository.fetchByBeaconId` already filters
to `status=0` at the SQL level — never a live bug. Kept the explicit check
anyway (harmless, consistent with the sibling method) and kept the new PG
test (commit `2b036e3a3`) as a permanent regression guard, since the
underlying repository logic this task changed was otherwise completely
untested end-to-end.

Independently reran: `dart test --exclude-tags pg` (1625/1625), both
`check-custom-lints.sh` (server 0/0, client 32/32), `git diff --check`
(clean), `beacon_hierarchy_lifecycle_atomic_pg_test.dart` (3/3, including
the single-statement EXPLAIN proof and the rollback-together fault
injection), `transactional_attention_producer_inventory_test.dart` (5/5,
now covering the new producer), extended `review_finalization_case_test.dart`
(7/7, including the manual-vs-expiry shape-equality proof and the
didClose-gating proof) — all match.

Task 05 is ACCEPTED. Proceeding to Task 06 (durable hierarchy delivery
worker).

### Task 06 — manager review and acceptance (2026-09-06)

Two consecutive external memory-pressure kills on this task (see the two
salvage checkpoints above, commits `fc6151f1b` and `66b3afd12`). Both times
the manager verified with the real toolchain before committing anything —
including catching and correcting my own tooling mistake (an anchored
`grep "^error"` silently hiding real `dart analyze` errors that carry
leading whitespace) and, separately, my own inaccurate claim in the first
salvage commit message that `TaskWorkerCase`'s sweep wiring was left dead —
re-reading the full diff (not a truncated `sed` excerpt) showed it was
already correctly wired all along. Recorded both corrections rather than
letting an inaccurate record stand.

Independently verified the final state:
1. Read `beacon_hierarchy_delivery_case.dart` in full — `runDue` claims a
   batch, processes each target in its own logical unit via
   `TransactionalAttentionCase.runAction` (one Postgres transaction per
   target, matching §4.4), routes failures through `scheduleDeliveryRetry`
   with the capped-exponential-backoff safe-error policy, logs poison-
   threshold warnings without leaking source content, and exposes
   `parkPoisonedDeliveryAsOperator` as a distinct method never called by
   `runDue` itself.
2. Read the outbox repository SQL directly: `claimDueDeliveries` correctly
   implements `FOR UPDATE SKIP LOCKED`, due = pending-and-due OR leased-
   and-lease-expired, excludes rows with an earlier pending/leased event
   for the same target (the per-pair ordering guarantee), and excludes
   `attempt_count >= poisonAttemptThreshold` from ordinary selection.
   **Every one of `markDeliveryDelivered`/`markDeliverySuppressed`/
   `markDeliveryParked`/`scheduleDeliveryRetry` is owner-qualified**
   (`WHERE event_id=$1 AND target_beacon_id=$2 AND state='leased' AND
   lease_owner=$3`) — confirmed directly in the SQL, not inferred.
   `operatorParkPoisonedDelivery` is correctly unfenced (gates on
   `state='pending' AND attempt_count >= threshold` instead, since a
   poisoned row is never actively leased).
3. Read the claim-fencing and poison-escape-hatch PG tests line-by-line:
   both are genuine two-actor proofs — claim as worker-a, force-expire the
   lease via direct SQL, run a real `runDue()` as worker-b (which
   re-claims and delivers), then attempt worker-a's stale update directly
   and assert the row is unaffected (still `delivered` under worker-b).
   The poison test forces attempt_count to the threshold, confirms
   ordinary claim selection excludes it, parks it via the real operator
   method, and confirms a real subsequent `runDue()` now delivers the
   later same-pair event. Neither test is vacuous.
4. Confirmed the destination-audience-at-delivery-time test is real (fixed
   a wrong `room_access` seed value that made it initially fail).
5. Confirmed no GraphQL/API/client files touched anywhere across the whole
   task (`git diff --name-only` from before attempt 1 to HEAD).
6. Independently reran everything: `dart analyze` (properly this time)
   zero errors, `dart test --exclude-tags pg` 1634/1634, both new test
   files 8/8 and 12/12, existing outbox/lifecycle/commitment-attention PG
   suites unaffected, both lint baselines exact, `git diff --check` clean.

One accepted, documented limitation (not a defect): `BeaconHierarchyDeliverySafeError.classify`'s
`NoticeInsertFailure`/`AttentionDispatchFailure` substring branches can
never match a real production exception's `runtimeType` (only a test's
descriptive error *message* would contain those words, not its type name),
so in practice only `transactionFailed`/`unknown` are reachable from
`_processTarget`'s single blanket catch. The task's own test explicitly
documents and asserts this current behavior rather than hiding it, and the
prompt's instruction not to invent codes speculatively was correctly
followed — `unknown` is itself a valid safe code for an unrecognized
failure. Worth a note for Task 15's whole-product regression pass, not a
blocker now.

Task 06 is ACCEPTED. Proceeding to Task 07 (enforce General-only public
product).

### Task 07 — worker checkpoint (2026-09-06)

**Commits (this worker):**
- `1ddc79f26` — wire General-only + lifecycle write guards; split production/internal thread tests; `general_only_public_contract_test.dart` + `general_only_boundary_inventory_test.dart`; plan-only remind rules
- `a47e38033` — `m0156` DB triggers/functions; remove 25 retired GraphQL mutation fields; Hasura poll/state filters; disable responsibility projection
- `3250df6c9` — fix `getRoomMessageByLinkedPollingId` nullable Drift query; `retired_client_graphql_documents_test.dart`
- `e630b8715` — client repository/model/case + schema.graphql regeneration
- `b37e94ada` — delete 25 retired `.graphql` source files

**Guards wired:**
- `BeaconRoomCase`: `_rejectDisabledDiscussionScope` on list/mark/create/read paths; `_guardMessageMutation` on edit/delete/reaction/attachment/semantic-done; `_rejectOrdinaryUserWritesForLifecycle` on `createMessage`/`createPoll`; `listThreads` post-filters to General when `generalOnly`
- `PollingCase.create`: room-backed poll scope + lifecycle guard via linked room message
- Lifecycle boundary: ordinary user writes throw `BeaconCreateException(description: 'Discussion is read-only for this request')`; internal system-notice insertion bypasses app-level guards (DB trigger allows `system_message_kind IS NOT NULL` or null `author_id`)

**Regeneration (verified live):**
```bash
dart run bin/utils/run_migrations_once.dart          # applied m0156
./scripts/run-server-local.sh                        # server :2080
./scripts/hasura_apply_metadata.sh                   # is_consistent: true
docker compose run --rm schema_fetcher                 # updated schema.graphql
cd packages/client && dart run build_runner build -d   # Built in ~50s; 3974 outputs
```

**Tests:**
- `cd packages/server && dart test --exclude-tags pg` → 1651 passed
- `./scripts/check-custom-lints.sh packages/server` → 0 (baseline 0)
- `./scripts/check-custom-lints.sh packages/client` → 32 (baseline 32)
- `cd packages/client && flutter test --dart-define=ENV=test` → 2621 passed, 33 skipped

**Retired client documents:** 25 `.graphql` files removed under `coordination_item/data/gql/`; architecture test `retired_client_graphql_documents_test.dart` asserts absence.

**Note:** Retired coordination case methods on client remain as `UnsupportedError` stubs until Task 12 removes UI surfaces. PG suite for touched repos not re-run in this checkpoint (infra up; recommend `beacon_threads_repository_pg_test.dart` before manager acceptance).

### Task 07 — manager review and acceptance (2026-09-06)

Four external memory-pressure kills across this task's development (see
salvage checkpoints `96fa62e08`, `a8df29488`, `36b75466d` above), each
reviewed and salvaged before the final worker attempt completed the rest:
General-only + lifecycle write guards wired into every `BeaconRoomCase`
mutation surface plus `PollingCase.create`, `m0156` DB backstop, 25 retired
GraphQL mutations removed server-side, 25 client `.graphql` documents
deleted, Hasura poll/room-state filters tightened, and a verified-live
`schema_fetcher` + `build_runner` regeneration cycle.

Given this task's severity (breaking API removal + a brand-new DB-level
security guard), reviewed with the highest scrutiny used in this
orchestration:

1. Read `m0156.dart` in full. Confirmed the lifecycle-write-guard trigger's
   bypass for internal system notices (`system_message_kind IS NOT NULL OR
   author_id IS NULL`) and its blocked-status set (`beacon.status IN (1, 2,
   6)` = cancelled/deleted/closed, verified against the live `BeaconStatus`
   smallint mapping) are both correct.
2. **Found and fixed a critical, confirmed bug via direct SQL against a
   real disposable database, not just code reading**:
   `discussion_internal_fixture_allowed()` computed
   `current_setting(name, true) = 'allow_non_general'`, which evaluates to
   NULL (not false) whenever the GUC has never been SET — the case for
   every ordinary session. PL/pgSQL's `IF` treats a NULL condition as
   false, so the general-only guard trigger **never actually rejected
   anything in normal operation** — reproduced directly: a non-General
   insert on an open beacon with no bypass set silently succeeded.
   Fixed with `COALESCE(..., '')`, re-verified the full five-scenario
   matrix (reject-on-closed, permit-system-notice-on-closed, reject-non-
   General-no-bypass, permit-non-General-with-bypass, permit-ordinary-
   General) directly against Postgres, then wrote
   `m0156_general_only_lifecycle_guard_pg_test.dart` — the first and only
   direct test of this migration's triggers (commit `2b96efc65`).
3. That fix correctly restored REAL enforcement, which in turn (correctly)
   broke three pre-existing PG test files that fixture retired/thread-
   scoped rows directly via raw SQL or exercise repository methods with
   real thread-item ids to prove dormant mechanics below the case-layer
   guard: `beacon_threads_repository_pg_test.dart`,
   `attention_repository_pg_test.dart`, and (found via a systematic sweep
   for every PG test referencing `thread_item_id`/`semanticMarker`)
   `beacon_room_seen_upsert_pg_test.dart`. Fixed each with the same
   sanctioned bypass mechanism the new migration itself documents and
   tests, applied to the correct connection in each case (the raw `writer`
   for direct-SQL fixtures; the Drift-backed `database`/`db` — confirmed
   pinned to `maxConnectionCount == 1` in `tentura_db.dart`, so a single
   `SET` reliably persists — for tests exercising the repository API
   directly). Commits `dfdd566fd`, `d69c1599e`.
4. Verified the guard wiring is comprehensive: grepped every call site of
   `_rejectDisabledDiscussionScope`/`_rejectOrdinaryUserWritesForLifecycle`/
   `_guardMessageMutation` across `BeaconRoomCase` — covers
   createMessage/listMessages/markThreadSeen/roomMessageMarkSemanticDone/
   reactionToggle/addMessageAttachment/deleteMessage/editMessage/
   attachment download/createPoll, matching §5.2's full surface list.
5. Confirmed the 6 tests I had left `skip:`-marked in the prior salvage
   round were properly split (not just re-enabled): each file now builds
   both a `ProductionDiscussionProductPolicy` `sut` (asserting
   `DiscussionScopeDisabledException`) and a separate
   `InternalMultiThreadDiscussionProductPolicy` `internalSut` (asserting
   the original dormant-mechanics behavior) — read the diffs directly,
   confirmed no stray skips remain anywhere in the touched files.
6. Confirmed `InternalMultiThreadDiscussionProductPolicy` has zero
   references in `packages/server/lib/` outside its own definition (only
   test files use it), and `di.config.dart` has exactly one singleton
   registration for `DiscussionProductPolicyPort`, resolving to
   `ProductionDiscussionProductPolicy` — no bypass path exists in
   production.
7. Confirmed the retired-client-documents test
   (`retired_client_graphql_documents_test.dart`) is real (checks the
   actual filesystem directory against the exact 25 retired basenames) and
   passes; confirmed the client `gql` directory now has exactly 9 files
   (34 − 25, matching Task 00's independently-confirmed count).
8. Read the Hasura metadata diff: `polling` gets a `room_general_visible`
   computed field (backed by the already-verified `polling_room_general_visible`
   SQL, which correctly preserves standalone/non-room-linked polls
   unaffected); `polling_act`/`polling_variant` inherit the same via FK
   relationship rather than duplicating logic; `beacon_room_state`'s
   previous complex owner/steward/participant `_or` filter is replaced
   with a single `general_visible` computed field reusing Task 03's
   `beacon_effective_admission`. No new relationships, no widened columns.
9. Independently reran everything: full `dart test --exclude-tags pg`
   (1652/1652), `beacon_threads_repository_pg_test.dart` (12/12),
   `attention_repository_pg_test.dart` (17/17),
   `beacon_room_seen_upsert_pg_test.dart` (3/3),
   `m0156_general_only_lifecycle_guard_pg_test.dart` (5/5), both
   `check-custom-lints.sh` (server 0/0, client 32/32), `cd packages/client
   && flutter test --dart-define=ENV=test` (2621 passed / 33 skipped,
   matching the worker's report exactly), `git diff --check` clean.
10. Confirmed no stray local server process was left running after the
    live regeneration cycle.

This was the largest and highest-risk task in the plan, and also the one
requiring the most manager intervention: four salvage rounds plus one
critical bug found only through direct database verification. Task 07 is
ACCEPTED. Proceeding to Task 08 (safe request deletion and account
erasure).

### Task 08 — worker checkpoint (2026-09-06)

**Migration `m0157.dart` (commit `7133dd306`, manager-verified salvage):**
- `beacon.user_id` → nullable, `ON DELETE SET NULL`, check
  `beacon_owner_or_deleted_ck` (`user_id IS NOT NULL OR status = 2`).
- Nullable-and-anonymise FK forward migrations (live constraint names verified
  via `pg_constraint` on disposable DB): `beacon_fact_card.pinned_by`,
  `beacon_commitment_event.actor_user_id`,
  `beacon_help_offer_admission_event.actor_user_id`,
  `beacon_help_offer_coordination.author_user_id`,
  `coordination_item.{creator_id,target_person_id,accepted_by_id}`.
- **No migration needed (already nullable + SET NULL pre-m0157, re-verified
  live):** `beacon_activity_event.{actor_id,target_user_id}`,
  `beacon_room_state.updated_by`, `invite_genealogy.{ancestor_user_id,
  descendant_user_id}`, `beacon_room_message.author_id` (Task 02 `m0154`).
- **`beacon_help_offer.user_id` — manifest says nullable-and-anonymise but
  column is part of composite PK `(beacon_id, user_id)`:** attempted
  `DROP NOT NULL` fails with `42P16`; disposition stays **`cascade-is-correct`**
  (offer rows removed with account; cannot anonymise owner in PK).

**Account-erasure transaction sequence (`UserErasureCase.deleteById`, §4.5
point 2):**
1. `TransactionalAttentionCase.runAction` (attention UoW).
2. `BeaconHierarchyRepositoryPort.lockMutationScope()`.
3. For each owned published beacon (`published_at IS NOT NULL`, not draft):
   - If already deleted: scrub content only.
   - Else: `runInBeaconStateTransaction` →
     `BeaconLifecycleEffectsCase.recordEligibleSourceTransition` (deleted) →
     `BeaconRepository.recordBeaconStatusTransition` →
     `UserErasurePort.scrubDeletedOwnedBeaconContent` (placeholders
     `'Deleted request'` / `'This request was deleted.'`, clear optional
     fields/media refs, delete owned `image` rows inside txn).
4. Hard-delete owned draft beacons (`DELETE FROM beacon WHERE status = draft`).
5. `deleteUserScopedEvaluationAndCapabilityRows` (scrub-then-delete tables:
   `beacon_evaluation*`, `person_capability_event`).
6. `deleteOwnedImageRows` (profile/other author-scoped `image` rows).
7. **`deleteOrdinaryRoomMessagesAuthoredByUser`** — `DELETE FROM
   beacon_room_message WHERE author_id = $user AND system_message_kind IS NULL`
   (required so user delete's SET NULL on `author_id` does not violate
   `beacon_room_message_author_or_system_ck`; system hierarchy notices keep
   rows with null author).
8. `UserRepository.deleteById` — owner FKs SET NULL; `beacon_owner_or_deleted_ck`
   blocks raw delete while non-deleted owned requests remain.
9. **Post-commit only:** `ImageObjectGcPort.enqueue` for collected image ids
   (no object-store delete inside DB txn).

**Structural/tombstone read path (§4.5 point 6):**
- `BeaconStructuralRecord` + `BeaconHierarchyRepository.loadStructuralRecord`.
- `BeaconRepository.getBeaconById`: null `user_id` on deleted status →
  `BeaconStructuralOnlyException` (not a fake populated entity).

**Tests added/extended:**
- `beacon_hierarchy_erasure_pg_test.dart` (6 PG tests: A/B hierarchy erasure,
  raw `DELETE FROM user` denied, rollback fault injection, FK dispositions,
  delivered hierarchy notices survive author erasure).
- `user_delete_attention_pg_test.dart` wired through `UserErasureTestStack`.
- `BeaconHierarchyFixture.seedFullTopology` sets
  `tentura.discussion_internal_fixture = allow_non_general` (Task 07 guard bypass
  for retired-thread fixture rows); tearDown also clears hierarchy delivery/event
  rows before beacon delete.

**User-FK disposition handling (Task 00 manifest, verified at erasure time):**
| Disposition | Handling |
|---|---|
| nullable-and-anonymise actor columns | SET NULL on user delete (m0157) |
| `beacon_room_message.author_id` (system notices) | SET NULL; CHECK satisfied via `system_message_kind` |
| `beacon_room_message.author_id` (ordinary) | deleted in step 7 before user row |
| scrub-then-delete evaluation/capability/image | explicit DELETE in steps 5–6 |
| `beacon_help_offer.user_id` (PK) | CASCADE removes offers |
| cascade-is-correct | unchanged |

### Task 08 — worker completion (2026-09-06)

Verification:
- `./scripts/check-custom-lints.sh packages/server` → 0/0; client → 32/32.
- `cd packages/server && dart test --exclude-tags pg` → 1651/1651.
- PG: `beacon_hierarchy_erasure_pg_test.dart` 6/6,
  `user_delete_attention_pg_test.dart` 2/2,
  `beacon_hierarchy_delivery_pg_test.dart` 12/12 (fixture bypass fix restores
  suite under live m0156 guard).
- Commits: `7133dd306` (migration salvage) + Task 08 erasure implementation
  commit (this worker turn).

Task 08 complete. Proceeding to Task 09 when scheduled.

### Task 08 — manager review and acceptance (2026-09-06)

One salvage round (killed by external memory pressure before its first
commit — found and fixed two real defects verified live: a missing `part
'm0157.dart';` registration that meant the whole migration silently didn't
exist, and a wrong guessed constraint name that left
`beacon_help_offer_coordination` with two conflicting FKs on the same
column; see commit `7133dd306`). The completing attempt added the full
domain-owned erasure transaction (`UserErasureCase`), structural/tombstone
read-path support, and the remaining 3 nullable-and-anonymise tables plus
scrub-then-delete handling.

Independently verified:
1. `beacon_help_offer.user_id` staying `CASCADE` is correct and
   unavoidable — confirmed the table's primary key is the composite
   `(beacon_id, user_id)`, so `user_id` cannot be nullable at all.
2. **Investigated a consequence of that CASCADE directly against a live
   database rather than trusting the code**: `beacon_commitment_event` and
   `beacon_help_offer_admission_event` both carry a composite FK to
   `beacon_help_offer(beacon_id, user_id)` with `ON DELETE CASCADE`, so
   erasing the OFFERING user removes not just their offer row but every
   commitment/admission event tied to that pair — even ones where a
   different, still-live user was the acting party. Verified separately
   that erasing a mere commitment ACTOR (not the offerer) correctly
   anonymises the event in place instead. Neither property had any test
   coverage before this review. This is a defensible, intentional
   consequence (the offer's own identity disappearing removes its whole
   lifecycle together, same as a user's own messages being deleted rather
   than orphaned) — added one test making both properties explicit and
   verified rather than an unverified side effect (commit `0834ee2f9`).
3. Read the "failed erasure rolls back completely" test — genuine fault
   injection (`_FailingUserRepository.failOnDelete` throws deep inside the
   real `deleteById` call, at the END of the erasure sequence), and the
   test asserts the beacon's status/title/description/user_id are ALL
   still their original un-scrubbed values, proving the whole sequence —
   not just the final step — rolled back together.
4. Confirmed no object-store deletion happens inside the DB transaction:
   `_imageObjectGc.enqueue(...)` calls are outside the
   `_hierarchyRepository`-locked transaction block, firing only after
   commit.
5. Confirmed the raw-delete-denied backstop
   (`beacon_owner_or_deleted_ck`) fires correctly at the DB level for a
   direct `DELETE FROM "user"` bypassing the application entirely.
6. Independently reran: full `dart test --exclude-tags pg` (1651/1651,
   1652 pre-existing minus the deliberate legacy-cascade behavior change
   accounted for), `beacon_hierarchy_erasure_pg_test.dart` (7/7 including
   the new test), `user_delete_attention_pg_test.dart` (2/2),
   `beacon_hierarchy_delivery_pg_test.dart` (14/14, unaffected), custom-
   lints baseline unchanged, `git diff --check` clean.

Task 08 is ACCEPTED. Proceeding to Task 09 (scoped legacy cleanup
migration).

### Task 09 — manager review and acceptance (2026-09-06)

Highest-blast-radius task in the plan (irreversible legacy ask/promise/
blocker + non-General thread cleanup, m0158). Multiple worker attempts
were killed by external memory pressure; the surviving migration body was
salvaged and committed at `7277c7856` (see its message for the full
salvage story), with the required acceptance test still missing at that
point. A further attempt produced
`test/data/database/nested_requests_cleanup_pg_test.dart` but was itself
killed before finishing; salvaged directly by the manager rather than
dispatching a fourth Cursor attempt blind, per the remediation-loop rule
(same defect class, second consecutive kill on this file):

1. The salvaged test tried to fixture a `beacon_promotions` row whose
   `source_message_id` pointed at a non-General (doomed) message. Verified
   directly against the live schema that this is unconstructible: m0154's
   `beacon_promotions_consistency_guard` trigger rejects any insert/update
   whose source message has a non-null thread scope, at draft time as
   well as publish time (plan §3.4.9). Removed the impossible fixture
   INSERT and its corresponding assertion — there is nothing for m0158's
   own provenance-nulling UPDATE to exercise on that table under the live
   schema.
2. With that fixed, the suite got past `setUpAll` but failed the main test:
   `Rm158survlnk1` (a real General user message meant to survive cleanup
   with just its footer link cleared, per plan §5.3 step 4: "prefer
   deletion of obsolete system anchor rows, keeping user messages") was
   being fully deleted instead. Traced to root cause by reading
   `CoordinationItemRepository._emitCreatedRoomNotify` directly: it sets
   `linked_event_kind` unconditionally on every message it ever touches —
   both the disposable, empty-bodied system-notify row it creates for
   itself, AND (in its linked-source-message branch) the pre-existing real
   user message it updates in place to carry the same footer. m0158's
   step-4 DELETE criterion (`linked_event_kind IS NOT NULL`) could not
   tell these apart and deleted both. Fixed by adding `AND m.body = ''` to
   the DELETE, matching the one column that actually distinguishes a
   bodyless system-notify anchor from a real user message carrying an
   incidental retired-item footer. Verified against the fixture's own
   `systemAnchorMessageId` (empty body, correctly deleted) vs.
   `survivorLinkedMessageId` (non-empty body, now correctly survives with
   `linked_item_id`/`linked_event_kind`/`system_payload` all cleared by
   the following UPDATE).
3. Independently reran (not trusting prior worker-reported results):
   `dart analyze` on both changed files — zero errors (only pre-existing
   `info`-level lint noise); `dart test -t pg` on
   `nested_requests_cleanup_pg_test.dart` — 3/3 passing, including the
   `nested_requests_apply_legacy_cleanup is safe to invoke again`
   re-invocation idempotency test; `dart test -t pg` on
   `beacon_hierarchy_erasure_pg_test.dart` (7/7) and
   `beacon_hierarchy_fixture_pg_test.dart` (5/5) to confirm the migration
   fix didn't disturb Task 08's erasure suite — unaffected, still green.
4. Confirmed via `git log` that `m0158.dart` had only ever been committed
   locally (`7277c7856`) and never applied to any shared/persistent
   database — disposable test databases are dropped every run — so
   amending its DELETE criterion before Task 09's final acceptance does
   not violate the plan's migration-immutability rule (that rule protects
   migrations already applied somewhere real, not in-progress local work
   within the same task).
5. Commit: `46e3805e3` (test suite + migration fix, single focused
   commit — the fix and the test that caught it belong together).

Task 09 is ACCEPTED. Proceeding to Task 10 (V2 hierarchy schema and
generated client transport).

### Task 10 — first attempt killed; foundation salvaged (2026-09-06)

First Cursor worker attempt was killed by external memory pressure before
its first commit. Diff inspection found real, correctly-scoped
foundational progress (not a false start): extraction of the existing
private cursor encode/decode pair out of `BeaconHierarchyRepository`
(added by Task 02) into a new shared
`packages/server/lib/domain/beacon_hierarchy_cursor.dart`, a new typed
`BeaconHierarchyCursorInvalidException` replacing the previous generic
`UnspecifiedException` on cursor decode failure (matching §3.5's
`BEACON_HIERARCHY_CURSOR_INVALID`), and GraphQL object-type declarations
in `custom_types.dart` for all five new hierarchy operations' result
shapes — verified field-by-field against the actual domain entities
under `lib/domain/entity/` rather than guessed.

Found and fixed two real defects, both careless import edits from the
kill, before accepting any of it:
1. `gql_v2_dto_maps.dart`'s new import block deleted the pre-existing
   `beacon_close_review_result.dart` import instead of inserting above
   it — `BeaconCloseReviewResult` (used later in the same file) went
   undefined. Restored the import.
2. `beacon_hierarchy_repository.dart`'s import cleanup dropped the file's
   only `exception.dart` import (reasonable-looking, since the cursor
   methods being extracted were its only visible user in the diff) but
   missed that `loadPromotionSource` in the same file independently
   throws `IdNotFoundException` from that same import. Restored it.
Also fixed a trailing-blank-line-at-EOF left by the extraction
(`git diff --check` violation).

Independently verified after both fixes: `dart analyze lib` — 0 errors;
`dart test -t pg` on `beacon_hierarchy_repository_pg_test.dart` (8/8,
confirming the cursor extraction preserved pagination behavior exactly,
same test file Task 02/03 already relied on); `dart test --exclude-tags
pg` (1651/1651); custom-lints baseline unchanged (0/0); `git diff --check`
clean. Commit: `4f4b22206`.

Not accepted as task-complete — no `query_beacon_hierarchy.dart`,
`mutation_beacon_hierarchy.dart`, registry wiring, DTO-mapping functions,
Hasura metadata reload, schema_fetcher regeneration, or any client-side
transport exist yet. A fresh worker continues Task 10 from this
foundation.

### Task 10 — second attempt killed; GraphQL resolvers salvaged (2026-09-06)

Second Cursor worker attempt also killed by external memory pressure
before its first commit (system had 50GiB available at review time but
~7.7GiB in swap — likely a transient spike from cursor-agent + build
tooling running alongside other desktop applications, not a sustained
shortage; not something to work around by touching unrelated processes).
This attempt made real, correctly-scoped progress on top of the first
attempt's salvaged foundation (`4f4b22206`):

- `query/query_beacon_hierarchy.dart` (new): `beaconHierarchyCapabilities`,
  `beaconChildren`, `beaconParentReference`, `beaconPromotionSource` —
  thin resolvers over the already-implemented
  `BeaconHierarchyRepositoryPort`.
- `mutation/mutation_beacon_hierarchy.dart` (new): `beaconChildCreate` —
  thin resolver over the already-implemented `BeaconChildCreatePort`,
  correctly reusing the existing `InputFieldBeaconTitle`/`Description`/
  `Coordinates`/`Context` wrappers from `beaconCreate` rather than
  duplicating them.
- Five DTO-mapping functions added to `gql_v2_dto_maps.dart`.
- Both resolver classes registered in `_queries_all.dart`/
  `_mutations_all.dart`.

Manager review, before accepting:
1. Confirmed the resolvers do not locally catch
   `BeaconHierarchyCursorInvalidException` — verified this is correct,
   not an oversight: this codebase already funnels every `ExceptionBase`
   through one top-level `on ExceptionBase catch` in
   `graphql_controller.dart:90`; no other resolver in the codebase
   catches domain exceptions locally either.
2. Confirmed `beaconChildCreateResultToGqlMap` never exposes the full
   `beacon` object for the `alreadyPromoted` outcome (only for
   `created`/`replayed`) — matches plan §4.3's "carrying the existing
   child ID only if currently readable" / §3.5's "do not disclose a
   conflicting child ID before authorizing it".
3. Confirmed the existing `beaconPublish` mutation needed no changes:
   read `BeaconCase.publishDraft` directly and confirmed it already
   branches to `_childCreateCase.publishDraft` when
   `beacon.parentBeaconId` is set (Task 04), so child-draft publication
   was already wired at the domain layer before this task started.
4. Wrote and ran a throwaway schema-build smoke test (real prod DI via
   `configureDependencies`/`getIt.allReady`, then constructed
   `graphqlSchema` directly) to catch schema-wiring failures `dart
   analyze` cannot see (duplicate type names, unresolved GraphQL type
   references) — passed, then discarded; not a permanent addition.
5. Independently reran: `dart analyze lib` 0 errors; `dart test
   --exclude-tags pg` 1651/1651; `test/app/di_smoke_test.dart` (prod+dev
   DI graphs resolve, pre-existing, unaffected); custom-lints baseline
   unchanged (0/0); `git diff --check` clean. Commit: `38db4c001`.

Not accepted as task-complete — still missing Hasura metadata reload,
schema_fetcher regeneration, all client-side transport (`.graphql`
documents, direct-routing registration, repository/adapter, DI), and all
four required tests. A fresh worker continues Task 10 from here.

### Task 10 — third attempt killed with zero progress; manager takes over directly (2026-09-06)

Third consecutive Cursor worker attempt on Task 10 was killed by external
memory pressure, this time before producing any file changes at all (git
status was identical to the pre-launch snapshot). Its log shows it was
mid-exploration of starting a local server process to introspect the V2
schema for the Hasura reload step when killed — starting a live Dart
server process alongside cursor-agent's own overhead is a plausible
trigger for the memory spike, on top of the same pattern seen repeatedly
elsewhere in this session (Tasks 04, 06, 07, 09 also required multiple
kill/salvage cycles).

Per the overseer skill's remediation-loop rule ("If the same defect
survives two well-scoped Cursor attempts, stop dispatching further Cursor
attempts and take over diagnosis yourself... Do not accept a third blind
Cursor retry without first understanding why the first two failed"): this
is the third consecutive kill on this task with no net new committed
progress from this attempt. Stopping Cursor dispatch for the remainder of
Task 10. The manager is completing the remaining scope directly (Hasura
metadata reload, schema_fetcher regeneration, client-side transport, and
the four required tests), building on the already-accepted, verified
server GraphQL surface from commits `4f4b22206`/`38db4c001`.

### Task 10 — manager completion and acceptance (2026-09-06)

After three consecutive Cursor worker kills (the last with zero committed
progress), completed the remaining Task 10 scope directly rather than
dispatching a fourth blind attempt, per the overseer skill's remediation-
loop rule:

1. Started the local Tentura dev server (`dart run bin/tentura_dev.dart`,
   port 2080, root `.env` loaded) and ran
   `./scripts/hasura_apply_metadata.sh` — `is_consistent: true`, no
   inconsistent objects — to reload the Tentura remote schema with the
   five new V2 fields from commits `4f4b22206`/`38db4c001`.
2. Regenerated `packages/client/lib/data/gql/schema.graphql` via
   `docker compose run --rm schema_fetcher`; confirmed it contains
   `beaconHierarchyCapabilities`/`beaconChildren`/`beaconParentReference`/
   `beaconPromotionSource`/`beaconChildCreate` and no retired public
   coordination mutations. Commit `b70ee3061`.
3. Added the five client `.graphql` documents, registered them in
   `_tenturaDirectOperationNames`, added typed client-side translation for
   all nine of §3.5's error codes (`BeaconHierarchyException` sealed
   hierarchy + `throwIfBeaconHierarchyError`, wired into `_V2RoutingLink`'s
   existing `onGraphQLError` — the codebase's one prior precedent for
   numeric-code translation, at the link layer, same as
   `BeaconFactAlreadyPinnedException`). Ran client codegen. Commit
   `b70ee3061`.
4. Added `BeaconHierarchyRepositoryPort`/`BeaconHierarchyRepository`
   under `features/beacon/` (matching the plan's own stated test path,
   not `features/beacon_threads/`), reusing the shared `tentura_root`
   hierarchy entities directly rather than duplicating client-local
   copies. Registered via `@Singleton`, confirmed in the generated
   (gitignored) `di.config.dart`. Commit `d9b41013e`.
5. Wrote all four required acceptance tests:
   - `packages/client/test/data/service/beacon_hierarchy_direct_routing_test.dart`
     (2/2) and `packages/client/test/features/beacon/beacon_hierarchy_repository_test.dart`
     (8/8) — the latter required refactoring the repository's five inline
     mapping blocks into `@visibleForTesting` static methods so the test
     exercises the real mapping code via a fake Ferry `Link`, matching
     the existing `beacon_threads_repository_test.dart` precedent. Commit
     `4a9e190c7`.
   - `packages/server/test/api/beacon_hierarchy_graphql_contract_test.dart`
     (11/11) — invokes the real `QueryBeaconHierarchy`/
     `MutationBeaconHierarchy` resolvers directly against real ports
     backed by a disposable Postgres database with real JWT auth (no
     Hasura), reusing `beacon_child_create_atomic_pg_test.dart`'s exact
     dependency wiring. Found and fixed two real fixture-interaction
     bugs while writing it (wrong viewer for the parent-reference
     "admitted" case — the one-edge grant needs admission to the PARENT,
     not the child under test; description validation runs before
     authorization checks in `BeaconChildCreateCase`, so every createChild
     call needs a valid description even when testing a later failure
     path) and one test-hygiene gap (dynamically created child beacons
     need their own tearDown cleanup before the fixture's own topology
     teardown, or its FK blocks on them). Ran twice consecutively to rule
     out order-dependent flakiness. Commit `692d552d9`.
6. Independently reran the full picture: `dart analyze` 0 errors on both
   packages; `dart test --exclude-tags pg` 1651/1651 (server);
   `flutter test` on all new client test files; the two other
   hierarchy-adjacent PG suites (`beacon_hierarchy_repository_pg_test.dart`
   7/7, `beacon_child_create_atomic_pg_test.dart` 13/13) unaffected;
   custom-lints baseline unchanged on both packages; `git diff --check`
   clean throughout.

All four plan-specified acceptance criteria are met: the three named test
files exist and pass; each operation was exercised over direct V2 with
real user auth, proving results/errors map correctly and unauthorized/
invalid IDs are rejected without disclosure; the regenerated schema
contains the new fields and no retired public mutations; DI bootstraps
correctly for both server (di_smoke_test.dart, unaffected) and client
(generated di.config.dart registration confirmed, exercised by the
passing repository test).

Task 10 is ACCEPTED. Proceeding to Task 11 (extend existing composer/
save flow).

### Task 11 — complete (Cursor CLI worker, 2026-09-06)

**Architectural decision:** Added a separate `BeaconHierarchyCase` rather than
extending `BeaconCreateCase` internals. Child field creation uses
`BeaconHierarchyRepositoryPort.createChild` (V2 transport from Task 10); media
staging/reconcile and draft updates reuse `BeaconCreateCase` unchanged.
Standalone `BeaconCreateCase.create/saveDraft/makeLive` paths are untouched.

**Delivered**
- `packages/client/lib/domain/use_case/beacon_hierarchy_case.dart`:
  `openComposer` (clientCommandId mint/persist via
  `BeaconChildCommandStorePort`, promotion source preview seeds description
  only), `ensureChildDraft`/`saveChildDraft` (idempotent create + exact-retry
  snapshot for ambiguous responses + update-after-recovery), `publishChildDraft`
  (existing `BeaconWritePort.publishDraft`, publish-phase `BeaconSaveFailure`),
  typed `BeaconChildPromotionConflict` for `alreadyPromoted`.
- `BeaconChildCommandStorePort` + `BeaconChildCommandStore` (secure storage,
  keyed by parent/source context).
- `BeaconCreateCase`: `BeaconSavePhase.publish`, optional
  `BeaconSaveFailure.clientCommandId`, public `reconcileMedia`, `copyWith` on
  `BeaconSaveCommand`.
- `BeaconCreateCubit`/`State`: optional `childCreationContext` constructor
  param; child-mode routing for ensureDraft/saveDraft/makeLive/deleteDraft;
  `childPromotionConflict` + `existingPromotedChildBeaconId` UI state;
  hierarchy case resolved from DI only when `childCreationContext != null`
  (standalone widget tests unaffected).

**§3.4 coverage**
| Requirement | Implementation |
|---|---|
| clientCommandId at composer open, persisted across retry/restart | `openComposer` + `BeaconChildCommandStore` |
| Restored draft uses canonical id, no fresh command | `openComposer(restoredDraftBeaconId:)` → null command id |
| draft-first create via hierarchy port, media after | `createChild(draft:true)` then `reconcileMedia` |
| Exact retry before edited resubmit | `exactRetrySnapshot` on `BeaconChildSaveCommand` |
| alreadyPromoted never treated as own publication | `BeaconChildPromotionConflict` + cubit state flag |
| Publish via existing `publishDraft` | `publishChildDraft` → `BeaconWritePort.publishDraft` |
| Denial keeps draft/media | publish-phase failure preserves beaconId/images |
| Promotion preview seeds description only | `fetchPromotionSource` once at open |

**Verification**
```bash
cd packages/client
flutter test test/domain/use_case/beacon_child_save_test.dart \
  test/features/beacon_create/beacon_child_create_cubit_test.dart   # 18/18
flutter test test/features/beacon_create/ test/domain/use_case/    # 129/129
dart analyze lib/domain/use_case/beacon_hierarchy_case.dart \
  lib/domain/use_case/beacon_create_case.dart \
  lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart \
  lib/data/service/beacon_child_command_store.dart                  # 0 errors (1 info)
dart analyze test/domain/use_case/beacon_child_save_test.dart \
  test/features/beacon_create/beacon_child_create_cubit_test.dart   # 0 issues
./scripts/check-custom-lints.sh packages/client                       # 32/32 baseline
```

**Commits**
- `825ed279d` — `feat(client): add BeaconHierarchyCase for child draft-first save`
- `c9685fd51` — `feat(client): wire child creation into BeaconCreateCubit`
- `67de5744d` — `test(client): add child save and cubit acceptance tests for Task 11`

**Deferred to Task 12:** Screen/route wiring passing `childCreationContext` from
promotion entry points, l10n for promotion-conflict copy, and dedicated child
composer navigation (this task delivers the save protocol + cubit hooks only).

**Next task:** Task 12 — child request surface, General host, and safe navigation.

### Task 11 — manager review and acceptance (2026-09-06)

Cursor worker completed in one clean pass (no kills), four commits
(`825ed279d`, `c9685fd51`, `67de5744d`, `7c9b8322d`). Reviewed the full
diff and design directly rather than trusting the worker-reported 18/18
and 129/129:

1. Confirmed the `_saveChild` exact-retry-then-edit-apply logic
   (`BeaconHierarchyCase._saveChild`/`_sameCreatePayload`) genuinely
   implements §3.4.4: when `exactRetrySnapshot` differs from the current
   (possibly user-edited) `saveCommand`, it retries the ORIGINAL
   pre-edit payload first to recover the canonical id, then applies the
   edited fields as an ordinary draft update — verified directly against
   its test ("changed form after unknown result"), which asserts the
   hierarchy `createChild` call received the original title while the
   subsequent draft update received the edited title.
2. Confirmed `BeaconCreateCase`'s changes (`BeaconSavePhase.publish`,
   `BeaconSaveCommand.copyWith`, nullable `BeaconSaveFailure.
   clientCommandId`, public `reconcileMedia`) are purely additive —
   nothing in the existing standalone `create`/`saveDraft`/`makeLive`
   paths was touched.
3. Confirmed `BeaconCreateCubit`'s `_hierarchyCase` is resolved from
   `GetIt` only when `childCreationContext != null`, and every child-mode
   branch has a parallel unmodified standalone `else` branch — verified
   directly (not just via the passing regression count) by reading the
   full diff, and confirmed by the worker's own two "normal standalone
   regression" tests asserting the ORIGINAL `BeaconCreateCase`/
   `BeaconWritePort` methods are what standalone mode still calls.
4. **Traced the server's actual `alreadyPromoted` trigger conditions**
   directly in `beacon_child_create_case.dart` (server) rather than
   trusting the client design: `createChild`'s own
   `existingChildId != null → alreadyPromoted` early-exit is gated on
   `!draft` — since `BeaconHierarchyCase._runCreateChild` always sends
   `draft: true` (this client's draft-first architecture never varies
   this), that branch can never fire for this client's `createChild`
   calls in practice. The actually-reachable trigger for this
   architecture is `publishDraft`'s own race check (`_PromotionRaceLost`
   → `BeaconSourceAlreadyPromotedException`), thrown when a concurrent
   publisher wins the same source between this draft's creation and its
   publish attempt — exactly plan §3.4.6's described scenario. Found
   that `BeaconHierarchyCase.publishChildDraft`'s catch-all wrapped this
   as a generic `BeaconSavePhase.publish` `BeaconSaveFailure` instead of
   the typed `BeaconChildPromotionConflict` `_runCreateChild` already
   produces for the (rarely reachable) create-time variant — the UI
   would have shown a plain error instead of the intended promotion-
   conflict state, and `existingChildBeaconId` would never have reached
   the composer. Fixed directly: `publishChildDraft` now catches
   `BeaconSourceAlreadyPromotedException` and throws
   `BeaconChildPromotionConflict`, matching `_runCreateChild`'s handling.
   Confirmed via code read that `BeaconCreateCubit.makeLive`'s existing
   `on BeaconChildPromotionConflict catch` wiring was already present but
   dead until this fix — the worker's cubit code anticipated this
   correctly even though the underlying case-layer bug prevented it from
   ever firing.
5. Also fixed a latent, lower-severity bug found in the same review:
   `_runCreateChild`'s `alreadyPromoted` branch set
   `draftBeaconId: outcome.beaconId`, but `outcome.beaconId` in that
   branch names the OTHER (already-published, winning) child, never a
   draft belonging to the current actor — no draft is ever created for
   this actor in that branch. Left as-is, `BeaconCreateCubit`'s
   `draftId: state.draftId ?? conflict.draftBeaconId` would have
   hijacked the composer's own draft id to someone else's beacon ID (not
   observed in practice today since this branch is effectively
   unreachable for this client's draft:true-only usage, but a real
   latent bug — removed the incorrect field, leaving it null).
6. Added a use-case-level test for the actually-reachable publish-time
   scenario (`beacon_child_save_test.dart`: "a publish-time race loss
   surfaces as a promotion conflict, not a generic publish failure") —
   the worker's own "promotion conflict" test only covered the
   create-time discriminator (the unreachable path), and its "denied
   publication" test used a different exception
   (`BeaconParentNotCoordinatableException`), so nothing had exercised
   the real trigger before this review.
7. Independently reran (not trusting worker-reported numbers):
   `dart analyze` on the changed files — 0 issues; `flutter test` on
   both new test files — 19/19 (was 18/18, +1 for the new test); the
   broader `test/features/beacon_create/` + `test/domain/use_case/`
   suite — 130/130 (was 129/129); custom-lints baseline unchanged
   (32/32); `git diff --check` clean. Fix commit: `b474afcaf`.

Task 11 is ACCEPTED (with the above remediation). Proceeding to Task 12
(child request surface, General host, and safe navigation).

### Task 12 — worker timed out; manager salvaged, fixed, and dispatched scoped remediation (2026-09-06)

Cursor worker hit its own 1-hour hard timeout (exit 124) with zero
commits. Found and killed one orphaned `flutter test` child process
(PID surviving the worker's own kill, 7:45 elapsed, running the very
test files this task added) before reviewing — a reminder that a
`timeout`-wrapped worker's own child processes are not always reaped
with it; checked for and cleaned this up per standing practice.

Reviewed the full uncommitted diff (19 changed files, ~2400 lines) directly:

1. Reverted one out-of-scope change: the worker bumped
   `packages/client/pubspec.yaml`/`web/index.html`'s cache-busting
   version string 6.16.4 → 6.16.5 — not part of this task; a version
   bump is a deliberate release decision. Reverted both.
2. Fixed 4 real `dart analyze` warnings the worker's own pass had missed
   (unused imports in three files, one unnecessary null assertion).
3. Found ~240 lines of newly-dead code in `beacon_room_body.dart`
   (`_showPromoteFieldsDialog`/`_admittedParticipantsForPromote`/
   `_needInfoTargetLabel`/`_PromoteFieldsSheet(State)` — the retired ask/
   promise/blocker "promote fields" dialog, unreferenced after the
   message-action rewiring to "Create child request") — confirmed via
   `dart analyze`'s `unused_element` warning, traced every reference,
   confirmed the still-live `_BeaconRoomTextBottomSheet`/
   `showBeaconRoomUpdatePlanSheet` sitting immediately after it in the
   same file were NOT part of the same dead chain (still used at three
   other call sites), and removed exactly the dead range. This is
   precisely what plan §Task 12 asks for ("remove retired creation
   controls... this task removes only the remaining UI surfaces") —
   the worker had stopped calling the dead code but not deleted it.
4. **Root-caused the worker's own stall directly**, since I had already
   independently confirmed the exact same test file hangs when run
   standalone: `nested_beacon_navigation_test.dart`'s "router pop after
   nested push drops child from stack" test called
   `await router.push(BeaconViewRoute(id: 'child-1'))` — AutoRoute's
   `push()` returns a Future that only resolves when the pushed route is
   POPPED, not when the push itself completes (confirmed against this
   repo's own established pattern in
   `test/app/router/home_tab_branch_routing_test.dart`, which always
   wraps `router.push(...)` in `unawaited(...)`). The test awaited that
   Future three lines before ever calling `router.pop()` — a genuine
   self-deadlock, not a `flutter pub get`/tooling flake as the worker's
   own log concluded while it repeatedly re-ran the same hanging test
   under a 15s-per-test cap for over two minutes. Fixed with
   `unawaited(...)` + `pumpAndSettle()`; confirmed directly (240s
   timeout → <1s, 5/5, twice).
5. Independently reran EVERY changed/new test file individually (not
   trusting a single combined multi-directory run, whose
   `--reporter compact` output turned out to have serious sticky
   line-overwrite artifacts in a non-interactive terminal — spot-checked
   one apparently-failing file from that noisy run
   (`help_offer_chip_roundtrip_test.dart`) in isolation and found it
   fully passing, confirming the combined run's signal was unreliable
   for files outside this task's own diff): `beacon_hierarchy_cubit_test.dart`
   9/9, `beacon_hierarchy_view_test.dart` 5/5, `nested_beacon_navigation_test.dart`
   5/5, `threads_cubit_test.dart` 7/7, `threads_list_test.dart` 4/4,
   `beacon_operational_scroll_view_pinned_facts_test.dart`/
   `beacon_tab_reselect_folds_test.dart` 3/3 (+1 legitimately skipped,
   documented reason), `promise_composer_live_wiring_test.dart` 1
   skipped with a clear "retired from Discussion overview (Task 12)"
   comment.
6. Found two files with genuine, real failures, both the same root
   cause: `request_threads_adaptive_test.dart` (9 of 18 failing) and
   `thread_detail_test.dart` (2 of 5 failing) both assert on retired
   semantic ask/item-thread rendering (`request.thread.item-only-thread`,
   `request.thread.log-ask` row keys; `ThreadDetailTitle` for an "ask
   thread"; an "item-only authorization" model; item-inclusive unread
   badge totals) that `threads_list.dart`/`thread_detail_screen.dart`
   correctly no longer produce after this task's intentional removal.
   Traced one representative case (`draft row opens composer` —
   constructs an unpublished coordination-item draft and expects it to
   open the old `coordinationComposerTitle`) to confirm this is testing
   retired functionality, not a real regression. Left both files
   uncommitted (they still compile — the worker's own edits kept them
   buildable — but 11 assertions need updating/pruning to match the new
   behavior, which requires case-by-case judgment about what layout
   coverage is still worth preserving vs. what's purely retired).

Committed the verified-good salvage in two commits: `8601e904b`
(production code) and `239c008d8` (passing tests + the router fix).
Dispatching a fresh, precisely-scoped Cursor worker for the remaining 11
test failures (see next journal entry for its prompt/dispatch).

### Task 12 — test remediation checkpoint (2026-09-06)

Cursor remediation worker updated the two stale adaptive/detail test files
to match Task 12's General-only Discussion surface:

- Rewrote compact/regular adaptive push-pop tests to tap General instead of
  retired semantic rows.
- Deleted draft-composer, expanded semantic row-switch, item-only semantic
  row, Log ask-focus, and both semantic `ThreadDetail*` cases.
- Fixed Discussion tab badge expectation to General-only (`threadsTabUnreadCount`).
- Replaced unknown-thread fallback with legacy-unavailable placeholder coverage.
- Deleted optimistic-read-during-semantic-switch test (no equivalent row to
  switch; badge counting covered by sibling unread tests).
- Switched `_HarnessThreadsCubit` to extend real `Cubit<ThreadsState>` so
  mid-test `emitState` reaches `BlocBuilder` listeners reliably.

Verified: `request_threads_adaptive_test.dart` 13/13,
`thread_detail_test.dart` 3/3; all other previously-passing
`test/features/beacon_threads/` and `test/app/router/` files still pass.
(`thread_host_cubit_test.dart` still fails on pre-existing semantic-host
assertions outside this remediation scope.)

### Task 12 — test remediation complete (2026-09-06)

Committed test-only remediation for the 11 Task-12 stale assertions. No
production changes.

Per-case disposition:
1. compact semantic push → **rewrote** (General row push on compact)
2. draft composer → **deleted** (retired coordination-item composer flow)
3. regular push/pop → **rewrote** (General-only fixture)
4. expanded row switch → **deleted** (no second Discussion row to switch)
5. item-only semantic row → **deleted** (retired item-only authorization UI)
6. unknown thread fallback → **rewrote** (legacy thread unavailable placeholder)
7. tab badge totals → **fixed fixture** (expect General-only count `1`)
8. optimistic read during close → **deleted** (depended on semantic switch;
   sibling tests cover General-only badge rules)
9. Log ask focus → **deleted** (retired semantic thread focus from Log)
10. semantic ThreadDetail body → **deleted** (General-only host ignores semantic select)
11. ask ThreadDetail AppBar → **deleted** (retired semantic AppBar path)

Note: `thread_host_cubit_test.dart` semantic/multi-select cases remain failing
from Task 12 production changes and were intentionally out of scope here.

### Task 12 — manager final acceptance (2026-09-06)

Remediation worker completed cleanly (1 commit, `92aa1bdf1`), fixing 11
of the diagnosed stale-test cases across `request_threads_adaptive_test.dart`
and `thread_detail_test.dart`. Reviewed its full diff directly (not just
its self-reported pass count): confirmed each of the 11 dispositions
(rewrite/delete/fixture-fix) was well-reasoned and non-mechanical — e.g.
the "unknown thread id falls back to first accessible row" rewrite now
asserts the actual new behavior (`l10n.beaconLegacyThreadUnavailable`
shown) rather than just deleting coverage, and the tab-badge fixture fix
correctly updated the expected count from the old item-inclusive total
(5) to the new General-only total (1). Independently reran both files
twice — 16/16 passing consistently.

The worker's own report surfaced one honest, correctly-scoped-out
finding: `thread_host_cubit_test.dart` had 4 additional pre-existing
failures from the same General-only `ThreadHostCubit.select()` change,
outside its remediation's stated file list. Verified this myself
(4/8 failing, all selecting a non-General thread after the cubit's
`if (!thread.isGeneral) return;` no-op guard was added) and fixed it
directly given the fix pattern was now well-understood from reviewing
the other 11 analogous cases: two tests rewritten to exercise the same
close-before-recreate/generation-coalescing guarantees using repeated
General selects instead of semantic-thread switches; one test deleted
(asserted passing a non-General item id to the room-cubit factory —
structurally impossible now) and replaced with a new test asserting the
actual current invariant (`select` no-ops for non-General) instead of
silently losing coverage of that code path; one test's setup swapped
from a now-inert semantic-thread `select()` to General so its `clear()`
assertions had a cubit to close. Commit `1b65d8ae9`.

Swept the wider test suite for any other collateral: grepped for
`_semanticThread`/`RequestThreadKind.ask`/`ItemActionsCubit`/
`coordinationSemanticAskOpened`/`coordinationComposerTitle` across
`test/`, found 4 more matching files
(`item_card_golden_test.dart`, `beacon_threads_repository_test.dart`,
`coordination_item_composer_sheet_test.dart`,
`test/domain/entity/request_thread_test.dart`) and ran each
individually — all pass (or, for the golden test, skip as before,
unrelated to this task) since they test still-supported lower-level
concerns (the `ItemCard` widget component itself, `RequestThread`
domain-entity mapping, the still-used promise/ask composer sheet
component) rather than the retired Discussion-overview entry points this
task actually changed.

Final verification: `dart analyze lib test` (client) — 0 errors, 0
warnings; custom-lints baseline unchanged (32/32); every test file
touched or flagged across this task's full arc — production commits
`8601e904b`, test commits `239c008d8`/`92aa1bdf1`/`1b65d8ae9` — passes
in isolation, run at least twice where timing/ordering sensitivity was a
concern.

Task 12 is ACCEPTED. Proceeding to Task 13 (typed notices and promoted-
source footer).
