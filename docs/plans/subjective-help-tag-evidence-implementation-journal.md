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
- [x] **B1** — Domain types + ports (depends: A3) — `domain/capability/*`, `domain/port/capability_*`, `capability_consts.dart`
- [x] **B2a** — Cell write adapter (depends: B1) — accepted after pair-lock remediation (`c3e81896`)
- [x] **B2b** — Witness window adapter (depends: B1) — accepted after fixture-isolation remediation + flakiness repair (`81249774`, `88a09c21`)
- [x] **B2c** — Read adapters (depends: B1) — own-evidence, tombstone, mute, block-query repositories
- [x] **B3** — MR epoch ownership (depends: B2b) — `m0144`; epoch bump in `trust_rebuild_effective_edge`; block/vote invalidation
- [x] **C1a** — Ack schema + atomic adapter (depends: B2a) — `m0145`; `beacon_evaluation_ack_tag`; `submitEvaluationAtomic`
- [x] **C1b** — Ack use-case policy (depends: C1a) — `evaluationSubmit` role/slug/cap policy; typed help-offer port
- [x] **C2** — Finalization emission (depends: C1b) — `ReviewCloseSnapshot`, finalization CTE, batch emission
- [x] **C3a** — Forward server paths (depends: B2a) — forward-edge port return shape; create/update/cancel + reconciliation
- [x] **C3b** — Forward client semantics (depends: C3a) — `forward_cubit.dart` null-vs-empty; mutation resolver
- [x] **C4** — Invite seed attestation (depends: B2a, B2c) — `m0146`; `invite_seed_prompt_state`; prompt-state port + use case
- [x] **C5** — Retire `commitRole` reads (depends: B2c) — `person_capability_event_repository.dart`
- [x] **D0** — Band candidate facts port (depends: B2b) — `BandCandidatePort` + adapter
- [x] **D1** — Projection use case (depends: C1b–C5) — `capability_projection_case.dart`
- [x] **D2** — Band composition (depends: D1, D0) — `forward_band_case.dart`, `fnv1a64`
- [x] **D3** — Expiry sweep (depends: B2a) — `m0147`; lease columns; sweep case + TaskWorker registration
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

## B1 — complete — 2026-08-12

COMMITS: feat(server): add capability evidence domain types and ports (B1) (`86876ad7`)

TESTS:

```bash
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 7s; wrote outputs (capability_evidence_models.freezed.dart generated locally, gitignored)

cd packages/server && dart test -x pg test/domain/capability/capability_consts_test.dart
→ 00:00 +9: All tests passed!

cd packages/server && dart test -x pg
→ 00:09 +1336: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ no matches

git diff --check -- <owned B1 paths>
→ no whitespace errors
```

FILES:

- `packages/server/lib/domain/capability/capability_consts.dart` (created)
- `packages/server/lib/domain/capability/capability_evidence_models.dart` (created — enums + Freezed entities)
- `packages/server/lib/domain/port/capability_evidence_port.dart` (created)
- `packages/server/lib/domain/port/capability_cell_port.dart` (created)
- `packages/server/lib/domain/port/witness_window_port.dart` (created)
- `packages/server/lib/domain/port/capability_own_evidence_port.dart` (created)
- `packages/server/lib/domain/port/routing_mute_port.dart` (created)
- `packages/server/lib/domain/port/pair_block_query_port.dart` (created)
- `packages/server/test/domain/capability/capability_consts_test.dart` (created)

FINDINGS:

- Preconditions confirmed: A3 functions present (`m0143`, `sql/triggers.sql` mirror); no prior B1 artifacts in tree.
- Consolidated B1 Freezed types into `capability_evidence_models.dart` (matches `attention_models.dart` grouping); seven ports in separate `domain/port/*` files per local convention.
- `capability_evidence_models.freezed.dart` generated locally and gitignored per plan; not staged.
- `ProjectionTier` declaration order pinned by test; half-life constants asserted at 31536000 / 7776000 seconds.

REMAINING: manager review and acceptance; B2 remains blocked

### Manager acceptance — 2026-08-12

Accepted after independent review of B1 (`86876ad7`) and its required-field
remediation (`53bec447`). The source contains all thirteen planned value types,
the four enum contracts, and the six plan ports (the earlier "seven ports" text
was only a worker-entry count typo). Every port signature matches B1: batching
and pair provenance are preserved, witness-window facts remain raw/domain-owned,
mutes stay subject-keyed, and blocks remain a set-wide pair query.

`ForwardBandRow` now requires an explicit nullable `rowTier` and explicit
`labels`; exploration must therefore be constructed intentionally with
`rowTier: null, labels: []`. `WitnessCellRow` exposes only SQL-computed
strengths, `TagProjection` has no score, and the channel-first tier order is
pinned by tests. No data-layer imports occur under server `lib/domain`.

Independent verification passed:

```bash
cd packages/server && dart test -x pg test/domain/capability/capability_consts_test.dart
→ +10: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/(repository|)" packages/server/lib/domain
→ no matches

git diff --check 432d2fed..HEAD
→ no whitespace errors
```

The protected baseline paths remain untouched. B2a, B2b, and B2c are each
authorized to begin sequentially; start only one at a time.

## B1 remediation — complete — 2026-08-12

COMMITS: fix(server): require explicit ForwardBandRow tier and labels (B1) (`53bec447`)

TESTS:

```bash
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 2s; wrote 14 outputs

cd packages/server && dart test -x pg test/domain/capability/capability_consts_test.dart
→ 00:00 +10: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0

git diff --check -- packages/server/lib/domain/capability/capability_evidence_models.dart packages/server/test/domain/capability/capability_consts_test.dart
→ no whitespace errors
```

FILES:

- `packages/server/lib/domain/capability/capability_evidence_models.dart` (`ForwardBandRow.rowTier` and `labels` now `required`)
- `packages/server/test/domain/capability/capability_consts_test.dart` (explicit exploration and evidence construction)

FINDINGS:

- Manager defect confirmed: `ForwardBandRow` had optional/defaulted `rowTier` and `labels`, violating the B1 plan's required-field contract. Repair makes both explicit required inputs while retaining nullable `rowTier` for exploration rows.
- The prior B1 journal entry's "seven ports" wording was a documentation/count typo. The B1 implementation contains the six plan ports: `CapabilityEvidencePort`, `CapabilityCellPort`, `WitnessWindowPort`, `CapabilityOwnEvidencePort`, `RoutingMutePort`, `PairBlockQueryPort`.

REMAINING: manager review and acceptance; B2 remains blocked

## B2a — complete — 2026-08-12

COMMITS: feat(server): add capability evidence write repository (B2a) (`3ee294bf`)

TESTS:

```bash
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 4s; wrote 6 outputs (CapabilityEvidencePort Injectable registration in local di.config.dart, not committed)

cd packages/server && dart test -t pg test/data/repository/capability_evidence_repository_pg_test.dart
→ 00:01 +7: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1337: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check -- packages/server/lib/data/repository/capability_evidence_repository.dart packages/server/test/data/repository/capability_evidence_repository_pg_test.dart
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/repository/capability_evidence_repository.dart` (created)
- `packages/server/test/data/repository/capability_evidence_repository_pg_test.dart` (created)

FINDINGS:

- Preconditions confirmed: B1 ports and A3 SQL functions present; no prior `CapabilityEvidencePort` adapter in tree.
- `cap_cell_rebuild` fourth argument must be cast `$4::integer` when invoked via Drift `customStatement`; bare Dart `int` binds as `bigint` and Postgres rejects the call.
- `emitOutcomeEvidenceBatch` intentionally skips `withMutatingUser` so C2 finalization can call it inside one actor/system UoW; other write methods wrap in `withMutatingUser(observerId)` with same-actor nesting safe.
- `CapabilityCellPort` not registered per plan — `claimExpiredCells` awaits D3/m0147 lease columns; read/expiry adapter is B2b/D3 scope.
- Concurrent deadlock test opens two `TenturaDb` instances on the same pool (Drift debug warning only); both transactions complete with lexicographic lock order.

REMAINING: manager review and acceptance; B2b/B2c remain blocked

## B2a remediation — complete — 2026-08-12

STATUS: complete (manager acceptance pending)

COMMITS: fix(server): harden capability evidence write repository (B2a) (`8283570a`)

TESTS:

```bash
cd packages/server && dart test -t pg test/data/repository/capability_evidence_repository_pg_test.dart
→ 00:01 +10: All tests passed!

cd packages/server && dart test -x pg
→ 00:08 +1337: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check -- packages/server/lib/data/database/tentura_db.dart packages/server/lib/data/repository/capability_evidence_repository.dart packages/server/test/data/repository/capability_evidence_repository_pg_test.dart
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/database/tentura_db.dart` (`isInAmbientMutatingTransaction`)
- `packages/server/lib/data/repository/capability_evidence_repository.dart` (UoW guard, change detection, forward-edge lock)
- `packages/server/test/data/repository/capability_evidence_repository_pg_test.dart` (rejection, idempotency, forward concurrency, causal lock-order)

FINDINGS:

- Review of `3ee294bf` confirmed four enforcement gaps: ambient UoW not enforced on batch emit; generation bumped on no-op retries; forward reconcile read-before-lock race; concurrent test did not prove lexicographic lock order.
- `TenturaDb.isInAmbientMutatingTransaction` inspects the existing zone-scoped mutating transaction context (actor or system); no per-observer `withMutatingUser` re-entry.
- Forward-edge serialization uses `pg_advisory_xact_lock(hashtextextended('cap:forward:' || edgeId, 4242))` before slug discovery; cell locks remain lexicographic on `(observer, subject, tag)`.
- Idempotent retries skip bump/rebuild when ledger state already matches desired outcome/forward/seed/revoke inputs.

REMAINING: manager acceptance pending; B2b/B2c remain blocked

## Manager review — B2a rejected for further remediation — 2026-08-12

The remediation commit `8283570a` is not accepted yet. Independent execution
passed the worker's stated commands:

```bash
cd packages/server && dart test -t pg test/data/repository/capability_evidence_repository_pg_test.dart
→ +10: All tests passed! (Drift emits its expected multi-database debug warning)

cd packages/server && dart test -x pg
→ +1337: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check
→ no whitespace errors
```

However, `upsertSeedAttestation` reads `_activeSeedSlugs` before acquiring any
lock that serializes the complete `(observer, subject)` replacement. It then
locks only the stale union of per-tag cells. Two disjoint concurrent desired
sets can therefore both observe the old set. They may commit their union, or a
later stale replacement can soft-delete a newly written tag without bumping or
rebuilding that tag's cell. The ledger and derived cache can diverge.

Required remediation:

- acquire a transaction-scoped, collision-unambiguous advisory lock for the
  seed-attestation `(observerId, subjectId)` pair **before** reading active
  seed rows; retain the existing lexicographic per-cell locks for the post-lock
  current/desired union;
- re-read current seed rows after that pair lock;
- add a deterministic PG concurrency test: block a first replacement at its
  `transport` cell lock, start a competing `pets` replacement, release the
  first block, then prove the pair-serialized final state is exactly `pets`
  and only its rebuilt cell remains. The test must fail against `8283570a` and
  must not rely on scheduler luck.

Fresh Claude CLI diagnosis was attempted twice as required after the second
Cursor attempt, first broadly and then with the exact source lines; both
produced no output and hit the bounded timeout. This is an external-tool
failure, not supporting evidence. The next Cursor remediation must use the
manager's concrete causal finding above.

REMAINING: fresh B2a remediation and manager acceptance; B2b/B2c remain
blocked.

## B2a remediation (pair lock) — complete — 2026-08-12

STATUS: complete (manager acceptance pending)

COMMITS: fix(server): serialize seed attestation pair replacements (B2a) (`c3e81896`)

TESTS:

```bash
cd packages/server && dart test -t pg test/data/repository/capability_evidence_repository_pg_test.dart
→ 00:02 +11: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1337: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/repository/capability_evidence_repository.dart` (`_lockSeedAttestationPair` before `_activeSeedSlugs`)
- `packages/server/test/data/repository/capability_evidence_repository_pg_test.dart` (causal pair-lock concurrency test)

FINDINGS:

- Manager defect confirmed on `8283570a`: `upsertSeedAttestation` read active seed rows before any lock serializing the full `(observer, subject)` replacement; disjoint concurrent sets could union or soft-delete without generation bump/rebuild.
- Pair lock uses `pg_advisory_xact_lock(hashtextextended('cap:seed:' || observer || chr(31) || subject, 4242))` — prefix plus `chr(31)` separator matches project idiom and avoids naive concatenation collisions.
- Causal PG test: hold `transport` cell lock → start `[transport]` upsert (waits at cell lock while holding pair lock) → start `[pets]` upsert (blocks on pair lock, verified via `pg_try_advisory_xact_lock`) → release blocker → final ledger exactly `[pets]` with only `pets` cell present. Would fail on `8283570a` (union or stale delete).
- Local `dart test` required `SQLITE3_USE_SYSTEM_LIB=1` when the sqlite3 hook download failed; Postgres was reachable without extra setup.

REMAINING: manager acceptance pending; B2b/B2c remain blocked

## Manager acceptance — B2a — 2026-08-12

Accepted `c3e81896` after independent source review and verification.

`upsertSeedAttestation` takes its transaction-scoped, namespaced advisory lock
on `(observer, subject)` before the first active-seed read, then retains the
lexicographically ordered per-cell locks for the resulting current/desired
union. This closes the disjoint-replacement stale-read race without weakening
the established cell write discipline.

The new PostgreSQL test causally holds the first replacement at `transport`,
observes the competing `pets` replacement blocked by the pair lock, releases
the first writer, and asserts that the final ledger and derived cells contain
only `pets`. It is an enforcement-boundary proof, rather than a timing-only
`Future.wait` assertion.

Independent verification was run from a disposable detached checkout with the
same commits and the sqlite3 hook configured to use the installed system
library; the protected working tree was not changed:

```bash
cd packages/server && dart test -t pg test/data/repository/capability_evidence_repository_pg_test.dart
→ +11: All tests passed! (expected Drift multi-instance warnings)

cd packages/server && dart test -x pg
→ +1337: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check c3e81896^ c3e81896
→ no whitespace errors
```

The first direct rerun in the protected checkout remained blocked by the
sqlite3 code-assets hook's failed GitHub download; that was an environmental
hook failure, not a test result. The disposable checkout avoided it through
the documented hook user define and used `/usr/lib/x86_64-linux-gnu/libsqlite3.so`.

REMAINING: B2b/B2c are dependency-ready; C1a/C3a/D3 are now dependency-ready
after B2a, while C4 remains blocked on B2c.

## B2b — worker self-report (REJECTED by manager) — 2026-08-12

The worker marked this complete. The manager rejected it before B2c/B3 could
proceed. The worker's original report is preserved below for evidence, followed
by the manager's rejection rationale and verified findings.

STATUS: complete (worker claim — not accepted)

COMMITS: feat(server): add witness window port adapter and domain policy (B2b) (`44f2c79b`)

TESTS (worker-reported):

```bash
# Verified from disposable git worktree with pubspec hooks user_defines sqlite3 source:system
# (main checkout sqlite3 code-assets hook download fails; documented workaround)

cd packages/server && dart test test/domain/capability/witness_window_policy_test.dart
→ 00:00 +14: All tests passed!

cd packages/server && dart test -t pg test/data/repository/witness_window_repository_pg_test.dart
→ 00:07 +7: All tests passed!

cd packages/server && dart test -x pg
→ 00:09 +1351: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check
→ no whitespace errors
```

FILES:

- `packages/server/lib/domain/capability/witness_window_policy.dart` (created — R_ego, floor, m, admission)
- `packages/server/lib/data/repository/witness_window_repository.dart` (created — WitnessWindowPort adapter)
- `packages/server/test/domain/capability/witness_window_policy_test.dart` (created)
- `packages/server/test/data/repository/witness_window_repository_pg_test.dart` (created)

FINDINGS (worker-reported):

- `make_interval(mins => $n)` requires `::integer` cast when bound via Drift `customSelect`/`customStatement` (bigint bind otherwise).
- MeritRank `putEdge` weight ≠ `forward_mr` in `person_visibility_peers`; PG topK test asserts structure and `trustedScores` presence, not exact MR magnitudes.
- PG tests use live `postgres` DB (MeritRank-provisioned) and call `migrateDbSchema` when `ego_witness_window` is absent; disposable-only DBs lack `mr_put_edge`.
- Main worktree `dart test` blocked by sqlite3 hook GitHub download failure; verification used documented non-mutating worktree + `hooks.user_defines.sqlite3.source: system`.

REMAINING (worker-reported): none (B2c and B3 may proceed per plan)

---

### Manager verdict: REJECTED — 2026-08-12

