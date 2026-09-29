# Episode closure — step-by-step implementation plan

**Status:** draft, rev 5 (2026-09-29). Rev 2 applied the Codex (gpt-6-astra, high) review of rev 1 (28 findings); rev 3 adds U58, the helper → author edge; rev 4 adds unit A7a (support self-scaling tests) and the new helper copy in A21; rev 5 adds U59, the support edge (unit A1b, A2, A14, A21) (§9).
**For:** an implementer (human or model) who follows steps literally. Every unit lists its inputs, the exact files, the steps, the tests and a "done when" check. Do not skip units or change their order unless the dependency column allows it.

**Sources of truth (read before starting any unit):**
1. `docs/plans/episode-closure-architecture.md` (rev 6) — the technical design. Section numbers below like "Arch §5.5" point there.
2. `docs/plans/episode-closure-implementation-plan.md` (Russian, rev 23) — product decisions U1–U59, P1–P11, and all UI copy. When copy is quoted below it is copied from there; use it verbatim.
3. `docs/plans/episode-closure-simulator.html` — reference math for settlement (n ≤ 8).

If a step here contradicts the architecture document, stop and report it; do not guess.

---

## 0. Rules for every unit

### 0.1 Repository conventions

- Read `AGENTS.md` and `.cursor/rules/architecture.mdc` once. Domain code (`packages/server/lib/domain/**`) must not import `data/` or `api/`. Repositories return domain entities.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.schema.dart`). After changing DI annotations, freezed classes or GraphQL documents, run code generation:
  - server: `cd packages/server && dart run build_runner build --delete-conflicting-outputs`
  - client: `cd packages/client && dart run build_runner build --delete-conflicting-outputs`
- Migrations: one file per version in `packages/server/lib/data/database/migration/`, written like `m0199.dart` (`part of '_migrations.dart';`, `final m0NNN = Migration('0NNN', [ r'''SQL''', ... ]);`). Register it in `_migrations.dart` (the `part` line and the `_allMigrations` list). Before creating a migration, check the highest existing number and use the next one; the numbers below (0201–0205) assume `m0200` is the latest (main at 2026-09-29). **Never edit a migration that is already on `main`.**
- Migrations must not call any `mr_*` function (test databases have no pgmer2 extension). Function bodies are not validated during test migrations, so a wrong column name inside a function only fails when the function runs — every new SQL function needs a pg test that calls it.
- Real names in the current schema (do not guess others): `user_trust_edge(subject, object, prev_sent_weight, …)`; deletion trigger `trust_edge_effective_delete_mr` on `user_trust_edge`, executing function `trust_edge_on_effective_delete`; pair lock `trust_pair_lock(text, text)` (m0193.dart:4214); baseline functions are declared with `CREATE FUNCTION`, not `CREATE OR REPLACE`.
- **Transactions.** Server code uses Drift with ambient transactions. Use cases get `MutatingUnitOfWorkPort` (S/domain/port/mutating_unit_of_work_port.dart) and call `_uow.run(actorUserId: …, action: () async { … })`; every repository called inside `action` automatically joins that transaction. Repository ports take **domain arguments only** — never a `Session`, `Tx` or Drift type. Raw SQL inside a repository: `_db.customStatement(sql, [args])` / `_db.customSelect(...)`.
- **Per-request lock.** `SELECT pg_advisory_xact_lock(hashtextextended(@beaconId, 4242))` (the key the current review code uses, evaluation_repository.dart:677). Lock order everywhere: hierarchy scope lock `tentura.beacon_hierarchy.v1` (only if the operation already takes it) → per-request lock → trust pair locks sorted by `(subject, object)`.
- **Connection pool.** The database uses a pool (tentura_db.dart:173), so session-level advisory locks are unreliable. Long-running exclusive jobs use a lease row with a fencing token (A3, A4), never `pg_advisory_lock`.
- **New periodic job registration.** `TaskWorkerCase` is built by its `@FactoryMethod() create` (task_worker_case.dart:35). A new job needs: a parameter on `create`, forwarding to the constructor, a stored field, a cadence/last-run field like the existing jobs, and an entry in `_tasks`. Add a test that the production factory supplies the job (not null).
- **Localization.** After editing `packages/client/l10n/app_en.arb` / `app_ru.arb` run `cd packages/client && flutter gen-l10n`, then build_runner. Each client UI unit adds its own keys; A23 only deletes old keys.
- **Client GraphQL schema.** Start the changed server, apply Hasura metadata, reload the `tentura` remote schema (DEVELOPMENT.md:189–211), then `docker compose run --rm schema_fetcher`; then write `.graphql` documents against the fetched schema (Tentura V2 fields appear with `v2_`-style stitched names — copy the naming of an existing document such as `features/evaluation/data/gql/beacon_close.graphql`) and run client build_runner.
- UI: use the design system (`context.tt` tokens, `TenturaText.*`); no raw colors, font sizes, `EdgeInsets` or `BorderRadius` from numbers. Invoke the `material-3-flutter` skill before writing UI. Touch and desktop: never rely on long-press alone.
- User-facing words: "Request" / «запрос», never "beacon"; code keeps `beacon_*` names.
- No golden tests.

### 0.2 Running tests (always wrapped, always one at a time)

```bash
# server, pure tests
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
# server, one file
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/closure/episode_settlement_test.dart
# server, Postgres tests
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags pg --exclude-tags mr
# server, Postgres + MeritRank tests (serial)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags mr -j 1
# client
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env
# lints
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client
```

Never run two wrapped commands at the same time (they delete each other's temp files).

### 0.3 Definition of done for every unit

1. The unit's tests pass.
2. `dart analyze` (server) / `flutter analyze` (client) show no new issues in touched files.
3. Custom lints pass for the touched package; compare with `scripts/custom-lint-baseline.txt` (the count may only go down).
4. A unit must compile and pass on its own. It may add a temporary adapter for code that a later unit replaces, but it must not implement a later unit's scope. If a step reveals work outside the unit, stop and report it instead of expanding the unit.
5. One commit per unit: `feat(closure): <unit id> <short title>` (or `refactor`, `test`, `chore`), ending with the attribution line required by the session.

### 0.4 Glossary

| Term | Meaning |
|---|---|
| member | helper with an accepted (acknowledged) offer on the request; the author is never a member |
| voter | member who was active when evaluation opened and is not removed by the author (U49) |
| A | members whose outcome is done, can't judge or unanswered |
| epoch | one closure attempt; `beacon_closure.epoch` |
| pool_h | `(1 − ρ)·B = 0.7`, the helper pool of one episode |
| band | result word relative to colleagues' silence: raised, asIfSilent, lowered, none |
| projection | recomputing `user_trust_edge` for one pair from the ledger |

---

## 1. Unit map

| Id | Title | Depends on | Package |
|---|---|---|---|
| P0.1 | Publish non-negative weights (m0201) | — | server |
| P0.2 | pgmer2 0.8.1 and `mr_sync` barrier | P0.1 | infra, server |
| P0.3 | Score-scale audit note | P0.2 | docs |
| A7 | EpisodeSettlement (pure) | — | server domain |
| A7a | Support self-scaling tests (added in rev 4, after A7 landed) | A7 | server domain tests |
| A8 | Author split apportionment (pure) | — | server domain |
| A9 | MembershipReducer (pure) | — | server domain |
| A1 | Trust ledger schema (m0202) | P0.* merged | server SQL |
| A1b | Seed kind 9 `supported_colleague` (m0204; added in rev 5, after A1 landed) | A1, A6 | server SQL |
| A2 | Trust domain types and repository (additive) | A1 | server |
| A3 | TrustPublisher task | A2 | server |
| A4 | TrustCutoverCase and startup | A3 | server |
| A5 | Vote, block and maintenance callers on the new ledger | A2 | server |
| A10 | ForwardRoutingSettlement and removal of the old trust types | A2, A5 | server domain |
| A6 | Closure schema (m0203), Drift, erasure, Hasura | A1 | server SQL, hasura |
| A11 | ClosureRepository | A6, A9 | server data |
| A11b | Closure ports for receipts and finalization | A11 | server domain |
| A12 | ClosureCase: lock, lifecycle, membership hooks | A11b | server |
| A13 | ClosureCase: author and voter writes | A12, A8 | server |
| A14 | Finalize and sweep | A13, A7, A10, A1b | server |
| A15 | Stream 2 (approval edge) | A2, A12 | server |
| A16 | GraphQL V2 closure API | A13, A14 | server api |
| A17 | Notifications and reminder sweeps | A14 | server, docs contract, client classification |
| A18 | Remove the review subsystem (server) | A16, A17 | server |
| A19 | Client data layer and schema refresh | A16 | client |
| A20 | Author screen | A19 | client |
| A21 | Helper screen and flow diagram | A19 | client |
| A22 | Results card and My Work archive | A19 | client |
| A23 | Remove the review feature (client) | A20–A22 | client |
| A24a | QA closure-expiry control | A14 | server, client e2e helpers |
| A24 | Release: versions and deploy runbook | A7a, A18, A23 | all |
| A25 | End-to-end tests | A24a, A24 | client e2e |
| B1 | Ban wall | A* released | server |
| B2 | Noisy-contact wall | B1 | server |
| B3 | "I pinged them" display factor | B2 | server |
| B4 | Wall invariant suites | B1, B2 | server tests |

A7, A8 and A9 have no dependencies; do them first. Units are listed in execution order. A7a was added after A7 landed; it only adds tests and can run at any time.

## 2. Phase 0 (separate PR, ships first)

### P0.1 — Publish non-negative weights (m0201)

**Goal:** MR v0.11.0 treats a negative weight as a wall. Until phase B, never publish negatives.

**Files**
- create `packages/server/lib/data/database/migration/m0201.dart`
- modify `packages/server/lib/data/database/migration/_migrations.dart`
- modify `packages/server/test/data/database/m0199_fact_history_migration_pg_test.dart` — it runs the full registry (line ~49) and then asserts the latest version is exactly `0200` (line ~64). Change that fixture to `migrateDbSchemaThrough(writer, '0200')` for the m0199-specific checks, and keep a separate assertion that the full registry reaches the newest version.
- create `packages/server/test/data/database/m0201_clamp_mr_test.dart` (tags `pg`, `mr`) and `m0201_clamp_pg_test.dart` (tag `pg`)

**Steps**
1. In `m0193.dart` find `CREATE FUNCTION public.trust_rebuild_effective_edge` (around line 4256). Copy the whole function into `m0201` as `CREATE OR REPLACE FUNCTION`.
2. Change only the assignment of `_target`: `_target := CASE WHEN <the existing blocked condition> THEN 0 ELSE greatest(_w, 0) END;` (keep the block override that is already there around line 4304). Publication and `prev_sent_weight` keep using `_target`. Everything else (ε test, error deferral) stays identical.
3. Register `m0201`.

**Tests**
- `mr`: a negative effective weight publishes 0 to MR; a positive one publishes its value; a blocked pair with positive weight publishes 0.
- `pg` (no MR): the publication error is still caught and deferred (the function returns normally).

**Done when:** tests pass; the PR description says the operator runs `trustForceRefreshAll` after deploy.

### P0.2 — pgmer2 0.8.1 and `mr_sync` barrier

**Files**
- `compose.dev.yaml`, `compose.prod.yaml`, CI workflows: replace `postgres-tentura:v0.8.0` with the 0.8.1 tag (`grep -rn "postgres-tentura:" .`).
- `packages/server/lib/data/repository/*witness_window*` (the implementation of `WitnessWindowPort.bumpMrEpoch`, used at trust_maintenance_case.dart:103 and meritrank_case.dart:39): run `SELECT mr_sync()` before bumping the epoch.
- Any SQL function in `m0193.dart` that bumps the publish epoch after MR writes (`grep -n "publish_epoch" m0193.dart`): if one exists, `CREATE OR REPLACE` it in `m0201` (if P0.1 is not merged yet) or in the next free migration, adding `PERFORM mr_sync();` before the bump.

**Tests:** existing `mr`-tagged tests pass against the new image; a new `mr` test calls `bumpMrEpoch` and asserts no error.

### P0.3 — Score-scale audit note

**Files:** create `docs/plans/mr-0-11-score-scale-audit.md`.

**Steps:** list every absolute threshold on MR scores: grep `merit_score_lookup`, `mr_score_value`, `score >`, `score >=`, visibility and cluster thresholds in `packages/server/lib` and migrations. For each: file:line, current value, whether it needs rescaling (MR 0.11.0 scores are ~6× smaller). Do not change code in this unit.

---

## 3. Phase A — server foundations

### A1 — Trust ledger schema (m0202)

**Goal:** Arch §4.1–§4.3 and §10 row m0202.

**Files**
- create `packages/server/lib/data/database/migration/m0202.dart`; register it
- modify `packages/server/lib/data/database/table/user_trust_edges.dart` (drop the removed columns, add `trustW`, `wallD`, `targetW`); remove Drift table classes and `TenturaDb` registrations of `trust_evidence_event`, `user_trust_source_edge`, `trust_context_config`, `meritrank_edge_tombstone` if they exist; run server build_runner
- create `packages/server/test/data/database/m0202_trust_ledger_pg_test.dart` (tag `pg`)

**Steps (one SQL string per list entry, in this order)**
1. Inventory first (write the result into the migration's doc comment): `grep -n "trust_evidence_event\|user_trust_source_edge\|trust_context_config\|trust_apply_source_evidence\|trust_resync_source\|trust_rebuild_effective\|meritrank_edge_tombstone\|half_life_seconds" packages/server/lib/data/database/migration/*.dart packages/server/lib --include=*.dart -r`. Every SQL function, trigger or view that references them must be dropped or rewritten in this migration; every Dart caller is handled by A2/A4/A5 — list them.
2. `CREATE TABLE trust_kind_config` as Arch §4.1 (including `linear_window_s` and `counts_for_immunity`); insert kinds 1–5 (half-life seconds: 365 d = 31536000, 182 d = 15724800; vouch NULL) and kind 8 `worked_with_author` (polarity 0, `half_life_s` NULL, `linear_window_s` = 15552000 (180 d), `k_sat` 1, `mix_weight` 0.08, `counts_for_immunity` false). Kinds 6–7 come in B2.
3. `CREATE TABLE trust_evidence` with its four indexes (Arch §4.1).
4. `CREATE TABLE trust_publish_queue` and `trust_publisher_lease` (insert row id 1) (Arch §4.1).
5. `CREATE TABLE trust_cutover_state (id smallint PRIMARY KEY CHECK (id = 1), status text NOT NULL CHECK (status IN ('pending','done')), owner text NULL, token bigint NOT NULL DEFAULT 0, lease_until timestamptz NOT NULL DEFAULT 'epoch', updated_at timestamptz NOT NULL DEFAULT now()); INSERT INTO trust_cutover_state (id, status) VALUES (1, 'pending');`
6. `CREATE TABLE trust_config (key text PRIMARY KEY, value jsonb NOT NULL); INSERT INTO trust_config VALUES ('wall_publish_enabled', 'false'), ('epsilon', '0.1');`
7. Wipe: `ALTER TABLE user_trust_edge DISABLE TRIGGER trust_edge_effective_delete_mr; DELETE FROM user_trust_edge; ALTER TABLE user_trust_edge ENABLE TRIGGER trust_edge_effective_delete_mr;`
8. `CREATE OR REPLACE FUNCTION trust_edge_on_effective_delete()` — new body: `IF OLD.prev_sent_weight <> 0 THEN INSERT INTO trust_publish_queue (subject_user_id, object_user_id) VALUES (OLD.subject, OLD.object) ON CONFLICT (subject_user_id, object_user_id) DO UPDATE SET next_attempt_at = now(); END IF; RETURN OLD;` — no MR call. Keep the trigger itself.
9. Drop `meritrank_edge_tombstone` and any function that drains it (from the inventory).
10. Alter `user_trust_edge`: drop `s_very_bad, s_bad, s_no_effect, s_good, s_very_good, anchor_at`; add `trust_w`, `wall_d`, `target_w` (`double precision NOT NULL DEFAULT 0`).
11. Drop (with `IF EXISTS`, functions with their exact signatures): `trust_apply_source_evidence`, `trust_resync_source`, `trust_rebuild_effective_edge`, `trust_rebuild_effective_batch`, tables `trust_evidence_event`, `user_trust_source_edge`, `trust_context_config`, column `trust_policy.half_life_seconds`.
12. `CREATE FUNCTION trust_fold_pair(p_subject text, p_object text) RETURNS TABLE (trust_w double precision, trust_recent double precision, n_noisy double precision)` — Arch §4.2: over live rows of `trust_evidence` joined to `trust_kind_config`; `age = extract(epoch from now() - occurred_at)`; decay = `greatest(0, 1 - age / linear_window_s)` when `linear_window_s` is not NULL, else `power(2, -age / half_life_s)` when `half_life_s` is not NULL, else 1; `T = Σ over polarity-0 kinds of mix·s/(k+s)`; vouch contributes `1.0·s/(1+s)` with `s = 1` when `vote_user(subject → object).amount > 0`; `trust_recent` = same over rows with `age ≤ 180·86400` of kinds with `counts_for_immunity = true`, plus vouch; `n_noisy` = decayed sum of kind 7 (0 in phase A).
13. `CREATE FUNCTION trust_project_pair(p_subject text, p_object text) RETURNS void`:
    - `PERFORM trust_pair_lock(p_subject, p_object);`
    - read `trust_fold_pair`; `eps := (SELECT (value)::text::double precision FROM trust_config WHERE key = 'epsilon')`;
    - `target := 0` if a `user_block` row blocks this pair (copy the exact block condition from the old `trust_rebuild_effective_edge`), else `T` if `T > 0`, else 0 (wall branches only if `wall_publish_enabled`; phase A leaves them out);
    - `INSERT INTO user_trust_edge (subject, object, trust_w, wall_d, target_w) VALUES (…) ON CONFLICT (subject, object) DO UPDATE SET trust_w = EXCLUDED.trust_w, wall_d = EXCLUDED.wall_d, target_w = EXCLUDED.target_w RETURNING prev_sent_weight` (check the real unique key of `user_trust_edge` in m0193.dart ~5921 and use it);
    - if `target = 0 AND coalesce(prev, 0) = 0` ⇒ `DELETE FROM user_trust_edge WHERE subject = p_subject AND object = p_object` (the trigger does nothing because prev is 0);
    - if `abs(target − coalesce(prev, 0)) > eps OR sign(target) <> sign(coalesce(prev, 0))` ⇒ upsert into `trust_publish_queue` with `next_attempt_at = now()`.
14. Rewrite `meritrank_init()` to read `target_w` from `user_trust_edge` (all rows with `target_w <> 0`) plus polling edges (unchanged part).

**Tests (pg)**
- On a database migrated through `0201` with seeded old trust rows (`migrateDbSchemaThrough(connection, '0201')`, seed, then migrate the rest): `user_trust_edge` is empty afterwards, no error, `trust_cutover_state.status = 'pending'`.
- `trust_fold_pair`: one `helped` row (count 1, now) ⇒ `T = 0.5`; plus a vouch ⇒ `1.0`; one `marked` row ⇒ `0.1333…`; one `helped` row 365 days old ⇒ `0.3333…`; one `worked_with_author` row (count 1, now) ⇒ `T = 0.04` and `trust_recent = 0`; the same row 90 days old ⇒ s = 0.5, `T = 0.08·0.5/1.5 = 0.02667`; 181 days old ⇒ 0; count 0.5, now ⇒ `0.02667`; retracted rows ignored.
- `trust_project_pair`: target change 0 → 0.5 enqueues; 0.5 → 0.55 does not; 0 → 0.05 enqueues (sign change); 0.5 → 0 keeps the row with `target_w = 0` and enqueues.
- Deleting a `user_trust_edge` row with `prev_sent_weight = 0.5` inserts a queue row; with `prev_sent_weight = 0` inserts nothing; deleting a user cascades and enqueues.
- `meritrank_init` is called only in `mr` tests (A4).

### A1b — Seed kind 9 `supported_colleague` (m0204)

**Goal:** Arch §4.1 kinds table row 9 and §5.9b (U59). A1 (`m0202`) and A6 (`m0203`) have already landed: **do not edit them**; add a new migration.

**Files**
- create `packages/server/lib/data/database/migration/m0204.dart` (check first that `0204` is the next free number; if not, use the next one and update this plan's references); register it in `_migrations.dart`.
- create `packages/server/test/data/database/m0204_support_edge_kind_pg_test.dart`.

**Steps**
1. `INSERT INTO trust_kind_config (kind, slug, polarity, half_life_s, k_sat, mix_weight, linear_window_s, counts_for_immunity) VALUES (9, 'supported_colleague', 0, NULL, 1, 0.1, 15552000, false);` — same column list as the kind 8 insert in `m0202`.
2. If the m0203 (or m0202) migration test asserts that the latest registered version is `0203`, pin that fixture with `migrateDbSchemaThrough(writer, '0203')`, as done for m0199 in P0.1.

**Tests (pg):** after migrating, `trust_fold_pair` for one `supported_colleague` row with count 1 at age 0 ⇒ `0.05`, at 90 days ⇒ `0.1·0.5/1.5 = 0.03333`, at 181 days ⇒ 0; count `1/sqrt(2)` at age 0 ⇒ `0.04142`; `trust_recent` of the pair stays 0.

**Done when:** `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test test/data/database/m0204_support_edge_kind_pg_test.dart` is green and the earlier migration tests still pass.

### A2 — Trust domain types and repository

**Goal:** Arch §4.4.

**Files**
- create `packages/server/lib/domain/trust/trust_evidence_kind.dart` — `enum TrustEvidenceKind { vouch(1), helped(2), marked(3), routed(4), usefulForward(5), engaged(6), noisy(7), workedWithAuthor(8), supportedColleague(9) }` with `final int code`.
- create `packages/server/lib/domain/trust/ledger_evidence.dart` — immutable class `LedgerEvidence` (the old `TrustEvidence` class stays until A10 deletes it; this keeps A2 compiling on its own) `TrustEvidence { subjectId, objectId, kind, count, sourceKey, beaconId?, epoch?, relatedUserId?, occurredAt?, metadata }`; assert `subjectId != objectId`, `count > 0`.
- create `packages/server/lib/domain/port/trust_ledger_port.dart` (new port; the old `TrustEvidenceRepositoryPort` is deleted in A10):
  ```dart
  abstract interface class TrustLedgerPort {
    Future<void> record(List<LedgerEvidence> evidence);
    Future<void> retract(String sourceKey);
    Future<void> unretract(String sourceKey);
    Future<bool> exists(String sourceKey);
    Future<bool> hasLiveUsefulForwardSince(String subjectId, String objectId, DateTime since);
    Future<void> lockPair(String subjectId, String objectId);
    Future<void> project(List<(String, String)> pairs);
  }
  ```
  No transaction parameter: callers wrap calls in `MutatingUnitOfWorkPort.run` (§0.1).
- create `packages/server/lib/data/repository/trust_ledger_repository.dart` (`@Singleton(as: TrustLedgerPort)`, injects `TenturaDb`) and a mock in `data/repository/mock/`.

**Steps**
1. `record`: `INSERT INTO trust_evidence (...) VALUES (...) ON CONFLICT (source_key) DO NOTHING` for each row; collect the distinct `(subject, object)` pairs; call `project`.
2. `retract`: `UPDATE trust_evidence SET retracted_at = now() WHERE source_key = @k AND retracted_at IS NULL RETURNING subject_user_id, object_user_id`; project that pair.
3. `unretract`: same with `retracted_at = NULL WHERE ... IS NOT NULL`.
4. `project`: sort pairs by `(subject, object)` ascending; for each run `SELECT trust_project_pair(@s, @o)`.
5. `lockPair`: `SELECT trust_pair_lock(@s, @o)`. `hasLiveUsefulForwardSince`: `SELECT 1 FROM trust_evidence WHERE kind = 5 AND subject_user_id = @s AND object_user_id = @o AND retracted_at IS NULL AND occurred_at > @since LIMIT 1`.
6. The old `TrustEvidenceRepository` still calls the dropped `trust_rebuild_effective_edge` (trust_evidence_repository.dart:61). Replace that call with `SELECT trust_project_pair(@s, @o)` so the old path keeps compiling and running until A10/A18 remove it; do not touch its callers.

**Tests**
- pure: `LedgerEvidence` asserts.
- pg: record twice with the same key ⇒ one row; retract ⇒ projection drops; unretract ⇒ restored; two pairs are projected in sorted order (assert via a spy on the mock or by checking queue rows).

### A3 — TrustPublisher task

**Goal:** Arch §4.3 (lease + fencing token).

**Files**
- create `packages/server/lib/domain/port/trust_publish_port.dart`:
  ```dart
  abstract interface class TrustPublishPort {
    Future<int?> acquireLease(String owner);            // returns token or null
    Future<bool> leaseValid(int token);
    Future<List<PublishRow>> readBatch(int limit);      // PublishRow(subject, object, target)
    Future<void> publish(PublishRow row);                // mr_put_edge / mr_delete_edge
    Future<void> sync();                                 // mr_sync()
    Future<void> ack(int token, List<PublishRow> rows);  // in one transaction, see step 5
    Future<void> fail(List<PublishRow> rows, String error);
    Future<bool> cutoverPending();
  }
  ```
- create `packages/server/lib/data/repository/trust_publish_repository.dart`
- create `packages/server/lib/domain/use_case/trust_publisher_case.dart` with `run()` and `nudge()`
- modify `packages/server/lib/domain/use_case/task_worker_case.dart` per §0.1 "New periodic job registration" (cadence 10 s)
- tests: `test/domain/use_case/trust_publisher_case_test.dart` (pure, mocks), `test/data/trust_publish_repository_mr_test.dart` (`pg`, `mr`)

**Steps**
1. `run()`: return if `cutoverPending()`; `token = acquireLease(instanceId)` (instance id = a random id created once per process); return if null.
2. `acquireLease`: `UPDATE trust_publisher_lease SET owner = @me, token = token + 1, lease_until = now() + interval '2 minutes' WHERE id = 1 AND (lease_until < now() OR owner = @me) RETURNING token`.
3. `readBatch(200)`: `SELECT q.subject_user_id, q.object_user_id, coalesce(e.target_w, 0) FROM trust_publish_queue q LEFT JOIN user_trust_edge e ON e.subject = q.subject_user_id AND e.object = q.object_user_id WHERE q.next_attempt_at <= now() ORDER BY q.enqueued_at LIMIT 200`.
4. For each row: `if (!await leaseValid(token)) return;` then `publish(row)` (`SELECT mr_put_edge(@s, @o, @w, '', 0)` or `SELECT mr_delete_edge(@s, @o)` when target is 0). Then `sync()`.
5. `ack(token, rows)` in one transaction: `SELECT 1 FROM trust_publisher_lease WHERE id = 1 AND token = @token AND lease_until > now() FOR UPDATE` — no row ⇒ return without changes. For each row re-read `target_w` (missing = 0): if equal to the published value ⇒ `UPDATE user_trust_edge SET prev_sent_weight = target_w WHERE subject = @s AND object = @o`, then `DELETE FROM user_trust_edge WHERE subject = @s AND object = @o AND target_w = 0 AND prev_sent_weight = 0`, then delete the queue row; otherwise leave the queue row. Finally bump the publish epoch the same way `WitnessWindowPort.bumpMrEpoch` does.
6. Any exception in 4 ⇒ `fail(rows, e.toString())`: `attempts = attempts + 1`, `next_attempt_at = now() + least(3600, 10 * power(2, attempts)) * interval '1 second'`, `last_error`.
7. `nudge()` only schedules `run()` to happen on the next worker tick; it never runs a second publisher in parallel (the lease also prevents it).

**Tests**
- pure: publish failure ⇒ `fail`, no `ack`; pending cutover ⇒ nothing read; lease lost mid-batch ⇒ stops, no ack.
- mr: target 0.5 ⇒ MR has the edge, `prev_sent_weight = 0.5`, queue empty; target changed between read and ack ⇒ queue row kept, next run publishes the new value; zero target with prev 0.5 ⇒ MR edge deleted, row deleted, no new queue row; two publishers started together ⇒ only one gets the lease; stale token (lease taken over) ⇒ ack does nothing; crash after `sync` before `ack` (call steps manually) ⇒ next run republishes the same value and acks.

### A4 — TrustCutoverCase and startup

**Goal:** Arch §11.

**Files**
- create `packages/server/lib/domain/use_case/trust_cutover_case.dart` and port `trust_cutover_port.dart`
- modify `packages/server/lib/app/app.dart` — remove the `cutoverBackfillIfNeeded()` call (~line 31); after the pgmer2 upgrade (~line 27) call `TrustCutoverCase.runIfPending()` before workers start; keep the "`mr_edgelist()` empty ⇒ `meritrank_init()`" check (~line 83) but run it only when cutover is `done`.
- modify `packages/server/lib/data/repository/user_trust_edge_repository.dart` — delete `cutoverBackfillIfNeeded` (~line 95) and helpers only it used.
- test `test/domain/use_case/trust_cutover_case_mr_test.dart` (`pg`, `mr`)

**Steps (lease pattern as in A3, on `trust_cutover_state`, lease 10 min)**
1. `token = acquire(owner)` via `UPDATE trust_cutover_state SET owner = @me, token = token + 1, lease_until = now() + interval '10 minutes' WHERE id = 1 AND status = 'pending' AND (lease_until < now() OR owner = @me) RETURNING token`. Null ⇒ if status is `done` return; else wait 5 s and retry (another instance is cutting over), up to the lease length.
2. Project every vote pair: `SELECT subject, object FROM vote_user WHERE amount > 0 ORDER BY subject, object` (check the real column names of `vote_user` in m0193.dart), then for each pair `SELECT trust_project_pair(@s, @o)` in batches of 500 inside `MutatingUnitOfWorkPort.run`. Renew the lease between batches.
3. `SELECT mr_reset()`; `SELECT meritrank_init()`; `SELECT mr_sync()` (each re-checks the lease first).
4. One transaction: re-check the token with `FOR UPDATE`; `UPDATE user_trust_edge SET prev_sent_weight = target_w`; `DELETE FROM trust_publish_queue`; `UPDATE trust_cutover_state SET status = 'done', owner = NULL`.
5. All steps are idempotent; a crash before step 4 leaves `pending` and the next start repeats from step 1.

**Tests (mr)**
- two votes, status pending ⇒ MR holds exactly those edges plus polling edges; status done; second run does nothing.
- crash after step 3 (call steps separately) ⇒ next run finishes.
- two `runIfPending()` calls started concurrently ⇒ `mr_reset` runs once (count via a spy on the port) and the final state is correct.

### A5 — Vote, block and maintenance callers on the new ledger

**Files**
- `packages/server/lib/data/repository/user_trust_edge_repository.dart` — `_setVoteAmountCore` (~lines 138–184) writes vote evidence today: remove the evidence write and call `trust_project_pair(subject, object)` after every vote-state change, including removal (amount ≤ 0).
- `packages/server/lib/data/repository/user_repository.dart` — `_applyReciprocalTrustEdges` (~line 937): remove the evidence write; keep the `vote_user` rows (created around line 920); project both pairs in sorted order.
- `packages/server/lib/data/repository/user_block_repository.dart` — replace the three `trust_rebuild_effective_edge` calls (~lines 94, 162, 773: block withdrawal, unblock, inherited-block release) with `trust_project_pair` for the same pair (phase A: blocked ⇒ target 0).
- `packages/server/lib/domain/use_case/trust_maintenance_case.dart` — the maintenance SQL lives in this file (~lines 143, 150, calling `trust_rebuild_effective_*`): replace with a keyset sweep over `user_trust_edge (subject, object)` in batches of 200 calling `trust_project_pair`. Keep the 24 h cadence and the epoch bump (now with `mr_sync`, P0.2).

**Tests (pg)**
- vote up ⇒ `target_w = 0.5` and a queue row; vote removed after publication (`prev_sent_weight = 0.5`) ⇒ row kept with `target_w = 0` and a queue row; after a publisher ack (call the A3 repository) the row is gone.
- block ⇒ target 0 and queue row; unblock ⇒ target back to the fold value.
- maintenance re-queues a pair whose decayed value moved by more than 0.1.
- `grep -rn "trust_rebuild_effective" packages/server/lib` returns nothing after this unit.

### A6 — Closure schema (m0203), Drift, erasure, Hasura

**Goal:** Arch §5.4 and §10 row m0203.

**Files**
- create `m0203.dart`, register it
- Drift: remove table classes and `TenturaDb` registrations of the six dropped review tables; add no Drift classes for closure tables (closure SQL is raw, like the trust ledger); run build_runner. Code that still reads the review tables through Drift must be adapted in this unit to compile — replace its body with `throw UnimplementedError('removed in A18')` only for review-only code paths that A18 deletes, and list them in the commit message.
- `packages/server/lib/data/repository/user_erasure_repository.dart` (~lines 135–163) and `UserErasurePort` / `UserErasureCase`: remove the SQL for dropped review tables, keep capability cleanup.
- `hasura/metadata.json`: remove the `beacon_review_window` table entry (~line 15), the beacon relationship to it (~line 1914) and any entry for the other dropped tables (search `beacon_evaluation`, `beacon_review`).
- tests `test/data/database/m0203_closure_schema_pg_test.dart`; extend the account-erasure pg test to run through `UserErasureCase`.

**Steps**
1. Inventory: grep `m0193.dart`–`m0200.dart` for functions, views, triggers and indexes on the six review tables (`beacon_evaluation`, `beacon_evaluation_ack_tag`, `beacon_evaluation_participant`, `beacon_evaluation_visibility`, `beacon_review_status`, `beacon_review_window`, including `beacon_review_window_closes_at_idx`). Drop or rewrite each explicitly; list them in the doc comment.
2. Legacy windows: `UPDATE beacon SET status = 7 WHERE status = 5;` and retire their legacy review obligations (find the obligation table/kind used for review in the inventory and mark them superseded the same way the current reopen does). No evidence rows.
3. Create the nine closure tables exactly as Arch §5.4 (note `beacon_closure_member.active_at_open`, no `voter` column) with all constraints and indexes, plus `CREATE INDEX ON beacon_closure_member (user_id)`, `CREATE INDEX ON beacon_closure_support (beacon_id, version)`, `CREATE INDEX ON beacon_closure_mark (target_id)`.
4. Drop the six review tables.
5. Replace `notification_outbox__recipient_safe_chk` (m0193.dart ~5698) with a version whose presentation-key allowlist adds `closure_opened_bookmark_only`, `closure_finalized`, `closure_cancelled`.
6. Room system kind 3: there is **no** kind allowlist constraint; only update the column comment on `beacon_room_message.system_message_kind`. Add `static const closureStory = 3;` to `BeaconRoomSystemMessageKind` in `packages/server/lib/consts/beacon_hierarchy_consts.dart` and to the mirror in `packages/client/lib/domain/entity/beacon_room_consts.dart` (rendering is done in A22).
7. Do **not** track any `beacon_closure*` table in Hasura.

**Tests (pg):** each CHECK rejects a bad row (pct 7, pct 105, outcome 4, voter = target, story of 2001 chars, second live epoch); a request with status 5 before the migration has status 7 after it; deleting a user through `UserErasureCase` removes only that user's closure rows and succeeds without the old tables.

## 4. Phase A — pure domain

### A7 — EpisodeSettlement

**Goal:** Arch §5.5, exactly.

**Files**
- create `packages/server/lib/domain/closure/closure_outcome.dart` — `enum ClosureOutcome { done(1), notDone(2), cantJudge(3) }`; unanswered is `null` in inputs.
- create `packages/server/lib/domain/closure/closure_band.dart` — `enum ClosureBand { none(0), raised(1), asIfSilent(2), lowered(3) }`.
- create `packages/server/lib/domain/closure/settlement_params.dart` — `B = 1.0, rho = 0.3, alphaA = 0.5, beta = 0.5, t = 0.5, bandThreshold = 0.15`, `toJson()` for freezing, `const settlementVersion = 1`.
- create `packages/server/lib/domain/closure/episode_settlement.dart` — class `EpisodeSettlement` with `SettlementResult settle(SettlementInput input)`.
- create `packages/server/test/domain/closure/episode_settlement_test.dart`.

**Input/output types**
```dart
final class SettlementMember {
  final String userId;
  final ClosureOutcome? outcome;   // null = unanswered
  final bool voter;
  final Set<String>? support;      // committed support; null = none
}
final class SettlementInput {
  final List<SettlementMember> members;
  final Map<String, int>? authorSplit; // % over A; null = exact equal
  final SettlementParams params;
}
final class SettlementResult {
  final Map<String, double> helped;   // absolute, sums with lost to pool_h
  final Map<String, double> silent;   // same with all supports ignored
  final Map<String, ClosureBand> band;
  final double lost;
  final Set<String> closeAck;         // outcome == done
}
```

**Steps**
1. Sort members by `userId`. Implement the pseudocode of Arch §5.5 line by line; `silent` = the same function with every `support` treated as null.
2. Treat `outcome == null` as `cantJudge`.
3. Use `double`; compare bands with the rule in Arch §5.5 (`raised` when `silent == 0 && helped > 0` or `helped > 1.15·silent`; `lowered` when `helped < 0.85·silent`; `none` when `n ≤ 2` or both are 0).

**Tests — fixed vectors** (members `u1, u2, u3[, u4]`, all done unless stated, α = β = t = 0.5; values are absolute `helped`, pool_h = 0.7; compare with tolerance 1e-4):

| Id | Setup | helped u1 / u2 / u3 [/ u4] | lost | bands |
|---|---|---|---|---|
| V1 | equal split, silence | 0.2333 / 0.2333 / 0.2333 | 0 | asIfSilent ×3 |
| V2 | split 70/20/10, silence | 0.3856 / 0.2074 / 0.1069 | 0 | asIfSilent ×3 |
| V3 | split 70/20/10, u1 supports u3 | 0.3856 / 0.1471 / 0.1672 | 0 | asIfSilent / lowered / raised |
| V4 | split 10/20/70, u1 supports u3 | 0.1069 / 0.1990 / 0.3941 | 0 | asIfSilent ×3 |
| V5 | equal, u1 supports u2, u2 supports u1 | 0.2625 / 0.2625 / 0.1750 | 0 | asIfSilent / asIfSilent / lowered |
| V6 | u2 notDone, split u1 50 / u3 50, u1 and u3 support u2 | 0.2771 / 0.1458 / 0.2771 | 0 | lowered / raised / lowered |
| V7 | u2 cantJudge, u3 unanswered, split null | 0.2333 / 0.2333 / 0.2333 | 0 | asIfSilent ×3 |
| V8 | u2, u3 notDone, split null | 0.4667 / 0 / 0 | 0.2333 | asIfSilent / none / none |
| V9 | split 100/0/0, u1 supports u2 | 0.4667 / 0.1167 / 0 | 0.1167 | asIfSilent / raised / none |
| V10 | split 70/20/10, u1 supports u2 and u3 (all) | same as V2 | 0 | as V2 |
| V11 | split 70/20/10, u3 is not a voter and supports u2 | same as V2 | 0 | as V2 |
| V12 | n = 2, split 80/20, u1 supports u2 | 0.5600 / 0.1400 | 0 | none ×2 |
| V13 | n = 1, done | 0.7000 | 0 | none |
| V14 | n = 3, all notDone | 0 / 0 / 0 | 0 | none ×3 |
| V15 | n = 4, split 40/30/20/10, u1 supports u4 | 0.2616 / 0.1834 / 0.1301 / 0.1249 | 0 | asIfSilent / asIfSilent / asIfSilent / raised |

(The numbers were produced by an independent Python transcription of Arch §5.5 and cross-checked with the simulator for V2, V3, V5, V6, V8.)

**Tests — properties** (seeded `Random(42)`, 2000 cases, n from 1 to 8, random outcomes incl. null, random split over A in multiples of 5 or null, random voter flags, random supports):
1. Impartiality: for each i, changing only `members[i].support` leaves `helped[i]` unchanged (±1e-12).
2. Monotonicity: for each voter i with support U ≠ ∅, ≠ all: contribution of i to j ∈ U ≥ contribution under silence; to k ∉ U ≤ silence. (Compute contributions by running settle with only i's support set.)
3. Conservation: A non-empty ⇒ `Σ helped + lost == 0.7` (±1e-9); A empty ⇒ all 0, lost 0.
4. Permutation: shuffling the input list gives identical maps.
5. All-supported ≡ silence.
6. Not-done members get no author part: with every support set to null, `helped[j] == 0` for every notDone j. (With supports they may receive peer support — see V6.)

### A7a — Support self-scaling tests

**Goal:** pin Arch §5.5.2: the bonus from a support shrinks as the supported member's author share grows, and an unsupported member pays in proportion to its author share. Tests only; `EpisodeSettlement` is already implemented (A7) and must not change. If a vector fails, stop and report — do not change the algorithm to fit.

**Files:** modify `packages/server/test/domain/closure/episode_settlement_test.dart` (add a `group('support self-scaling (A7a)')`).

**Tests — fixed vectors** (same conventions as A7: members `u1, u2, u3`, α = β = t = 0.5, absolute `helped`, pool_h = 0.7, tolerance 1e-4, lost = 0 in all; u1 supports u3, u2 and u3 silent; all voters):

| Id | Outcomes / split u1/u2/u3 | silent u1 / u2 / u3 | helped u1 / u2 / u3 | bands |
|---|---|---|---|---|
| V16 | u3 notDone; 30/70/— | 0.3033 / 0.3967 / 0 | 0.3033 / 0.3412 / 0.0554 | asIfSilent / asIfSilent / raised |
| V17 | all done; 30/50/20 | 0.2275 / 0.3125 / 0.1600 | 0.2275 / 0.2729 / 0.1996 | asIfSilent / asIfSilent / raised |
| V18 | all done; 30/35/35 | 0.2154 / 0.2423 / 0.2423 | 0.2154 / 0.2146 / 0.2700 | asIfSilent ×3 |
| V19 | all done; 30/10/60 | 0.2528 / 0.0917 / 0.3556 | 0.2528 / 0.0838 / 0.3635 | asIfSilent ×3 |
| V20 | u2 notDone; 30/—/70 | 0.3033 / 0 / 0.3967 | 0.3033 / 0 / 0.3967 | asIfSilent / none / asIfSilent |

(Produced by the same independent Python transcription as V1–V15, which reproduces V2 and V3, and checked against the landed A7 implementation on 2026-09-29: all five match to 1e-4.)

**Tests — property** (seeded `Random(7)`, 500 cases): n = 3, all done, all voters, u1 supports u3 only; `a1` drawn from multiples of 5 in [5, 90]; for two splits with the same `a1` and `a3 < a3'` (both ≥ 5, `a2 = 100 − a1 − a3`, ≥ 5), the gain `helped[u3] − silent[u3]` for `a3` is ≥ the gain for `a3'` (−1e-12); and the loss `silent[u2] − helped[u2]` is ≥ 0 and non-decreasing in `a2`.

**Done when:** `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/closure/episode_settlement_test.dart` is green, and `git diff --stat` touches only that test file.

### A8 — Author split apportionment

**Goal:** Arch §5.4 write rules and §5.5.1.

**Files**
- create `packages/server/lib/domain/closure/author_split.dart` with:
  - `int minPct(int sizeOfA)` → `5` when `2 ≤ size ≤ 20`, `0` when size = 1; throws when size > 20 (callers must use null split).
  - `Map<String, int> apportion({required int total, required Map<String, num> weights, required int min, required String beaconId})`.
  - `Map<String, int> moveSlider({required Map<String, int> current, required String helperId, required int value, required String beaconId})`.
  - `Map<String, int>? renormalize({required Map<String, int>? current, required Set<String> newA, required String beaconId})` → null when `current` is null, `newA` is empty or `|newA| > 20`; `{only: 100}` when `|newA| = 1`.
  - `String? validate(Map<String, int> split, Set<String> a)` → error code or null.
- create `packages/server/test/domain/closure/author_split_test.dart`.

**Algorithm (`apportion`)**
1. If all weights are 0, use weight 1 for everyone.
2. Water-fill: `target_j = rem·w_j/Σw_rest` over the not-yet-fixed members, where `rem = total − min·|fixed|`. Every member with `target_j < min` is fixed at `min`; repeat until nobody new is fixed.
3. `units_j = floor(target_j / 5 + 1e-9)`; `R = total/5 − Σ units`; give one extra unit to the R members with the largest fractional part `target_j/5 − units_j`; ties by `sha256('$beaconId:$helperId')` hex ascending.
4. Return `units_j · 5`.

`moveSlider`: clamp `value` to `[min, 100 − min·(|A| − 1)]`, round to the nearest multiple of 5; the others get `apportion(total: 100 − value, weights: their current values, min: min)`.

`renormalize`: members of `newA` that were not in `current` get weight `100/|newA|`; members that left A are dropped; then `apportion(total: 100, ...)`.

`validate`: check `|a| > 20` first (error `splitTooLarge`, do not call `minPct`); `|a| = 0` ⇒ error `emptyA`; keys exactly equal `a`; each value a multiple of 5 in [0, 100]; sum 100; each ≥ `minPct(|a|)`; `|a| > 20` ⇒ error `splitTooLarge`.

**Fixed vectors** (beaconId `B1`)

| Id | Call | Expected |
|---|---|---|
| E1 | renormalize {u1 70, u2 20, u3 10} → A = {u1..u4} | u1 55, u2 15, u3 10, u4 20 |
| E2 | apportion(100, {90, 4, 3, 3}, min 5) | 85 / 5 / 5 / 5 |
| E3 | moveSlider equal {u1,u2,u3 = 1}, u1 → 50 | 50 / 25 / 25 |
| E4 | moveSlider equal 3, u1 → 45 | 45 / 30 / 25 (u2 wins the tie: sha256 of `B1:u2` starts `42ed9100`, of `B1:u3` starts `635cc707`) |
| E5 | 19 members h01..h19, moveSlider h01 → 30 | h01 = 10 (clamped), all others 5 |
| E6 | 20 members, moveSlider h01 → 30 | all 5 |
| E7 | renormalize {u1 70, u2 20, u3 10} → A = {u1, u2} | 80 / 20 |
| E8 | renormalize any → A = {u1} | u1 100 |
| E9 | moveSlider equal 3, u1 → 100 | 90 / 5 / 5 |
| E10 | renormalize 20 members → 21 members | null |
| E11 | renormalize {u1 50, u2 50} → A = {} | null |
| E12 | validate 21 members | `splitTooLarge` (no exception from `minPct`) |

Apportionment is the water-filling rule of Arch §5.5.1 rev 3; there is exactly one implementation.

### A9 — MembershipReducer

**Goal:** Arch §5.3.

**Files**
- create `packages/server/lib/domain/closure/membership_reducer.dart`
- create `packages/server/test/domain/closure/membership_reducer_test.dart`

**API**
```dart
enum Departure { voluntary(1), removed(2) }
final class MemberState { final bool member; final bool active; final Departure? departure; }
MemberState reduce(List<CommitmentEvent> eventsInOrder, {required DateTime now});
```
Use the existing commitment event entity (see `packages/server/lib/domain/commitment/`). Apply the table in Arch §5.3 in order. An `acknowledged` event that was rolled back inside the 24 h grace (check how `commitment_state.dart` detects this and reuse it) counts as not acknowledged.

**Tests:** one test per table row, plus: acknowledged → withdrawn → acknowledged ⇒ active, departure null; acknowledged → removedFromChat → readmittedToChat ⇒ active; offered only ⇒ not a member; blockedCleanup ⇒ removed.

### A10 — ForwardRoutingSettlement and removal of the old trust types

**Goal:** Arch §5.8. This unit also deletes the old valence types, because the forward engine is their last user.

**Files**
- rename `packages/server/lib/domain/trust/forward/forward_outcome_finalizer.dart` → `forward_routing_settlement.dart` (class `ForwardRoutingSettlement`), and its test.
- modify `forward_request_consolidator.dart` (imports `TrustBin` and `forward_outcome_policy.dart` today): key the consolidation by `(sender, recipient)` only; move any constant it still needs from `forward_outcome_policy.dart` into `forward_routing_settlement.dart`.
- delete `forward_outcome_policy.dart` (it declares `negativeRoute`) and its test; delete `unsuccessfulRequestForward` wherever it appears.
- delete `packages/server/lib/domain/trust/trust_bin.dart`, `trust_context.dart`, `trust_math.dart`, `trust_source_type.dart`, the old `trust_evidence.dart` / `trust_evidence_metadata.dart`, `TrustEvidenceRepositoryPort` + its repository and mock, and `test/domain/trust/trust_math_test.dart`. Fix remaining callers: review-finalization callers are replaced by `throw UnimplementedError('removed in A18')` only if A18 deletes them; other callers switch to `TrustLedgerPort`.

**Input** (read `forward_causal_graph_builder.dart:25` and `forward_outcome_finalizer.dart:65` and keep every input they need):
```dart
final class RoutingInput {
  final String beaconId;
  final int epoch;
  final String authorId;
  final Map<String, DateTime> seedOfferAt;   // M_route member → offer created_at
  final List<ForwardEdgeRecord> edges;       // all provenance edges of the request
  final Map<String, ...> attributionByBatch; // exactly what the builder/propagator need today
  final double budget;                       // rho * B = 0.3
}
```

**Steps**
1. Keep causal eligibility and propagation exactly as today (`ForwardCausalGraphBuilder`, `ForwardMassPropagator`, `ForwardLocalNormalizer`).
2. Every seed gets mass 1.0 regardless of outcome.
3. Per-sender budget per episode = `budget`.
4. Output `List<LedgerEvidence>` of kind `routed`, subject = sender, object = recipient, count = consolidated amount, `sourceKey = 'closure:$beaconId:$epoch:routed:$sender:$recipient'`; drop counts ≤ 0 and self-pairs.

**Tests:** adapted finalizer tests; chain A→B→C with seed C ⇒ each sender total ≤ 0.3; a voluntary leaver not in seeds produces no mass; a notDone seed still produces mass; an edge created after the offer, and an edge cancelled before the offer, give no credit.

## 5. Phase A — closure server

### A11 — ClosureRepository

**Files**
- create `packages/server/lib/domain/port/closure_repository_port.dart`
- create `packages/server/lib/data/repository/closure_repository.dart` (+ mock in `data/repository/mock/`)
- create `packages/server/lib/domain/closure/closure_entities.dart` (freezed or plain immutable classes: `ClosureEpoch`, `ClosureMemberRow`, `ClosureSupportRow`, `ClosureResultRow`)
- test `test/data/closure_repository_test.dart` (pg)

**Methods** (domain arguments only; they run inside the caller's `MutatingUnitOfWorkPort.run`):
`lockRequest(beaconId)` (`SELECT pg_advisory_xact_lock(hashtextextended(@id, 4242))`), `liveEpoch(beaconId)`, `createEpoch(...)`, `setEpochStatus(...)`, `insertMembers(...)` (with `active_at_open`), `setDeparture(beaconId, epoch, userId, departure?)`, `members(beaconId, epoch)`, `outcomes(beaconId)`, `saveOutcome(...)`, `split(beaconId)`, `replaceSplit(beaconId, Map?)`, `supports(beaconId, version)`, `toggleSupport(beaconId, voterId, targetId, on)`, `commitSupport(beaconId, voterId)`, `skip(beaconId, voterId)`, `clearCommitted(beaconId)`, `commits(beaconId)`, `setMark(...)`, `marks(...)`, `saveStory(...)`, `story(...)`, `insertResults(...)`, `resultFor(beaconId, userId)`, `selectArrivalEdge(beaconId, helperId, offerCreatedAt)` (Arch §5.6; this one goes into `forward_edge_repository.dart` instead if that file owns forward-edge SQL).

Each method is a single SQL statement; no business rules here (rules live in A12/A13).

**Tests (pg):** round-trip of every method; `selectArrivalEdge` picks the latest edge before the offer, ignores edges cancelled before the offer, ignores edges created after the offer, breaks equal timestamps by id DESC.

### A11b — Closure ports for receipts and finalization

**Goal:** give A12/A13 compiled interfaces for work implemented later, so every unit compiles on its own.

**Files**
- create `packages/server/lib/domain/port/closure_receipts_port.dart`: `opened(beaconId, epoch)`, `finalized(beaconId, epoch)`, `cancelled(beaconId, epoch)`; a no-op implementation `NoopClosureReceipts` registered in DI until A17 replaces it.
- create `packages/server/lib/domain/port/closure_finalizer_port.dart`: `Future<void> finalize({required String beaconId, required int epoch, required FinalizeReason reason})`; a temporary implementation that throws `UnimplementedError` until A14.
- create `packages/server/lib/domain/closure/finalize_reason.dart` (`authorCloseNow(1)`, `expired(2)`).

**Tests:** none beyond compilation and DI resolution (`build_runner`, then a DI smoke test that resolves both ports).

### A12 — ClosureCase: lock and lifecycle

**Goal:** Arch §5.1, §5.2, §5.3 (snapshot), §7 lifecycle mutations.

**Files**
- create `packages/server/lib/domain/use_case/closure_case.dart`
- create `packages/server/lib/domain/closure/closure_exception.dart` (codes: `notAuthor`, `notVoter`, `notMember`, `staleEpoch`, `wrongStatus`, `reopenLimit`, `extendLimit`, `notReady`, `invalidSplit`, `splitTooLarge`)
- modify `packages/server/lib/domain/use_case/coordination_case.dart` — `setBeaconStatus(reviewOpen → needsMoreHelp)` (~line 693) must call `ClosureCase.reopen`.
- test `test/domain/use_case/closure_case_lifecycle_test.dart` (pg)

**Every public method follows this template** (`_uow` is `MutatingUnitOfWorkPort`)
```dart
Future<T> _inClosureTx<T>({
  required String actorId,
  required String beaconId,
  required int? expectedEpoch,
  required Future<T> Function(ClosureEpoch? live) body,
}) =>
  _uow.run(actorUserId: actorId, action: () async {
    await _repo.lockRequest(beaconId);
    final live = await _repo.liveEpoch(beaconId);
    if (expectedEpoch != null && live?.epoch != expectedEpoch) {
      throw const ClosureException.staleEpoch();
    }
    return body(live);
  });
```

**Operations**
1. `close(authorId, beaconId)`: author only; beacon in open family {0, 7, 8}. **Preserve the current close effects** — read `evaluation_case.dart:169–234` and keep, in the same order: `recordBeaconStatusTransition`, `BeaconLifecycleEffectsCase.recordEligibleSourceTransition` (parent/child requests), `unansweredAtClose` events for pending offers, `supersedeAuthorHelpOfferObligationsOnBeaconClose`. Compute members with `MembershipReducer` over each offer's events. No member ever ⇒ `beacon.status = closed(6)`, no epoch (with the same effects). Else create epoch `max(epoch)+1`, `opened_at = now`, `closes_at = now + 7 days`; insert members (`active_at_open = active`, `departure` from the reducer, `arrival_edge_id` from `selectArrivalEdge`); if a custom split exists, replace it with `renormalize(current, A)` (new members may have joined since a reopen); `beacon.status = reviewOpen(5)`; `ClosureReceiptsPort.opened`.
2. `extend`: author; evaluating; `extensions_used < 2`; `closes_at += 7 days`.
3. `reopen`: author; evaluating; count of cancelled epochs < 1 (`kMaxReviewReopens = 1`); set epoch status cancelled; `repo.clearCommitted(beaconId)` (deletes version 1 supports and commit rows; drafts and outcomes stay); set beacon status `needsMoreHelp(7)` with the same status-transition effects the current `reopenFromReview` records; `ClosureReceiptsPort.cancelled`.
4. `closeNow`: author; evaluating; `canCloseNow` true (below) ⇒ `ClosureFinalizerPort.finalize(beaconId, epoch, authorCloseNow)` inside the same transaction (the lock is re-entrant within a transaction).
5. `canCloseNow(state)`: every member has a non-null outcome **and** (`|M| ≤ 2` **or** every voter has a commit row **or** `now ≥ opened_at + 48 h`).
6. `canReopen`: evaluating and no earlier cancelled epoch.
7. Membership hooks. Every use case that writes a commitment event must take the per-request lock **before** writing it, inside its existing transaction, and then call `ClosureCase.applyMembershipEvent(beaconId, helperId)` in the same transaction. Writers: `HelpOfferCase` withdrawal (help_offer_case.dart ~296), `CoordinationCase` acknowledge / release / remove / readmit (coordination_case.dart ~324 and neighbours), `UserBlockCase` blocked cleanup (user_block_case.dart ~193). Verify the list with `grep -rn "CommitmentEventKind\." packages/server/lib/domain/use_case`. If an operation already takes the hierarchy scope lock, take it first (§0.1 lock order).
   `applyMembershipEvent`: if an epoch is evaluating and the helper has a member row ⇒ recompute the reducer and `setDeparture` (removed / voluntary / null). `active_at_open` never changes. `voter` is always computed as `active_at_open && departure != removed`.

**Tests (pg)**
- close with zero members closes directly.
- close with 3 members ⇒ epoch 1, three voters.
- a member withdrawn before close ⇒ `voter = false, departure = voluntary`.
- reopen twice ⇒ second fails with `reopenLimit`; reopen keeps outcomes and drafts, removes committed rows.
- stale `expectedEpoch` ⇒ `staleEpoch`.
- canCloseNow: false with one unanswered outcome; true after 48 h even if voters did not commit; true immediately for 2 members with both outcomes set.
- author removes a member during the epoch ⇒ not a voter; readmitted afterwards ⇒ voter again (was active at open); a voluntary leave keeps the vote; a member inactive at open who is readmitted stays a non-voter.
- each hook path (withdraw, release, remove, readmit, blocked cleanup) run concurrently with finalize: either the event is reflected in the result rows or it lands after finalize; never a partial state.
- close preserves the effects listed in step 1 (pending offer ⇒ `unansweredAtClose`; child request ⇒ lifecycle effect on parent).

### A13 — ClosureCase: author and voter writes

**Goal:** Arch §5.4 write rules; §7 rows `closureSave*`, `closureToggleSupport`, `closureDone`, `closureSkip`, `closureSetMark`.

**Operations** (all through `_inClosureTx` with `expectedEpoch`; epoch must be evaluating unless stated; "voter" = `active_at_open && departure != removed`)
1. `saveOutcome(author, helperId, outcome?)`: helperId must be a member. After saving, recompute A; if a split exists, replace it with `renormalize(current, newA)` (null ⇒ delete rows).
2. `saveAuthorSplit(author, Map<String,int>? split)`: null ⇒ delete rows; else `validate(split, A)` and replace.
3. `toggleSupport(voter, targetId, on)`: caller must be a voter, epoch members ≥ 3, target a member other than the caller. `on = false` ⇒ delete the draft row. `on = true` ⇒ insert draft row with `pressed_at = now()`; then, if the draft now contains every other member, delete the row with the earliest `pressed_at` among them (never the one just pressed) and return its target id as `released`.
4. `done(voter)`: delete version-1 rows of the voter, copy version-0 rows to version 1, upsert the commit row with `committed_at = now()`.
5. `skip(voter)`: delete version-1 rows, upsert the commit row.
6. `setMark(user, targetId, on)`: allowed on evaluating **or** final epochs (for final: the latest final epoch, `expectedEpoch` must equal it). Caller is the author or has a member row; target is the author or a member; not self. Evaluating ⇒ write `beacon_closure_mark` only. Final ⇒ also write evidence: `on` ⇒ `record` (or `unretract` if the key exists) kind `marked`, count 1, `sourceKey = 'closure:$b:$e:mark:$me:$target'`, `occurredAt = finalized_at`; `off` ⇒ `retract`.
7. `saveStory(author, body)`: trim; empty ⇒ delete row; > 2000 chars ⇒ error.

**Tests (pg)**
- U56: three members; u1 toggles u2 then u3 ⇒ response `released = u2`, draft = {u3}.
- `pressed_at` of an existing row does not change when toggled on again (the insert is `ON CONFLICT DO NOTHING`).
- a non-voter cannot toggle; with 2 members nobody can toggle.
- done after edits copies the latest draft; editing after done leaves version 1 unchanged.
- saveOutcome notDone on a member with a custom split ⇒ split renormalized per E7.
- split with 21 members in A ⇒ `splitTooLarge`.
- setMark after finalize writes evidence dated `finalized_at`; off retracts; on again unretracts (same row id).

### A14 — Finalize and sweep

**Goal:** Arch §5.9.

**Files**
- create `packages/server/lib/domain/use_case/closure_finalize_case.dart` implementing `ClosureFinalizerPort` (replaces the A11b placeholder in DI).
- create `packages/server/lib/domain/use_case/closure_finalize_sweep_case.dart`; register in `TaskWorkerCase` per §0.1 (every 60 s). The review branch of `AttentionExpirySweepCase` is removed in A18.
- test `test/domain/use_case/closure_finalize_pg_test.dart` (pg; MR not required).

**`finalize(beaconId, epoch, reason)`** — runs inside the caller's transaction when called from `closeNow`; the sweep wraps it in `MutatingUnitOfWorkPort.run` and takes the per-request lock first.
1. Re-read the live epoch. It must be the same `epoch`, status evaluating, and for `expired` also `closes_at <= now()`. Otherwise return without changes (no-op, not an error, for the sweep; `closeNow` has already checked).
2. Set epoch `status = final`, `finalized_at = now`, `finalize_reason`, `settlement_version = 1`, `settlement_params = params.toJson()`; `beacon.status = closed(6)`; preserve the current finalize effects — read `review_finalization_case.dart:76–105` and keep `recordBeaconStatusTransition`, `BeaconLifecycleEffectsCase.recordEligibleSourceTransition` and obligation superseding in the same order.
3. Build `SettlementInput` from members (voter derived), outcomes, split, version-1 supports (a voter without a commit row has support null) and run `EpisodeSettlement.settle`.
4. Insert one `beacon_closure_result` per member: outcome (null stored as 3), band, draft flag (`notCounted` = version-0 rows exist and no commit row; `lastEditNotCounted` = commit row exists and version-0 target set ≠ version-1 target set; else none), helped.
5. Evidence through `TrustLedgerPort.record` (it projects and queues): `helped` for every j with `helped[j] > 0` (subject author, key `closure:$b:$e:helped:$j`); routed from `ForwardRoutingSettlement` with seeds = members whose departure ≠ voluntary; `marked` for every `beacon_closure_mark` row (key `closure:$b:$e:mark:$x:$y`, `occurredAt = finalized_at`); `workedWithAuthor` (U58, Arch §5.9a): `P` = members with `departure == null` at this moment; for each i in P record subject i, object author, `count = 1 / sqrt(P.length)`, key `closure:$b:$e:author_edge:$i`, `occurredAt = finalized_at` — independent of outcome and split; `supportedColleague` (U59, Arch §5.9b): for every member i with `voter == true`, `members.length >= 3` and committed support `U` with `U.isNotEmpty` and `U` ≠ all other members, for each j in U record subject i, object j, `count = 1 / sqrt(U.length)`, key `closure:$b:$e:support_edge:$i:$j`, `occurredAt = finalized_at` — also when `helped[j] − silent[j]` is 0.
6. Close-acks for `closeAck` over the offer's help types — copy the exact call from `review_finalization_case.dart`.
7. Story ⇒ room system message with `system_message_kind = 3`.
8. `ClosureReceiptsPort.finalized`.
9. After the transaction commits, `TrustPublisherCase.nudge()`.

**Sweep:** `SELECT beacon_id, epoch FROM beacon_closure WHERE status = 0 AND closes_at <= now() ORDER BY closes_at LIMIT 50`; for each row: `run(action: lockRequest; finalize(beaconId, epoch, expired))`; catch and log per row.

**Tests (pg)**
- scenario V3 through the database: result bands asIfSilent / lowered / raised; `helped` evidence counts 0.3856 / 0.1471 / 0.1672; queue rows exist; no MR call.
- U58: three members present ⇒ three `worked_with_author` rows helper → author with count `1/sqrt(3) = 0.57735`; a member marked notDone still gets the row; a member who withdrew during the evaluation window and a member removed by the author get none (and P shrinks, so the rest get `1/sqrt(2)`); a single member ⇒ count 1; a cancelled epoch (reopen) writes none; a blocked pair has published target 0; `trust_recent` of the pair stays 0.
- U59: four members, u1 commits support {u2, u3} ⇒ two `supported_colleague` rows u1→u2, u1→u3 with count `1/sqrt(2) = 0.70711`; scenario V20 (u2 notDone, u1 supports u3, zero bonus) still writes u1→u3 with count 1; support of a notDone or withdrawn member writes the row; no rows for a draft without Done, for a non-voter, for 2-member requests, for a cancelled epoch; the all-supported case is stored as silence (U56) and writes none.
- draft-only voter ⇒ `notCounted`, no effect on shares.
- finalize the same epoch twice ⇒ second is a no-op.
- sweep selected an epoch, then the author extended it before the sweep took the lock ⇒ no-op; same for reopen + reclose (new epoch) ⇒ the new epoch is untouched. Use a test hook between select and lock.
- Done vs finalize with controlled ordering: Done first ⇒ both succeed and the committed support is used; finalize first ⇒ Done fails with `wrongStatus` or `staleEpoch`.
- user deleted after finalize ⇒ other members' result rows unchanged, the deleted user's trust rows gone, queue rows for their published edges exist.
- pending offer at close and a child request: effects of step 2 recorded.

### A15 — Stream 2 (approval edge)

**Goal:** Arch §5.7.

**Files**
- modify `packages/server/lib/domain/use_case/coordination_case.dart` — `acceptHelpOffer()` (~line 324).
- modify `packages/server/lib/domain/use_case/help_offer_case.dart` — withdrawal (~line 296) and the grace rollback path (find where `acknowledged` is rolled back within 24 h).
- test `test/domain/use_case/stream2_test.dart` (pg).

**Steps**
1. In `acceptHelpOffer`, inside its existing transaction and after the acknowledgement is stored: `edge = selectArrivalEdge(beaconId, helperId, offer.createdAt)`; if null or `edge.senderId == authorId` or `edge.senderId == helperId` ⇒ stop.
2. `TrustLedgerPort.lockPair(helperId, edge.senderId)` (after the per-request lock, §0.1 order).
3. `key = 'approval:$beaconId:$helperId'`. If `exists(key)` ⇒ `unretract(key)` (re-acknowledgement after a withdrawal restores the original row and date); else if `!hasLiveUsefulForwardSince(helperId, senderId, now − 30 days)` ⇒ `record` kind `usefulForward`, count 1, `relatedUserId = senderId`, metadata `{arrival_edge_id: edge.id}`.
4. On voluntary withdrawal and on grace rollback ⇒ `retract(key)`. Author removal and block cleanup ⇒ nothing.

**Tests:** the six listed in Arch §5.7, including two approvals by the same helper of offers forwarded by the same sender on two requests within 30 days ⇒ one live row; run the two approvals concurrently.

### A16 — GraphQL V2 closure API

**Goal:** Arch §7.

**Files**
- modify `packages/client/test/data/gql/direct_v2_schema_overlay_test.dart` when the client side changes in A19 (it asserts `beaconExtendReview` today); nothing on the client in this unit.
- create `packages/server/lib/api/controllers/graphql/mutation/mutation_closure.dart`
- create `packages/server/lib/api/controllers/graphql/query/query_closure.dart`
- add types in `custom_types.dart` (or a new `closure_types.dart` next to it if that is the local style): `ClosureState`, `ClosureMember`, `ClosureResult`, enums `ClosureOutcome`, `ClosureBand`, `ClosureDraftFlag`, `ClosureRole` (author, voter, member).
- register in `_mutations_all.dart` and `_queries_all.dart`; move `beaconClose`, `beaconCloseNow`, `beaconReopen`, extend from `mutation_beacon.dart` / `mutation_evaluation.dart` into `mutation_closure.dart`.
- test `test/api/closure_graphql_test.dart`.

**Steps**
1. Mutations exactly as the table in Arch §7; each resolver: get the viewer id from the session, call `ClosureCase`, map `ClosureException` to GraphQL errors with the code as `extensions.code`.
2. `closureState(beaconId)`: resolve the viewer's role: author, voter, non-voter member (voluntary leaver, removed), **blocked member** (a member who is blocked by the author or has a `blockedCleanup` departure), or outsider. Outsider ⇒ not found. Blocked member ⇒ `closureState` is not found; they may only call `closureResultForViewer` and `closureSetMark` on their own bookmarks. Build the response with the field allowlist of Arch §7 — construct separate DTOs per role; never serialise a full entity.
3. `closureResultForViewer(beaconId)`: member only; returns `outcome, band, draftFlag, marks (own), story`.
4. No field named or containing `share`, `helped`, `pct` for other users anywhere in the closure schema. The author sees their own split values in `closureState.split` (author role only).

**Tests**
- Schema contract: introspect the schema; assert `ClosureResult` has exactly the fields `outcome, band, draftFlag, marks, story`.
- Role matrix: author, active voter, voluntary leaver, removed member, blocked member, outsider, and a forged `beaconId`/`expectedEpoch` — each sees exactly the allowed fields (assert on the serialized JSON response, not on DTOs); outsider and blocked member get not found for `closureState`.
- Receipts payloads (A17) contain no numbers other than codes.
- A voter never sees other voters' supports or commits; the author never sees who committed (only `canCloseNow`).

### A17 — Notifications and reminder sweeps

**Goal:** Arch §9.

**Files**
- modify `packages/server/lib/domain/attention/attention_models.dart` — add `AttentionEventType` values `closureOpened`, `closureDraftReminder`, `closureFinalized`, `closureCancelled`, `requestStale` (reuse `staleReminder` if its semantics fit; keep one of them, not both). Remove `reviewOpened`, `reviewAllPackagesIn`, `reviewWindowCancelled`, `trustGivenChanged`, `trustReceivedChanged` in A18.
- modify `attention_policy.dart`, the destination map and `AttentionIntentCase` to produce the receipts with the source keys and policies of the table in Arch §9.
- create `closure_draft_reminder_sweep_case.dart`, `stale_request_reminder_sweep_case.dart`; register both in `TaskWorkerCase` (every hour).
- update `docs/contracts/updates-event-contract.json` (the contract test requires exact equality), the server policy and destination mappings, and `packages/client/lib/domain/attention/attention_event_classification.dart` together, in this unit.
- replace the A11b no-op `ClosureReceiptsPort` binding with the real implementation.
- register both sweeps in `TaskWorkerCase` per §0.1.
- tests: `updates_event_contract_test` (server and client); `test/domain/use_case/closure_notifications_pg_test.dart`.

**Steps**
1. Implement the port called by A12/A14 (`ClosureReceiptsPort`) with methods `opened(beaconId, epoch)`, `finalized(beaconId, epoch)`, `cancelled(beaconId, epoch)`. Each writes one outbox row per recipient with key `<type>:<beacon>:<epoch>:<recipient>`.
2. Access policy: `beacon_content` for recipients who can still read the request; `recipient_safe` with presentation key `closure_opened_bookmark_only` / `closure_finalized` / `closure_cancelled` for removed or blocked members.
3. `closureFinalized` payload: `{outcome, band, draftFlag}` codes only.
4. Draft reminder: epochs with `status = 0` and `closes_at` between now + 23 h and now + 24 h; recipients = voters with (non-empty version-0 set **and** no commit row) **or** (a commit row **and** version-0 target set ≠ version-1 target set). Untouched voters and voters who pressed Skip without later edits get nothing. Key includes the epoch, so it fires once.
5. Stale reminder: Arch §9 rule; key `stale_request:<beacon>:<ISO week-year>-W<ISO week>` (compute with Dart `DateTime` helpers; write a small pure function `isoWeekKey(DateTime)` with tests for 2026-12-31 → `2026-W53`, 2027-01-01 → `2026-W53`, 2027-01-04 → `2027-W01`).

**Tests:** receipts written in the same transaction (roll back ⇒ no rows); a second finalize attempt writes nothing; draft reminder: untouched voter ⇒ none, committed Skip ⇒ none, draft without commit ⇒ one, edit after Done ⇒ one; stale reminder fires once per ISO week; the ISO week vectors above.

### A18 — Remove the review subsystem (server)

**Files to delete** (verify each with grep before deleting; delete tests together with code):
`domain/use_case/evaluation_case.dart` (move any closure-unrelated helpers it still owns into their proper cases first), `domain/use_case/evaluation/` (whole folder), `domain/port/evaluation_repository_port.dart`, `domain/port/review_finalization_port.dart`, their data repositories and mocks, `api/controllers/graphql/mutation/mutation_evaluation.dart`, `query/query_evaluation.dart`, the review branch of `attention_expiry_sweep_case.dart`, the removed attention event types, every `evaluation*` / `reviewWindow*` GraphQL type.

**Steps**
1. `grep -rln "evaluation\|reviewWindow\|review_window\|ReviewFinalization\|UnimplementedError('removed in A18')" packages/server/lib packages/server/test --include=*.dart | grep -v "/migration/" | grep -v "\.g\.dart"` — go file by file; delete or rewrite. Retained identifiers that are intentionally kept (allowlist): `BeaconStatus.reviewOpen`, `kMaxReviewReopens`.
2. Run build_runner (DI config changes).
3. Run all server tests (pure, pg, mr — serially).

**Done when:** the grep above returns only allowlisted identifiers. Shipped migrations are never edited and are excluded from the search.

---

## 6. Phase A — client

### A19 — Client data layer

**Files**
- create `packages/client/lib/features/closure/data/gql/*.graphql` — one document per operation of Arch §7 (`closure_state.graphql`, `closure_result_for_viewer.graphql`, `closure_save_outcome.graphql`, `closure_save_author_split.graphql`, `closure_toggle_support.graphql`, `closure_done.graphql`, `closure_skip.graphql`, `closure_set_mark.graphql`, `closure_save_story.graphql`, `beacon_close.graphql`, `beacon_close_now.graphql`, `beacon_extend_closure.graphql`, `beacon_reopen.graphql`).
- create `features/closure/data/repository/closure_repository.dart`, `features/closure/domain/entity/*.dart` (`ClosureState`, `ClosureMember`, `ClosureOutcome`, `ClosureBand`, `ClosureDraftFlag`, `ClosureResult`, `ClosureMark`), `features/closure/domain/use_case/closure_case.dart`.
- modify `packages/client/lib/data/gql/beacon_model.graphql` — remove the `beacon_review_window` selection (~line 43) and fix every compile error (the beacon entity loses its review-window field; replace UI uses with `closureState` or delete them).
- refresh the client schema per §0.1 "Client GraphQL schema" (server running with A16, Hasura metadata from A6 applied, remote schema reloaded, `docker compose run --rm schema_fetcher`); never edit generated `*.gql.dart`.
- update `packages/client/test/data/gql/direct_v2_schema_overlay_test.dart` (it asserts `beaconExtendReview`) to the new operation names.

**Tests:** repository mapping tests with fake responses; error codes map to typed exceptions.

### A20 — Author screen "Подвести итоги"

**Files:** `features/closure/ui/screen/closure_author_screen.dart`, `ui/bloc/closure_author_cubit.dart` (+ state), widgets under `ui/widget/`. Route `/beacon/closure/:id` (router in `C/app/router`) chooses author or helper screen by `closureState.role`.

**Behaviour (copy from Arch §8.2 and plan §5):**
1. Member rows sorted: active first, then leavers with "ушёл" / "исключён".
2. Outcome picker per row: «Выполнено» / «Не выполнено» / «Не могу судить»; vertical list on narrow screens; hint «Не выполнено» убирает человека из твоего распределения; «Не могу судить» оставляет его в равной доле».
3. Split section: locked; button «Изменить распределение» unlocks without changing values (show the equal values as a starting point; saving is required to leave null mode); sliders in steps of 5, min 5 %; «Вернуть поровну» sends `split: null`. More than 20 people in A ⇒ section disabled with explanation.
4. Live preview bars with names under the title «если коллеги промолчат» (compute locally with a Dart port of the silent settlement — reuse the domain algorithm from A7 by copying it into a client-side pure file `features/closure/domain/silent_preview.dart` with the V1/V2/V8 tests).
5. Two members: text «Долю каждого распределяешь ты. Каждый из двоих поймёт по своему итогу, как ты разделил».
6. Story field with hint; bookmark 🔖 toggle per member.
7. Footer: deadline, «Продлить на 7 дней» (hidden after 2), «Завершить сейчас» enabled by `canCloseNow`, with text «Можно закрыть раньше после <время>, или когда все помощники ответят». Never show who answered.
8. «Вернуть в работу» when `canReopen`.
9. Every write sends `expectedEpoch`; on `staleEpoch` reload the state and show a snackbar.

**Localization:** add every string of this screen as `closureAuthor*` keys to both ARB files (Russian verbatim, English short), run `flutter gen-l10n`.

**Tests (widget):** each state above; 12 members at 360 px width without overflow; semantics labels on the toggles; keyboard focus order.

### A21 — Helper screen "Поддержать коллег" and flow diagram

**Files:** `closure_helper_screen.dart`, `closure_helper_cubit.dart`, `ui/widget/support_toggle.dart`, `ui/widget/share_flow_diagram.dart` (`CustomPainter` + `TenturaAvatar`).

**Behaviour:**
1. Header «Чья работа, по-твоему, была важной? Твоя часть от этого не меняется» (do not use «сверх решения автора»: the helper does not see it).
2. One toggle per colleague: «☆ Поддержать» / «★ Поддерживаю». After the first press show ▲ on supported and ▼ on the others, with the legend «▲ получат добавку — ▼ её отдадут те, кого ты не выбрал».
3. When the server returns `released`, show «Поддержать всех — то же, что никого. Кто-то должен отдать: снята самая ранняя (<имя>)».
4. Status line: «В расчёте: поддержаны …» / «В расчёт ещё не входит» / «На экране иначе — «Готово» заменит расчёт».
5. Buttons «Готово» and «Пропустить — не отмечаю никого» with «Твоя часть не меняется никогда»; confirm dialog on Skip when a committed version exists.
6. «Автор может закрыть после <время> — или раньше, когда ответят все».
7. Privacy line «В приложении твой выбор не видят. По своим итогам другие могут о нём догадаться».
7a. U58 notice, shown to every member while the epoch is evaluating, including 1- and 2-member requests and non-voters: «Когда запрос закроется, в сети появится слабая связь от тебя к автору: вы работали вместе. Не хочешь её — выйди из запроса до закрытия».
8. Bookmark toggle per person (colleagues and the author) with the copy «Закладка чуть усиливает твою связь с этим человеком в сети. Ему не придёт уведомление, части в этом запросе не меняются. Поставить и снять можно и позже».
9. (i) button opens a sheet with `ShareFlowDiagram`: equal grey example flows labelled «пример», never real values; the U59 line «Поддержка ещё и чуть усиливает твою связь в сети с теми, кого ты выбрал. Им не придёт уведомление» under the ▲▼ legend and in the sheet; under the diagram the text «Ты не знаешь, как решил автор, — и знать не нужно. Поддержи тех, чья работа, по-твоему, была важной. Если автор уже оценил человека высоко, добавка будет маленькой; если низко — заметной. Отдают в основном те, кому автор дал больше. Автор твой выбор не видит».
10. Non-voter members (left or removed, or 2-member requests) see only the bookmark section and the deadline.
11. Desktop: hover and keyboard activation for toggles; no long-press.

**Localization:** `closureHelper*` keys (incl. `closureHelperAuthorEdgeNotice`, `closureHelperHeader`, `closureHelperInfoScaling`, `closureHelperSupportEdgeNote`), as in A20.

**Tests (widget):** toggling shows ▲/▼; `released` hint; status line for the three states; Skip confirm; non-voter view; the U58 notice is visible for 1-member, 2-member and non-voter views; the header text is «Чья работа, по-твоему, была важной? Твоя часть от этого не меняется»; the (i) sheet shows the scaling text; the U59 support-edge line appears with the ▲▼ legend and in the sheet; diagram never receives real numbers (its constructor takes only member count and avatars).

### A22 — Results card and My Work archive

**Files:** `features/closure/ui/widget/closure_result_card.dart` (shown on the request screen after finalize), modify `features/my_work/ui/widget/my_work_cards.dart` (~line 356, `showArchiveAffordance`) and its presenter.

**Behaviour:**
1. Outcome line (the author's outcome, always shown). Band sentence: raised «Коллеги подняли твою часть», asIfSilent «Твоя часть — как если бы коллеги промолчали», lowered «Коллеги опустили твою часть». «Автор отметил: не выполнено — части в итогах нет» **only** when outcome is notDone **and** band is none; a notDone member with band raised (peer support, V6) sees the outcome line plus the raised sentence. Band none for other outcomes ⇒ no band sentence.
5. Room rendering of system message kind 3 (`closureStory`): show the story text as a system card in the room.
2. Draft line: notCounted «Твои отметки не вошли…», lastEditNotCounted «В расчёте прошлая версия…» (full text from plan §5).
3. Own bookmarks with toggles (calls `closureSetMark` on the final epoch).
4. My Work: helper cards on open requests show the archive action too; it only hides the card for the viewer.

**Localization:** `closureResult*` keys, as in A20.

**Tests (widget):** each band; notDone with band none (V8) and notDone with band raised (V6); draft flags; archive visible on an open helper card; story system message renders.

### A23 — Remove the review feature (client) and l10n

**Steps**
1. Delete `packages/client/lib/features/evaluation/` after moving anything reusable to `features/closure/`.
2. Remove routes `/beacon/review`, `/beacon/reviews-received`, the profile "reviews about me" sliver, review receipts copy.
3. In both ARB files delete every `evaluation*` / `review*` key that is no longer referenced; run `flutter gen-l10n`, then build_runner.
4. Update existing integration helpers and scenarios that drive the old review flow (grep `integration_test/` for `review`, `evaluation`).
5. `grep -rln "evaluation\|reviewWindow\|review_window" packages/client/lib packages/client/test packages/client/integration_test --include=*.dart | grep -v "\.g\.dart\|\.gql\.dart"` ⇒ only allowlisted identifiers (`BeaconStatus.reviewOpen`) remain.

**Done when:** client tests and lints pass.

### A24a — QA closure-expiry control

**Goal:** e2e tests need to expire an epoch without waiting 7 days. No such control exists today (`QaIntegrationController` has fixtures and realtime controls only).

**Files:** `packages/server/lib/api/controllers/qa_integration_controller.dart` (new action), client integration helpers.

**Steps**
1. Add a QA-only action `expireClosure(beaconId)` that, only when QA integration mode is enabled (same guard as the existing QA actions), sets `closes_at = now() - interval '1 second'` on the live evaluating epoch of that request and then runs one `ClosureFinalizeSweepCase` pass (the real sweep, not a direct finalize).
2. Add a client e2e helper calling it.

**Tests:** the action is rejected when QA mode is disabled (production config); enabled ⇒ the request is finalized by the sweep.

### A24 — Release: versions and deploy runbook

**Steps**
1. Bump `packages/client/pubspec.yaml` version (minor bump from the current version (7.24.8 on main at 2026-09-29), e.g. `7.25.0` — check `main` first).
2. Run the web app once locally (or `flutter build web`) so `packages/client/web/index.html` gets `flutter_bootstrap.js?v=<new version>`; commit that diff.
3. Set `kDefaultMinClientVersion` in `packages/server/lib/env.dart` (~line 79) to the new version; update `packages/server/test/release_client_version_floor_test.dart` if it pins the value.
4. Write the release runbook into the PR description, copied from Arch §11 "Release sequence", plus "after deploy: check `trust_cutover_state.status = 'done'`, queue depth near 0".

### A25 — End-to-end tests

**Files:** a new scenario file in the web integration suite (see `scripts/run_client_integration_web_local.sh` and the existing integration tests for structure).

**Scenarios**
1. Author with three helpers closes; helper 1 supports helper 3, bookmarks the author, presses «Готово»; helper 2 skips; the epoch expires via the A24a helper; every helper sees a results card with the expected band (V3 bands if the author used 70/20/10).
2. Reopen: author closes, sets outcomes, reopens; closes again ⇒ outcomes and drafts are prefilled, committed versions are gone.
3. After finalize, helper toggles a bookmark off and on.

Run with `scripts/run_client_integration_web_local.sh` (not wrapped).

---

## 7. Phase B (separate PR after phase A is live)

### B1 — Ban wall

**Files:** new migration (next free number), `trust_project_pair` replacement, cutover-style bootstrap for existing bans, tests (`mr`).

**Steps**
1. In `trust_project_pair`: if `user_block(subject → object)` exists ⇒ `target = -1` even without evidence rows (create the `user_trust_edge` row).
2. `needs_publish` also when the sign changes or the wall level changes (bypass ε).
3. Block and unblock use cases call `project([(blocker, blocked)])`.
4. One-shot bootstrap: project every existing block pair (add to `TrustCutoverCase` as a second versioned step `ban_walls`, keyed in `trust_cutover_state` by a new row or a `version` column).
5. Set `trust_config.wall_publish_enabled = true`.

**Tests (mr):** block ⇒ MR edge −1; unblock ⇒ edge removed or back to T; score of the blocked user from the blocker's view drops to the wall behaviour described in `NEGATIVE_EDGES_FEATURE.md`.

### B2 — Noisy-contact wall

**Files:** migration adding `beacon_forward_edge.contact_outcome`, `contact_resolved_at`, `contact_deadline_at` and the partial index; insert kinds 6 (`engaged`) and 7 (`noisy`, `wall_levels` = `[{"min_n":3,"level":0.1},{"min_n":6,"level":0.3},{"min_n":10,"level":0.6}]`); `contact_resolution_sweep_case.dart`; changes in forward, help-offer and inbox cases.

**Steps:** implement the transition table of Arch §6 row by row. `contact_deadline_at = created_at + 7 days + jitter` with jitter seconds = `(('x' || substr(md5(edge_id), 1, 8))::bit(32)::bigint % 172801) − 86400` (always non-negative before the subtraction; never use Dart `hashCode`). Set only for edges created after the migration. Wall level in projection: `level(n_noisy)` when `T_recent < 0.05` and `n_noisy ≥ 3`, where `n_noisy` is the **decayed** sum (half-life 14 d).

**Tests:** one pg test per transition row; three count-1 `noisy` observations at the same instant (fixed clock) ⇒ `n_noisy = 3`, target −0.1; observations aged 0 / 7 / 14 days ⇒ `n_noisy = 1 + 0.7071 + 0.5 = 2.2071` ⇒ no wall; level crossings at 3 / 6 / 10 ⇒ 0.1 / 0.3 / 0.6; immunity: with 3 noisy observations and one `helped` row (count 1) 179 days old ⇒ no wall (T_recent ≥ 0.05); the same row 181 days old ⇒ wall (it no longer counts in T_recent); late engagement retracts `noisy`.

### B3 — "I pinged them" display factor

**Files:** the forward candidates query/use case (`forward_candidates_case.dart` and its repository).

**Steps:** multiply each candidate's displayed score by `1 − min(0.8, Σ 2^(−age_days))` over the viewer's own forwards to that candidate in the last 7 days. Display only; never written to trust tables.

**Tests:** zero forwards ⇒ factor 1.0; one forward right now ⇒ Σ = 1 ⇒ factor `1 − 0.8 = 0.2`; two forwards now ⇒ still 0.2 (clamped); one forward 7 days old ⇒ Σ = 2^−7 ≈ 0.0078 ⇒ factor ≈ 0.992; a forward older than 7 days ⇒ ignored.

### B4 — Wall invariant suites

**Files:** `test/trust/wall_invariants_mr_test.dart` (tags `pg`, `mr`, `-j 1`).

**Cases:** a wall never raises the walled user's score for the wall's owner; locality (unrelated frames change by at most ε) is asserted **only** for wall add / level change / remove while the owner's positive outgoing edges are unchanged; positive ↔ wall sign transitions are tested separately without the locality assertion (`NEGATIVE_EDGES_FEATURE.md:263,351` exempts them); removing a wall restores the previous scores within ε after `mr_sync`.

---

## 8. Final checklist before merging phase A

- [ ] All units A1–A25 committed separately.
- [ ] The A18 and A23 greps return only allowlisted identifiers (migrations and generated files excluded).
- [ ] Browser e2e (A25) green.
- [ ] Product §8 comprehension study done (RITE rounds, then 20 per role) — if not done, mark the release **blocked on comprehension gate**, do not silently skip.
- [ ] Pilot instrumentation of Arch §13 in place (or listed as a blocked gate).
- [ ] Server: pure, pg, mr suites green (run serially).
- [ ] Client: tests and custom lints green; baseline not increased.
- [ ] Hasura metadata has no closure tables and no `beacon_review_window`.
- [ ] `ClosureResult` schema contract test green (no numbers leave the server).
- [ ] Release runbook in the PR description.

## 9. Review log

- rev 5 (2026-09-29) — plan rev 23, arch rev 6: U59 support edge; new unit A1b (m0204 seeds kind 9, A1 already landed; phase B migration shifts to m0205); A2 enum, A14 step 5 and tests, A21 copy.
- rev 4 (2026-09-29) — plan rev 22, arch rev 5: support reframed as own judgement; new unit A7a (vectors V16–V20 and a scaling property, tests only, A7 already landed); A21 header and (i) text.
- rev 3 (2026-09-29) — U58 (plan rev 21, arch rev 4): kind 8 `worked_with_author` seeded in A1 (linear 180-day window, excluded from immunity), written in A14 for members present until closure with `count = 1/√|P|`, notice in A21.
- rev 2 (2026-09-29) — Codex gpt-6-astra (high) review of rev 1, all 28 findings applied: real `user_trust_edge` columns and trigger name; Drift ambient transactions via `MutatingUnitOfWorkPort`, ports without session types; publisher and cutover exclusivity by lease + fencing token (pooled connections); sweep passes and re-checks the selected epoch; P0.1 clamps `_target` keeping the block override, `mr_sync` before `bumpMrEpoch`; vote/block/maintenance callers moved to A5; legacy reviewOpen → needsMoreHelp; apportionment fixed to the single water-filling rule (architecture rev 3 aligned); `renormalize` nullable, empty/singleton A, reclose renormalization; routing input spelled out, old trust types removed in A10; membership hooks take the lock before writing events, incl. `UserBlockCase`, voter derived from `active_at_open`; current close/finalize effects preserved; blocked-member access; notDone result text conditional; TaskWorker factory, contract JSON and client classification wiring; Drift/erasure cleanup; deletion trigger enqueues; schema refresh, gen-l10n, overlay test; A11b ports so units compile alone; m0199 test pin; QA expiry control (A24a) and release gates; decayed `n_noisy` tests; reminder audience; B4 locality scope; grep gates exclude migrations with an allowlist.
- rev 1 (2026-09-29) — initial step plan from architecture rev 2; settlement and apportionment vectors computed with independent Python transcriptions (`settle_ref.py`, `apportion.py` in the session scratchpad) and cross-checked with the simulator.
