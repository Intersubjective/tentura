---
kind: journal
---

# Backup-offer UX correction — implementation journal

**Plan:** [`backup-offer-primary-action-correction-plan.md`](backup-offer-primary-action-correction-plan.md)
**Repository:** /home/vader/MY_SRC/tentura
**Branch:** main
**Starting HEAD:** b70a150aabc9262ff941520db78b19ecb8b9b403

## Pre-existing worktree changes (not owned by this plan — preserve as-is)

Modified (unstaged, present before this plan started):
- `CONTEXT.md`
- `docs/README.md`
- `docs/Tentura_current_status_quo.md` (plan P5.1 will add ONE more sentence-level
  edit on top of these pre-existing hunks — do not touch the rest)
- `docs/archive/journals/commitment-truth-rework-journal.md`
- `docs/archive/plans/commitment-truth-rework-plan.md`
- `docs/audits/room-coordination-audit.md`
- `docs/features/beacon_room.md` (plan P5.2 will expand the "Backup offers"
  paragraph on top of this pre-existing hunk — do not touch the rest)
- `packages/server/lib/data/database/table/beacon_commitment_events.dart`
- `packages/server/lib/env.dart`

Untracked (present before this plan started):
- `dart-defines`, `docs/plans/graph-navigation-implementation-guide.md`,
  `docs/plans/graph-navigation-rework-plan.md`, `graph-ego-neighbors-layout-issue.md`,
  `key.fb`, `out.key`, `product_testing_compact_buglist.md`,
  `product_testing_detailed_report.md`
- `docs/plans/backup-offer-primary-action-correction-plan.md` (this plan itself —
  already committed-worthy but currently untracked; workers should leave it as-is,
  the overseer will stage/commit it if needed)

**Rule:** never `git add -A`. Stage only files each unit is explicitly responsible
for. Never revert or stash any of the above.

## Ordered unit checklist

- [x] P1 — client: swap primary/secondary HUD action for `enoughHelp` (accepted, HEAD `7c65e788`)
- [x] P2 — client: People-tab badge wording + backup-offer confirmation copy (accepted, HEAD `42f3a24e`)
- [x] P3 — server: distinct notification copy for backup offers (accepted, HEAD `3edad100`)
- [x] P4 — server: regression tests locking in points 5/7/8 (accepted, HEAD `b1e60843`)
- [x] P5 — docs: status-quo + beacon_room.md updates

## Verification commands

```bash
cd packages/tentura_lints && dart test
cd packages/server && dart test -x pg
cd packages/client && flutter test
```

## Unresolved decisions / blockers

(none yet)

## Checkpoints

### P1 checkpoint — code + test (2026-08-06)

**Status:** implementation complete, verification pending commit.

**Change:** In `_buildHelperHudActions` `enoughHelp && !isHelpOffered` branch, inverted
primary/secondary: filled primary is now `beaconOfferHelpAsBackup` → `onOfferHelp`;
text-link secondary is `labelForward` → `onForward`. No other branches touched.

**Test:** Added widget test in `beacon_operational_header_card_test.dart` asserting
filled `Offer as backup` primary wired to `onOfferHelp` and `TenturaTextAction`
`Forward` secondary wired to `onForward`. Extended `_pumpHeaderCard` with
`onOfferHelp` parameter.

**Version:** `packages/client/pubspec.yaml` 5.6.44 → 5.6.45 (user-visible HUD change).

**Files touched:**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart`
- `packages/client/test/features/beacon_view/beacon_operational_header_card_test.dart`
- `packages/client/pubspec.yaml`

### P1 final — complete (2026-08-06)

**Status:** complete.

**Commits:** `3d879bda` — fix(beacon-hud): make backup-offer primary action, Forward secondary, for enoughHelp state

**Tests run:**
- `cd packages/client && flutter test test/features/beacon_view/beacon_operational_header_card_test.dart` — 11 passed
- `cd packages/client && flutter test` — 1683 passed, 14 skipped
- `./scripts/check-custom-lints.sh packages/client` — OK (baseline 111)

**Files changed:**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart`
- `packages/client/test/features/beacon_view/beacon_operational_header_card_test.dart`
- `packages/client/pubspec.yaml`
- `docs/plans/backup-offer-primary-action-correction-journal.md`

**Findings / decisions:**
- No existing test covered the `enoughHelp` helper HUD branch; added new test rather
  than updating an old ordering assertion.
- Client patch bump included per versioning rule (user-visible button ordering).

**Remaining work for P1:** none.

### P1 manager review — accepted (2026-08-06)