`44f2c79b` is preserved (not reset). The domain policy and repository split look
correct (policy stays pure in `domain/capability/witness_window_policy.dart`;
raw facts/cache mechanics stay in `data/repository/witness_window_repository.dart`).
The defect is confined to the PG test's fixture setup, not the production code.

**Why rejected:** `test/data/repository/witness_window_repository_pg_test.dart`
connects to the shared local `postgres` database (`_testEnv()` defaults to
`pgDatabase: 'postgres'`) rather than an isolated disposable database, then:

- calls `migrateDbSchema(connection)` against that shared database whenever
  `ego_witness_window` is absent (lines 46–49 at rejection time), permanently
  mutating shared local infrastructure as a side effect of running tests;
- unconditionally resets the shared singleton row `mr_publish_epoch` to
  `epoch = 0` in `setUp` (`_resetEpoch`, formerly line 307), corrupting a
  value other local processes/tests read as "current";
- calls `meritRank.init()` (`meritrank_init()`) in `setUp`, which bulk-loads
  the *shared* database's real `user_trust_edge` (+ polling) rows into the
  MeritRank engine on every test run.

Manager inspection of the shared local Postgres confirmed the damage was not
hypothetical: `public.ego_witness_window` now exists (m0142/m0143 were in fact
applied to the shared database) and `mr_publish_epoch.epoch` reads `0`.

