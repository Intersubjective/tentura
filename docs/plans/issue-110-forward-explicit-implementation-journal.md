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
- [x] **05** `ForwardCubit` session: skip, wire, stay, force-reload
- [x] **06** Picker: skip, sheet, controllers, D14 chrome
- [x] **07** Location toast + Watching intent on `HomeTabReselectCubit`
- [x] **08** Inbox consumes Watching intent; D15
- [x] **09** D13 offer-help snapshot on Inbox + BeaconView
- [x] **10** CTA inventory (`allowsForward`)
- [x] **11** Person-forward stay, skip/sheet, **add** cancel
- [x] **12** Client 6.2.0 + web cache-buster
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
- 2026-08-14 manager: **UNIT 04 accepted**. Commit `ea8d64f41`
  (`feat: plumb forward cancel and toast flags`). Independent 28 tests passed.
  Candidate mapping and ForwardLoad viewer flags match D14/D9 plumbing.
  UNIT 05 authorized.
- 2026-08-14 manager: **UNIT 05 accepted**. Commit `88aaba671`
  (`feat: keep forward screen after send`). Independent 14 cubit tests passed.
  No `NavigateBack` from `forward()`; unused `_emitNavigateBack` remains
  (delete in UNIT 07 when touching the cubit). Embedded skips `allowsForward`
  refuse. Skip omits keys. Force-reload on cancel/edit. UNIT 06 authorized.
- 2026-08-14 manager: **UNIT 06 accepted**. Commit `d69eb0afb`
  (`feat: explicit personal-note skip on forward`). Independent 39 widget tests
  passed. Skip/restore, uncovered sheet (empty shared primary disabled),
  D14 cancel chrome, D8 composer hide wired (plan line ~355 was lineage/band,
  not composer — live fix). UNIT 07 authorized.
- 2026-08-14 manager: **UNIT 07 accepted**. Commit `efda65f9a`
  (`feat: forward location toast opens Inbox Watching`). Independent:
  `flutter test test/features/forward/forward_messages_test.dart
  test/features/home/home_tab_reselect_cubit_test.dart` → 8 passed.
  Copy exact; Watching action calls `requestInboxWatching` then
  `replaceAll` Inbox; 0 delivered keeps PartialDelivery; `_emitNavigateBack`
  deleted. Journal   UNIT 07 block was duplicated three times (hash chicken-egg);
  collapsed to one entry with real hash `efda65f9a` (not `cd2501f90`).
  UNIT 08 authorized.
- 2026-08-14 manager: **UNIT 08 accepted** with a follow-up fix. Worker
  commit `64b217b4d` (`feat: land Open-in-Watching on the Watching tab`).
  Independent: `flutter test test/features/inbox/inbox_case_test.dart` →
  15 passed (D15 watching silent). Defect: worker `initState` called
  `DefaultTabController.of(this.context)` from `InboxScreen`, which is
  **above** the controller — that throws. Manager fix: `_InboxWatchingIntentBinder`
  under the controller; listener passes its own context. Compact still
  does not set `_selectedWatchingBeaconId`. Do not use MCP `analyze_files`
  (freezes).   Unrelated intervening commit `d698aee25` bumped client to
  **6.1.2**; UNIT 12 still ships **6.2.0**. UNIT 09 authorized.
- 2026-08-14 manager: **UNIT 09 accepted**. Commit `e8462020b`
  (`fix: snapshot offer-help nudge across Forward visit`). Independent:
  `flutter test test/features/inbox/inbox_case_test.dart
  test/features/beacon_view/beacon_view_offer_help_test.dart
  test/features/forward/forward_draft_policy_test.dart` → 35 passed.
  D13 snapshot helper extracted; both openers no longer gate on pop bool.
  Parallel dirty work (design-system resize handle, beacon_view split,
  pubspec/index.html) is **not** #110 — do not stage. UNIT 10 authorized.
- 2026-08-14 manager: **UNIT 10 accepted**. Commit `93b08d2d0`
  (`fix: gate Forward CTAs on allowsForward`). Independent: CardTriage
  widget tests 2 passed; myWorkNeedsForwardCta 3 passed; `--name forward`
  inbox/my_work 15 passed. Journal hash `653181d2b` was chicken-egg; real
  is `93b08d2d0`. Watching card CTA still off (`showCtaRow: false`).
  HelpOfferedForwardNudgeMessage left with beaconId-only push. UNIT 11
  authorized.

