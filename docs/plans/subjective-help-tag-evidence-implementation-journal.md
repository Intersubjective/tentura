# Subjective Help-Tag Evidence — implementation journal

## Objective

Implement the subjective help-tag evidence system end to end per the implementation
plan: ledger extensions, evidence SQL, domain ports and repositories, emission paths
(acknowledgement, forward reason, invite seed), projection and band composition,
GraphQL surface, client data layer and UI, telemetry, docs/ADR, and integration
proofs.

## Authority

| Document | Path |
|---|---|
| Implementation plan | `docs/plans/subjective-help-tag-evidence-implementation-plan.md` |
| Architecture (design authority) | `docs/plans/subjective-help-tag-evidence-architecture.md` |

Live code wins over both documents when they disagree.

## Repository baseline

| Field | Value |
|---|---|
| Repository | `/home/vader/MY_SRC/tentura` |
| Branch | `main` |
| Starting HEAD | `925dc3e2b9602eee3a7d8e3a516601d54f00d9e8` (`925dc3e2 docs: accept web tab manual validation as pending`) |
| Journal started | 2026-08-12 |

## Protected pre-existing worktree changes

Recorded verbatim from `git status` at journal creation. Do not edit, stage,
revert, or commit these unless a later unit proves a file is genuinely required;
in that case stop and record the conflict in this journal.

```text
 M docs/archive/journals/commitment-truth-rework-journal.md
 M docs/archive/plans/commitment-truth-rework-plan.md
 M docs/audits/room-coordination-audit.md
 M packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart
 M scripts/run_client_integration_web_local.sh
?? dart-defines
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/received-reviews-trust-changes-plan.md
?? docs/plans/subjective-help-tag-evidence-architecture.md
?? docs/plans/subjective-help-tag-evidence-implementation-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
```

The source plan and architecture files are pre-existing untracked artifacts for
this run. They are authoritative but must not be staged or committed by
implementation workers unless a dedicated docs unit owns them. This journal is
orchestrator-owned.

## Ordered manifest (plan §4)

Strictly sequential except: B2a/B2b/B2c may run in any order after B1; F2–F5 in
any order after F1b. One worker at a time.

