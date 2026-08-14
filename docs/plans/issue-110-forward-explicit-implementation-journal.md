# Issue #110 — Explicit forwarding — implementation journal

## Scope

- Objective: implement
  `docs/plans/issue-110-forward-explicit-implementation-plan.md` end to end
  against architecture
  `docs/plans/issue-110-forward-explicit-architecture.md` **rev 3**.
- Repository: `/home/vader/MY_SRC/tentura`
- Branch / starting HEAD: `main` /
  `5bfbefb77ff37ec7dbafc66e3ed39846fda2545a`
- Started: 2026-08-14.
- Overseer: cursor-plan-overseer (Composer 2.5 workers, sequential, local
  commits only, no push).

## Protected pre-existing worktree changes

Do not edit, stage, revert, or commit these unless a later unit proves a
file is genuinely required for #110; in that case stop and record the
conflict. `docs/README.md` already has a small #110 index bump (rev 1 →
rev 3 + implementation-plan link); leave it until a docs-owned unit
explicitly stages that hunk.

```text
M  docs/README.md
M  docs/archive/journals/commitment-truth-rework-journal.md
M  docs/archive/plans/commitment-truth-rework-plan.md
M  docs/audits/room-coordination-audit.md
M  scripts/run_client_integration_web_local.sh
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
```

The architecture and implementation-plan files are untracked and
authoritative for this run. Do not stage or commit them unless a later
unit explicitly owns that docs commit. This journal is orchestrator-owned
and is the only file UNIT 00 may add/commit.

Secrets (`key.fb`, `out.key`, `dart-defines`) must never be staged.

## Live baseline (manager, 2026-08-14)

```text
latest migration                    m0149  (no m0150)
packages/client/pubspec.yaml        6.1.1
packages/client/web/index.html      flutter_bootstrap.js?v=6.1.1
packages/server/lib/env.dart        kDefaultMinClientVersion = '6.0.0'
architecture                        rev 3
HomeTabReselectCubit                @singleton (GetIt)
InboxCubit                          NOT registered in GetIt (per-screen)
ForwardCubit.embedded               still present
beacon_create send path             sendRequest(forwardCubit:) then dialog/pop
                                    (publish still precedes forward)
```

Stop conditions from plan §1 (worker re-check, 2026-08-14):

| Condition | Result |
|-----------|--------|
| `m0150` exists | **no** (`m0149` is latest) |
| `ForwardCubit.embedded` removed or beacon_create publish no longer precedes `forward()` | **no** (`embedded` field present; `sendRequest` calls `publishDraft` then `forward()`) |
| `HomeTabReselectCubit` not GetIt `@singleton` | **no** (`@singleton` on cubit) |
| `InboxCubit` registered in GetIt | **no** (no `InboxCubit` in `di.dart` / `*.config.dart`) |
| Owned file with unrelated dirty state blocking narrow edit | **no** (arch/plan untracked by design; `docs/README.md` protected) |

None triggered.

## Ordered manifest

- [x] **00** Journal and baseline — complete
- [x] **01** Pure coverage / note / cancel helpers
- [x] **02** Server `cancelForward` honours `recipientRejected`
- [x] **03** `MyForwardRecipient` hasOnwardChild + recipientRejected
- [x] **04** Map flags onto `ForwardCandidate` / `ForwardLoad`
- [ ] **05** `ForwardCubit` session: skip, wire, stay, force-reload
- [ ] **06** Picker: skip, sheet, controllers, D14 chrome
- [ ] **07** Location toast + Watching intent on `HomeTabReselectCubit`
- [ ] **08** Inbox consumes Watching intent; D15
- [ ] **09** D13 offer-help snapshot on Inbox + BeaconView
- [ ] **10** CTA inventory (`allowsForward`)
- [ ] **11** Person-forward stay, skip/sheet, **add** cancel
- [ ] **12** Client 6.2.0 + web cache-buster
- [ ] **13** Plan-wide closeout

Do not parallelize. Do not start a downstream unit while a prerequisite is
red.

## Acceptance and verification