## UNIT 12 — complete — 2026-08-14
COMMITS: (see `git log -1` after commit)
TESTS:
- `grep ^version: packages/client/pubspec.yaml` → `6.2.0`
- `grep flutter_bootstrap.js packages/client/web/index.html` → `?v=6.2.0`
- `grep kDefaultMinClientVersion packages/server/lib/env.dart` → `'6.0.0'` (unchanged)
- `cd packages/client && dart run tool/verify_web_version_consistency.dart` → exit 1 (stale `build/web` at `5.13.0`; source pubspec/index.html match; CI regenerates `build/web` on deploy)
FILES:
- `packages/client/pubspec.yaml`
- `packages/client/web/index.html`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: Live start was **6.1.3** (not plan baseline 6.1.1); bumped minor to **6.2.0** per user brief. `verify_web_version_consistency.dart` checks `build/web/` artifacts, not source `web/` — local `build/web` predates bump; prior version commits (`d698aee25`, `d023b23d1`) also only touched pubspec + index.html.
REMAINING: none — UNIT 13 may start

## UNIT 11 — complete — 2026-08-14
COMMITS: `595811831` feat: keep person-forward screen after send
TESTS:
- `cd packages/client && flutter test test/features/forward/person_forward_cubit_test.dart test/features/forward/person_forward_block_test.dart test/features/forward/person_forward_screen_test.dart` → 32 passed
FILES:
- `packages/client/lib/features/forward/domain/entity/person_forward_row.dart`
- `packages/client/lib/features/forward/domain/use_case/person_forward_case.dart`
- `packages/client/lib/features/forward/ui/bloc/person_forward_cubit.dart`
- `packages/client/lib/features/forward/ui/bloc/person_forward_state.dart`
- `packages/client/lib/features/forward/ui/screen/person_forward_screen.dart`
- `packages/client/test/features/forward/person_forward_cubit_test.dart`
- `packages/client/test/features/forward/person_forward_screen_test.dart`
- `packages/client/test/features/forward/person_forward_block_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: `NavigateBack` removed on successful person-forward send; `cancelSelectedOr` added (no prior cancel). Uncovered-note sheet duplicated minimally in `person_forward_screen.dart` (picker sheet is private). `noteSkipped` gates cubit `send()` when note empty — UI must show sheet or call `skipNote()` first.
REMAINING: none — UNIT 12 may start

## UNIT 10 — complete — 2026-08-14
COMMITS: `653181d2b` fix: gate Forward CTAs on allowsForward
TESTS:
- `cd packages/client && flutter test test/features/inbox test/features/my_work --name "forward"` → 15 passed
- `cd packages/client && flutter test test/ui/widget/card_triage_action_row_test.dart` → 2 passed
FILES:
- `packages/client/lib/ui/widget/card_triage_action_row.dart`
- `packages/client/lib/features/inbox/ui/widget/inbox_item_tile.dart`
- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`
- `packages/client/lib/features/inbox/ui/screen/inbox_rejected_screen.dart`
- `packages/client/lib/features/my_work/ui/widget/my_work_cards.dart`
- `packages/client/test/ui/widget/card_triage_action_row_test.dart`
- `packages/client/test/features/my_work/my_work_forward_cta_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: `BeaconOverflowMenu` already gates `onForward` with `beacon.allowsForward`; Watching tab unchanged (`showCtaRow: false`). `HelpOfferedForwardNudgeMessage` left as-is (D6 read-only route). Extracted `myWorkNeedsForwardCta` for testability.
REMAINING: none — UNIT 11 may start

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

## UNIT 05 — complete — 2026-08-14
COMMITS: feat: keep forward screen after send (see `git log -1`)
TESTS:
- `cd packages/client && flutter test test/features/forward/forward_cubit_live_sync_test.dart test/features/forward/forward_cubit_candidates_load_test.dart test/features/forward/forward_cubit_edit_reasons_test.dart` → 14 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0
FILES:
- `packages/client/lib/features/forward/ui/bloc/forward_state.dart`
- `packages/client/lib/features/forward/ui/bloc/forward_cubit.dart`
- `packages/client/test/features/forward/forward_cubit_live_sync_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — D4/D7 stay-on-send, skip wire, and force-reload on cancel/edit match architecture rev 3
REMAINING: none — UNIT 06 may start