- [x] **A0** — Journal + baseline (journal only)
- [x] **A1** — Ledger extension (depends: A0) — `m0141`; `person_capability_events.dart`; `CapabilityEventSource.seedRoutingAttestation(4)`
- [x] **A2** — Derived tables + context fn (depends: A1) — `m0142`; cell/window/mute/generation/epoch tables + Drift; `cap_normalize_context`
- [x] **A3** — Evidence SQL functions (depends: A2) — `m0143`; `cap_strength`, `cap_cell_lock`, `cap_generation_bump`, `cap_cell_rebuild`
- [ ] **B1** — Domain types + ports (depends: A3) — `domain/capability/*`, `domain/port/capability_*`, `capability_consts.dart`
- [ ] **B2a** — Cell write adapter (depends: B1) — `capability_evidence_repository.dart`
- [ ] **B2b** — Witness window adapter (depends: B1) — `witness_window_repository.dart`
- [ ] **B2c** — Read adapters (depends: B1) — own-evidence, tombstone, mute, block-query repositories
- [ ] **B3** — MR epoch ownership (depends: B2b) — `m0144`; epoch bump in `trust_rebuild_effective_edge`; block/vote invalidation
- [ ] **C1a** — Ack schema + atomic adapter (depends: B2a) — `m0145`; `beacon_evaluation_ack_tag`; `submitEvaluationAtomic`
- [ ] **C1b** — Ack use-case policy (depends: C1a) — `evaluationSubmit` role/slug/cap policy; typed help-offer port
- [ ] **C2** — Finalization emission (depends: C1b) — `ReviewCloseSnapshot`, finalization CTE, batch emission
- [ ] **C3a** — Forward server paths (depends: B2a) — forward-edge port return shape; create/update/cancel + reconciliation
- [ ] **C3b** — Forward client semantics (depends: C3a) — `forward_cubit.dart` null-vs-empty; mutation resolver
- [ ] **C4** — Invite seed attestation (depends: B2a, B2c) — `m0146`; `invite_seed_prompt_state`; prompt-state port + use case
- [ ] **C5** — Retire `commitRole` reads (depends: B2c) — `person_capability_event_repository.dart`
- [ ] **D0** — Band candidate facts port (depends: B2b) — `BandCandidatePort` + adapter
- [ ] **D1** — Projection use case (depends: C1b–C5) — `capability_projection_case.dart`
- [ ] **D2** — Band composition (depends: D1, D0) — `forward_band_case.dart`, `fnv1a64`
- [ ] **D3** — Expiry sweep (depends: B2a) — `m0147`; lease columns; sweep case + TaskWorker registration
- [ ] **D4** — Model invariant suite (depends: D2) — `test/domain/capability/model_invariants_test.dart`
- [ ] **E1a** — Query resolvers + authz (depends: D2, D3, D4) — `subjectiveTags`, `forwardContext`, `tagExplanation`, `CapabilityRoutingCase` read methods
- [ ] **E1b** — Mutation resolvers + authz (depends: E1a) — `myRoutingTags`, seed, revoke, setMute, prompt answer/skip
- [ ] **F1a** — Client schema + routing (depends: E1b) — `schema.graphql`, `_tenturaDirectOperationNames`
- [ ] **F1b** — Client gql docs + repository (depends: F1a) — `.graphql` documents, repository, client entities
- [ ] **F2** — Forward band UI (depends: F1b) — forward cubit/state/screen
- [ ] **F3** — Profile projection UI (depends: F1b) — `profile_view_body.dart` + cubit/state (new field, not `viewerVisible`)
- [ ] **F4a** — Invite prompt receipt (depends: F1b, C4) — receipt card + prompt state machine
- [ ] **F4b** — Seed edit/withdraw (depends: F4a) — inviter-side edit path on invitee profile
- [ ] **F5** — Routing mute screen (depends: F1b) — route + registration + cubit + settings entry
- [ ] **F6** — Client release checks (depends: F2–F5) — semver bump, web cache-buster, min-client-version
- [ ] **G1a** — Telemetry — producers (depends: F6) — band fill/conversion, seed renewal, mute rate
- [ ] **G1b** — Telemetry — analysis signals (depends: G1a) — window coverage, floor margin, eligible-witness coverage, reciprocity histogram
- [ ] **G2** — Docs and ADR (depends: G1) — `trust_edges.md` rewrite, ADR
- [ ] **G3a** — Server-side e2e proof (depends: G2) — pg-level 4-user fixture
- [ ] **G3b** — Browser e2e proof (depends: G3a) — web harness assertions on rendered band

## Verification commands (plan §2)

Codegen (when schema/types change):

```bash
cd packages/server && dart run build_runner build -d
cd packages/client && flutter gen-l10n && dart run build_runner build -d
```

Standard verification:

```bash
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
cd packages/client && flutter test
cd packages/server && dart test -x pg
cd packages/server && dart test -t pg
bash scripts/check-user-facing-terminology.sh
```

Live Postgres for `-t pg`: `sudo service docker start && ./scripts/dev-up.sh` (see
`local-debug` skill).

## Worker protocol

1. Read `AGENTS.md`, clean-architecture skill, architecture rules, this journal
   (full), plan §1–§3, and the assigned unit body including Preconditions.
2. Implement only the assigned unit. If another unit is incomplete, record it;
   do not fix it.
3. If a unit's Preconditions are false in the tree, stop and report.
4. Preserve protected pre-existing changes; commit only owned coherent steps.
5. Append a checkpoint on meaningful progress and a final entry before exit.

## Entry template (every later unit appends below)

```
## <unit id> — <status: complete|partial|blocked> — <ISO date>
COMMITS: <hashes + subjects>
TESTS: <exact commands + outcomes>
FILES: <changed paths>
FINDINGS: <facts that contradicted the plan, decisions taken>
REMAINING: <concrete unfinished work or "none">
```

## Open questions

- None at journal creation. Record new questions here; do not re-litigate plan §3
  decisions without an explicit architecture/plan revision.

---

## A0 — complete — 2026-08-12

