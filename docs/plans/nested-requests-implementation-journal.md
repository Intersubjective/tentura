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
| 06 | Durable hierarchy delivery worker | 05 | pending |
| 07 | Enforce General-only public product | 06 | pending |
| 08 | Safe request deletion and account erasure | 07 | pending |
| 09 | Scoped legacy cleanup migration | 08 | pending |
| 10 | V2 hierarchy schema and generated client transport | 09 | pending |
| 11 | Extend existing composer/save flow | 10 | pending |
| 12 | Child request surface, General host, and safe navigation | 11 | pending |
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