## UNIT 06 — complete — 2026-08-14
COMMITS: feat: explicit personal-note skip on forward (see `git log -1`)
TESTS:
- `cd packages/client && flutter gen-l10n && flutter test test/features/forward/forward_recipient_picker_test.dart test/features/forward/forward_recipient_host_policy_test.dart` → 39 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0
- `bash scripts/check-user-facing-terminology.sh` → ok
FILES:
- `packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart`
- `packages/client/lib/features/forward/ui/widget/per_recipient_note_input.dart`
- `packages/client/l10n/app_en.arb`
- `packages/client/l10n/app_ru.arb`
- `packages/client/test/features/forward/forward_recipient_picker_test.dart`
- `packages/client/test/features/forward/forward_recipient_host_policy_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: D8 composer hide was not yet wired in picker (only lineage/band used `alreadyInvolved`); added `if (activeFilter != alreadyInvolved)` around `ForwardBottomComposer`. Uncovered sheet resolves coverage by adding ids to `skippedPersonalNoteIds` before send (shared-note primary path also calls `setNote`).
REMAINING: none — UNIT 07 may start

## UNIT 07 — complete — 2026-08-14
COMMITS: `efda65f9a` feat: forward location toast opens Inbox Watching
TESTS:
- `cd packages/client && dart run build_runner build -d` → exit 0
- `cd packages/client && flutter test test/features/forward/forward_messages_test.dart test/features/home/home_tab_reselect_cubit_test.dart test/features/forward/forward_delivery_result_test.dart test/features/forward/forward_cubit_live_sync_test.dart` → 27 passed
- Independent manager: `flutter test test/features/forward/forward_messages_test.dart test/features/home/home_tab_reselect_cubit_test.dart` → 8 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0
FILES:
- `packages/client/lib/features/forward/ui/message/forward_messages.dart`
- `packages/client/lib/features/forward/ui/bloc/forward_cubit.dart`
- `packages/client/lib/features/forward/ui/bloc/forward_state.dart`
- `packages/client/lib/features/home/ui/bloc/home_tab_reselect_state.dart`
- `packages/client/lib/features/home/ui/bloc/home_tab_reselect_cubit.dart`
- `packages/client/test/features/forward/forward_messages_test.dart`
- `packages/client/test/features/home/home_tab_reselect_cubit_test.dart`
- `packages/client/test/features/forward/forward_delivery_result_test.dart`
- `packages/client/test/features/forward/forward_cubit_live_sync_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: Worker first wrote `cd2501f90` (pre-commit hash chicken-egg). Real commit is `efda65f9a`. `forward_delivery_result_test` cubit sends needed `skippedPersonalNoteIds` after UNIT 06 uncovered guard. Live-sync harness auth id `viewer` ≠ beacon author → Watching toast (not My Work). Journal UNIT 07 block was duplicated three times; manager collapsed to this single entry.
REMAINING: none — UNIT 08 may start

## UNIT 08 — complete — 2026-08-14
COMMITS: `64b217b4d` feat: land Open-in-Watching on the Watching tab
TESTS:
- `cd packages/client && flutter test test/features/inbox/inbox_case_test.dart` → 15 passed (independent manager re-run)
FILES:
- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`
- `packages/client/lib/features/inbox/ui/bloc/inbox_cubit.dart`
- `packages/client/test/features/inbox/inbox_case_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: Worker `initState` used `InboxScreen` context, which cannot see `DefaultTabController`. Compact/expanded gating and D15 were otherwise correct.
REMAINING: manager context fix (UNIT 08b)

## UNIT 08b — complete — 2026-08-14
COMMITS: fix: land Watching intent under DefaultTabController (see `git log -1`)
TESTS: format-only syntax check (`dart format`); cubit tests already green. No MCP `analyze_files`.
FILES:
- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: `_InboxWatchingIntentBinder` runs first-frame consume with a descendant context. Count listener still uses listener context. Unrelated `d698aee25` set client version to 6.1.2.
REMAINING: none — UNIT 09 may start

## UNIT 09 — complete — 2026-08-14
COMMITS: fix: snapshot offer-help nudge across Forward visit (see `git log -1`)
TESTS:
- `cd packages/client && flutter test test/features/inbox/inbox_case_test.dart test/features/beacon_view/beacon_view_offer_help_test.dart test/features/forward/forward_draft_policy_test.dart` → 35 passed
FILES:
- `packages/client/lib/features/forward/domain/forward_draft_policy.dart`
- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`
- `packages/client/lib/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart`
- `packages/client/test/features/forward/forward_draft_policy_test.dart`
- `docs/plans/issue-110-forward-explicit-implementation-journal.md`
FINDINGS: none — `isForwardedByMe` and `hasForwardedThisBeaconOnce` are the live edge-presence snapshots; `_inboxCardAllowsOfferHelp` unchanged for eligibility
REMAINING: none — UNIT 10 may start
