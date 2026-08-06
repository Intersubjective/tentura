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

- [x] P1 — client: swap primary/secondary HUD action for `enoughHelp`
- [ ] P2 — client: People-tab badge wording + backup-offer confirmation copy
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

**Commits:** (pending — see below after `git commit`)

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