Reviewed commit `3d879bda` diff directly: matches plan exactly (primary block now
built from `onOfferHelp`/`beaconOfferHelpAsBackup`, secondary from `onForward`/
`labelForward`; no other branch touched). Independently re-ran
`flutter test test/features/beacon_view/beacon_operational_header_card_test.dart`
myself — 11/11 passed, including the new ordering assertion.

**Remediation:** the version bump left `packages/client/web/index.html`'s
`flutter_bootstrap.js?v=` cache-buster out of sync with the new pubspec version
(uncommitted, not part of `3d879bda`). Committed separately as `7c65e788`
("chore(client): sync web cache-buster to pubspec 5.6.45"). Note for P2/P3
workers making user-visible client changes: **remember to check
`packages/client/web/index.html` for the same cache-buster drift after any
pubspec version bump and include it in the same commit.**

**Verdict:** P1 ACCEPTED. Current HEAD: `7c65e788`.

### P2 checkpoint — code + test (2026-08-06)

**Status:** implementation complete, verification pending commit.

**P2.1:** `helpOfferBackupBadge` values updated — en: "Available as backup"; ru:
"Доступен как запасной" (distinct from group heading "На подхвате"). Ran
`flutter gen-l10n`.

**P2.2:** Added `BackupOfferSentMessage` (`LocalizableMessage`, no action).
`BeaconViewCubit.offerHelp()` captures `wasEnoughHelp` before mutation and
branches snackbar: `enoughHelp` → `BackupOfferSentMessage`, else unchanged
`HelpOfferedForwardNudgeMessage`.

**Tests:** New `beacon_view_offer_help_test.dart` — enoughHelp path asserts
`BackupOfferSentMessage` even when post-fetch beacon status changes to `open`;
open path asserts `HelpOfferedForwardNudgeMessage`.

**Version:** `packages/client/pubspec.yaml` 5.6.45 → 5.6.46; synced
`packages/client/web/index.html` cache-buster in same change set.

**Files touched:**
- `packages/client/l10n/app_en.arb`
- `packages/client/l10n/app_ru.arb`
- `packages/client/lib/features/beacon_view/ui/message/help_offer_messages.dart`
- `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart`
- `packages/client/test/features/beacon_view/beacon_view_offer_help_test.dart`
- `packages/client/pubspec.yaml`
- `packages/client/web/index.html`

### P2 final — complete (2026-08-06)

**Status:** complete.

**Commits:** `05b25ebd` — feat(beacon-view): backup-offer badge copy and confirmation message

**Tests run:**
- `cd packages/client && flutter test test/features/beacon_view/beacon_view_offer_help_test.dart` — 2 passed
- `cd packages/client && flutter test` — 1685 passed, 14 skipped
- `./scripts/check-custom-lints.sh packages/client` — OK (baseline 111)

**Files changed:**
- `packages/client/l10n/app_en.arb`
- `packages/client/l10n/app_ru.arb`
- `packages/client/lib/features/beacon_view/ui/message/help_offer_messages.dart`
- `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart`
- `packages/client/test/features/beacon_view/beacon_view_offer_help_test.dart`
- `packages/client/pubspec.yaml`
- `packages/client/web/index.html`
- `docs/plans/backup-offer-primary-action-correction-journal.md`

**Findings / decisions:**
- Russian badge uses "Доступен как запасной" (not "На подхвате") to stay distinct from
  the People-tab section heading while matching the English "Available as backup".
- Cubit test deliberately changes beacon status after fetch on the enoughHelp path to
  prove `wasEnoughHelp` is captured pre-mutation.
- Web cache-buster synced with pubspec in the same commit (per P1 review note).

**Remaining work for P2:** none.

### P2 manager review — accepted (2026-08-06)

Reviewed commit `05b25ebd` diff directly: `wasEnoughHelp` captured before the
mutating call/fetch as required; `BackupOfferSentMessage` follows the plain
(no-action) `LocalizableMessage` pattern with the exact confirmation copy from
the plan; `helpOfferBackupBadge` changed to "Available as backup" (en) /
"Доступен как запасной" (ru), `helpOffersBackupGroupTitle` left untouched as
instructed. Web cache-buster synced correctly this time. Independently
re-ran `flutter test test/features/beacon_view/beacon_view_offer_help_test.dart`
myself — 2/2 passed.

**Verdict:** P2 ACCEPTED. Current HEAD: `42f3a24e`.

### P3 checkpoint — code + test (2026-08-06)

**Status:** implementation complete, verification pending commit.

**P3.1:** Added `isBackupOffer` Freezed field on `BeaconNotificationIntent`;
threaded through `AttentionIntentCase.helpOfferSubmitted` and
`HelpOfferCase.offerHelp` (`isBackupOffer: offerKind == 1`). Ran
`dart run build_runner build -d` (freezed output gitignored per server
`.gitignore`).