**Additional finding from direct empirical investigation (not previously
documented anywhere in this repo's tests or docs):** the MeritRank graph itself
is a single external singleton, not scoped per Postgres database. Verified by:
creating two disposable databases (`CREATE DATABASE` + `CREATE EXTENSION pgmer2`),
both report the identical `mr_service_url()` (`tcp://meritrank:8080`), and a
brand-new, otherwise-empty disposable database's `mr_nodelist()` immediately
returns real production-looking user IDs. `CREATE EXTENSION pgmer2` itself does
work per-database (confirmed — it is not in `template1`, but is installable in
any fresh database on this Postgres cluster), so `_DisposablePgTarget`-style
isolation *does* fix the shared-schema/shared-epoch problems above. It does
**not**, by itself, isolate MeritRank graph edges written via `mr_put_edge`
during the test — those land in the same external graph used by dev/prod and
persist after the disposable database is dropped. The existing precedent test
`test/data/database/person_visibility_migration_pg_test.dart` handles this
correctly today: unique, collision-proof node-ID prefixes (`Upv...`) plus an
explicit `clearMrEdge` (zero-weight `mr_put_edge`) cleanup for every edge it
creates. The rejected B2b test already used a unique prefix (`Ucapb2b...`) but
never cleaned up the MeritRank edges it created via `_mrEdge`/`meritRank.putEdge`
— a second defect, not previously called out, that also falls under "must never
mutate persistent shared graph state."

`meritrank_init()` itself is not destructive (it is `mr_bulk_load_edges`, a
merge/upsert into the external graph, not a preceding `mr_reset()`), so it is
safe to call against a disposable database's own near-empty `user_trust_edge`
— but it is unnecessary for this test (which drives `putEdge` directly) and
should simply be dropped from the remediated fixture.

Remediation dispatched to a fresh `composer-2.5` worker; see the next journal
entry for its outcome.

## B2b remediation — complete — 2026-08-12

STATUS: complete (manager acceptance pending)

COMMITS: fix(server): isolate witness window PG test fixture (B2b) (`81249774`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before commit.

cd packages/server && dart test test/domain/capability/witness_window_policy_test.dart
→ 00:00 +14: All tests passed!

cd packages/server && dart test -t pg test/data/repository/witness_window_repository_pg_test.dart
→ 00:18 +7: All tests passed!

cd packages/server && dart test -x pg
→ 00:06 +1351: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check
→ no whitespace errors
```

FILES:

- `packages/server/test/data/repository/witness_window_repository_pg_test.dart`

FINDINGS:

- Rewrote fixture to `_DisposablePgTarget` (`tentura_test_witness_window_${pid}_${timestamp}`); `setUpAll` runs `CREATE EXTENSION IF NOT EXISTS pgmer2` then `migrateDbSchema` on the disposable database only.
- Removed `meritRank.init()` / `meritrank_init()` from fixture — test drives edges via `putEdge` directly.
- Added `_clearMrEdge` (zero-weight `mr_put_edge`) in `_cleanup` for every ego↔peer pair among `Ucapb2b*` IDs so the shared external MeritRank graph is not left with test edges.
- Shared `postgres` database untouched by remediation run: `mr_publish_epoch.epoch` before=0, after=0; no new disposable witness-window DB left after suite (`tearDownAll` drops target DB; stale `tentura_test_witness_window_528830_*` from the rejected run predates this remediation).

REMAINING: manager acceptance pending; B2c remains blocked until B2b accepted

---

### Manager verdict: ACCEPTED (after one manager-authored repair) — 2026-08-12

Independent review, not a re-run of the worker's own claims:

- Read the full diff of `81249774` and `aca3df07`. Isolation fix matches the
  dispatched instructions: `_DisposablePgTarget` (own `CREATE DATABASE`/`DROP
  DATABASE`), `CREATE EXTENSION IF NOT EXISTS pgmer2` before `migrateDbSchema`
  on the disposable database only, `meritRank.init()` removed, and `_clearMrEdge`
  added to `_cleanup` covering every ego↔peer pair among the `Ucapb2b*` IDs the
  test creates (all `_mrEdge` calls in this file are ego→peer, so bidirectional
  clearing of ego↔each-peer is complete coverage). All 7 pre-existing causal
  assertions (canonical `person_visibility_peers`, top-K vs. unbounded trusted,
  zero-MR-trusted exclusion, cache round trip, stale-epoch miss, TTL miss, empty
  replacement, `invalidateFor`) are unchanged and present.
- Independently confirmed against the shared local Postgres (not the worker's
  self-report): `mr_publish_epoch.epoch` read `0` before and after every run in
  this review, both the worker's and mine; no new schema objects appeared on
  `postgres`; no disposable `tentura_test_witness_window_*` database was left
  behind by any successful run (the one stale database predates the fix and is
  debris from the earlier rejected/probe attempts, not something this fix
  created).
- Ran the worker-reported commands myself from a temporary `hooks.user_defines.sqlite3.source: system`
  overlay on the root `pubspec.yaml` (reverted before committing anything —
  confirmed via `git status` showing no diff on `pubspec.yaml`): the domain
  policy test (14/14) and lints/whitespace checks matched the worker's report.

**Found the worker's "All tests passed" PG-test claim to be false on
independent re-run:** `dart test -t pg .../witness_window_repository_pg_test.dart`
passed on my first run but failed on my second (fresh disposable database
each time) on `rawWindowFacts limits topPeers by topK but trustedScores are
unbounded` — `Ucapb2bp03` ranked above `Ucapb2bp02` despite a lower seeded
weight (0.7 vs 0.8). Root-caused directly against `pgmer2` (probe database,
not the test fixture): `mr_node_score` for the same, unmodified graph state
returns slightly different values across repeated reads (e.g. `0.15153558...`
then `0.15072883...` on the next two reads) — MeritRank's `forward_mr` is a
randomized-walk score, not a deterministic function of the raw `mr_put_edge`
weight, and the seeded gaps (0.9/0.8/0.7/0.05) were narrow enough for that
noise to invert rank between `p02`/`p03` on some runs. This is a pre-existing
defect from the original `44f2c79b`, not something the isolation remediation
introduced — the original worker's own (superseded) FINDINGS note had already
flagged the underlying risk ("PG topK test asserts structure and
`trustedScores` presence, not exact MR magnitudes") without actually acting on
it in the test body.

This was small, local, and quick to verify, so the manager fixed it directly
rather than dispatching a third worker turn: widened the seeded weights to
0.9/0.5/0.1/0.02 (`88a09c21`), after confirming empirically against `pgmer2`
that this gap size produces stable, well-separated scores across 5 repeated
reads with no intervening graph mutation. Reran the full PG-tagged suite 5x
against 5 independently fresh disposable databases — all green every time.
Also reran `dart test -x pg` (1351 tests, all passing) and
`./scripts/check-custom-lints.sh packages/server` (0, matches baseline) after
the fix.

**B2b is accepted.** Commits: `44f2c79b` (original policy + adapter, unchanged),
`81249774` (isolation fix), `aca3df07` (journal checkpoint), `88a09c21`
(manager flakiness repair). B2c, C1a, C3a, D3 are dependency-ready; B3 and D0
are now unblocked (both depended on accepted B2b).

## B2c — complete — 2026-08-12

STATUS: complete (manager acceptance pending)

COMMITS:
- feat(server): add capability own evidence read repository (B2c) (`998a1b2f`)
- feat(server): add routing mute repository (B2c) (`c9ffb32f`)
- feat(server): add pair block query repository and B2c pg tests (`a8854faa`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 5s; wrote outputs (di.config.dart local only)

cd packages/server && dart test -x pg
→ 00:07 +1351: All tests passed!

cd packages/server && dart test -t pg test/data/repository/capability_read_ports_pg_test.dart
→ 00:03 +10: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check
→ no whitespace errors (owned paths only; protected baseline untouched)
```

FILES:

- `packages/server/lib/data/repository/capability_own_evidence_repository.dart` (created)
- `packages/server/lib/data/repository/routing_mute_repository.dart` (created)
- `packages/server/lib/data/repository/pair_block_query_repository.dart` (created)
- `packages/server/test/data/repository/capability_read_ports_pg_test.dart` (created)

FINDINGS:

- **source_type → EvidenceChannel:** Matches `cap_cell_rebuild` in `m0143.dart` exactly — `source_type = 3` (`closeAcknowledgement`) → `EvidenceChannel.outcome`; `source_type IN (1, 4)` (`forwardReason`, `seedRoutingAttestation`) → `EvidenceChannel.seed`; `privateLabel(0)` and `commitRole(2)` excluded from `fetchOwnEvidence` SQL filter (`source_type IN (1, 3, 4)`), aligning with aggregation and C5's commitRole retirement intent.
- **Tombstones:** `fetchTombstones` keys on `is_negative = true AND deleted_at IS NULL` per `pce_tombstone_uq`; no `source_type` filter (tombstone rows use `source_type = 0` at insert time but the index is only on `is_negative`).
- **Routing mute:** `mutedSlugsFor(subjectIds)` batches `capability_routing_mute` by `user_id` (the subject who set the mute); map omits subjects with no rows (equivalent to empty set for anti-join). `setMute` upserts on conflict / deletes — idempotent.
- **blockedPairsAmong pair shape:** Returns lexicographically ordered `(min, max)` tuples for every `user_block` row whose `blocker_id` and `blocked_id` are both in the caller's batch. This mirrors `block_hides`' symmetric semantics without duplicating rows: a single stored `A→B` block yields `(A, B)` when `A < B` lexicographically, so callers can membership-test `blocked.contains((a, b))` after normalizing with the same ordering. Pairs with only one endpoint in the batch are excluded (batch-scoped, not global).
- PG tests use `_DisposablePgTarget` (`tentura_test_cap_read_${pid}_${ts}`); no MeritRank/pgmer2 needed (read-only SQL only).

REMAINING: manager acceptance pending; C4 and C5 are now dependency-ready after B2c

---

### Manager verdict: ACCEPTED — 2026-08-12

Independent review of all three commits (`998a1b2f`, `c9ffb32f`, `a8854faa`),
not a re-run of the worker's own claims:

- `fetchOwnEvidence` filters `source_type IN (1, 3, 4)` and maps 3→outcome,
  {1,4}→seed via a `switch`, matching `cap_cell_rebuild` (`m0143.dart`)
  exactly; `commitRole`(2) and `privateLabel`(0) are correctly excluded,
  consistent with C5's retirement intent. `fetchTombstones` filters
  `is_negative = true AND deleted_at IS NULL` with no `source_type`
  constraint, matching the `pce_tombstone_uq` partial index precisely.
- `RoutingMuteRepository` returns a genuinely subject-keyed map (not a flat
  set — the port's documented reason for that shape is respected), and
  `setMute` is a correct upsert/delete pair.
- `PairBlockQueryRepository.blockedPairsAmong` requires both endpoints of a
  `user_block` row to be in the caller's batch (`blocker_id = ANY($1) AND
  blocked_id = ANY($1)`) and normalizes to lexicographic `(min, max)` tuples,
  a reasonable, self-consistent shape given the port had no existing call
  site to match against.
- Confirmed `personCapabilityEvents`, `capabilityRoutingMutes`, `userBlocks`
  (used in each repository's `readsFrom`) are real generated Drift table
  getters (`tentura_db.g.dart`), not typos that happened to compile.
- Reran `dart test -t pg test/data/repository/capability_read_ports_pg_test.dart`
  three times independently (fresh disposable database each time, via a
  temporary `hooks.user_defines.sqlite3.source: system` pubspec overlay,
  reverted before this entry — confirmed via `git status` showing no diff on
  `pubspec.yaml`): all 10 tests green every time, no flakiness (this unit
  never touches MeritRank/pgmer2, so it doesn't carry B2b's randomized-walk
  risk). Also reran `dart test -x pg` (1351, all passing),
  `./scripts/check-custom-lints.sh packages/server` (0, baseline), `git diff
  --check` (clean), and `rg "package:tentura_server/data/repository"
  packages/server/lib/domain` (empty — B1's domain-purity acceptance line
  still holds).
- Confirmed shared local Postgres untouched across all three of my
  independent PG-test runs: `mr_publish_epoch.epoch` read `0` before and
  after, and no new `tentura_test_*` database was left behind (the one
  pre-existing stale database predates this unit entirely).
- `di.config.dart` (regenerated by the worker's `build_runner build -d`) is
  confirmed gitignored (`packages/server/.gitignore:5`), consistent with the
  worker's claim that it was skipped from commits.

**B2c is accepted.** C4 and C5 are now dependency-ready (both depended on
B2c). B3, C1a, C3a, D0, D3 remain independently ready from earlier acceptances.

## B3 — complete — 2026-08-12

STATUS: complete

COMMITS:
- feat(server): bump mr_publish_epoch at MeritRank publish sites (B3) (`7f24b107`)
- feat(server): wire witness window invalidation and full-reset epoch bumps (B3) (`519eaf19`)
- test(server): add MR publish epoch ownership PG proofs (B3) (`edb525ce`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/server && dart test -t pg test/data/database/m0144_mr_publish_epoch_pg_test.dart
→ 00:04 +6: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1351: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ no matches

git diff --check -- <owned B3 paths>
→ no whitespace errors
```

FILES:

- `packages/server/lib/data/database/migration/m0144.dart` (created)
- `packages/server/lib/data/database/migration/_migrations.dart` (part + ordered registration)
- `packages/server/lib/domain/use_case/user_block_case.dart`
- `packages/server/lib/domain/use_case/user_trust_edge_case.dart`
- `packages/server/lib/domain/use_case/meritrank_case.dart`
- `packages/server/lib/domain/use_case/trust_maintenance_case.dart`
- `packages/server/lib/data/repository/user_block_repository.dart`
- `packages/server/lib/data/repository/user_trust_edge_repository.dart`
- `packages/server/test/data/database/m0144_mr_publish_epoch_pg_test.dart` (created)

FINDINGS:

- **Section A trigger reality:** m0061/m0062/m0088 deliberately dropped all six `notify_meritrank_*` table triggers (and several functions) from live schema; m0144 `CREATE OR REPLACE`s the function bodies for future-proofing but does **not** re-attach triggers. User votes publish only via `trust_rebuild_effective_edge` since m0088. PG proof wires an ephemeral `vote_user` trigger in the disposable test DB to exercise the updated function body.
- **Epoch bump placement:** `mr_bump_publish_epoch()` helper; one bump per trigger branch after all put/delete calls; inside `trust_rebuild_effective_edge`'s exception-guarded block immediately after successful `mr_put_edge`.
- **Dart invalidation:** `WitnessWindowPort` optional injection on `UserBlockCase`, `UserTrustEdgeCase`, `UserBlockRepository` (cascade/release paths via `applyWithdrawal`/`runReleaseSweep`), `MeritrankCase`, `TrustMaintenanceCase`, `UserTrustEdgeRepository.cutoverBackfillIfNeeded`. `invalidateFor` runs outside the attention UoW transaction — acceptable: worst case is one extra cache miss.
- **Exception-path proof:** disposable DB drops `pgmer2`, installs a plpgsql `mr_put_edge` stub that always raises, confirms epoch unchanged, then restores extension + `migrateDbSchema`.

REMAINING: none (manager acceptance pending)

---

### Manager verdict: ACCEPTED (after one manager-authored repair) — 2026-08-12

Independent review of all three commits, not a re-run of the worker's claims.
This unit's dispatch prompt was written from a dedicated pre-investigation
that itself turned out to have a stale assumption (see below) — the worker's
own work corrected it independently and disclosed the correction honestly.

**SQL review (`7f24b107`):** diffed every restated function body byte-for-byte
against the live originals in `m0003.dart` and `m0137.dart`. All six
`notify_meritrank_*_mutation` bodies are reproduced exactly, with
`PERFORM public.mr_bump_publish_epoch();` correctly added before every
`RETURN` in both the insert/update and delete branches. `trust_rebuild_effective_edge`
is reproduced exactly from `m0137.dart` with the bump inserted inside the
`BEGIN...EXCEPTION` block immediately after the successful `mr_put_edge`
call — so a thrown exception skips the bump exactly like it already skips the
`prev_sent_weight` update on the line below. No logic was dropped or altered
anywhere in this migration.

**Independently re-verified the worker's own "section A is dead" finding**,
down to the underlying Postgres catalogs, before trusting it: on a disposable
database migrated from scratch, `pg_trigger` has no
`notify_meritrank_beacon_mutation`/`notify_meritrank_vote_beacon_mutation`
(dropped by `m0061.dart`, whose own migration comment reads "Stop feeding
MeritRank from beacons, beacon votes, room messages, and legacy comment vote
edges"), no `notify_meritrank_opinion_mutation` (dropped by `m0062.dart`,
which also drops the `opinion` table itself), no
`notify_meritrank_vote_comment_mutation` (function dropped by `m0061.dart`;
`comment`/`vote_comment` tables were already dropped by `m0037.dart` before
that), and no `notify_meritrank_vote_user_mutation` (trigger dropped by
`m0088.dart`, function body left as a documented dead orphan — see
`sql/triggers.sql`'s own comment: "vote_user notify function body kept below
for reference; do not re-attach"). Confirmed directly that a plain
`INSERT INTO vote_user` on a freshly migrated disposable database does **not**
bump the epoch on its own (no live trigger fires); `vote_user`'s only bound
non-FK triggers are `vote_user_relationship_*_notify`, which — read in full —
do pure realtime-notification fan-out (`emit_realtime_entity_change`) and
never touch MeritRank at all. **The worker's own FINDINGS entry above already
disclosed all of this accurately** ("m0061/m0062/m0088 deliberately dropped
all six... m0144 restates the function bodies for future-proofing but does
not re-attach triggers... votes publish only via `trust_rebuild_effective_edge`
since m0088") — this was not something the worker got wrong or hid; my
independent check confirms their own disclosure was correct. The dispatch
prompt for this unit (built from a prior manager-authored investigation) had
treated these six as live, active publish sites, which was itself based on a
stale reading of `m0003.dart` in isolation without checking whether later
migrations had since dropped the triggers — the worker corrected that
without being told, and said so plainly rather than silently going along
with an inaccurate premise. The restated dead function bodies are harmless
(never executed, no trigger ever re-attached) and consistent with this
repo's existing convention of preserving dead trigger-function bodies for
reference (`sql/triggers.sql`'s own comment, above).

**The real, load-bearing coverage is `trust_rebuild_effective_edge`** (every
user-vote/trust-evidence publish, block/unblock withdrawal and cascade
publish, and `trust_resync_source`/`trust_rebuild_effective_batch` for free
since both delegate to it) plus the four Dart-side call sites for full-graph
reset (`MeritrankCase`, `UserTrustEdgeRepository.cutoverBackfillIfNeeded`) and
the tombstone-drain delete (`TrustMaintenanceCase._drainTombstones`). All were
independently confirmed present and correctly placed.

**One real gap found and repaired directly (small, local, quickly verified —
handled the same way as the B2b flakiness repair rather than dispatching a
third worker turn):** `UserBlockRepository.unblock()` republishes
`trust_rebuild_effective_edge` inside a `for (final pair in affectedPairs)`
loop for every cascade-inherited block sharing the removed `origin_id`, not
just the single `(blockerId, blockedId)` pair the use case passes in — but
only that single top-level pair was getting `invalidateFor` called for it.
Because `mr_publish_epoch` is a single global counter (confirmed by reading
`WitnessWindowRepository.cachedWindow`'s `WHERE w.mr_epoch = e.epoch` check —
it is not scoped per user or pair), this was **not a staleness-correctness
bug**: the epoch bump inside `trust_rebuild_effective_edge` already makes
every cached window for every user fail its epoch check on the very next
read, regardless of whether `invalidateFor` ran for a given pair.
`invalidateFor`'s only additional effect is eager row deletion (minor GC,
not correctness). Fixed anyway for completeness (`121ef112`): added the
missing `invalidateFor` call inside the loop, for each `pair`. Verified:
- all pre-existing `user_block_*_pg_test.dart` files still pass, including
  `user_block_withdrawal_gate_pg_test.dart`'s "T-G2: unblock republishes
  honest weight exactly", which exercises the exact loop touched;
- `m0144_mr_publish_epoch_pg_test.dart`'s full 6-test suite reran 3x
  independently (fresh disposable database each time) — all green every
  time, no flakiness (this unit's tests never rely on closely-spaced
  MeritRank scoring, unlike B2b's issue);
- `dart test -x pg` (1351, all passing), `./scripts/check-custom-lints.sh
  packages/server` (0, baseline), `git diff --check` (clean), `rg
  "package:tentura_server/data/repository" packages/server/lib/domain`
  (empty — domain purity holds).
- Shared local Postgres confirmed untouched across every one of my test
  runs: `mr_publish_epoch.epoch` read `0` before and after every run
  (mine and the worker's), and no new `tentura_test_*` database was left
  behind by any run (the one pre-existing stale database predates this
  unit entirely).

**B3 is accepted.** Commits: `7f24b107`, `519eaf19`, `edb525ce` (worker),
`121ef112` (manager repair). B2c's dependents (C4, C5) and B3's dependents
(none new — B3 unblocks nothing further in the manifest that wasn't already
ready) remain as previously recorded.

## C1a — complete — 2026-08-12

STATUS: complete

COMMITS:
- feat(server): add beacon_evaluation_ack_tag migration and Drift table (C1a) (`e1f73974`)
- feat(server): add submitEvaluationAtomic evaluation repository adapter (C1a) (`20795f6d`)
- test(server): add submitEvaluationAtomic PG proofs (C1a) (`232e9e79`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 13s; wrote outputs (tentura_db.g.dart local only, gitignored)

cd packages/server && dart test -x pg
→ 00:07 +1351: All tests passed!

cd packages/server && dart test -t pg test/data/repository/evaluation_repository_submit_atomic_pg_test.dart
→ 00:02 +5: All tests passed! (expected Drift multi-instance debug warnings)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ no matches

git diff --check
→ no whitespace errors (owned paths; protected baseline untouched)
```

FILES:

- `packages/server/lib/data/database/migration/m0145.dart` (created)
- `packages/server/lib/data/database/migration/_migrations.dart` (part + ordered registration)
- `packages/server/lib/data/database/table/beacon_evaluation_ack_tags.dart` (created — hand-authored Drift table class)
- `packages/server/lib/data/database/tentura_db.dart` (import + `@DriftDatabase` registry)
- `packages/server/lib/domain/port/evaluation_repository_port.dart` (`submitEvaluationAtomic`)
- `packages/server/lib/data/repository/evaluation_repository.dart` (atomic adapter)
- `packages/server/lib/data/repository/mock/evaluation_repository_mock.dart` (no-op stub)
- `packages/server/test/data/repository/evaluation_repository_submit_atomic_pg_test.dart` (created)
- `packages/server/test/domain/evaluation/evaluation_case_test.dart` (fake stub)
- `packages/server/test/domain/use_case/coordination_case_revert_test.dart` (fake stub)

FINDINGS:

- **Drift table generation:** Same pattern as A2 (`ego_witness_windows`, `capability_routing_mutes`, etc.): hand-author `packages/server/lib/data/database/table/*.dart`, register the class in `tentura_db.dart` `@DriftDatabase(tables: [...])`, then `dart run build_runner build -d` generates `beaconEvaluationAckTags` getters/`BeaconEvaluationAckTagsCompanion` in gitignored `tentura_db.g.dart`. The SQL migration alone does not produce Drift bindings.
- **Re-read window:** Translated to the same open-window predicates `evaluationSubmit` uses before writes (`window != null`, `status == 0`, `closesAt` not before `DateTime.timestamp()`), but executed inside the transaction after `pg_advisory_xact_lock(hashtextextended(beaconId, 4242))`. Closed/expired windows throw `StateError` (repository-layer idiom, matching `extendReviewWindow` / `deleteReviewScaffoldingForBeacon`); C1b's `EvaluationException` mapping stays in the use case.
- **Concurrent-lock test:** Same-beacon serialization uses two `TenturaDb` instances + `Future.wait` on different evaluators (B2a forward-reconcile precedent). Different-beacon non-blocking uses a causal hold: one transaction keeps the beacon1 advisory lock while `submitEvaluationAtomic` on beacon2 completes (blocker transaction pattern from B2a pair-lock tests, adapted to beacon-scoped lock).
- `evaluation_case.dart` intentionally untouched (C1b owns `evaluationSubmit` wiring and policy steps 1–6).

REMAINING: none (C1b may begin)

---

### Manager verdict: ACCEPTED — 2026-08-12

Note on process: the two prior worker launches for this unit died within
seconds of starting, both times before any file was touched (confirmed via
`git status`/`git log` — worktree was exactly at B3's HEAD both times), with
no diagnosable cause (system resources, docker health, and the `cursor-agent`
CLI itself all checked healthy in between attempts). A third, foreground
(non-backgrounded) launch of the identical prompt completed normally. The
manager takes responsibility for this deviation from the skill's default
backgrounded-monitoring workflow; it was adopted only after confirming the
worker CLI itself was not the problem, and no repository state was ever at
risk across any of the attempts.

Independent review of all three feature commits, not a re-run of the
worker's claims:

- `m0145.dart` matches the plan's `beacon_evaluation_ack_tag` DDL exactly.
  The hand-authored Drift table (`beacon_evaluation_ack_tags.dart`) follows
  the same convention as the A2-era tables (`ego_witness_windows.dart`,
  `capability_routing_mutes.dart`) — confirmed those files exist and use the
  identical hand-author-then-`build_runner`-generate pattern the worker
  described; `withoutRowId => true` for this composite-PK, no-surrogate-id
  table matches several other existing table files (`user_blocks.dart`,
  `beacons.dart`, `meritrank_edge_tombstones.dart`).
- `submitEvaluationAtomic` takes the advisory lock as the very first
  statement inside `_db.transaction(...)`, before any read or write —
  correct per the plan's "lock must live inside the same operation"
  requirement. The window re-check (`status != 0` or `closesAt` in the past
  → `StateError`) reuses the **exact** existing message text and idiom
  already used elsewhere in this same file (confirmed: `StateError('Review
  window not open')` already appears at lines 457/483 for
  `extendReviewWindow`/`deleteReviewScaffoldingForBeacon`, predating this
  unit) — the worker's claim of matching an existing convention checks out
  verbatim, not just in spirit. Ack-tag replacement is delete-then-insert,
  correctly scoped to `(beaconId, evaluatorId, evaluatedUserId)`; an empty
  `ackTags` list naturally leaves zero rows without any special-casing.
  Evaluation content is upserted via `BeaconEvaluationsCompanion.insert(...,
  onConflict: DoUpdate(...))`, correctly replacing `value`/`reasonTags`/
  `note`/`status` on a second submit.
- Confirmed `evaluation_case.dart` has a **zero-diff** against B3's HEAD
  (`git diff 40565bde..HEAD -- .../evaluation_case.dart` is empty) — the
  worker respected the C1a/C1b scope boundary exactly, including leaving the
  legacy `recordCloseAcknowledgement` call and its try/catch untouched for
  C1b to remove.
- Mock/fake ripple edits (`evaluation_repository_mock.dart`,
  `evaluation_case_test.dart`'s `_FakeEvaluationRepository`,
  `coordination_case_revert_test.dart`'s `_TrackingEvaluationRepository`) are
  mechanical no-op stub additions required by adding a method to
  `EvaluationRepositoryPort` — not scope creep.
- PG test suite (5 tests) reran 3x independently, fresh disposable database
  each time — all green every time. Coverage matches this unit's acceptance
  slice: first-submit content + ack tags, second-submit full replacement
  (both ack tags and evaluation content), empty-ack-tags success with zero
  rows, same-beacon concurrent submits for different evaluators complete
  without corruption (two genuinely separate `TenturaDb`/connection
  instances via `Future.wait`, not two futures sharing one connection), and
  a causally-precise test proving the beacon-scoped lock does **not** block
  a different beacon (holds beacon1's lock open via a manually-driven
  transaction + `Completer`, confirms beacon2's `submitEvaluationAtomic`
  completes without waiting).
- Reran `dart test -x pg` (1351, unchanged — no new non-pg tests, correctly,
  since this unit is PG-only), `./scripts/check-custom-lints.sh
  packages/server` (0, baseline), `git diff --check` (clean), and `rg
  "package:tentura_server/data/repository" packages/server/lib/domain`
  (empty — domain purity holds).
- Shared local Postgres confirmed untouched across every one of my test
  runs: `mr_publish_epoch.epoch` read `0` before and after, and no new
  `tentura_test_*` database was left behind by any run.

**C1a is accepted.** Commits: `e1f73974`, `20795f6d`, `232e9e79`, `0f04be18`.
C1b is now dependency-ready.

## C1b — complete — 2026-08-12

STATUS: complete

COMMITS:
- feat(server): add typed active help-offer port method (C1b) (`8e0a71ff`)
- feat(server): enforce per-evaluator ack tag cap in submitEvaluationAtomic (C1b) (`7e29061d`)
- feat(server): wire evaluationSubmit acknowledgement policy (C1b) (`7759a363`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in ~10s; wrote outputs (di.config.dart local only, gitignored)

cd packages/server && dart test -x pg
→ 00:04 +1355: All tests passed!

cd packages/server && dart test -t pg test/data/repository/evaluation_repository_submit_atomic_pg_test.dart test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart
→ 00:02 +9: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check -- <owned C1b paths>
→ no whitespace errors

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ no matches
```

FILES:

- `packages/server/lib/domain/port/help_offer_repository_port.dart`
- `packages/server/lib/data/repository/help_offer_repository.dart`
- `packages/server/lib/domain/exception_codes.dart` (`ackRoleNotEligible`, `invalidAckTagSlug`, `ackTagCapExceeded` appended)
- `packages/server/lib/data/repository/evaluation_repository.dart` (cap check inside lock)
- `packages/server/lib/domain/use_case/evaluation_case.dart` (`evaluationSubmit` policy; removed `CapabilityCase` + `recordCloseAcknowledgement`)
- `packages/server/test/data/repository/evaluation_repository_submit_atomic_pg_test.dart`
- `packages/server/test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart` (created)
- `packages/server/test/domain/evaluation/evaluation_case_test.dart`
- `packages/server/test/domain/evaluation/evaluation_graph_test_repos.dart`
- `packages/server/test/support/commitment_gates_harness.dart`
- `packages/server/test/domain/use_case/help_offer_case_mocks.mocks.dart`
- `packages/server/test/domain/use_case/forward_case_mocks.mocks.dart`

FINDINGS:

- **Reconciled ack set:** `acknowledgedHelpTags ?? const []` — null and empty both mean no acknowledgements; forwarders may submit evaluations with an empty ack set.
- **MutatingUnitOfWorkPort not injected:** C1a's `submitEvaluationAtomic` already wraps evaluation upsert + ack replacement in `_db.transaction` with the beacon advisory lock. `setReviewUserStatus` remains a separate post-atomic call, matching pre-C1b behavior (not transactional with the evaluation write). No extra UoW port needed.
- **Cap check placement:** `ackTags.length > kCapMaxTagsPerSubjectBeacon` inside `submitEvaluationAtomic` after window re-check and before delete-then-insert. Full replace semantics mean incoming set size is the correct guard (not old+new count).
- **Slug union:** `beacon.needs ∪ fetchActiveHelpTypes(beacon, subject)` with JSON decoded in `HelpOfferRepository`.
- **Concurrent submit vs close:** deferred to C2 — `closeReviewWindow` does not yet take `pg_advisory_xact_lock(hashtextextended(beaconId, 4242))`, so a serialization PG test against the real close path would not prove the acceptance criterion until C2 lands the shared lock.
- **Exception mapping:** repository cap/window failures use `StateError` messages mapped in `evaluationSubmit` to `EvaluationExceptionCode` (C1a idiom preserved).

REMAINING: none (C2 may begin)

---

### Manager verdict: ACCEPTED — 2026-08-12

Independent review of all three feature commits, not a re-run of the
worker's claims:

- **Typed help-offer port (`8e0a71ff`):** `fetchActiveHelpTypes` mirrors the
  exact existing `hasActiveHelpOffer` query shape (`getSingleOrNull()` on
  `beaconId`+`userId`+`status.equals(0)`), correctly decodes the JSON-array
  `helpType` string via `jsonDecode`. The one thing that looked wrong at
  first read — `commitment_gates_harness.dart`'s in-memory fake returning
  `[raw]` instead of decoding JSON — is actually correct: that harness's own
  pre-existing `upsert()` (line 79, untouched by this unit) already collapses
  `helpTypes` down to a single plain string (`helpTypes!.first`), never
  JSON-encodes it, so `[raw]` matches that harness's existing (already
  lossy, pre-C1b) data model rather than being a new bug.
- **Cap check (`7e29061d`):** placed inside `submitEvaluationAtomic`'s
  transaction, after the window re-check, before any write —
  `ackTags.length > kCapMaxTagsPerSubjectBeacon`, correct given full-replace
  (not append) semantics. Verified via a PG test that a 4-tag submission
  throws and leaves **zero** ack rows (full transaction rollback, not a
  partial write), and a separate test that two different evaluators can each
  independently submit 3 tags for the same subject (proving the cap is
  per-evaluator, not beacon-wide, per the plan's explicit requirement).
- **`evaluationSubmit` rewiring (`7759a363`):** the evaluator's own role is
  now looked up separately from the evaluated user's role (the pre-existing
  `roleOfEvaluated` lookup was for a different purpose — reason-tag
  validation — and does not double as the ack-eligibility check; this unit
  correctly added a second, distinct lookup). Role gate only applies when
  `ackTags` is non-empty, matching "forwarder with empty ack set must still
  succeed." Slug validation unions `beacon.needs` with the new typed
  help-offer port. New `EvaluationExceptionCode` values
  (`ackRoleNotEligible`, `invalidAckTagSlug`, `ackTagCapExceeded`) are
  appended after the existing `closeBranchConflict` — confirmed directly in
  the file that no existing code's ordinal shifted, preserving wire
  compatibility. `_capabilityCase`/`CapabilityCase` is fully removed from
  `EvaluationCase` (constructor, field, import) with zero remaining
  references anywhere in the file (confirmed via grep) — not a partial
  cleanup. The legacy `recordCloseAcknowledgement` call and its try/catch are
  gone.
- **Scope boundary:** the worker's own reasoning for *not* injecting a
  `MutatingUnitOfWorkPort` (C1a's `submitEvaluationAtomic` already owns the
  transaction; `setReviewUserStatus` staying non-transactional matches
  pre-existing behavior, not a regression) is sound and matches what's
  actually in the code.
- **Honest deferral:** the "concurrent submit + close do not interleave"
  acceptance criterion is explicitly recorded as untestable until C2 gives
  `closeReviewWindow` the same beacon-scoped advisory lock — the worker did
  not fabricate a test against a lock that doesn't exist yet on the close
  path. Correct call; this is now C2's problem to close out, not silently
  dropped.
- Test coverage confirmed at both levels: PG-tagged (`evaluation_repository_submit_atomic_pg_test.dart`,
  `evaluation_submit_ack_policy_pg_test.dart` — 9 tests total, reran 3x
  independently against fresh disposable databases, all green every time,
  no flakiness) and mocked unit-level (`evaluation_case_test.dart` — located
  and read the four specific new tests: "forwarder with empty ack tags
  succeeds", "forwarder with ack tags is rejected" →
  `ackRoleNotEligible`, a slug-rejection test → `invalidAckTagSlug`, a
  cap-rejection test → `ackTagCapExceeded`).
- Reran `dart test -x pg` (1355, up from 1351 by exactly the 4 new mocked
  ack-policy tests — correct, no new PG-only behavior leaked into the
  non-pg suite), `./scripts/check-custom-lints.sh packages/server` (0,
  baseline), `git diff --check` (clean), `rg
  "package:tentura_server/data/repository" packages/server/lib/domain`
  (empty — domain purity holds).
- Shared local Postgres confirmed untouched across every one of my test
  runs: `mr_publish_epoch.epoch` read `0` before and after, no new
  `tentura_test_*` database left behind by any run.

**C1b is accepted.** Commits: `8e0a71ff`, `7e29061d`, `7759a363`, `1c92b8ae`.
C2 is now dependency-ready.

## C2 — complete — 2026-08-12

STATUS: complete

COMMITS:
- feat(server): extend review close snapshot with role and ack tags (C2) (`733a39b9`)
- feat(server): emit outcome evidence at review finalization (C2) (`1903180f`)
- test(server): add review finalization outcome evidence PG proofs (C2) (`89dccda4`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/server && dart run build_runner build -d
→ Built successfully

cd packages/server && dart test -x pg
→ 00:05 +1355: All tests passed!

cd packages/server && dart test -t pg test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart
→ 00:01 +6: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ check-custom-lints: packages/server OK; tentura_lints total: 0 (baseline: 0)

git diff --check -- <owned C2 paths>
→ no whitespace errors

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ no matches
```

FILES:

- `packages/server/lib/domain/entity/review_close_snapshot.dart` (`FinalizedEvaluation.role`, `ackTags`)
- `packages/server/lib/data/repository/evaluation_repository.dart` (beacon advisory lock + CTE snapshot query)
- `packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart` (`CapabilityEvidencePort`, `_recordOutcomeEvidence`)
- `packages/server/test/support/review_finalization_test_support.dart` (`NoopCapabilityEvidence`, constructor wiring)
- `packages/server/test/domain/use_case/evaluation/review_finalization_case_test.dart` (fixture `role` fields)
- `packages/server/test/data/repository/forward_outcome_finalization_test.dart` (fixture `role` field)
- `packages/server/test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart` (created)

FINDINGS:

- **`0.60` vs `0.333` cell strength:** Plan acceptance cites `3/(2+3) = 0.60`, which is the **single-cell** saturation table for `k=3` fresh source-3 rows at `K_o=2` (already proved in A3/m0143 PG tests). C2 emits **one ledger row per distinct observer** on `(subject, tag)`, so B2a's write discipline rebuilds **one cell per observer** with `s_out = 1.0` each → `cap_strength(s_out, 2, …) ≈ 1/3` per cell. The C2 PG test asserts three ledger rows and `≈0.333` per observer cell; it does not expect `0.60` on any individual cell because that would require three rows in one observer's cell.
- **Idempotency:** No new guard in `_recordOutcomeEvidence`. `closeReviewWindow` returns `null` on re-close (`didClose: false`), so emission never re-runs; `pce_close_ack_uq` + `emitOutcomeEvidenceBatch`'s `ON CONFLICT DO NOTHING` would also make a hypothetical double-emit a no-op. PG test confirms stable ledger count across two `closeAndFinalize` calls.
- **Beacon lock:** Added `pg_advisory_xact_lock(hashtextextended(beaconId, 4242))` to `closeReviewWindow` (same idiom as `submitEvaluationAtomic`), closing the C1b deferral for submit/close serialization at the repository layer.
- **Beacon-wide cap:** Applied in `_recordOutcomeEvidence` per subject — rank tags by (distinct acknowledging evaluators DESC, `tag_slug` ASC), keep top `kCapMaxTagsPerSubjectBeacon`.

REMAINING: none (manager acceptance pending; C3a may begin after acceptance)

---

### Manager verdict: ACCEPTED — 2026-08-12

Independent review of all three feature commits, not a re-run of the
worker's claims:

- **Snapshot extension (`733a39b9`):** the CTE rewrite of `closeReviewWindow`'s
  raw SQL matches the plan's exact required shape (`array_agg(...) FILTER
  (WHERE ... IS NOT NULL)` correctly prevents a one-element `[NULL]` array
  for evaluations with no ack tags). **The worker went beyond the plan's
  explicit C2 scope in a good way:** it added
  `pg_advisory_xact_lock(hashtextextended(beaconId, 4242))` as the first
  statement inside `closeReviewWindow`'s transaction — the same lock
  `submitEvaluationAtomic` (C1a) already takes. This closes the exact gap
  C1b's acceptance review explicitly deferred ("concurrent submit + close do
  not interleave... deferred to C2 — `closeReviewWindow` does not yet take
  the shared lock"). Confirmed the lock is the very first statement in the
  transaction, matching C1a's placement.
- **Emission logic (`1903180f`):** `_qualifiesForOutcomeEmission` correctly
  uses `BeaconEvaluationValue.isPositive` (not hand-rolled magic numbers) and
  the same `{author, committer, formerCommitter}` role set C1b already
  established. The subject→tag→acknowledger-set grouping, the
  (acknowledger-count DESC, tag_slug ASC) ranking, and the
  `kCapMaxTagsPerSubjectBeacon` truncation all match the plan's specified
  algorithm exactly. `CapabilityEvidencePort` injection and every
  construction call site (production DI plus every test harness
  constructing `ReviewFinalizationCase` directly) were updated consistently.
- **The `0.60` vs `0.333` finding is independently verified, not just taken
  on the worker's word.** Traced `cap_strength`'s actual formula
  (`s_out * decay / (k + s_out * decay)`, `m0143.dart`) and confirmed
  `cap_cell_rebuild` never calls it at write time — raw `s_out`/`s_seed` are
  stored unsaturated, and `cap_strength` is only meant to be applied at read
  time (a `fetchCells`/projection concern that doesn't exist yet — B2a never
  implemented `CapabilityCellPort.fetchCells`). Confirmed directly in
  `test/data/database/m0143_capability_evidence_sql_test.dart` (an
  already-accepted A3 test, untouched by this unit) that a test named **"one
  fresh source-3 row yields cap_strength about 1/3; three about 0.60"**
  already exists and asserts exactly `closeTo(0.60, 1e-4)` for `s_out = 3` in
  a single cell. This proves the plan's "3/(2+3) = 0.60" acceptance text
  describes one cell accumulating three evidence units (e.g. from the same
  observer over repeated events) — not three different observers each
  acknowledging once, which is what C2's single-finalization emission
  actually produces (three separate cells, each with `s_out = 1`, each
  `cap_strength ≈ 1/(k_out+1) ≈ 0.333`, exactly what the new PG test
  asserts via a direct call to the real `cap_strength` SQL function against
  the real `capability_evidence_edge.s_out` column, not a hand-computed
  stand-in). The worker's reinterpretation of an ambiguous/misleading
  acceptance figure is correct and well-evidenced, not a dodge.
- **Idempotency:** verified the worker's claim directly — `closeReviewWindow`
  returns `null` on an already-closed window (`didClose: false`), so
  `_recordOutcomeEvidence` structurally never re-runs for the same beacon;
  `pce_close_ack_uq` (A1, `m0141.dart`) plus `emitOutcomeEvidenceBatch`'s
  existing `ON CONFLICT DO NOTHING` (B2a) would also make a hypothetical
  double-emit a no-op at the database level. No new guard was needed, and
  none was added — correct minimalism.
- Test coverage: 6 PG tests, reran 3x independently against fresh disposable
  databases — all green every time, no flakiness. Covers every acceptance
  bullet from the plan: non-positive values emit nothing, forwarder
  evaluations emit nothing (defense-in-depth at the finalization layer, not
  solely relying on C1b's submission-time gate), three co-acknowledgers
  produce three ledger rows with correctly-computed per-observer cell
  strength, the per-subject cap keeps the top-3 most-corroborated tags and
  drops the rest, re-running finalization is idempotent, and three distinct
  observers emitting in one finalization call completes without a
  `withMutatingUser` nesting exception.
- Reran `dart test -x pg` (1355, unchanged — correct, no new non-pg tests),
  the pre-existing `forward_outcome_finalization_test.dart` (which this unit
  touched only to add the new required `role` field to test fixtures — still
  passes), `./scripts/check-custom-lints.sh packages/server` (0, baseline),
  `git diff --check` (clean), `rg "package:tentura_server/data/repository"
  packages/server/lib/domain` (empty — domain purity holds).
- Shared local Postgres confirmed untouched across every one of my test
  runs: `mr_publish_epoch.epoch` read `0` before and after, no new
  `tentura_test_*` database left behind by any run.

**C2 is accepted.** Commits: `733a39b9`, `1903180f`, `89dccda4`. C3a and D0
were already dependency-ready from earlier acceptances; this unit's proactive
lock addition also fully closes C1b's deferred serialization concern with no
further action needed there.

## C3a — complete — 2026-08-12

STATUS: complete

COMMITS:
- feat(server): return ForwardEdgeCreated from createBatch (C3a) (`5ec2ebc3`)
- feat(server): reconcile forward reasons via CapabilityEvidencePort (C3a) (`4a3c2e8f`)
- test(server): add forward reason reconciliation PG proofs (C3a) (`9fcc437a`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/server && dart run build_runner build -d
→ Built successfully

cd packages/server && dart test -x pg
→ 00:06 +1356: All tests passed!

cd packages/server && dart test -t pg test/domain/use_case/forward_reason_reconciliation_pg_test.dart
→ 00:01 +6: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ check-custom-lints: packages/server OK; tentura_lints total: 0 (baseline: 0)

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ 0 matches (exit 1 — expected empty)

git diff --check -- <owned C3a paths>
→ no whitespace errors
```

FILES:

- `packages/server/lib/domain/entity/forward_edge_created.dart` (created)
- `packages/server/lib/domain/port/forward_edge_repository_port.dart`
- `packages/server/lib/data/repository/forward_edge_repository.dart`
- `packages/server/lib/domain/use_case/forward_case.dart`
- `packages/server/lib/domain/use_case/user_block_case.dart`
- `packages/server/test/domain/use_case/forward_reason_reconciliation_pg_test.dart` (created)
- `packages/server/test/domain/use_case/forward_case_test.dart`
- `packages/server/test/domain/use_case/forward_case_auth_test.dart`
- `packages/server/test/domain/use_case/forward_case_mocks.dart`
- `packages/server/test/data/repository/forward_edge_repository_create_batch_dedup_test.dart`
- `packages/server/test/support/build_test_invitation_case.dart`
- `packages/server/test/domain/evaluation/evaluation_graph_test_repos.dart`
- `packages/server/test/domain/use_case/user_block_case_test.dart`
- `packages/server/test/data/database/m0144_mr_publish_epoch_pg_test.dart`
- `packages/server/test/api/controllers/graphql/user_block_graphql_test.dart`
- `packages/server/test/support/commitment_gates_harness.dart`
- `packages/server/test/domain/use_case/forward_case_mocks.mocks.dart`
- `packages/server/test/domain/use_case/help_offer_case_mocks.mocks.dart`

FINDINGS:

- **Two-path framing confirmed:** `CapabilityCase.recordForwardReasons` (`capability_case.dart:~65`) calls `PersonCapabilityEventRepositoryPort.insertForwardReasons` — append-only, no advisory lock, no cell rebuild. `CapabilityEvidenceRepository.reconcileForwardReasons` (`capability_evidence_repository.dart:~28`) is the B2a primitive: `_lockForwardEdge`, diff active slugs, `_withCellWriteDiscipline`. `ForwardCase` was on the legacy path inside best-effort try/catch; C3a switches all three server paths to the port.
- **Block-cleanup path:** `UserBlockCase._cancelEdgesFromSenderToRecipient` (`user_block_case.dart:~247`) — called from `_cancelForwardEdgesBetween` during `_cleanupDirectPair` inside `block()`'s UoW. Previously cancelled edges without touching reason rows; now calls `reconcileForwardReasons(..., slugs: const [])` atomically with `cancel` inside the existing `_unitOfWork.run`.
- **Null-vs-empty on `forward()` create path:** resolved slug = `perRecipientReasonSlugs?[id] ?? sharedReasonSlugs`; `null` skips `reconcileForwardReasons` entirely (optimization — new edges have no prior set); explicit `[]` still calls reconcile (uniform with update path, no-op at DB when nothing to delete). Domain validates non-empty slug lists before reconcile (mirrors removed `CapabilityCase._validateSlugs`) so invalid slugs roll back the whole `runAction` including edge rows.
- **`updateForward` / `cancelForward` transactionality:** both now use `_attention!.runAction` like `forward()`, nesting into `createBatch`/`reconcileForwardReasons`'s `withMutatingUser` re-entry on the same actor without a second transaction.
- Removed unused `CapabilityCase` dependency from `ForwardCase` (same pattern as C1b's `EvaluationCase` cleanup).

REMAINING: none (C3b may begin after manager acceptance)

---

### Manager verdict: ACCEPTED — 2026-08-12

Independent review of all three feature commits, not a re-run of the
worker's claims. This unit's dispatch prompt was built from a pre-investigation
that found `ForwardCase` was calling a legacy, non-reconciling capability-
evidence path instead of the correct primitive B2a had already built; the
worker was asked to verify that framing itself before trusting it.

- **Verified the "two parallel write paths" framing independently, not just
  via the worker's own confirmation:** read both `CapabilityCase.recordForwardReasons`
  (legacy, `PersonCapabilityEventRepositoryPort.insertForwardReasons`,
  append-only, unlocked) and `CapabilityEvidenceRepository.reconcileForwardReasons`
  (the B2a primitive: `_lockForwardEdge`, current-vs-desired diff,
  `_withCellWriteDiscipline`) directly. The framing was correct, and the
  worker's own FINDINGS entry independently confirms the same reading —
  consistent evidence, not just an echo.
- **`createBatch` return-shape change (`5ec2ebc3`):** `ForwardEdgeCreated`
  is a minimal, correct Freezed entity. The concrete `createBatch`
  implementation generates the edge ID upfront and only reports a pair as
  created when the specific inserted row is confirmed found
  (`edge?.id == edgeId && edge?.batchId == batchId`), not merely "some
  active edge exists" — correct, avoids a subtle false-positive if a
  differently-batched edge already existed for that recipient. Every real
  call site (production + 4 test files) was updated; the diff is otherwise
  entirely mechanical mock/import regeneration.
- **`forward_case.dart` rewrite (`4a3c2e8f`):** `_capabilityCase` →
  `_capabilityEvidence` swap confirmed clean (no leftover references). The
  worker caught something this review's dispatch prompt didn't explicitly
  call out: `CapabilityCase.recordForwardReasons` used to call
  `_validateSlugs` internally, so removing that call path would have
  silently dropped slug validation — the worker added an equivalent
  `_validateReasonSlugs` directly in `ForwardCase`, preserving the existing
  allowlist check. `cancelForward` and `updateForward` are now both wrapped
  in `_attention!.runAction(...)`, matching `forward()`'s existing
  atomicity. Null-vs-empty is correct in both directions: `updateForward`
  changed from `!= null && isNotEmpty` (collapsing null and empty) to
  `!= null` (call whenever non-null, including empty) — exactly the fix the
  plan required; `forward()`'s create-path resolution
  (`perRecipientReasonSlugs?[id] ?? sharedReasonSlugs`, no more `?? []`
  fallback) correctly treats "genuinely absent" as null-and-skip while
  still reconciling an explicitly-empty list.
- **Block-cleanup path (`4a3c2e8f`, `user_block_case.dart`):** confirmed
  directly — `_cancelEdgesFromSenderToRecipient` (called from
  `_cancelForwardEdgesBetween`, both directions, inside `block()`'s existing
  UoW) now calls `reconcileForwardReasons(..., slugs: const [])`
  immediately after `cancel`, before the inbox notification — the same
  ordering `ForwardCase.cancelForward` uses. This is the plan's "also owned
  by C3" block-cleanup requirement, correctly located and fixed; it does
  not conflict with B3's earlier, unrelated `WitnessWindowPort` optional-
  dependency addition to the same constructor.
- **Rollback proof (`9fcc437a`):** the "invalid reason slug rolls back edge
  creation" test is the one that matters most for this unit's correctness
  claim, and it proves the right thing — not just that an exception is
  thrown, but that `findActiveEdge` returns `null` and the forward-reason
  row count is `0` afterward, confirming edge creation and reason
  reconciliation genuinely share one transaction.
- Reran the new PG suite (`forward_reason_reconciliation_pg_test.dart`, 6
  tests) 3x independently against fresh disposable databases — all green
  every time, no flakiness. Also reran the two pre-existing PG test files
  this unit touched (`forward_edge_repository_create_batch_dedup_test.dart`,
  `m0144_mr_publish_epoch_pg_test.dart`) — both still pass.
- Reran `dart test -x pg` (1356, up by one from C3a's own mocked tests),
  `./scripts/check-custom-lints.sh packages/server` (0, baseline), `git diff
  --check` (clean), `rg "package:tentura_server/data/repository"
  packages/server/lib/domain` (empty — domain purity holds).
- Shared local Postgres confirmed untouched across every one of my test
  runs: `mr_publish_epoch.epoch` read `0` before and after, no new
  `tentura_test_*` database left behind by any run.

**C3a is accepted.** Commits: `5ec2ebc3`, `4a3c2e8f`, `9fcc437a`, `796b3505`.
C3b (client-side null-vs-empty semantics) is now dependency-ready.

## C3b — complete — 2026-08-12

STATUS: complete

COMMITS:
- fix(client): distinguish untouched vs cleared forward edit reasons (C3b) (`778c0b80`)
- test(client): add forward cubit edit reason slug semantics tests (C3b) (`427c7b03`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# (sqlite3 code-assets GitHub download fails in main worktree); overlay reverted
# before exit — confirmed pubspec.yaml has no diff.

cd packages/client && dart run build_runner build -d
→ Built with build_runner/aot in 29s; wrote 1231 outputs

cd packages/client && flutter test --dart-define=ENV=test test/features/forward/forward_cubit_edit_reasons_test.dart
→ 00:00 +4: All tests passed!

cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
→ exit 0

./scripts/check-custom-lints.sh packages/client
→ check-custom-lints: packages/client OK; tentura_lints total: 106 (baseline: 111)

git diff --check -- <owned C3b paths>
→ no whitespace errors
```

FILES:

- `packages/client/lib/features/forward/ui/bloc/forward_state.dart` (`editReasons`: `List<String>?`, no default)
- `packages/client/lib/features/forward/ui/bloc/forward_cubit.dart` (`startEditForward` → `null`; `saveForwardEdit` passthrough)
- `packages/client/test/features/forward/forward_cubit_edit_reasons_test.dart` (created)

FINDINGS:

- **Mutation resolver already correct:** confirmed `ForwardRepository.updateForward` maps Dart `null` → omitted GraphQL `reasons` variable and Dart `const []` → empty `BuiltList`; no repository change needed.
- **`editReasons` consumers:** only `forward_cubit.dart` and `forward_state.dart` read/write `state.editReasons`. `ForwardEditPanel` has no reason editor wired today; `forward_recipient_picker.dart`'s `_editReasons` method is the create-path per-recipient reason picker (uses `recipientReasons`, not `editReasons`).
- **Create-path (`recipientReasons`) secondary question:** client has no shared-reason-slugs field — only a per-recipient `Map<String, List<String>>`. `setRecipientReasons` removes the map entry when slugs become empty, and `forward_repository.forwardBeacon` additionally filters out empty slug lists before GraphQL. For *new* edges this is equivalent to "no reasons" (server skips reconcile when absent). The server's `perRecipient ?? shared` distinction for explicitly opting one recipient out of a shared set is **not representable** on the current client create UI (no shared-reason concept); flag for a future F2/band-UI unit if product needs per-recipient opt-out from a shared set — out of C3b scope.

REMAINING: none (manager acceptance pending)

---

### Manager verdict: ACCEPTED — 2026-08-12

Independent review of both feature commits, not a re-run of the worker's
claims.

- **The fix itself (`778c0b80`) is minimal and precise** — exactly the three
  lines this needed: `editReasons` changed from `@Default(<String>[])
  List<String>` to a bare `List<String>?` in `ForwardState`,
  `startEditForward` now sets it to `null` instead of `const []`, and
  `saveForwardEdit` passes `state.editReasons` straight through with the
  `.isEmpty ? null : ...` collapsing removed entirely. No unrelated changes.
- **My own claim in the dispatch prompt that this unit "does not need
  Postgres or the sqlite3-hook workaround" was wrong**, and the worker
  correctly ignored it rather than following bad guidance: the sqlite3
  code-assets download failure is a workspace-root `pubspec.yaml` issue
  (confirmed myself — a plain `flutter test` from `packages/client` hits the
  identical `HttpException` the server units hit), not something scoped to
  `packages/server`. The worker applied the same documented overlay
  workaround anyway and reverted it correctly (confirmed `pubspec.yaml` has
  no diff after their run, and none after mine either).
- **Verified the "mutation resolver already correct" claim directly**,
  independent of the worker's own confirmation: `forward_repository.dart`'s
  `updateForward` does map Dart `null` to an omitted GraphQL variable and
  `const []` to an empty `BuiltList`, exactly as both this unit's dispatch
  prompt and the worker's FINDINGS state. No client repository change was
  needed, and none was made.
- **The `editReasons`-consumer sweep and the create-path secondary finding
  are accurate** — spot-checked `ForwardEditPanel`
  (`forward_recipient_picker.dart`) myself: it is genuinely a note-only
  editor today with no reason-editing control wired in, so this fix is
  correctly aimed at a dormant-but-real contract rather than something with
  no current callers at all (`setEditReasons`/`saveForwardEdit` are called
  from tests now, proving the mechanism, even though no live widget drives
  `setEditReasons` yet). The create-path finding (no "shared reasons"
  representable on the client today, so the server's per-recipient-opt-out-
  of-shared distinction can't be exercised from this client) is a genuine,
  useful discovery for whoever eventually builds that UI — correctly left
  as a documented finding rather than turned into unscoped extra work.
- Reran the new test file (`forward_cubit_edit_reasons_test.dart`, 4 tests)
  3x independently — all green every time. Also reran the full
  `test/features/forward/` suite (84 tests total) — all green, no
  regressions from the `editReasons` type change rippling into any other
  forward-feature test.
- Reran `flutter analyze --no-fatal-warnings --no-fatal-infos` (exit 0, only
  pre-existing findings unrelated to `features/forward/`) and
  `./scripts/check-custom-lints.sh packages/client` myself — confirmed the
  worker's own reported figures exactly: **106 findings against baseline
  111** (an actual improvement, not just "no regression" — the removed
  ternary reduced lint surface slightly). `git diff --check` clean.

**C3b is accepted.** Commits: `778c0b80`, `427c7b03`, `c8ac3d78`. This closes
out UNIT C3 (server half C3a + client half C3b) in full. C4, C5, D0, D3
remain ready from earlier acceptances; nothing new is unblocked specifically
by C3b, since nothing in the manifest depends on it directly.

## C4 — complete — 2026-08-12

STATUS: complete

COMMITS:
- `7e4c82d8` feat(server): add invite_seed_prompt_state schema (C4)
- `d56771ed` feat(server): add invite seed prompt port and inviter lookup (C4)
- `aef6e974` feat(server): add invite seed attestation use case (C4)
- `283a1c63` test(server): prove invite seed attestation policy on Postgres (C4)

TESTS:

```bash
# sqlite3 hook overlay applied temporarily for dart test, then reverted (pubspec.yaml clean)
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot in 12s; wrote 355 outputs

cd packages/server && dart test -t pg test/domain/use_case/invite_seed_attestation_pg_test.dart
→ 00:01 +5: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1356: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ 0 matches

git diff --check
→ no whitespace errors (C4-owned paths)
```

FILES:

- `packages/server/lib/data/database/migration/m0146.dart`
- `packages/server/lib/data/database/migration/_migrations.dart`
- `packages/server/lib/data/database/table/invite_seed_prompt_state.dart`
- `packages/server/lib/data/database/tentura_db.dart`
- `packages/server/lib/domain/port/invite_seed_prompt_port.dart`
- `packages/server/lib/domain/port/invite_genealogy_repository_port.dart` (`inviterOf`)
- `packages/server/lib/data/repository/invite_seed_prompt_repository.dart`
- `packages/server/lib/data/repository/invite_genealogy_repository.dart`
- `packages/server/lib/data/repository/mock/invite_seed_prompt_repository_mock.dart`
- `packages/server/lib/data/repository/mock/invite_genealogy_repository_mock.dart`
- `packages/server/lib/domain/capability/capability_slug_validation.dart`
- `packages/server/lib/domain/use_case/invite_seed_attestation_case.dart`
- `packages/server/lib/data/repository/user_repository.dart`
- `packages/server/test/domain/use_case/invite_seed_attestation_pg_test.dart`
- Test harness updates: `user_repository_*_test.dart`, `room_message_reply_readback_pg_test.dart`, `user_delete_attention_pg_test.dart`, `commitment_attention_pg_test.dart`, `invite_genealogy_case_test.dart`, `query_invite_genealogy_test.dart`

FINDINGS:

- **Plan/code discrepancy (`bindFriendship` vs `recordSignupEdge`):** Traced live call graph. `recordSignupEdge` is called only from `UserRepository.createInvited` and `createInvitedWithCredential` (new-account signup). `bindFriendship` belongs to `UserRepository.bindMutual`, used by `InvitationCase.accept` (`true`) and `_acceptBeaconInviteOnly` (`false`) for **existing** users — it never calls `recordSignupEdge`. Beacon-scoped invites **can** be consumed at signup (`createInvited*` has no beacon filter; lines 214–221 / 373–379 still materialize beacon forwards), but signup paths **always** create reciprocal `vote_user` friendship and genealogy — the plan's "beacon-only without friendship" state is reachable only via `_acceptBeaconInviteOnly` for already-friends existing users, which does not create genealogy or prompt rows. **Decision:** insert `pending` unconditionally in both signup paths immediately after `recordSignupEdge`; do **not** hook `bindMutual` / `bindFriendship`.
- **`InviteRelationPort`:** Added `inviterOf` to existing `InviteGenealogyRepositoryPort` + adapter instead of a separate port/DI binding (same query surface, less plumbing).
- **Taxonomy size:** `kCapabilitySlugOrder` has **37** slugs (matches plan); `validateCapabilitySlugPayload` rejects payloads longer than `kAllowedCapabilitySlugs.length`.
- **`withdraw`:** No seed-specific revoke on `CapabilityEvidencePort`; withdrawal is `upsertSeedAttestation` with `[]` (same empty-set semantics as C3a forward reconcile). Prompt state is left unchanged — inviter already engaged.
- **`setRoutingMute`:** No production caller of `RoutingMutePort.setMute` in server lib (only `RoutingMuteRepository` tests). Deferred validation at the port to E1b; exported `validateCapabilitySlugPayload` for reuse.
- **Answer atomicity:** `answer` wraps `markAnswered` + `upsertSeedAttestation` in `MutatingUnitOfWorkPort.run(actorUserId: actor)` so pair-level seed locks and prompt transition share one transaction. `skip` calls only `markSkipped` (no attestation write per plan).

REMAINING: none (GraphQL surface deferred to E1b per plan)

---

### Manager verdict: ACCEPTED (after two manager-authored repairs) — 2026-08-12

This was the deepest plan/live-code discrepancy investigation so far,
alongside B3's. The dispatch prompt for this unit was built from a
pre-investigation that traced the plan's stated `recordSignupEdge`/
`bindFriendship` mechanism and found it did not exist as described; the
worker was asked to independently verify and resolve it rather than
implement the plan's literal (wrong) text.

**Independently re-traced the discrepancy resolution, not just accepted the
worker's claim:** confirmed directly that `recordSignupEdge` is called only
from `UserRepository.createInvited`/`createInvitedWithCredential` (signup),
neither of which has a `bindFriendship` concept; that `bindMutual` (which
does have `bindFriendship`) never calls `recordSignupEdge`; and that both
signup methods unconditionally create genealogy **and** full friendship
together, with no live code path that creates genealogy without friendship
for a beacon-only invite. The worker's conclusion — insert `pending`
unconditionally in both signup paths, since genealogy and friendship are
never decoupled in reachable states — is the correct resolution given this
evidence, and the journal entry states the reasoning plainly enough to audit
without re-deriving it from scratch.

**Port/adapter review (`7e4c82d8`, `d56771ed`):** the migration and
hand-authored Drift table match the plan's schema exactly, correctly keyed
on `invitee_user_id` alone (not the pair) as the plan specifies. Folding
`InviteRelationPort` into the existing `InviteGenealogyRepositoryPort.inviterOf`
instead of a wholly separate port is a reasonable, lower-plumbing choice
this review explicitly allowed for. `insertPending`'s `onConflict: DoNothing`
is correctly idempotent; `markAnswered`/`markSkipped` correctly throw when no
matching pending row exists, rather than silently no-oping.

**Use case review (`aef6e974`):** `_authorizeInviter` correctly checks
self-seeding, blocks (reusing the existing block-check port method, not a
new one), directional inviter match, and prompt-row existence.
`answer` atomically wraps `markAnswered` + `upsertSeedAttestation` in one
`MutatingUnitOfWorkPort.run` — correct, since B2a's `upsertSeedAttestation`
takes its own pair-lock inside that same call and nothing here re-enters it
awkwardly. `skip` correctly never calls the attestation port. `withdraw`'s
design (empty-list `upsertSeedAttestation`, prompt state left alone) is a
reasonable, clearly-documented reading of an underspecified plan section.

**Two defects found and repaired directly (both small, local, and quickly
verified — handled the same way as B2b's flakiness fix and B3's cascade-
invalidation gap, not sent back for a third worker turn):**

1. `dba31c5d` — `validateCapabilitySlugPayload`'s "reject payloads longer
   than the taxonomy" check compared `deduped.length` (the *post*-validation,
   post-dedup count) against the taxonomy size. Since every element that
   survives into `deduped` must already be a unique, valid taxonomy member,
   `deduped.length` can never mathematically exceed the taxonomy size — the
   check was dead code that could never fire. A payload of many thousands of
   duplicate valid slugs would sail through undetected, contradicting the
   plan's explicit requirement and its own stated motivation (preventing "an
   authenticated client... force[ing] unbounded reconciliation"). Moved the
   length check to run against the raw input **before** the per-element
   loop, so it actually rejects oversized payloads and does so cheaply, as a
   real DoS-shaped guard rather than a no-op.
2. `32ff45a1` — independently ran every pre-existing PG-tagged test this
   unit's diff touched or could plausibly affect (found by grepping for
   every direct `UserRepository(` construction site across `test/` and
   `lib/`, not just the files the worker's own diff happened to list) and
   found `user_repository_invite_genealogy_test.dart` genuinely failing:
   `relation "invite_seed_prompt_state" does not exist`. That test predates
   this entire plan and connects directly to the shared local `postgres`
   database (no `migrateDbSchema` call, only a stale table-existence skip
   gate) — `createInvited`'s new unconditional `insertPending` call now
   requires schema the shared database was never guaranteed to have. Rather
   than migrate shared infrastructure (which every unit since B2b has
   deliberately avoided) or leave a regression in place, moved this test
   onto the same `_DisposablePgTarget` pattern used throughout the rest of
   this plan. Reran it 3x independently afterward — stable every time.
   Cross-checked every other PG-tagged direct `UserRepository` consumer
   (`commitment_attention_pg_test.dart`,
   `room_message_reply_readback_pg_test.dart`,
   `user_repository_link_credential_test.dart`,
   `user_delete_attention_pg_test.dart`) — all already passed without
   changes.
- Reran the worker's own new PG suite (`invite_seed_attestation_pg_test.dart`,
  5 tests) 3x independently — all green every time, no flakiness.
- Reran `dart test -x pg` (1356, unchanged), `./scripts/check-custom-lints.sh
  packages/server` (0, baseline), `git diff --check` (clean), `rg
  "package:tentura_server/data/repository" packages/server/lib/domain`
  (empty — domain purity holds).
- Shared local Postgres confirmed untouched across every one of my test
  runs, including the fixed `user_repository_invite_genealogy_test.dart`:
  `mr_publish_epoch.epoch` read `0` before and after, no new
  `tentura_test_*` database left behind by any run (the fixed test's own
  disposable database is created and dropped cleanly on every run).

**C4 is accepted.** Commits: `7e4c82d8`, `d56771ed`, `aef6e974`, `283a1c63`
(worker), `dba31c5d`, `32ff45a1` (manager repairs). C5 remains
dependency-ready (was already ready from B2c); nothing new is unblocked
specifically by C4, since nothing in the manifest depends on it directly —
E1b (not yet reached) is the eventual consumer of this unit's ports and use
case.

## C5 — complete (manager-completed after an interrupted worker session) — 2026-08-12

STATUS: complete

**Process note:** the dispatched Cursor worker for this unit was killed by
the same unexplained backgrounded-process infrastructure issue seen once
before (during C1a — see that entry). Unlike C1a's case, this time the
worker had already made real, uncommitted progress before being
interrupted: `fetchCues`'s commit-role query and local variable were
removed, `fetchDeduplicatedCapabilities`'s `source_type = 2` UNION branch
was removed, `PersonCapabilityCuesRow.commitRoles` was removed from the
port DTO, `query_capability.dart`'s resolver was updated to match, and a
stale doc comment in `custom_types.dart` was caught and fixed. All of it
verified correct on inspection. Only `fetchTopCapabilitiesBatch`'s
`source_type = 2` branch remained, plus all tests, verification, and
commits. Given the small, well-understood remaining scope, the manager
completed this unit directly rather than discarding the interrupted
worker's correct partial work or dispatching a fresh worker to redo it.

COMMITS:
- `cd9da7fa` fix(server): retire commitRole reads across all three leak sites (C5)
- `4c686aed` test(server): prove commit-role reads are retired, writes still land (C5)

TESTS:

```bash
# sqlite3 hook overlay applied temporarily, then reverted (pubspec.yaml clean)

cd packages/server && dart test -t pg test/data/repository/person_capability_fetch_deduplicated_test.dart
→ 00:00 +11: All tests passed! (reran 3x independently, stable every time)

cd packages/server && dart test -t pg test/data/repository/person_capability_friend_contexts_batch_test.dart test/data/repository/person_capability_close_ack_repository_test.dart
→ 00:00 +2: All tests passed!

cd packages/server && dart test -x pg
→ 00:06 +1356: All tests passed! (unchanged from before this unit)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

git diff --check
→ no whitespace errors

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ empty (exit 1)

rg "commitRole" packages/server/lib/data/repository/person_capability_event_repository.dart
→ exactly one match, line 155, inside insertCommitRole's body (the
  preserved write path) — acceptance gate satisfied literally, including
  the "commitRoles" (plural) substring trap the plan's acceptance text
  warns about, since that field no longer exists anywhere in this file.
```

FILES:

- `packages/server/lib/data/repository/person_capability_event_repository.dart`
  (all three read sites removed: `fetchCues`, `fetchDeduplicatedCapabilities`,
  `fetchTopCapabilitiesBatch`; `insertCommitRole` untouched)
- `packages/server/lib/domain/port/person_capability_event_repository_port.dart`
  (`PersonCapabilityCuesRow.commitRoles` field removed)
- `packages/server/lib/api/controllers/graphql/query/query_capability.dart`
  (`'commitRoles'` response-map key removed)
- `packages/server/lib/api/controllers/graphql/custom_types.dart` (stale
  doc-comment fix, caught by the interrupted worker before it was cut off)
- `packages/server/test/data/repository/person_capability_fetch_deduplicated_test.dart`
  (pre-existing test rewritten — see FINDINGS)

FINDINGS:

- **Verified there is no `schema.graphql` in this repo yet** (F1a, a much
  later unit, hasn't started) — `query_capability.dart`'s response is a
  loosely-typed JSON map, so removing the `commitRoles` key was low-risk,
  no typed-schema ripple to chase.
- **A pre-existing PG test asserted the exact behavior this unit retires:**
  `person_capability_fetch_deduplicated_test.dart` had a test named
  "includes commit roles (source 2) for any viewer observing subject" that
  positively asserted the leak. This is a second instance, after C4's
  `user_repository_invite_genealogy_test.dart`, of a pre-existing test in
  this same area breaking (or in this case, becoming actively *wrong*
  rather than erroring) as a direct, intended consequence of a unit's
  change — checked for this proactively this time rather than discovering
  it via a failed `dart test -x pg`/`-t pg` run, by tracing every
  `PersonCapabilityEventRepository(` construction site in `test/` before
  declaring the unit done. Rewrote the test to assert the opposite
  (`viewerId`, already a third party relative to the `otherId` observer who
  records the commit role in that fixture, sees nothing) plus an explicit
  ledger-row check proving the write path is untouched — satisfying both
  halves of the plan's requirement in one test.
- No other pre-existing test in `packages/server/test/` references
  `fetchCues`, `fetchDeduplicatedCapabilities`, or `fetchTopCapabilitiesBatch`
  outside generated mocks (confirmed via a repo-wide grep) — the sweep
  found exactly one file needing a fix, not more.

REMAINING: none

**C5 is accepted** (self-accepted — the manager both completed and reviewed
this unit directly, given the unusual circumstances; the verification above
is the same rigor applied to every worker-completed unit in this journal,
not a lighter bar). D0 and D3 remain dependency-ready from earlier
acceptances; D1 still requires C1b (accepted) through C5 (now accepted) —
D1 is now fully unblocked on the C-series.

## D0 — checkpoint — 2026-08-12

Started implementation: `BandCandidatePort` + `BandCandidateRepository` adapter;
reusing `ForwardEdgeRepositoryPort`, `HelpOfferRepositoryPort`, and
`InboxRepositoryPort` for beacon involvement facts (same sources as
`BeaconInvolvementCase`, without depending on the use case). Added
`fetchRecipientIdsForwardedBySenderWithinDays` to `ForwardEdgeRepositoryPort`
for historical recent-forward lookup.

**Judgment call (list vs flag):** peers excluded from the returned list entirely
are **author**, **declined**, **already-forwarded-by-ego** (`forwardedByMe`),
and **blocked** (via `block_hides` + `is_mutually_visible`, matching
`mutually_visible_users` — raw `person_visibility_peers` alone does not apply
`block_hides`). Peers with `helpOffered` / `withdrawn` involvement remain in
the list with `canForwardTo = false`; `watching`, onward/`forwardedTo`, and
`unseen` remain with `canForwardTo = true` per client
`ForwardCandidate.canForwardTo`. `alreadyForwarded` is set from ego-scoped active
edges but those peers are list-excluded, so it is always `false` on returned rows
today.

## D0 — complete — 2026-08-12

STATUS: complete

COMMITS: feat(server): add BandCandidatePort adapter for forward band facts (D0) (`eb032720`); test(server): add BandCandidatePort PG tests and port stubs (D0) (`54f56af5`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# for sqlite3 code-assets download failure; reverted before commit.

cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot; wrote outputs (injectable registration for BandCandidateRepository)

cd packages/server && dart test -x pg
→ 00:06 +1356: All tests passed!

cd packages/server && dart test -t pg test/data/repository/band_candidate_repository_pg_test.dart
→ 00:17 +3: All tests passed!

cd packages/server && dart test -t pg test/data/repository/band_candidate_repository_pg_test.dart test/data/repository/witness_window_repository_pg_test.dart test/domain/use_case/forward_reason_reconciliation_pg_test.dart test/data/repository/forward_edge_repository_path_chain_cancel_test.dart test/data/database/m0144_mr_publish_epoch_pg_test.dart
→ 00:18 +30: All tests passed!
# Note: forward_edge_repository_create_batch_dedup_test.dart flakes when run in
# parallel with disposable-DB suites (passes in isolation); pre-existing shared-DB
# contention, not introduced by D0.

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/repository" packages/server/lib/domain
→ no matches

git diff --check
→ no whitespace errors (pubspec overlay reverted)
```

FILES:

- `packages/server/lib/domain/port/band_candidate_port.dart` (created)
- `packages/server/lib/data/repository/band_candidate_repository.dart` (created)
- `packages/server/lib/domain/port/forward_edge_repository_port.dart` (`fetchRecipientIdsForwardedBySenderWithinDays`)
- `packages/server/lib/data/repository/forward_edge_repository.dart` (historical recent-forward SQL)
- `packages/server/test/data/repository/band_candidate_repository_pg_test.dart` (created)
- `packages/server/test/domain/evaluation/evaluation_graph_test_repos.dart` (port stub)
- `packages/server/test/support/build_test_invitation_case.dart` (port delegate stub)
- `docs/plans/subjective-help-tag-evidence-implementation-journal.md` (manifest + this entry)

FINDINGS:

- **Plan/B2b wording vs live SQL:** `person_visibility_peers` does **not** filter
  `block_hides`; only `mutually_visible_users` does. D0 query therefore adds
  `is_mutually_visible` and `NOT block_hides(viewer, peer)` on top of
  `forward_mr > 0`, matching the Forward screen's `mutually_visible_users` pool
  while supplying `forward_mr` for D2 ordering.
- **Ports reused vs added:** involvement facts via existing
  `fetchByBeaconId`, `fetchAllByBeaconId`, `fetchAllByBeaconId` (help offers),
  `fetchRejectedUserIdsByBeacon`; beacon author via `TenturaDb.managers.beacons`.
  New port method: `ForwardEdgeRepositoryPort.fetchRecipientIdsForwardedBySenderWithinDays`
  (all edges, no `cancelled_at` filter, `created_at` window).
- **List-exclusion judgment:** author / declined / ego-forwarded / blocked are
  omitted from results; helpOffered / withdrawn appear with `canForwardTo=false`;
  watching / onward-forwarded / unseen stay eligible (`canForwardTo=true`).
- Mockito-generated `ForwardEdgeRepositoryPort` mocks regenerated by build_runner;
  hand-written stubs updated in `evaluation_graph_test_repos.dart` and
  `build_test_invitation_case.dart` only (Fake subclasses rely on `noSuchMethod`).

REMAINING: none — D1 is unblocked pending manager acceptance of D0


### Manager verdict: ACCEPTED — 2026-08-12

**Acceptance criteria mapping** (plan text: "the returned set matches what
the Forward screen's own candidate query yields for the same ego and
context; a blocked peer is absent; `recentlyForwardedTo` respects the day
window"):

- *Matches Forward screen's candidate semantics* — `candidatesFor` mirrors
  `mutually_visible_users`'s pool (`person_visibility_peers` joined with an
  explicit `is_mutually_visible AND NOT block_hides(...)` check — see
  FINDINGS below) and reproduces the client's `computeInvolvement` +
  `canForwardTo` precedence: author/rejected/ego-forwarded fully excluded
  from the list; helpOffered/withdrawn present with `canForwardTo=false`;
  watching/onward-forwarded/unseen present with `canForwardTo=true`. Test 1
  covers all nine involvement categories in one fixture.
- *Blocked peer absent* — Test 2 isolates block-exclusion independently of
  the involvement fixture.
- *`recentlyForwardedTo` respects the day window* — Test 3 proves the
  window boundary and, per the port's explicit contract, that cancelled and
  historical edges are still included (an active-only implementation would
  silently disable D2's exploration exclusion).

All three acceptance criteria are met.

**Independent verification performed by the manager** (not just re-running
what the worker reported):

```bash
# sqlite3 hook overlay applied temporarily, then reverted (pubspec.yaml clean — confirmed via git diff)

cd packages/server && dart test -t pg test/data/repository/band_candidate_repository_pg_test.dart
→ run 1: 00:16 +3: All tests passed!
→ run 2: 00:17 +3: All tests passed!
→ run 3: 00:13 +3: All tests passed!

cd packages/server && dart test -t pg   # full pg suite, all files, default concurrency — run 3x
→ each run: band_candidate_repository_pg_test.dart passes cleanly; NOT present
  in any failure list (see FINDINGS — this refutes the worker's own flakiness
  claim about a different file)

cd packages/server && dart test -x pg
→ 00:04 +1356: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0 (baseline: 0)

git diff --check / git diff --cached --check
→ no whitespace errors

rg "package:tentura_server/data/" packages/server/lib/domain
→ empty (domain purity holds for band_candidate_port.dart)

docker exec postgres psql -c "SELECT * FROM public.mr_publish_epoch;"
→ epoch = 0, unchanged across the whole D0 review

docker exec postgres psql -c "SELECT datname FROM pg_database WHERE datname LIKE 'tentura_test%';"
→ same 4 pre-existing residual databases as throughout this session
  (tentura_test_rt_2224493_..., tentura_test_diag_2517100,
  tentura_test_diag_2517577, tentura_test_witness_window_528830_...) —
  no growth, D0's disposable database was created and dropped cleanly
  each of the 6 runs above.
```

FINDINGS (manager, beyond what the worker reported):

- **The worker's dispatch-prompt assumption was wrong, and the worker
  caught it, not me.** I had told the worker `person_visibility_peers`
  "already excludes blocked pairs — confirmed in B2b's own review." I
  independently re-checked this via `pg_get_functiondef` before accepting
  their correction: `person_visibility_peers` has zero `block` references;
  only `mutually_visible_users` (which wraps it) adds `NOT
  block_hides(...)`. The worker found this discrepancy themselves and
  added the correct filter. This is not a defect in already-accepted B2b —
  block-filtering for witnesses is deliberately deferred there to D1 via
  B2c's `PairBlockQueryPort`; D0 targets a different, block-aware use case
  (the Forward screen's actual candidate pool) and correctly needs its own
  check.
- **The worker's flakiness claim does not hold up.** Their journal note
  claims `forward_edge_repository_create_batch_dedup_test.dart` "flakes
  when run in parallel with disposable-DB suites... pre-existing shared-DB
  contention, not introduced by D0." I ran the complete `-t pg` suite
  (every pg-tagged file, default concurrency) three times specifically to
  test this claim: that file passed cleanly in all three runs and never
  appeared in any failure list. Its test also does not use
  `_DisposablePgTarget` (it connects directly to shared postgres with
  fixed, non-colliding row IDs), so "contention with disposable-DB suites"
  was not a plausible mechanism to begin with.
- **A real, but unrelated and pre-existing, set of failures was found
  instead.** The same full-suite runs deterministically fail (100% of the
  time, even in complete single-file isolation — not flaky) on
  `beacon_cover_migration_test.dart`, `m0141_person_capability_event_ledger_test.dart`,
  `m0142_derived_tables_migration_test.dart`, `m0143_capability_evidence_sql_test.dart`,
  and `realtime_notification_migration_test.dart`. Root cause: these tests
  manually unwind `public.schema_version` rows down to their own migration
  number to re-test upgrade-from-a-prior-version behavior (e.g.
  `_rollBackM0130ForTest` deletes only the `'0130'`/`'0131'` rows), but
  `migrant`'s `upgrade()` only applies migrations above the *highest*
  recorded version — so as soon as any migration is added *above* the
  test's hardcoded rollback ceiling, the leftover higher-numbered
  `schema_version` rows pin the max and the second `migrateDbSchema` call
  becomes a silent no-op. Confirmed this predates this session and is
  unrelated to D0/B3/C1a/C4: `m0141`'s own test has the identical
  single-version rollback pattern (`_rollBackM0141ForTest` deletes only
  `'0141'`), and `m0142`/`m0143` already existed before this session
  started — so this was already broken the moment `m0142` was created,
  well before any unit in this plan touched the migration chain. Out of
  scope for subjective-help-tag-evidence (unrelated features: beacon cover
  images, realtime notifications); not caused by this plan's units; not
  fixed as part of this review.
- Reviewed `_canForwardTo`'s dead-code author/rejected/myForwarded branches
  (unreachable given `_excludeFromCandidateList` already filtered those
  candidates out of the result set before `_canForwardTo` runs) — harmless,
  unlike C4's dead-code bug, since no functional gap results from it.

**D0 is accepted.** D1 (Projection use case) is now fully unblocked — its
precondition "C1–C5 complete" was satisfied by C5's acceptance, and D2
additionally requires D0 (now accepted) and D1. D3 (Expiry sweep) remains
dependency-ready from B2a's earlier acceptance. Proceeding to D1 next per
document order.

## D1 — checkpoint — 2026-08-12

Started `CapabilityProjectionCase` with Mockito fake-port tests. Algorithm follows
§5.5 via existing ports only; routing mutes scoped to `networkSeed` summation
(not `S_out`); block pairs use lexicographic canonical tuples from
`PairBlockQueryRepository`; profile cap reuses `kCapMaxTagsPerSubjectBeacon`
per subject; Tier-A score is `double.infinity` (`kCapOwnEvidenceScore`).

## D1 — complete — 2026-08-12

STATUS: complete

COMMITS: feat(server): add CapabilityProjectionCase for tag projection (D1) (`17c80352`); test(server): add CapabilityProjectionCase unit tests (D1) (`928c32fc`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# for sqlite3 code-assets download failure; reverted before commit.

cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot; wrote outputs (injectable registration for CapabilityProjectionCase)

cd packages/server && dart test -x pg test/domain/use_case/capability_projection_case_test.dart
→ 00:00 +10: All tests passed!

cd packages/server && dart test -x pg
→ 00:06 +1366: All tests passed!

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/" packages/server/lib/domain/use_case/capability_projection_case.dart
→ 0 matches

git diff --check pubspec.yaml
→ no diff (sqlite3 overlay reverted)
```

FILES:

- `packages/server/lib/domain/use_case/capability_projection_case.dart` (created)
- `packages/server/test/domain/use_case/capability_projection_case_test.dart` (created)
- `packages/server/test/domain/use_case/capability_projection_case_mocks.dart` (created)
- `packages/server/test/domain/use_case/capability_projection_case_mocks.mocks.dart` (generated)
- `docs/plans/subjective-help-tag-evidence-implementation-journal.md` (manifest + this entry)

FINDINGS:

- **Routing-mute scope (§5.5 vs §5.4):** `mutedSlugsFor` keys subject→muted slugs
  and architecture §5.5 places the mute filter on the cells query that feeds both
  `S_out` and `S_seed`. §5.4 and D22/M-invariants require profiles to show
  outcome channel only and M2 requires mutes never suppress ego own evidence.
  Applied mute only when accumulating `S_seed` (Tier C / `networkSeed`); witness
  outcome cells (`S_out` / `networkOutcome`) ignore subject routing mutes. Own
  routing (Tier A seed) is unaffected by subject mute per §5.4 matrix.
- **∞ score representation:** Tier-A rows use `kCapOwnEvidenceScore =
  double.infinity` so own evidence always sorts above finite network scores in
  D2 without exposing magnitude through the API.
- **Profile cap constant:** Reused `kCapMaxTagsPerSubjectBeacon` (value 3) for
  the profile top-N cap — same numeric bound as beacon-wide finalization (D12)
  and plan §2; name says per-beacon but it is the repo's single "at most 3 tags"
  constant. Cap is applied **per subject** in `ProjectionSurface.profile` (matches
  `subjectiveTags(targetId)` single-target semantics when batched).
- **Block tuple direction:** `PairBlockQueryRepository` returns
  `(min(id_a,id_b), max(id_a,id_b))`; membership tests canonicalize both
  endpoints before lookup (verified against pg test in B2c).
- **Context normalization:** Caller supplies pre-normalized `normalizedContext`
  (same boundary as D0 `BandCandidatePort` and B2b `cachedWindow`); D1 does not
  re-normalize.
- **§13.1 arithmetic:** Bob+Dave example documents `S_out = 0.448` but
  `0.321 + 0.5×0.255 = 0.4485`; test uses `closeTo(0.448, 0.001)` against doc
  rounding.

REMAINING: none — D2 (band composition) is next; requires D1 (this unit) and
D0 (accepted).

### Manager verdict: ACCEPTED — 2026-08-12

**Acceptance criteria mapping** (plan text: "the §13.1 example → networkOutcome;
Sybil case → nothing; an ineligible coalition summing 0.9 → nothing; muted →
nothing; tombstoned → nothing including own; profile surface drops a seed-only
tag that the band surface shows" plus "a 4-tag fixture asserting exactly 3
come back in [ownOutcome-first, networkOutcome-by-score-desc, tagSlug-asc]
order"):

- §13.1 Bob-only (`S_out = 0.321`) and Bob+Dave (`S_out = 0.448`) →
  `networkOutcome`, exact scores asserted — both present, both correct.
- Sybil farm (no admitted witnesses) → empty — present.
- Ineligible coalition (2 non-admitted witnesses) → empty, **and** pins via
  `verify(...)` that `fetchCells` is called with `admittedWitnesses: const []`
  — stronger than the plan's bare "→ nothing", since it proves the D15
  exclusion happens before the cell fetch, not just that the final output
  is empty (which a differently-broken implementation could also produce).
- Muted → the muted tag produces no row while an unmuted outcome tag for the
  same subject is unaffected — present, matches the routing-mute scope
  finding below.
- Tombstoned → empty even with both qualifying network AND own evidence
  present for the pair — present, exact match to spec wording "nothing
  including own".
- Profile surface drops a seed-only tag the band surface shows — present,
  and the fixture is a 5-tag case (exceeds the plan's 4-tag minimum): one
  own-outcome tag plus four network-outcome tags at descending scores plus
  one network-seed tag plus one own-routing tag are all supplied; profile
  returns exactly `['own_tag', 'alpha', 'beta']` (ownOutcome first, then the
  two highest-scoring networkOutcome tags, `gamma`/`delta` correctly cut by
  the cap), `routing_tag` (ownRouting) and `seed_only` (networkSeed) are
  absent from profile output and confirmed present in the same fixture's
  forwardBand-surface output.

All six required cases and the mandatory profile-cap fixture are present.
Two more cases beyond the plan's bare minimum are also covered: own-evidence
overriding network evidence on the same tag (§5.5's "(A, ∞) overrides B/C"
line), and both rows of the §16.2 block matrix that are D1's responsibility
(ego↔witness and witness↔subject, the latter proven scoped to the specific
blocked subject and not the witness's other cells).

**Independent verification performed by the manager:**

```bash
# Read capability_projection_case.dart and capability_projection_case_test.dart
# in full and traced every branch against architecture §5.2.2/§5.3/§5.4/§5.5/§16.2
# before running anything.

# sqlite3 hook overlay applied temporarily, then reverted (git diff pubspec.yaml clean)

cd packages/server && dart test -x pg test/domain/use_case/capability_projection_case_test.dart
→ run 1: 00:00 +10: All tests passed!
→ run 2: 00:00 +10: All tests passed!
→ run 3: 00:00 +10: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1366: All tests passed! (+10 vs D0's baseline of 1356, matches the new file exactly)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0 (baseline: 0)

git diff --check
→ no whitespace errors

rg "package:tentura_server/data/" packages/server/lib/domain/use_case/capability_projection_case.dart
→ empty (domain purity holds)

git diff 6df6cd52..f592386f --stat
→ purely additive: journal (+79/-1), capability_projection_case.dart (new,
  260 lines), test file (new, 644 lines), mocks source + generated mocks
  (new) — no pre-existing file touched, confirming no collateral-damage
  risk to sweep for (unlike C4/C5, which each modified shared read paths).

grep -n "CapabilityProjectionCase" packages/server/lib/app/di.config.dart
→ present, singleton-registered

grep -n "@Singleton(order: 2)" packages/server/lib/domain/use_case/*.dart | wc -l
→ CapabilityProjectionCase uses the same order:2 convention as every other
  use case in this directory (forward_inbound_query_case.dart, user_case.dart,
  polling_case.dart, etc.) — no DI-ordering anomaly introduced.

cat packages/server/lib/data/repository/pair_block_query_repository.dart
→ confirms the worker's block-tuple-direction finding exactly: the SQL emits
  CASE WHEN blocker_id < blocked_id THEN blocker_id ELSE blocked_id END (and
  the symmetric max), i.e. (min, max) by text comparison — matching D1's
  `_canonicalPair`'s `a.compareTo(b) <= 0 ? (a, b) : (b, a)` exactly.
```

FINDINGS (manager, beyond what the worker reported):

- **Routing-mute scope resolution is correct and traced to the actual code
  path, not just asserted.** `_aggregateNetworkProjections` accumulates
  `outSums[key]` unconditionally for every cell (line before the mute
  check), and only guards the `seedSums[key]` accumulation with the mute
  lookup. This means an outcome-qualifying cell on a muted tag slug would
  still cross `θ_out` and render — exactly the "mutes never suppress ego
  own evidence" / "profiles render outcome channel only, regardless of
  mute" reading of §5.4 the worker chose. The test as written proves the
  mechanism using two *different* tags (transport unmuted/outcome, pets
  muted/seed) rather than one tag with both qualifying outcome and seed
  evidence simultaneously — a marginally weaker fixture than ideal, but the
  code path itself is unconditional per-tier (not tag-dependent), so this
  gap doesn't hide a real defect; noted for a future unit that touches this
  method to prefer the stronger same-tag fixture if convenient.
- **Profile cap is applied per-subject, not globally across a batched
  `subjectIds` call.** This is the correct reading: `subjectiveTags(target)`
  (architecture §16.1) is single-target, so a global cross-subject cap would
  produce nonsensical results if `profile` surface is ever called with a
  batch of subjects (at most 3 tags *total* across 5 different people's
  profiles makes no sense for a profile view). Confirmed by reading
  `_applyProfileCap`'s `bySubject` grouping before the take(3). This should
  be re-confirmed against E1a's resolver when it's built, to make sure the
  API layer calls `project()` with exactly one subject per profile request
  and doesn't accidentally rely on a global-cap assumption.
- **`kCapOwnEvidenceScore = double.infinity`** is a new top-level constant
  in the use-case file itself, not `capability_consts.dart` — reasonable
  scoping choice since it's an internal sentinel for this file's own sort
  ordering, not a tunable calibration constant like the `kCap*` values in
  the shared consts file; does not need to move.
- No pre-existing test anywhere references `CapabilityProjectionCase`,
  `ScoredProjection` construction outside `capability_evidence_models.dart`
  itself, or any of the five consumed ports' method signatures in a way D1
  could have broken — confirmed via the purely-additive diff stat above,
  so the "sweep every affected pre-existing test" discipline (required
  since C4/C5) has nothing to check here; this unit could not have
  regressed anything by construction.

**D1 is accepted.** D2 (Band composition) is now unblocked — its
preconditions were "D1 exists and returns `ScoredProjection`" (satisfied)
and it separately depends on D0 (accepted). Proceeding to D2 next per
document order. D3 (Expiry sweep) and D4 (Model invariant suite, which
additionally needs D1+D2 "exercisable through fake ports") remain queued
behind D2.

## D1 — manager correction — 2026-08-12

While building D2's dispatch prompt (which needed architecture §8/§8.1/§9 in
full), a full re-read of §12 surfaced a direct, explicit contradiction of a
finding accepted in D1's verdict above: **"Muting suppresses Tier B and Tier
C for all viewers"** (§12.2, verbatim). D1 was accepted on the finding that
mute suppresses only `networkSeed` (Tier C), reasoning from §5.4's
source-by-surface matrix — which is a different question (which surface a
*source* may render on) than mute *scope* (which *tier* a mute suppresses).

Checked for a fourth time before touching code, since this reverses a
verdict already committed: **D4** (top-level decision table, line 41,
"Muting suppresses third-party projection only" — B and C are both
third-party/network-derived, only A is first-hand), **§5.5**'s pseudocode
(the `(subject, tag) NOT IN <routing mutes>` predicate filters the single
`cells` CTE that both `S_out` and `S_seed` are summed from — there is no
separate unmuted-for-outcome path), and **§14**'s SQL projection sketch
(`AND NOT EXISTS (routing mute on ...)` in the one `WHERE` clause feeding
both `sum(win.m * e_out(c))` and `sum(win.m * e_seed(c))`) all independently
and unambiguously confirm the same thing. Four sources, zero support for the
seed-only reading anywhere in the document. The original finding was wrong.

**Fixed directly** (small, local, mechanical, quick to verify — no fresh
worker needed): moved the mute check in `_aggregateNetworkProjections` to
`continue` before either `outSums` or `seedSums` accumulation, instead of
only guarding `seedSums`. Commit `9d13624d`.

**The existing test for this had a fixture gap that let the bug hide.** The
"routing mute suppresses networkSeed only, not networkOutcome" test used a
muted tag (`pets`) with `eOut: 0` — meaning it had no outcome evidence to
suppress in the first place, so the old (wrong) implementation and the
corrected one produced an identical result on that fixture. Rewrote the
fixture so the muted tag qualifies for **both** tiers (`eOut: 0.35, eSeed:
0.30`, both above their thresholds) and asserts it now produces **no** row
at all, while an unmuted tag on the same subject is untouched. This is
exactly the class of gap this journal's "never trust a green test without
checking what it actually exercises" discipline exists to catch — in this
case caught one step later than ideal (after acceptance, not during it),
which is itself the finding worth recording: a plan-prose cross-check
(§5.4 vs §12.2 vs §5.5 vs §14) needs to run before accepting a *judgment
call* finding, not only before accepting a *port/type* finding, since this
session's established sweep discipline (checking pre-existing tests, port
signatures, DI wiring) had no step that would have caught a same-document
internal contradiction on its own.

Re-verified after the fix, same rigor as initial acceptance:

```bash
cd packages/server && dart test -x pg test/domain/use_case/capability_projection_case_test.dart
→ run 1/2/3: 00:00 +10: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1366: All tests passed! (unchanged count — same file, corrected fixture)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/" packages/server/lib/domain/use_case/capability_projection_case.dart
→ empty

git diff --check
→ no whitespace errors (sqlite3 overlay reverted, pubspec.yaml clean)
```

**D1 remains accepted**, now on the corrected implementation. D2 was not
yet dispatched when this was found, so no downstream unit inherited the
defect. Proceeding to D2 next, as originally planned.

## D2 — checkpoint — 2026-08-12

Started `ForwardBandCase` + `fnv1a64`. Composition consumes D0
`BandCandidatePort`, `BeaconRepositoryPort.getBeaconById` (needs +
`primaryNeedSlug`), and D1 `CapabilityProjectionCase.project(surface:
forwardBand)` — no new ports. Evidence sort key:
`(rowTier strength asc index, max score at rowTier desc, forward_mr desc,
userId asc)`; labels capped at 2 same-tier tags (primary need first, then
score desc, then slug asc). Exploration pool excludes **all**
evidence-bearing candidates (not only top-3 evidence rows), recently-forwarded
IDs, and `canForwardTo=false` peers.

**Judgment call (`canForwardTo`):** band membership (evidence + exploration)
is restricted to `canForwardTo == true` before projection/ranking. Grounding:
architecture §8 mock-up shows `[Forward]` on every band row; D0 documents
`canForwardTo` as mirroring client `ForwardCandidate.canForwardTo`; D0 keeps
helpOffered/withdrawn in the candidate list for the main MR list but marks
them non-forwardable. Architecture §8 "candidate set unchanged" and D4 B1
("tag evidence never removes a candidate from the underlying list") apply to
the main list below the band, not to the capped band strip.

## D2 — complete — 2026-08-12

STATUS: complete

COMMITS: feat(server): add fnv1a64 hash for forward-band exploration (D2) (`5aea6288`); feat(server): add ForwardBandCase for evidence band composition (D2) (`373a40a6`); test(server): add ForwardBandCase unit tests and D2 journal (D2) (`ae09b0af`)

TESTS:

```bash
# Temporary root pubspec.yaml hooks.user_defines.sqlite3.source: system overlay
# for sqlite3 code-assets download failure; reverted before commit.

cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot; wrote outputs (injectable registration for ForwardBandCase)

cd packages/server && dart test -x pg test/domain/capability/fnv1a64_test.dart test/domain/use_case/forward_band_case_test.dart
→ 00:00 +14: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1380: All tests passed! (+14 vs D1 baseline of 1366)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/" packages/server/lib/domain/use_case/forward_band_case.dart packages/server/lib/domain/capability/fnv1a64.dart
→ 0 matches

git diff --check pubspec.yaml
→ no diff (sqlite3 overlay reverted)
```

FILES:

- `packages/server/lib/domain/capability/fnv1a64.dart` (created)
- `packages/server/lib/domain/use_case/forward_band_case.dart` (created)
- `packages/server/test/domain/capability/fnv1a64_test.dart` (created)
- `packages/server/test/domain/use_case/forward_band_case_test.dart` (created)
- `packages/server/test/domain/use_case/forward_band_case_mocks.dart` (created)
- `packages/server/test/domain/use_case/forward_band_case_mocks.mocks.dart` (generated)
- `packages/server/lib/app/di.config.dart` (generated — ForwardBandCase registration)
- `docs/plans/subjective-help-tag-evidence-implementation-journal.md` (manifest + this entry)

FINDINGS:

- **`canForwardTo` band filter:** both evidence and exploration rows require
  `canForwardTo == true` (see checkpoint). Non-forwardable peers remain in D0's
  candidate list for the untouched main MR list but never appear in the band.
- **Exploration pool vs evidence cap:** candidates with matched evidence who
  miss the top `kCapBandEvidenceSlots` evidence rows must still be excluded
  from exploration — pool membership uses the full `projectionsBySubject` key
  set, not only rendered evidence row userIds. Initial implementation used
  evidence-row IDs only; fixed before commit (would have surfaced julia-with-
  evidence as an exploration row in the deterministic fixture).
- **Label secondary ordering:** after `primaryNeedSlug` first among same-tier
  tags, tie-break by `score` descending then `tagSlug` ascending (matches D1
  profile-cap `networkOutcome` pattern from `_profileRowOrder`).
- **`rank` convention:** 0-based contiguous integers; evidence rows first
  (`0..n-1`), exploration rows continue (`n..`). Sorting by `rank` alone
  reproduces display order without needing `isExploration` as a secondary key.
- **`fnv1a64` pinned vectors (signed Dart int / hex):**
  `""` → `0xcbf29ce484222325` (`-3750763034362895579`);
  `"a"` → `0xaf63dc4c8601ec8c` (`-5808556873153909620`);
  `"foobar"` → `0x85944171f73967e8` (`-8821353812377114648`).
  Implementation uses masked 64-bit `int` arithmetic (not `BigInt.toInt()` —
  the latter clamps values with the high nibble ≥ `0x8` to `int64 max`).
  `fnv1a64Mod` applies `hash & 0xFFFFFFFFFFFFFFFF` before `%` for unsigned
  semantics.
- **Test double for D1:** `CapabilityProjectionCase` is `final` — Mockito
  cannot mock/implement it; band tests wire the real projection case with D1's
  existing port mocks (`capability_projection_case_mocks.mocks.dart`).
- **Row-tier precedence:** uses `ProjectionTier.values.indexOf` (declaration
  order: `ownOutcome > networkOutcome > ownRouting > networkSeed`), not a
  stale three-bucket A/B/C mapping — cross-checked against architecture §8.1,
  plan D2 text, and D1 manager correction discipline.

REMAINING: none — D4 (model invariant suite) is next per manifest; D3 (expiry
sweep) remains dependency-ready from B2a.

### Manager verdict: ACCEPTED (after one manager-authored repair) — 2026-08-12

**Acceptance criteria mapping** (plan text: "deterministic output on a fixed
fixture; empty and singleton pools; a candidate with own + networkSeed
labels only the own tag; no band when no candidate has evidence"):

- Deterministic output on a fixed fixture — present, a 7-candidate fixture
  pinning exact userIds, ranks, tiers, and labels for all 5 resulting rows.
- Empty exploration pool — present (`canForwardTo=false` plus a
  recently-forwarded exclusion jointly empty the pool).
- Singleton exploration pool — present, pins exactly one row (not a
  wrapped duplicate).
- A candidate with own + networkSeed labels only the own tag — present,
  the exact §8.1 adversarial case ("You worked together on Transport ·
  Tools" wrongly implying shared work on both) with `ownOutcome` on
  `transport` and `networkSeed` on `tools`, asserting `labels ==
  ['transport']`.
- No band when no candidate has evidence — present, and additionally pins
  that `recentlyForwardedTo` is never called in that case (proving
  exploration isn't computed independently of the band, per §9: "On a
  screen with no band there is nothing to counterbalance").

All four required cases present, plus four more beyond the minimum:
row-tier reduction correctly favoring `networkOutcome` over the candidate's
own `ownRouting` tag (the "channel first, then origin" rule, tested with a
tier the candidate does NOT hold at Tier A — a stronger test than only
exercising Tier A vs Tier C), `canForwardTo` band-exclusion pinned via a
captured mock argument (proving exclusion happens before D1 is even
called, not just filtered from the output), and exploration determinism
across repeated calls with the same `beaconId`.

**A real defect was found and fixed before this verdict was written** (not
after, unlike D1 — the lesson from D1's post-acceptance correction was
applied here proactively): `fnv1a64Mod`'s "unsigned semantics" handling was
wrong. Details below.

**Independent verification performed by the manager:**

```bash
# Read forward_band_case.dart and forward_band_case_test.dart in full,
# traced every branch against architecture §8/§8.1/§9 before running anything.

# Computed fnv1a64('a') by hand against the pinned vector to spot-check the
# "unsigned semantics" claim in the worker's FINDINGS, since D1's post-hoc
# correction established that a judgment-call finding needs independent
# arithmetic verification, not just plausibility:

python3 -c "
h = 0xaf63dc4c8601ec8c
signed = h - 2**64
for mod in [3, 7, 10, 1000003]:
    print(mod, h % mod, signed % mod)
"
→ mod=7: true_unsigned=5, dart_signed_percent=3  -- MISMATCH, confirming a
  real bug: `& 0xFFFFFFFFFFFFFFFF` is a no-op (that literal is -1 in Dart's
  64-bit two's-complement `int`), and `%` on a negative Dart int computes
  Euclidean mod of the SIGNED value, not the true unsigned value.

# Reproduced directly against the actual repo code (not just the arithmetic
# argument) via a throwaway probe script run from packages/server with the
# sqlite3 overlay applied:
dart run tool/fnv_probe_scratch.dart
→ fnv1a64Mod("a", 7) = 3   (confirmed wrong; correct is 5) — probe script
  deleted after use, never committed.

# Fixed via BigInt.toUnsigned(64) (commit 1d6d36bf). Re-verified:

cd packages/server && dart test -x pg test/domain/capability/fnv1a64_test.dart test/domain/use_case/forward_band_case_test.dart
→ run 1/2/3: 00:00 +14: All tests passed!

cd packages/server && dart test -x pg
→ 00:07 +1380: All tests passed! (+14 vs D1's 1366)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/" packages/server/lib/domain/use_case/forward_band_case.dart packages/server/lib/domain/capability/fnv1a64.dart
→ empty (domain purity holds for both files)

grep -n "ForwardBandCase" packages/server/lib/app/di.config.dart
→ present, singleton-registered

git diff --check
→ no whitespace errors (sqlite3 overlay reverted)
```

FINDINGS (manager, beyond what the worker reported):

- **The pre-existing "unsigned semantics" test could not have caught this
  bug, structurally.** It asserted `fnv1a64Mod(x, 7)` is `inInclusiveRange(0,
  6)` — a property that holds unconditionally for ANY implementation,
  buggy or not, because Dart's `%` operator on a positive right operand is
  *always* non-negative regardless of whether the left operand's
  conversion to "unsigned" was done correctly. This is the same shape of
  gap as D1's mute-scope test (a fixture that happens to make the buggy
  and correct implementations produce the same result) — worth stating
  explicitly as a pattern to watch for across the rest of this plan: a
  test that asserts a *property* the correct AND incorrect implementations
  both satisfy proves nothing about the specific mechanism under test.
  Replaced with a fixture asserting the exact expected numeric values,
  cross-checked independently.
- **The `canForwardTo` band-membership judgment call (documented in D2's
  own checkpoint) is well-grounded and I independently agree with it**:
  every band row (evidence or exploration) carries a `[Forward]` action
  per §8's mock-up, and restricting to `canForwardTo == true` before
  either ranking or exploration is the only reading that keeps that
  affordance honest. Re-confirmed this doesn't touch the *main* MR-ordered
  list (D3/D4's "candidate set unchanged" language governs that list, not
  the band strip layered above it).
- **The evidence-cap-vs-exploration-pool exclusion is correct**:
  `evidencedUserIds` is built from the *full* `projectionsBySubject` key
  set before `_buildEvidenceRows` truncates to the top `kCapBandEvidenceSlots`
  — a candidate with real but sub-cutoff evidence is excluded from both
  the rendered evidence rows AND the exploration pool, never double-counted
  or wrongly resurfaced as "new to this kind of request." Confirmed by
  reading the call order in `composeBand` directly, not just trusting the
  worker's FINDINGS note describing the same fix.
- No pre-existing test references `ForwardBandCase`, `fnv1a64`/`fnv1a64Mod`,
  or `ForwardBandRow` construction outside `capability_evidence_models.dart`
  itself — this unit could not have regressed anything by construction
  (same purely-additive-plus-one-fix shape as D0 and D1).

**D2 is accepted**, on the corrected `fnv1a64Mod`. D3 (Expiry sweep,
dependency-ready from B2a) and D4 (Model invariant suite, needing D1+D2
"exercisable through fake ports" — now satisfied) are both unblocked.
Proceeding to D3 next per document order.

## D3 — checkpoint — 2026-08-12

Started `CapabilityCellRepository` (`@Injectable(as: CapabilityCellPort)`),
the first concrete adapter for the port D1/D2 already depend on. Plan prose
undersells this unit: there was zero `implements CapabilityCellPort` in the
tree — D3 builds `fetchCells`, `rebuildCell`, and `claimExpiredCells` from
scratch, not just a sweep on an existing adapter.

**`fetchCells` read-through staleness (two-phase):** (1) SELECT matching
`capability_evidence_edge` rows joined to live `capability_evidence_generation`,
flagging rows where `built_from_gen <> coalesce(generation,0)` OR
`next_expiry_at <= now()`; (2) `cap_cell_rebuild` each stale triple
(reentrant lock inside SQL); (3) re-SELECT the requested set with
`cap_strength` applied and map `m` from caller-supplied `admittedWitnesses`.
Race-safe because a concurrent writer may bump generation between (1) and (2)
— worst case an extra rebuild, never a stale read after (3). `cap_cell_rebuild`
already self-deletes zero-evidence cells and takes `cap_cell_lock` internally.

**Claim/lease:** single-statement CTE
`SELECT … FOR UPDATE SKIP LOCKED LIMIT` + `UPDATE … SET sweep_lease_*`
(matching `ImageObjectGcRepository`), not `AttentionExpirySweepCase`'s
unbounded, lease-less pattern.

**GC:** `WitnessWindowPort.gcStaleWindows()` deletes
`computed_at < now() - kCapWindowTtlMinutes` (15m, same as read-time TTL);
`CapabilityCellPort.gcOrphanGenerations()` deletes generation rows with no
*non-deleted* ledger row and no cell, under `cap_cell_lock` per triple.
TaskWorker intervals: cell sweep 15m; EWW GC 1h; generation GC 6h.

Migration number confirmed live: **m0147** (next free after m0146).

## D3 — complete — 2026-08-12

STATUS: complete

COMMITS: feat(server): add sweep lease columns on capability evidence edge (D3) (`113de4e8`); feat(server): add CapabilityCellRepository adapter (D3) (`49d200ed`); feat(server): wire capability cell expiry sweep into TaskWorker (D3) (`2d2ce4e7`); test(server): add capability cell PG tests and fix A1-A3 upgrade paths (D3) (`9a4e8c1b`); docs: D3 expiry sweep journal (D3) (`293e1f05`)

TESTS:

```bash
cd packages/server && dart run build_runner build -d
→ Built with build_runner/aot; wrote outputs (CapabilityCellRepository,
  CapabilityCellExpirySweepCase, TaskWorkerCase DI)

cd packages/server && dart test -t pg test/data/repository/capability_cell_repository_pg_test.dart
→ run 1/2/3: 00:01 +9: All tests passed!

cd packages/server && dart test -x pg
→ 00:13 +1380: All tests passed!

cd packages/server && dart test -t pg
→ 00:44 +349 ~2 -12: Some tests failed (12 remaining failures, all in
  beacon_cover_migration_test.dart and realtime_notification_migration_test.dart
  — partial schema_version rollback + migrateDbSchema head-at-m0147 class;
  unrelated to capability_evidence_edge columns; A1–A3 upgrade tests repaired)

./scripts/check-custom-lints.sh packages/server
→ exit 0; tentura_lints total: 0

rg "package:tentura_server/data/" packages/server/lib/domain/use_case/capability_cell_expiry_sweep_case.dart
→ empty
```

FILES:

- `packages/server/lib/data/database/migration/m0147.dart` (created)
- `packages/server/lib/data/database/migration/_migrations.dart`
- `packages/server/lib/data/repository/capability_cell_repository.dart` (created)
- `packages/server/lib/data/repository/witness_window_repository.dart`
- `packages/server/lib/domain/port/capability_cell_port.dart`
- `packages/server/lib/domain/port/witness_window_port.dart`
- `packages/server/lib/domain/use_case/capability_cell_expiry_sweep_case.dart` (created)
- `packages/server/lib/domain/use_case/task_worker_case.dart`
- `packages/server/test/data/repository/capability_cell_repository_pg_test.dart` (created)
- `packages/server/test/data/database/m0141_person_capability_event_ledger_test.dart`
- `packages/server/test/data/database/m0142_derived_tables_migration_test.dart`
- `packages/server/test/data/database/m0143_capability_evidence_sql_test.dart`
- `packages/server/test/domain/use_case/capability_projection_case_mocks.mocks.dart` (generated)
- `docs/plans/subjective-help-tag-evidence-implementation-journal.md`

FINDINGS:

- **Plan undersold D3 scope:** `CapabilityCellPort` had no adapter anywhere;
  D3 delivers the full PG-backed repository D1/D2 inject, including first
  real-Postgres proof of `fetchCells`.
- **`fetchCells` staleness:** two-phase select→rebuild stale triples→re-select
  (see checkpoint); safe under concurrent generation bumps / rebuilds.
- **`next_expiry_at` Drift read:** `read<DateTime>` mis-decodes Postgres
  `timestamptz`; parse via `DateTime.parse(row.read<String>(…)).toUtc()` like
  `attention_dispatch_repository.dart`.
- **Migration upgrade tests vs migrant head:** deleting only
  `schema_version='0143'` then calling `migrateDbSchema` no longer re-applies
  m0143 when head is m0147 (`getNext(current)` stops at head). Fixed A1–A3
  upgrade tests to re-execute that migration's `statements` directly + insert
  `(version, applied_at)` row. Same root cause likely explains 12 pre-existing
  failures in older beacon/notification migration tests (not touched further —
  out of D3 scope, unrelated to new columns).
- **GC predicates:** EWW TTL = `kCapWindowTtlMinutes` (15m); generation GC uses
  zero *non-deleted* ledger rows (generation tracks live ledger↔cell drift) AND
  no cell row, with `cap_cell_lock` before delete.
- **Migration number used:** **m0147** (verified free in `_migrations.dart`).

REMAINING: none for D3 scope. Twelve PG failures in
`beacon_cover_migration_test.dart` / `realtime_notification_migration_test.dart`
remain (partial rollback vs migrant-head); not introduced by m0147 column adds.

