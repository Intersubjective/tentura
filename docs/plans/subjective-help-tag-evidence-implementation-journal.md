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
- [ ] **A1** — Ledger extension (depends: A0) — `m0141`; `person_capability_events.dart`; `CapabilityEventSource.seedRoutingAttestation(4)`
- [ ] **A2** — Derived tables + context fn (depends: A1) — `m0142`; cell/window/mute/generation/epoch tables + Drift; `cap_normalize_context`
- [ ] **A3** — Evidence SQL functions (depends: A2) — `m0143`; `cap_strength`, `cap_cell_lock`, `cap_generation_bump`, `cap_cell_rebuild`
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