COMMITS: docs: initialize subjective help-tag evidence implementation journal (A0) (`1d15bcb2b0ada46a4237141a9a1b56bf10244a59`)

TESTS:

```bash
git diff --check -- docs/plans/subjective-help-tag-evidence-implementation-journal.md
→ no whitespace errors (A0 is docs-only; no code verification required)
```

FILES:

- `docs/plans/subjective-help-tag-evidence-implementation-journal.md` (created)

FINDINGS:

- Starting HEAD matches verified baseline `925dc3e2b9602eee3a7d8e3a516601d54f00d9e8` on branch `main`.
- Pre-existing worktree matches the protected list supplied to A0; additionally `docs/plans/issue-115-reply-to-message-implementation-journal.md` is untracked (not in the user-supplied list but present in `git status`).
- Plan and architecture files exist untracked at expected paths; left unstaged per A0 scope.

REMAINING: none

### Manager acceptance — 2026-08-12

Accepted after independent inspection. The final A0 artifact is commit
`1d15bcb2b0ada46a4237141a9a1b56bf10244a59`; scoped `git diff --check` passed
and every protected baseline path remains untouched. The A0 worker made two
local amend attempts while trying to self-reference that commit, then was
interrupted for scope drift. No unrelated file was staged or committed.

## A1 — complete — 2026-08-12

COMMITS: feat(server): extend person_capability_event ledger for help-tag evidence (A1) (`97b9d6235db9dfef7992de0599ad1ca388994c5b`)

TESTS:

```bash
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 3s; wrote 2 outputs

cd packages/server && dart test -t pg test/data/database/m0141_person_capability_event_ledger_test.dart
→ 00:01 +2: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1319: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check -- <owned A1 paths>
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/database/migration/m0141.dart` (created)
- `packages/server/lib/data/database/migration/_migrations.dart` (part + ordered registration)
- `packages/server/lib/data/database/table/person_capability_events.dart` (`forwardEdgeId`, `invitationId`)
- `packages/server/lib/domain/capability/capability_event_source.dart` (`seedRoutingAttestation(4)`)
- `packages/server/test/data/database/m0141_person_capability_event_ledger_test.dart` (created)

FINDINGS:

- Preconditions confirmed: m0140 is latest registered migration; `person_capability_event` had no `source_type` CHECK; `invitation.id` is `text` PK — FK enforced as planned.
- `tentura_db.g.dart` is gitignored under `packages/server/.gitignore`; codegen run locally but generated output not committed per plan rules.
- Disposable-db pg test pattern (rollback m0141 → seed → re-migrate) mirrors `beacon_cover_migration_test.dart`.

REMAINING: none

### Manager acceptance — 2026-08-12

Accepted after independent review of `97b9d623`: migration registration is
contiguous in both the part list and ordered `InMemory` list; SQL constraints,
partial indexes, Drift references, and source enum match A1. Independent
`dart test -t pg test/data/database/m0141_person_capability_event_ledger_test.dart`
passed, as did `./scripts/check-custom-lints.sh packages/server`. Protected
baseline paths remain untouched.

## A2 — complete — 2026-08-12

COMMITS: feat(server): add capability evidence derived tables and context normalization (A2) (`0a932540011e84c5a93653c6d3bf0e77f1c08c28`)

TESTS:

```bash
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 11s; wrote 327 outputs

cd packages/server && dart test -t pg test/data/database/m0142_derived_tables_migration_test.dart test/domain/capability/context_normalization_pg_test.dart
→ 00:01 +9: All tests passed!

cd packages/server && dart test -x pg
→ 00:06 +1326: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check -- <owned A2 paths>
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/database/migration/m0142.dart` (created)
- `packages/server/lib/data/database/migration/_migrations.dart` (part + ordered registration)
- `packages/server/lib/data/database/table/capability_evidence_edges.dart` (created)
- `packages/server/lib/data/database/table/capability_evidence_generations.dart` (created)
- `packages/server/lib/data/database/table/ego_witness_windows.dart` (created)
- `packages/server/lib/data/database/table/capability_routing_mutes.dart` (created)
- `packages/server/lib/data/database/table/mr_publish_epochs.dart` (created)
- `packages/server/lib/data/database/tentura_db.dart` (imports + table registry)
- `packages/server/lib/domain/capability/context_normalization.dart` (created)
- `packages/server/test/data/database/m0142_derived_tables_migration_test.dart` (created)
- `packages/server/test/domain/capability/context_normalization_test.dart` (created)
- `packages/server/test/domain/capability/context_normalization_pg_test.dart` (created)