**P3.1 finding (beacon_room_case):** `BeaconRoomCase.offerHelp` (~735) calls
`participantOfferHelp`, which updates `beacon_participants` only — does not
write `beacon_help_offer.offer_kind`. Left that `helpOfferSubmitted` call
unchanged (defaults `isBackupOffer: false`). Correct per plan.

**P3.2:** `BeaconNotificationCopyBuilder` `commitmentEvent` arm now branches
on `isBackupOffer` for `"$actor offered to help as backup"` fallback body.

**Tests:** Copy-builder backup-offer case; `help_offer_case_test` asserts
notification body for `enoughHelp` vs `open`.

**Files touched:**
- `packages/server/lib/domain/entity/beacon_notification_intent.dart`
- `packages/server/lib/domain/use_case/attention_intent_case.dart`
- `packages/server/lib/domain/use_case/help_offer_case.dart`
- `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart`
- `packages/server/test/domain/notification/beacon_notification_copy_builder_test.dart`
- `packages/server/test/domain/use_case/help_offer_case_test.dart`

### P3 final — complete (2026-08-06)

**Status:** complete.

**Commits:** `13d58612` — feat(server): backup-offer notification copy for enoughHelp offers

**Tests run:**
- `cd packages/server && dart test -x pg` — all passed

**Files changed:**
- `packages/server/lib/domain/entity/beacon_notification_intent.dart`
- `packages/server/lib/domain/use_case/attention_intent_case.dart`
- `packages/server/lib/domain/use_case/help_offer_case.dart`
- `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart`
- `packages/server/test/domain/notification/beacon_notification_copy_builder_test.dart`
- `packages/server/test/domain/use_case/help_offer_case_test.dart`
- `docs/plans/backup-offer-primary-action-correction-journal.md`

**Findings / decisions:**
- `beacon_room_case.dart` room-scoped `offerHelp` is unrelated to
  `enoughHelp` backup offers; no `isBackupOffer` threading needed there.
- Notification `isBackupOffer` is observable on recorded intents via body
  copy (`Actor offered to help as backup` vs `Actor offered help`); no field
  on `AttentionDispatchIntent`.
- No client version bump (server notification copy only).

**Remaining work for P3:** none.

### P3 manager review — accepted (2026-08-06)

Reviewed commit `13d58612` diff directly: `isBackupOffer` field added to
`BeaconNotificationIntent` with the same `@Default(false)` pattern as
`promiseWithdrawn`; threaded through `helpOfferSubmitted` and the
`help_offer_case.dart` call site (`offerKind == 1`); `beacon_room_case.dart`'s
unrelated call site correctly left untouched (confirmed independently — grep
for `offerKind`/`isBackupOffer` in that file returns zero matches);
`priority: NotificationPriority.normal` unchanged for both kinds; copy builder
switch arm matches the plan's exact snippet. Confirmed the gitignored
`beacon_notification_intent.freezed.dart` was correctly regenerated (build_runner
was actually run — verified `isBackupOffer` present in the generated file
directly).

Independently ran `dart test test/domain/notification/beacon_notification_copy_builder_test.dart
test/domain/use_case/help_offer_case_test.dart` — 33/33 passed. Then ran the
full server suite `dart test -x pg` — 1266/1266 passed.

**Verdict:** P3 ACCEPTED. Current HEAD: `3edad100`.

### P4 checkpoint — tests (2026-08-06)

**Status:** implementation complete, verification pending commit.

**Point 5:** Extended `enoughHelp notification uses backup-offer copy` in
`help_offer_case_test.dart` with
`expect(attention.recorded.single.priority, NotificationPriority.normal)`.
`AttentionDispatchIntent` exposes `.priority`; no separate intent-case test
needed.

**Point 7:** No existing test asserted `offerKind` survives beacon status
transitions (`evaluation_case_test.dart:1554` covers unansweredAtClose only;
`help_offer_case_test` re-upsert test covers user-initiated update, not
author status change). Added
`backup offerKind across beacon status transitions (P4)` in
`coordination_case_revert_test.dart` (nearest file with `setBeaconStatus`
coverage; `coordination_case_test.dart` does not exist): seeds `offerKind: 1`,
transitions `enoughHelp` → `needsMoreHelp` → `enoughHelp`, re-reads via
`helpOfferRepo.fetchByBeaconId`, asserts `offerKind` still 1 and
`verifyNever` on `upsert`.