Frozen contracts: `docs/plans/issue-110-forward-explicit-implementation-plan.md`
§0. Architecture decisions D1–D15 are normative.

Per-unit verify commands live in the implementation plan. Plan-wide closeout
(UNIT 13):

```bash
cd packages/server && dart test test/domain/use_case/forward_case_test.dart --name "cancelForward"
cd packages/server && dart test test/domain/use_case/beacon_involvement_case_test.dart
cd packages/client && flutter test test/features/forward test/features/inbox/inbox_case_test.dart
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
```

Client user-visible work ends at **6.2.0**. Do not raise
`kDefaultMinClientVersion`. No SQL migration. Never edit generated files.
Never introduce a `Request` domain entity. User-facing copy: Request / Chat.

## Worker protocol

Every worker must:

1. Read the complete current journal before inspecting or editing.
2. Read the assigned plan unit and architecture rev 3.
3. Inspect live code before trusting plan line numbers.
4. Preserve all protected pre-existing changes. Stage explicit owned paths
   only.
5. Never edit generated files or expose secrets. Never push.
6. Append a checkpoint after meaningful progress or an unexpected finding.
7. After each completed coherent implementation step and its relevant
   verification, commit owned changes immediately with a focused message.
   Do not defer commits until the end of the unit.
8. Append a final UNIT entry before exit using the template below.

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
REMAINING: <specific work, or none>
```

## Unresolved decisions and blockers

None at start. Architecture rev 3 is frozen. If live code contradicts a
frozen contract, stop that unit with `BLOCKED` instead of improvising.

## Manager checkpoints

- 2026-08-14 manager: scope established. `cursor-agent --list-models`
  confirms `composer-2.5`. Baseline matches plan §1. UNIT 00 assigned to a
  fresh session.
- 2026-08-14 manager: **UNIT 00 accepted**. Commit `a72580baf`
  (`docs: start issue 110 implementation journal`). Journal-only; protected
  worktree unchanged. Worker used local `--amend` to stabilize the COMMITS
  line (unpushed, docs-only). UNIT 01 authorized.
- 2026-08-14 manager: **UNIT 01 accepted**. Commit `a25b58acb`
  (`feat: add forward draft policy helpers`). Independent re-run:
  `flutter test test/features/forward/forward_draft_policy_test.dart` →
  14 passed. No Flutter import. Frozen signatures match. UNIT 02 authorized.
- 2026-08-14 manager: **UNIT 02 accepted**. Commit `e80268198`
  (`fix(server): refuse cancel after recipient decline`). Independent re-run:
  `dart test test/domain/use_case/forward_case_test.dart --name "cancelForward"`
  → 8 passed, including `returns false when recipientRejected`. Guard sits
  after `recipientReadAt` and before `existsWithParent`. UNIT 03 authorized.
- 2026-08-14 manager: **UNIT 03 accepted**. Commits `9efb6902c` (server DTO/GQL),
  `fa8c2b950` (client map + fixture compile), `cb0ee07ab` (journal).
  Independent: server involvement 7 passed; client map 9 passed.
  `hasOnwardChild`/`recipientRejected` are non-null on GQL + schema.
  No migration. UNIT 04 authorized.
- 2026-08-14 worker: **UNIT 03 complete**. Commits `9efb6902c`
  (`feat(server): add hasOnwardChild and recipientRejected to MyForwardRecipient`),
  `fa8c2b950` (`feat(client): map involvement cancel flags`). Server:
  `childParentIds` computed in-memory from fetched edges; client typedef extended
  with two `Map<String, bool>` fields. UNIT 04 authorized.
- 2026-08-14 worker: **UNIT 04 complete**. Commit `48e12886d`
  (`feat: plumb forward cancel and toast flags`).

## Unit entries

## UNIT 00 — complete — 2026-08-14
COMMITS: docs: start issue 110 implementation journal (see `git log -1`)
TESTS:
- `git rev-parse HEAD` → `5bfbefb77ff37ec7dbafc66e3ed39846fda2545a`
- `git branch --show-current` → `main`
- `git status --short` → matches protected worktree list above (journal was `??`, now committed)
- `ls packages/server/lib/data/database/migration/m014*.dart` → tail `m0149`; `ls m015*.dart` → none
- `grep ^version: packages/client/pubspec.yaml` → `6.1.1`
- `grep flutter_bootstrap.js packages/client/web/index.html` → `?v=6.1.1`
- `grep kDefaultMinClientVersion packages/server/lib/env.dart` → `'6.0.0'`
- Stop-condition code inspection (ForwardCubit.embedded, beacon_create `sendRequest`, HomeTabReselectCubit, InboxCubit GetIt) → all match plan §1 baseline
FILES: `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — live baseline matches plan §1 and manager stub; architecture source rev 3 confirmed in `issue-110-forward-explicit-architecture.md`
REMAINING: none — UNIT 01 may start