FINDINGS:

- Drift `int64` defaults require `Constant(BigInt.zero)` (not `const Constant(0)`); regenerated `tentura_db.g.dart` is gitignored.
- `pg_get_function_identity_argument` unavailable in disposable test Postgres; used `pg_get_functiondef` + `proname` filter instead for MVU normalization assertion.
- `tentura_db.g.dart` is gitignored under `packages/server/.gitignore`; codegen run locally but generated output not committed per plan rules.

REMAINING: none

### Manager review — remediation required — 2026-08-12

Rejected pending a narrow parity repair. The Dart implementation uses
`String.trim()`, while PostgreSQL `btrim(text)` (the A2 SQL authority) removes
ASCII spaces only. A tab-delimited input remains tab-delimited in SQL but not in Dart,
which can split canonical context keys across layers. A fresh remediation worker must make the
Dart implementation exactly match the SQL behavior, add a tab-delimited parity
case to both pure and pg tests, rerun the focused tests and server custom lint,
and commit its source/test repair and journal checkpoint separately. No other
A2 scope is reopened.

## A2 remediation — complete — 2026-08-12

COMMITS: fix(server): match capNormalizeContext to PostgreSQL btrim (A2 parity) (`cdbf9b35a40cc26d17b40808766562ca8029c1e1`)

TESTS:

```bash
cd packages/server && dart test test/domain/capability/context_normalization_test.dart
→ 00:00 +8: All tests passed!

cd packages/server && dart test -t pg test/data/database/m0142_derived_tables_migration_test.dart test/domain/capability/context_normalization_pg_test.dart
→ 00:01 +10: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check -- packages/server/lib/domain/capability/context_normalization.dart packages/server/test/domain/capability/context_normalization_test.dart packages/server/test/domain/capability/context_normalization_pg_test.dart
→ no whitespace errors
```

FILES:

- `packages/server/lib/domain/capability/context_normalization.dart` (replaced `String.trim()` with `_btrimAsciiSpaces` matching PostgreSQL `btrim(text)`)
- `packages/server/test/domain/capability/context_normalization_test.dart` (tab-delimited valid case)
- `packages/server/test/domain/capability/context_normalization_pg_test.dart` (tab-delimited parity case)

FINDINGS:

- Manager defect confirmed: `String.trim()` strips tabs; PostgreSQL `btrim(text)` removes only ASCII U+0020 spaces. Input `'\tAbC\t'` normalizes to `'\tAbC\t'` in SQL but was `AbC` in Dart.
- Repair: private `_btrimAsciiSpaces` helper; no migration/SQL changes.

REMAINING: none (A2 remediation scope complete; manager re-review pending)

### Manager acceptance — 2026-08-12

Accepted after independent review of the A2 implementation and the focused
remediation. `m0142` is registered contiguously, its five tables/indexes and
singleton/check constraints match the plan, and `mutually_visible_users`
preserves the prior block and visibility predicates while passing normalized
context to `person_visibility_peers`. The original Dart/SQL whitespace mismatch
is closed by `cdbf9b35`: only U+0020 is trimmed, while tab-delimited context
remains unchanged in both layers. Independent evidence passed:

```bash
cd packages/server && dart test test/domain/capability/context_normalization_test.dart
→ 00:00 +8: All tests passed!

cd packages/server && dart test -t pg test/data/database/m0142_derived_tables_migration_test.dart test/domain/capability/context_normalization_pg_test.dart
→ 00:01 +10: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0 (tentura_lints total: 0)

git diff --check cdbf9b35^ cdbf9b35
→ no whitespace errors
```

Protected baseline paths remain untouched. A3 may now begin.

## A3 — complete — 2026-08-12

COMMITS: feat(server): add capability evidence SQL functions (A3) (`4dab460b41557c61268e4751f817265de8431692`)

