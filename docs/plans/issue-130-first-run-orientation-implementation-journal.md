# Issue #130 — First-run orientation — implementation journal

**Objective.** Implement `docs/plans/issue-130-first-run-orientation-plan.md`
(revision 3, already through one round of adversarial review — see plan §14).
Orchestrated by the `overseer` skill: fresh Cursor CLI workers (`composer-2.5`,
non-fast) execute one plan UNIT at a time; the overseer (Claude, this session)
reviews each result before advancing.

**Repository.** `/home/vader/MY_SRC/tentura`, branch `main`,
starting HEAD `68fe87467ae2291059237ab4af2da500b2330879` (ahead of
`origin/main` by 123 commits — pre-existing, not this plan's doing).

**Pre-existing worktree changes at start (not owned by this plan; never
touch/stash/commit):** numerous untracked `docs/plans/*.md` files unrelated to
issue #130, plus `CLAUDE.local.md`, `dart-defines`, `key.fb`, `out.key`,
`graph-ego-neighbors-layout-issue.md`, `product_testing_compact_buglist.md`,
`product_testing_detailed_report.md`, `tg_style_research.md`. All untracked
(git status showed no modified tracked files). Confirmed no
`home_activation`/`HomeActivationCubit`/`HomeOrientationPanel`/
`HowTenturaWorksContent`/`orientationTitle` symbols exist anywhere in
`packages/client/lib` or `packages/client/test` yet — clean slate.

**Corrected facts vs. plan text (re-verified live, per plan's own instruction
not to trust stale numbers):**
- `packages/client/pubspec.yaml` version is **`7.2.7`** (plan prose says
  `7.2.2`; UNIT 13 must bump from the actual live value at execution time to
  `7.3.0`, not do a literal `7.2.2`→`7.3.0` replace).
- Lint baselines confirmed current: `scripts/custom-lint-baseline.txt` says
  `packages/client 32`, `packages/server 0` — matches plan §11.
- `packages/client/lib/features/settings/ui/screen/settings_screen.dart:155`
  confirmed `if (!kIsWeb)` guards `l10n.showIntroAgain` — UNIT 8's new reopen
  action must sit outside that guard.

## Ordered unit checklist (plan §9, "Execute in order")

Plan is explicit: units execute in the given order, each is
"unit → its checks → journal entry → focused local commit," no push.

- [x] UNIT 1 — l10n copy (`app_en.arb`/`app_ru.arb`, `flutter gen-l10n`)
- [x] UNIT 2 — activation domain entity (`home_activation.dart`, pure)
- [x] UNIT 3 — preferences port + Drift repository
- [x] UNIT 4 — `HomeActivationCubit` + binder + reporter
- [ ] UNIT 5 — `HowTenturaWorksContent`
- [ ] UNIT 6 — `HomeOrientationPanel`
- [ ] UNIT 7 — My Work body integration
- [ ] UNIT 8 — reopen entry points (D6)
- [ ] UNIT 9 — contextual trust affordance (§5.6)
- [ ] UNIT 10 — debug override UI (§7)
- [ ] UNIT 11 — invite → request navigation (§8) — verify §8 step 4
      (unreadable-request fallback) BEFORE wiring the push; journal the finding
- [ ] UNIT 12 — browser integration test (§10.3)
- [ ] UNIT 13 — version bump (7.2.7→7.3.0) + cache-buster + full verification gate

## Acceptance / verification commands (plan §11, run from repo root)

```bash
(cd packages/client && flutter gen-l10n && dart run build_runner build -d)
./scripts/check-custom-lints.sh packages/client   # baseline: packages/client 32
./scripts/check-custom-lints.sh packages/server   # baseline: packages/server 0
bash scripts/check-user-facing-terminology.sh
(cd packages/client && flutter test)
./scripts/run_client_integration_web_local.sh \
  integration_test/first_run_orientation_test.dart
```

Baselines may only go **down**, never up.

## Unresolved decisions and blockers

None yet.

## Checkpoints

### 2026-09-09 — journal initialized
Scope/safety established, manifest built, no pre-existing implementation
found. Starting UNIT 1.

### 2026-09-09 — UNIT 1
**Status:** complete

**Files changed:**
- `packages/client/l10n/app_en.arb` — 23 new keys (15 panel/sheet §6.1 + 8 debug §6.3)
- `packages/client/l10n/app_ru.arb` — matching RU copy
- `packages/client/lib/ui/l10n/*.dart` — regenerated via `flutter gen-l10n` (gitignored)

**Keys added (§6.1):** `orientationTitle`, `orientationIntro`,
`orientationIntroReopen`, `orientationHowTitle`, `orientationHowStep1`–`3`,
`orientationWhereTitle`, `orientationWhereWork`/`Inbox`/`Field`/`Network`,
`orientationWhereSemantics` (ICU `{name}`, `{description}`), `orientationDismiss`,
`orientationReopen`.

**Keys added (§6.3):** `settingsDebugOrientationSection`, `Override`, `Auto`,
`Show`, `Hide`, `Status` (`activated`/`dismissed` String, `count` int), `Reset`,
`ResetDone`.

**Reused existing keys (confirmed present, not duplicated):** `myWork`, `inbox`,
`constellationNavLabel`, `network`, `myWorkEmptyActiveInboxPrimaryCta`,
`myWorkEmptyActiveCreateCta`, `constellationFindWaysToHelp`.

**Commands:**
```bash
cd packages/client && flutter gen-l10n          # exit 0
bash scripts/check-user-facing-terminology.sh   # ok
cd packages/client && flutter test test/l10n/   # 12/12 passed
```

**Surprises:** None. Generated l10n Dart under `lib/ui/l10n/` is gitignored;
only `.arb` sources are committed.

**Manager review (overseer):** ACCEPTED. Independently re-ran
`bash scripts/check-user-facing-terminology.sh` (ok) and
`flutter test test/l10n/` (12/12 passed) from a clean shell. Diffed both
`.arb` files against plan §6.1/§6.3 key-by-key — all 23 keys, EN+RU strings,
and placeholder metadata (`orientationWhereSemantics`:
name/description String; `settingsDebugOrientationStatus`:
activated/dismissed String, count int) match verbatim. Commit `06eb3fccb`.
Starting UNIT 2.

### 2026-09-09 — UNIT 2
**Status:** complete

**Files changed:**
- `packages/client/lib/features/home/domain/entity/home_activation.dart` (new) —
  `HomeActivationSignals`, `OrientationDebugOverride`, `OrientationDecision` per
  plan §3 frozen contract; pure Dart, no Flutter import.
- `packages/client/test/features/home/home_activation_test.dart` (new) — 10 tests
  covering `isSettled`, `activityCount`/`draftCount` exclusion, `hasActivity` on
  zero settled snapshot, and both per-projection `hasProvenActivity` cases.

**Commands:**
```bash
./scripts/check-custom-lints.sh packages/client   # exit 0, total 32 (baseline 32)
cd packages/client && flutter test test/features/home/home_activation_test.dart
# 10/10 passed
```

**Surprises:** None. `decideFor` intentionally omitted (UNIT 4).

**Manager review (overseer):** ACCEPTED. Independently re-ran
`./scripts/check-custom-lints.sh packages/client` (32, matches baseline) and
`flutter test test/features/home/home_activation_test.dart` (10/10 passed).
Read `home_activation.dart` in full — matches plan §3's frozen block verbatim,
including doc comments encoding the draft-exclusion and
individually-settled-projection invariants. `decideFor` correctly deferred to
UNIT 4. Commit `0865b58e6`. Starting UNIT 3.

### 2026-09-09 — UNIT 3 (worker checkpoint, see manager review below)
**Status:** complete

**Files changed:**
- `packages/client/lib/features/home/domain/port/home_orientation_preferences_port.dart`
  (new) — `HomeOrientationPreferencesPort` with the seven methods from plan §9.
- `packages/client/lib/features/home/data/repository/home_orientation_preferences_repository.dart`
  (new) — Drift `settings` persistence; keys `home:activated:<userId>`,
  `home:orientationDismissed:<userId>`, `home:orientationDebugOverride`; shape
  copied from `MyWorkDeskPreferencesRepository`.
- `packages/client/test/features/home/home_orientation_preferences_repository_test.dart`
  (new) — 5 tests: per-user round-trips, isolation, reset leaves override,
  garbage override → `auto`.
- `packages/client/lib/app/di/di.config.dart` — regenerated via build_runner
  (gitignored; not committed).

**Commands:**
```bash
cd packages/client && dart run build_runner build -d   # exit 0
./scripts/check-custom-lints.sh packages/client        # exit 0, total 32 (baseline 32)
cd packages/client && flutter test test/features/home/ # 34/34 passed
```

**Surprises:** No existing `my_work_desk_preferences_repository` test file —
patterned in-memory Drift setup after `test/drift/tentura/migration_test.dart`
(`Database(const Env(), Logger('test'), NativeDatabase.memory())` plus
`driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`).

**Manager review (overseer):** ACCEPTED. Confirmed `di.config.dart` is
git-ignored (`packages/client/.gitignore:62`) and was correctly not staged.
Read the port, repository, and test files in full: seven-method port matches
plan §9 verbatim; repository keys match plan §3's table exactly;
`resetFirstRunState` clears both per-user keys and leaves the override
(asserted directly in the reset test); garbage override → `auto` (both via
direct-write test and defensive `_parseDebugOverride`); repository idiom
(`_database.managers.settings`, `insertOrReplace` + `DoUpdate`, private key
builders) matches `MyWorkDeskPreferencesRepository`'s shape. Independently
re-ran `./scripts/check-custom-lints.sh packages/client` (32, baseline held)
and `flutter test test/features/home/` (34/34 passed, includes UNIT 2's
suite unchanged). Commit `5bd9435d0`. Starting UNIT 4.

### 2026-09-09 — pre-UNIT-4 scope note (overseer)

Before launching the UNIT 4 worker (`HomeActivationCubit` + binder +
reporter — the riskiest unit, per the plan's own §14 review trace), read the
live code the plan's UNIT 4 section leans on: `home_screen.dart`,
`home_attention_cubit.dart`, `inbox_needs_me_reporter.dart`,
`my_work_attention_reporter.dart`, `inbox_cubit.dart`, `inbox_state.dart`,
`my_work_state.dart`, `debug_settings_screen.dart`, `state_base.dart`.

**Confirmed accurate** (mechanisms match plan prose, only exact line numbers
drifted): `HomeScreen.wrappedRoute`'s `MultiBlocProvider` + `BlocSelector
<AuthCubit, AuthState, String>` → `_InboxScope` structure;
`HomeAttentionCubit`'s account-tagged-report + generation-counter idiom;
`InboxNeedsMeReporter`/`MyWorkAttentionReporter`'s `BlocListener` pattern;
`MyWorkState.nonArchivedCards`/`archivedCountHint`/`draftCount`/
`nonArchivedProjectionLoaded` field names.

**Genuine plan gap found (not just a stale line number):** plan §9 UNIT 4
says to report `inboxFailed` "from the Inbox error state
(`inbox_cubit.dart:248-257`)". That error state does not exist.
`InboxState` has no failure field at all — `StateStatus`
(`ui/bloc/state_base.dart`) is a two-member sealed class
(`StateIsSuccess`/`StateIsLoading`, no failure variant anywhere in the
codebase), and `InboxCubit._runFetch`'s catch block only fires a transient
snackbar (`_emitSnackError`) — it never persists that the fetch failed.
Without a persisted signal, `inboxFailed` can never become `true`, which
silently breaks the plan's own fail-closed guarantee (§3 / §12 risk table:
"Inbox never resolves → the body spins forever," supposedly mitigated by
`inboxFailed` settling the decision to `ordinaryEmpty` — that mitigation
would not actually exist).

Resolved without escalating to the user: this is a small, local, unambiguous
addition in the spirit of the plan's own intent (not a design change) —
mirror the existing `projectionLoaded` field exactly. Instructed the UNIT 4
worker to add `InboxState.projectionFailed` (bool, default false), set
`false` alongside `projectionLoaded: true` on fetch success, and set to
`!state.projectionLoaded` (i.e. only while this account's Inbox has never
yet succeeded once) in the catch branch — so a transient background-retry
failure after a prior success cannot regress a working Inbox back into
fail-closed. `HomeActivationReporter` then reports
`inboxFailed: state.projectionFailed`. Existing snackbar behavior on
failure is unchanged (additive, not a replacement). Worker instructed to
journal this as a distinct finding and test it (initial failure → true;
success clears it; failure after a prior success does not re-set it).

Also decided: `HomeActivationBinder` (new StatefulWidget calling
`bindAccount` on account change) has no file path pinned by the plan —
placed at `features/home/ui/widget/home_activation_binder.dart` to match
the existing reporter/binder convention in that directory.

### 2026-09-09 — UNIT 4
**Status:** complete

**Plan gap, resolved (discovered during UNIT 4 implementation):** plan §9
UNIT 4 instructed reporting `inboxFailed` from an Inbox error state that did
not exist — `InboxState` had only `projectionLoaded`, and `_runFetch`'s catch
branch fired a transient snackbar without persisting failure. Without a
persisted flag the fail-closed orientation guarantee could never trigger.
**Fix:** added `InboxState.projectionFailed` (default `false`, same freezed
pattern as `projectionLoaded`); success emits `projectionFailed: false`;
catch emits `projectionFailed: !state.projectionLoaded` so only a never-yet-
successful Inbox fetch counts as failed (transient background-retry failures
after a prior success do not regress). `HomeActivationReporter` reports
`inboxFailed: state.projectionFailed`. Snackbar behavior unchanged.

**Files changed:**
- `packages/client/lib/features/inbox/ui/bloc/inbox_state.dart` —
  `projectionFailed` field.
- `packages/client/lib/features/inbox/ui/bloc/inbox_cubit.dart` — set/clear
  `projectionFailed` in `_runFetch`.
- `packages/client/test/features/inbox/inbox_case_test.dart` — 3 tests for
  initial failure, success clears, post-success failure ignored.
- `packages/client/lib/features/home/ui/bloc/home_activation_state.dart` (new) —
  freezed state + `decideFor` per plan §3 (with `boundAccountId.isEmpty` →
  stable `ordinaryEmpty` when hydrated so sign-out does not spin forever).
- `packages/client/lib/features/home/ui/bloc/home_activation_cubit.dart` (new) —
  `@singleton`, generation-guarded `bindAccount`, account-tagged `report*`,
  activation latch write on `hasProvenActivity` under all debug overrides.
- `packages/client/lib/features/home/ui/widget/home_activation_binder.dart`
  (new) — binds off raw `AuthCubit` account id above `_InboxScope`.
- `packages/client/lib/features/home/ui/widget/home_activation_reporter.dart`
  (new) — `MultiBlocListener` on `MyWorkCubit` + `InboxCubit`.
- `packages/client/lib/features/home/ui/screen/home_screen.dart` — provider,
  binder, reporter wiring.
- `packages/client/lib/features/settings/ui/screen/debug_settings_screen.dart`
  — `MultiBlocProvider` with `HomeActivationCubit` for UNIT 10.
- `packages/client/test/features/home/home_activation_cubit_test.dart` (new) —
  15 tests covering hydration, settlement, latch, dismiss, account safety,
  stale bind discard, unbind, debug overrides, non-active filter.

**Commands:**
```bash
cd packages/client && dart run build_runner build -d   # exit 0
./scripts/check-custom-lints.sh packages/client        # exit 0, total 32 (baseline 32)
cd packages/client && flutter test test/features/home/ test/features/inbox/
# 82/82 passed
```

**Surprises:** `decideFor` needed an explicit unbound-account branch: with
`hydrated: true` and empty signals after `bindAccount('')`, the frozen §3
auto rule would otherwise return `undecided` forever (not settled). Empty
bound account now resolves to `ordinaryEmpty`.

**Commits:** split into two — Inbox `projectionFailed` scaffold, then
activation cubit/binder/reporter + wiring (see finish block).
