# Person Selector Hardening — Implementation Journal

## Objective

Implement `docs/plans/person-selector-hardening-plan.md` (issue
https://github.com/Intersubjective/tentura/issues/103): fix three
person-selector bugs (error flash / false-empty message on the request
Recipients tab, lost/disabled Promise recipient picker, raw UUID leaking as
a person's name) via explicit mutually-exclusive loading/empty/error/ready
state instead of conflated booleans.

## Repository / branch

- Repo: `/home/vader/MY_SRC/tentura`
- Branch: `person-selector-hardening` (created off `main` at HEAD below,
  specifically to isolate this plan's automated commits)
- Starting HEAD: `560d037bfd2286bf6c757400290c24aac3d1b16c`
  ("Show graph hidden-neighbor badges on all nodes again.")

## Pre-existing worktree changes (untracked, NOT part of this plan — never
edit, delete, or commit these)

```
?? dart-defines
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
```

`key.fb` / `out.key` look like they may be key material — do not read,
move, print, or commit them under any circumstance.

`docs/plans/person-selector-hardening-plan.md` and this journal file are
part of this plan's own scope (tracked as new files, expected to be
committed alongside the first unit that touches `docs/plans/`, or in their
own small doc commit — worker's judgment, but do commit them so the branch
is self-contained).

## Ordered unit checklist

| # | Unit | Status |
|---|------|--------|
| 1 | Canonical, never-raw-id display helper | complete |
| 2 | Explicit candidate-load state for `ForwardCubit`/`ForwardState` | pending |
| 3 | Fix Recipients-tab open race + gate routing banner | pending |
| 4 | Explicit participants-load state for Promise/beacon-room picker | pending |
| 5 | Tests | pending |
| 6 | Integration and close-out | pending |

Full unit descriptions, root-cause evidence, and acceptance criteria are in
`docs/plans/person-selector-hardening-plan.md` — read it in full before
starting any unit.

## Verification commands (from the plan)

- `cd packages/client && flutter test` (full suite before declaring a unit
  or the plan done)
- `./scripts/check-custom-lints.sh packages/client` — the analyzer +
  tentura_lints gate. Do **not** use `flutter analyze` or `dart analyze
  <subdir>` for lint rules — they silently skip plugin diagnostics in this
  repo.
- `bash scripts/check-user-facing-terminology.sh` — required if any l10n
  string changes (Unit 1, Unit 3).

## Unresolved decisions / blockers

None yet.

## Checkpoints

### Unit 1 — Canonical display helper (2026-08-04)

**Changed:** `Profile.displayLabel`, `BeaconParticipant` extension `displayLabel`,
`l10n.unknownPerson` (en/ru), call sites in `coordination_target_candidates.dart`,
`recipients_tab.dart`, `coordination_participant_lookup.dart` (+ `participantDisplayLabel`,
handle on participant→Profile mapping). Client `5.6.29`.

**Decision:** `BeaconParticipant.displayLabel` is an extension, not a class method —
freezed generates `implements BeaconParticipant` (not `extends`), so custom methods
on the abstract class are not inherited by `_BeaconParticipant`.

**Tests:** `flutter test test/features/beacon_view/coordination_target_candidates_test.dart`
— 11 passed; `./scripts/check-custom-lints.sh packages/client` — ok;
`bash scripts/check-user-facing-terminology.sh` — ok.

(Workers: append below, most recent last. Include unit #, what changed,
commits, test results, and any decision you made that a later unit or the
manager needs to know about.)