TESTS:

```bash
cd packages/server && dart test -t pg test/data/database/m0143_capability_evidence_sql_test.dart
→ 00:02 +9: All tests passed!

cd packages/server && dart test -x pg
→ 00:09 +1335: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check -- packages/server/lib/data/database/migration/m0143.dart packages/server/lib/data/database/migration/_migrations.dart sql/triggers.sql packages/server/test/data/database/m0143_capability_evidence_sql_test.dart
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/database/migration/m0143.dart` (created)
- `packages/server/lib/data/database/migration/_migrations.dart` (part + ordered registration)
- `sql/triggers.sql` (A3 function mirror only)
- `packages/server/test/data/database/m0143_capability_evidence_sql_test.dart` (created)

FINDINGS:

- Preconditions confirmed: `m0142` registered; A3 functions absent before this unit.
- Local Postgres does not accept `SET TRANSACTION TIMESTAMP`; boundary and half-life proofs use literal expired `created_at` values (calendar now is past 2026-02-29 + 24 months) and transaction-scoped `now() - interval` inside `BEGIN` for exact 365-day decay.
- `provolatile` from `pg_proc` returns `UndecodedBytes` in the dart postgres driver; stability checked via `provolatile = 's'` in SQL instead.
- `cap_cell_rebuild` deletes the cell when both accumulators are zero; generation rows are not bumped inside rebuild (later units own write transactions).

REMAINING: none (B1 may begin)

## A3 remediation — complete — 2026-08-12

COMMITS: test(server): prove A3 month-window eligibility discriminator in PG (`e05a2fbb`); docs: record A3 eligibility test remediation pending manager acceptance (`33717598`)

TESTS:

```bash
cd packages/server && dart test -t pg test/data/database/m0143_capability_evidence_sql_test.dart
→ 00:02 +9: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check
→ no whitespace errors
```

FILES:

- `packages/server/test/data/database/m0143_capability_evidence_sql_test.dart`

FINDINGS:

- Manager rejection confirmed: prior boundary tests compared 2024 literals to live `now()`, so they would pass with the prohibited inverse cutoff `created_at > (now() - make_interval(months => …))` once calendar time crossed the expiry boundary.
- Causal discriminator at frozen reference instants (intended=false, flawed=true):
  - `2024-02-29 + 24 months` vs reference `2026-02-28T00:00:00Z`;
  - `2024-01-31 + 1 month` vs reference `2024-02-29T00:00:00Z`.
- `pg_get_functiondef(cap_cell_rebuild)` now asserted in the PG test: contains `e.created_at + make_interval(months => _window_months) > now()`; excludes `now() -` and `_cutoff`.
- Upgrade test extended: `cap_generation_bump` returns 1 then 2 for one triple; exactly one `capability_evidence_generation` row with generation 2.
- `m0143.dart` and `sql/triggers.sql` unchanged (SQL semantics already correct).

REMAINING: manager review and acceptance; B1 remains blocked

### Manager acceptance — 2026-08-12

Accepted after independent review of A3 (`4dab460b`) and the remediation
(`e05a2fbb`). The installed migration test proves both calendar discontinuities
at frozen reference instants: `2024-02-29 + 24 months` and
`2024-01-31 + 1 month` are expired while their prohibited inverse-cutoff forms
would still be eligible. It also inspects the installed `cap_cell_rebuild` with
`pg_get_functiondef`, rejecting both `now() -` and `_cutoff`, and proves that
two `cap_generation_bump` calls retain one authoritative row at generation 2.

Manager comparison of `m0143.dart` and `sql/triggers.sql` found the four SQL
function bodies identical after removing the Dart raw-string delimiters and
blank wrapping. Registration and upgrade behavior are covered by the fresh
migration test. Independent verification passed:

```bash
cd packages/server && dart test -t pg test/data/database/m0143_capability_evidence_sql_test.dart
→ +9: All tests passed!

cd packages/server && dart test -x pg
→ +1327: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check 4b9d7e10..HEAD
→ no whitespace errors
```

The protected baseline paths remain untouched. B1 is authorized to begin.