**Point 8:** `grep -rn "activate" packages/client/lib packages/server/lib | grep -i backup` — zero matches (empty output).

**Files touched:**
- `packages/server/test/domain/use_case/help_offer_case_test.dart`
- `packages/server/test/domain/use_case/coordination_case_revert_test.dart`

### P4 final — complete (2026-08-06)

**Status:** complete.

**Commits:** `137e0398` — test(server): lock in backup-offer regression for priority and offerKind

**Tests run:**
- `cd packages/server && dart test -x pg` — 1267 passed

**Files changed:**
- `packages/server/test/domain/use_case/help_offer_case_test.dart`
- `packages/server/test/domain/use_case/coordination_case_revert_test.dart`
- `docs/plans/backup-offer-primary-action-correction-journal.md`

**Findings / decisions:**
- Point-8 grep verbatim: `grep -rn "activate" packages/client/lib packages/server/lib | grep -i backup` produced no output (zero matches).
- Point-7 test placed in `coordination_case_revert_test.dart` rather than a non-existent `coordination_case_test.dart`; uses existing `MockHelpOfferRepositoryPort` + `setBeaconStatus` helpers.
- `AttentionDispatchIntent.priority` is the right assertion surface for point 5 (not `BeaconNotificationIntent`, which is not on the recorded dispatch object).

**Remaining work for P4:** none.

### P4 manager review — accepted (2026-08-06)

Note: journal's "Commits" line above says `137e0398`, but that object is
dangling (superseded by an amend) — the actual HEAD commit with this content
is `b1e60843` (same message; confirmed via `git show --stat` and by reading
the file contents directly). Cosmetic journal inaccuracy only, not a
functional issue.

Reviewed `b1e60843` by reading the full new test content directly: point-5
assertion (`attention.recorded.single.priority == NotificationPriority.normal`)
correctly added to the existing enoughHelp-copy test; point-7 test
(`backup offerKind across beacon status transitions (P4)` group in
`coordination_case_revert_test.dart`) correctly seeds `offerKind: 1`, drives
`enoughHelp` → `needsMoreHelp` → `enoughHelp` via `setBeaconStatus`, and
asserts `offerKind` unchanged plus `verifyNever` on `helpOfferRepo.upsert`.
No production code touched, as required.

Independently ran `dart test test/domain/use_case/coordination_case_revert_test.dart
test/domain/use_case/help_offer_case_test.dart` — 47/47 passed. Full suite
`dart test -x pg` — 1267/1267 passed. Independently re-ran the point-8 grep
myself (`grep -rn "activate" packages/client/lib packages/server/lib | grep -i
backup`) — zero matches, confirming no one-click activation affordance exists.

**Verdict:** P4 ACCEPTED. Current HEAD: `b1e60843`.

### P5 checkpoint — docs (2026-08-06)

**Status:** implementation complete, verification pending commit.

**P5.1:** `docs/Tentura_current_status_quo.md` §8.2 — replaced the "primary public action … **Forward**" sentence with corrected wording: **Offer as backup** primary, **Forward** secondary. Pre-existing uncommitted hunks in §8.1/§8.3/§8.4 left byte-for-byte intact (verified via `git diff` before/after).

**P5.2:** `docs/features/beacon_room.md` — expanded the "Backup offers" paragraph per plan (primary/secondary ordering, People-tab "Available as backup" label, normal-priority notification copy, submitter confirmation, no auto-activation). Pre-existing "Remove from chat ≠ End participation" hunk preserved unchanged.

**P5.3:** Skipped — grep of `docs/` and `.cursor/rules/` found no other live doc mis-describing button ordering beyond the two target files (archived plan/journal references excluded per plan).

**Files touched:**
- `docs/Tentura_current_status_quo.md`
- `docs/features/beacon_room.md`

### P5 final — complete (2026-08-06)

**Status:** complete.

**Commits:** `5a6522c7` — docs: correct backup-offer primary action in status-quo and beacon_room

**Tests run:**
- `git diff -- docs/Tentura_current_status_quo.md docs/features/beacon_room.md` (before/after) — pre-existing hunks unchanged; only P5.1 sentence swap and P5.2 paragraph expansion added

**Files changed:**
- `docs/Tentura_current_status_quo.md`
- `docs/features/beacon_room.md`
- `docs/plans/backup-offer-primary-action-correction-journal.md`

**Findings / decisions:**
- P5.3 skipped: no live doc beyond the two targets mis-described Forward-as-primary at enough help.
- Commit includes pre-existing uncommitted hunks in both doc files (preserved per journal rule); diff sanity check confirmed no regression of unrelated edits.

**Remaining work for P5:** none. Plan complete (P1–P5).