## UNIT 01 — complete — 2026-08-14
COMMITS: feat: add forward draft policy helpers (see `git log -1`)
TESTS:
- `cd packages/client && flutter test test/features/forward/forward_draft_policy_test.dart` → 14 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0
FILES:
- `packages/client/lib/features/forward/domain/forward_draft_policy.dart`
- `packages/client/test/features/forward/forward_draft_policy_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — frozen contracts matched architecture rev 3 §Domain functions
REMAINING: none — UNIT 02 may start

## UNIT 02 — complete — 2026-08-14
COMMITS: fix(server): refuse cancel after recipient decline (see `git log -1`)
TESTS:
- `cd packages/server && dart test test/domain/use_case/forward_case_test.dart --name "cancelForward"` → 8 passed
- `./scripts/check-custom-lints.sh packages/server` → exit 0
FILES:
- `packages/server/lib/domain/use_case/forward_case.dart`
- `packages/server/test/domain/use_case/forward_case_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — `ForwardEdgeEntity.recipientRejected` already present with `@Default(false)`
REMAINING: none — UNIT 03 may start

## UNIT 03 — complete — 2026-08-14
COMMITS:
- `9efb6902c` feat(server): add hasOnwardChild and recipientRejected to MyForwardRecipient
- `fa8c2b950` feat(client): map involvement cancel flags
TESTS:
- `cd packages/server && dart test test/domain/use_case/beacon_involvement_case_test.dart` → 7 passed
- `./scripts/check-custom-lints.sh packages/server` → exit 0
- `cd packages/client && flutter test test/features/forward/forward_repository_involvement_test.dart` → 9 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0
FILES:
- `packages/server/lib/domain/entity/gql_public/beacon_involvement_result.dart`
- `packages/server/lib/domain/use_case/beacon_involvement_case.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/lib/api/controllers/graphql/mappers/gql_v2_dto_maps.dart`
- `packages/server/test/domain/use_case/beacon_involvement_case_test.dart`
- `packages/client/lib/data/gql/schema.graphql`
- `packages/client/lib/features/forward/data/gql/beacon_involvement_data.graphql`
- `packages/client/lib/features/forward/data/repository/forward_repository.dart`
- `packages/client/test/features/forward/forward_repository_involvement_test.dart`
- `packages/client/test/features/forward/*` (12 fixture files updated for typedef compile)
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — frozen contract matched architecture rev 3 D14
REMAINING: none — UNIT 04 may start

## UNIT 04 — complete — 2026-08-14
COMMITS: feat: plumb forward cancel and toast flags (see `git log -1`)
TESTS:
- `cd packages/client && flutter test test/features/forward/forward_compute_involvement_test.dart test/features/forward/forward_repository_involvement_test.dart` → 28 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0
FILES:
- `packages/client/lib/features/forward/domain/entity/forward_candidate.dart`
- `packages/client/lib/features/forward/domain/entity/forward_load.dart`
- `packages/client/lib/features/forward/domain/use_case/forward_case.dart`
- `packages/client/test/features/forward/forward_repository_involvement_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — frozen contract matched architecture rev 3 D14 cancel/toast plumbing
REMAINING: none — UNIT 05 may start
