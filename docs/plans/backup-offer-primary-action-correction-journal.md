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
- [x] P2 — client: People-tab badge wording + backup-offer confirmation copy
- [ ] P3 — server: distinct notification copy for backup offers
- [ ] P4 — server: regression tests locking in points 5/7/8
- [ ] P5 — docs: status-quo + beacon_room.md updates

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
