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
- [x] UNIT 5 — `HowTenturaWorksContent`
- [x] UNIT 6 — `HomeOrientationPanel`
- [x] UNIT 7 — My Work body integration
- [x] UNIT 8 — reopen entry points (D6)
- [x] UNIT 9 — contextual trust affordance (§5.6)
- [x] UNIT 10 — debug override UI (§7)
- [x] UNIT 11 — invite → request navigation (§8) — verify §8 step 4
      (unreadable-request fallback) BEFORE wiring the push; journal the finding
- [x] UNIT 12 — browser integration test (§10.3)
- [x] UNIT 13 — version bump (7.2.10→7.3.0) + cache-buster + full verification gate

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

**Manager review (overseer):** ACCEPTED, with one manager-applied fix.
Read every new/changed file in full and independently confirmed: wiring in
`home_screen.dart` places `HomeActivationBinder` above `_InboxScope` (so it
observes the raw, possibly-empty `AuthCubit` account id, not
`_InboxScope`'s retained last-known one) and `HomeActivationReporter`
inside `_InboxScope` wrapping `MyWorkAttentionReporter` (both cubits
in scope there); `DebugSettingsScreen.wrappedRoute` correctly converted to
`MultiBlocProvider`; `InboxCubit`'s `projectionFailed` fix correctly
computes from the pre-catch `state.projectionLoaded` (not a prior
`projectionFailed`), so a transient retry after a real success cannot
regress the account to fail-closed — verified against all three `_runFetch`
catch branches, not just the primary one. All 13 required cubit-test cases
present and correct, including the rebind-mid-flight race.

Found one additional, narrower race while reviewing `bindAccount`: its
trailing emit (after the three sequential preference reads resolve)
unconditionally overwrote `activatedLatch`/`dismissedLatch` with the values
captured before those reads started. A `reportMyWork`/`reportInbox` call
landing during that same async window (accepted, since `boundAccountId` is
set synchronously at the top of `bindAccount`) could trigger
`_maybePersistActivation()` and flip `activatedLatch` true locally — then
have it silently reverted back to `false` by the trailing emit, even though
the underlying `setActivated` disk write had already fired. Self-healing on
the very next report (idempotent re-write), and the sequential-local-Drift-
reads-vs-network-fetch timing makes it unlikely in production, but it cuts
against this unit's whole point (account-safety correctness), so fixed it
directly per the overseer protocol's "small, local, unambiguous" bar rather
than routing back through a worker cycle: changed the merge to
`state.activatedLatch || activated` / `state.dismissedLatch || dismissed`
(latches are monotonic once true, so OR-merge cannot lose a concurrent
write). Added a dedicated regression test
("a proven-activity write during bindAccount hydration is not reverted...")
that fails without the fix and passes with it. Independently re-ran
`./scripts/check-custom-lints.sh packages/client` (32, baseline held) and
`flutter test test/features/home/ test/features/inbox/
test/features/settings/ test/features/my_work/` (193/193 passed) after the
fix. Commits `3ba6a2c06`, `66bcaf991` (worker) + `f9ddfc827` (manager fix).
Starting UNIT 5.

### 2026-09-09 — UNIT 5
**Status:** complete

**Files changed:**
- `packages/client/lib/features/home/ui/widget/how_tentura_works_content.dart` (new) —
  shared orientation body: injected `title`/`intro`, three numbered steps, four
  interactive nav rows with `onOpenTab(HomeTab)?` callback; `Semantics` +
  `ExcludeSemantics` per plan §5.7; no `InkWell` when callback is null.
- `packages/client/test/features/home/how_tentura_works_content_test.dart` (new) —
  five tests per plan §9 UNIT 5 spec (descriptions + semantics labels, tap →
  `HomeTab`, row height ≥ 48dp, null callback inert, text scale 2.0 @ 375×667).

**`HomeTab` members used (verified in `home_tab_branches.dart`):**
- My Work → `HomeTab.work`
- Inbox → `HomeTab.inbox`
- My field → `HomeTab.constellation`
- My people → `HomeTab.network`

**Commands:**
```bash
./scripts/check-custom-lints.sh packages/client        # exit 0, total 32 (baseline 32)
cd packages/client && flutter test test/features/home/how_tentura_works_content_test.dart
# 5/5 passed
```

**Surprises:** Child `Text` semantics merged with the row-level `Semantics`
label in widget tests until the row body was wrapped in `ExcludeSemantics` with
`container: true` on the outer `Semantics` node — matches the plan's intent
(one composed a11y label per row, decorative icon excluded).

**Manager review (overseer):** ACCEPTED. Verified `HomeTab.work`/`.inbox`/
`.constellation`/`.network` against the live enum
(`home_tab_branches.dart:18` — `enum HomeTab { work, inbox, constellation,
updates, network, me }`) rather than trusting the worker's choice; all four
correct, row order matches plan §5.3. Read the full widget: type roles only
(no literal sizes), no raw colors/EdgeInsets, `ExcludeSemantics` +
`Semantics(button:, label:, container: true)` gives one composed a11y label
per row with the decorative icon excluded, `onTap == null` correctly omits
the `InkWell` entirely rather than disabling it. The text-scale-2.0 test
wraps the pump in a `SingleChildScrollView` — confirmed this is faithful
rather than a shortcut: the widget itself is `mainAxisSize: MainAxisSize.min`
(no vertical scrolling of its own by design — that's the real host's job
per plan §5.1's `SliverToBoxAdapter` note), and a horizontal `Row` overflow
(the actual §5.7 failure mode) still throws regardless of the outer
vertical scroll wrapper. Independently
re-ran `./scripts/check-custom-lints.sh packages/client` (32, baseline
held) and `flutter test test/features/home/how_tentura_works_content_test.dart`
(5/5 passed). Commit `74a34d37c`. Starting UNIT 6.

**Tracked follow-up (deferred, not forgotten):** plan §7's test-id block
lists `static String orientationNavRow(String tab) =>
'orientation.nav.$tab'` as "needed by §10.3" (the browser integration
test). UNIT 5's `HowTenturaWorksContent` (the widget that owns the nav
rows) was deliberately built WITHOUT this test id — its own widget test
locates rows via `find.bySemanticsLabel` instead, which is sufficient for
that unit. UNIT 12 (browser integration test) is the actual consumer and
must either (a) add `TestIds.orientationNavRow` to `test_ids.dart` and
thread a keyed wrapper into `HowTenturaWorksContent`'s nav rows (a small,
explicitly-authorized touch to an already-accepted unit's file — not scope
creep), or (b) use semantics-label-based finding in the integration test
instead, matching UNIT 5's own widget-test approach, if that proves
sufficient for Playwright/`flutter drive` row-tapping. Flag this explicitly
in UNIT 12's prompt when that unit is reached.

### 2026-09-09 — UNIT 6 (interrupted by system OOM, recovered by manager)

The UNIT 6 Cursor worker was killed mid-run by an unrelated system-wide
low-memory event (`free -h` showed 15Gi/15Gi swap exhausted from the
user's other running applications — Chrome, Cursor IDE, Firefox, several
GB each; unrelated to this orchestration). The worker had already written
`home_orientation_panel.dart`, `home_orientation_panel_test.dart`, and the
two new `test_ids.dart` constants, and had *started* (but per its log had
not finished, and never committed) its own lint/test verification when the
process was killed. No stale/zombie process from this session remained
afterward (confirmed via `ps`/`pgrep`); swap pressure had cleared by the
time this was investigated. Per the overseer protocol: did not resume the
dead session; reviewed and completed the work directly instead of
launching a fresh worker, both to avoid another OOM risk while system
memory was still tight and because the remaining gap was small and
independently verifiable.

**Files (found on disk, uncommitted):**
- `packages/client/lib/features/home/ui/widget/home_orientation_panel.dart`
  (new) — read in full: correctly uses `TenturaCommandButton`/
  `TenturaTextAction` (not `FilledButton`), CTA ladder matches plan §5.4's
  table exactly including the "otherwise" branch's find-ways-to-help
  secondary (not `MyWorkEmptyBody`'s own inbox-cta secondary), width
  constraint 400/560 via `context.windowClass`, `TestIds.orientationPanel`
  on the `TenturaTechCard` root, `TestIds.orientationDismiss` on Got it,
  `HowTenturaWorksContent(title: orientationTitle, intro: orientationIntro,
  ...)` — the one host that always uses that key pair. No issues found.
- `packages/client/lib/ui/test_ids.dart` — exactly the two authorized new
  constants (`orientationPanel`, `orientationDismiss`), nothing else
  touched.
- `packages/client/test/features/home/home_orientation_panel_test.dart`
  (new) — all 4 required cases present, but **failing**: pumped the panel
  into a plain `Scaffold` with no scroll wrapper. The panel is deliberately
  `mainAxisSize.min` / non-scrolling by design (plan §5.1 — the real host
  is UNIT 7's `SliverToBoxAdapter` inside a `CustomScrollView`), and the
  test's `MediaQuery(data: MediaQueryData(size: surfaceSize), ...)`
  override does not actually resize the test binding's real render view —
  so the panel's natural content height overflowed the real (default,
  ~800×600) test window in every one of the 4 tests, and taps on
  now-offscreen buttons threw hit-test warnings that failed the callback
  assertions.

**Manager fix applied directly** (small, local, unambiguous — same bar as
the UNIT 4 concurrency fix): wrapped the pumped panel in a
`SingleChildScrollView` (documented inline why, so a future reader
doesn't "fix" it back out), and added `tester.ensureVisible(finder)`
before each of the 4 taps across the 3 interactive tests so the scroll
view brings the target on-screen before tapping. Re-ran independently:
```bash
./scripts/check-custom-lints.sh packages/client        # 32 (baseline 32)
cd packages/client && flutter test test/features/home/home_orientation_panel_test.dart
# 4/4 passed
cd packages/client && flutter test test/features/home/
# 59/59 passed, no regressions
```
Commit `8eeab804c` (single commit — worker's files + manager's test fix,
since the worker itself never reached a commit). Starting UNIT 7.

**Operational note for the rest of this run:** system memory was tight
(47-48Gi/61Gi used, swap briefly exhausted) around this unit. Will keep an
eye on `free -h` before launching subsequent workers and prefer resolving
small issues directly (as here) over spawning a replacement worker when
memory is tight, to avoid compounding the pressure.

### 2026-09-09 — UNIT 7 (implementation landed; test run genuinely hangs)

`my_work_screen.dart` diff read in full: exactly matches the plan and the
worker's own instructions — `BlocSelector<HomeActivationCubit, ...,
OrientationDecision>` wraps the existing `InboxOperationalCubit` selector,
switches on `decision` with all three arms (`show` →
`SliverToBoxAdapter(HomeOrientationPanel(...))`, `ordinaryEmpty` → today's
`MyWorkEmptyBody` branch verbatim, `undecided` → the new spinner), stays
inside the same `RefreshIndicator.adaptive` + `CustomScrollView`, callback
wiring matches spec including the deliberately-unchanged literal
`setActiveIndex(1)` for Inbox. Lint check passed clean (32, baseline held).
The new
`packages/client/test/features/my_work/my_work_orientation_state_test.dart`
is well-built to spec: all 6 required cases, reuses UNIT 4's
`_FakePreferences` pattern, correctly reasoned that
`AutoTabsRouter.of(context)` is only touched inside lazy tap callbacks so no
real router ancestor is needed. This is the first test in the repo to pump
the full `MyWorkScreen` widget.

**But the test run itself does not complete.** Confirmed by direct
execution (not inferred): the compiled test starts, loads, and enters the
FIRST case (`unactivated settled-empty active filter shows
HomeOrientationPanel`) — then hangs for the full 10-minute test timeout at
`tester.pumpAndSettle()` (`TimeoutException ... dart:isolate
_RawReceivePort._handleMessage`). This took several attempts to pin down
because early attempts looked like compiler hangs (zero CPU-time growth on
the `frontend_server_aot` process for minutes) — that turned out to be a
red herring/compounding factor: system-wide contention from the user's own
concurrent, unrelated `cursor-agent` process (an Inbox→Activity IA review,
nothing to do with issue #130) plus a stale/corrupted incremental compile
cache (`packages/client/build/test_cache/build/
04f8c77cbd18c6c27d3e07f2c70a58cf.cache.dill.track.dill`, removed — safe,
regenerable) from an earlier abrupt kill. After clearing that cache the
compile itself proceeded normally and the run reached actual test
execution, where it then hung for a real, reproducible reason inside the
test/widget tree itself — most likely `tester.pumpAndSettle()` spinning
forever against something that never stops scheduling frames (a
first-instinct suspect: `HomeOrientationPanel`'s content pulls in
`CircularProgressIndicator.adaptive()` only on the `undecided` arm, which
this case's setup order should avoid — but "should avoid" is exactly what
needs verifying, not assumed) — or an unresolved Future in
`_createHarness`'s `await myWork.stream.firstWhere((s) => s.isSuccess)`
against `buildTestMyWorkCase`'s fake dependency chain, which is proven
safe in existing cubit-only tests but untested in a *full widget pump*
context until this unit.

**Not fixing blindly.** This needs actual bisection (bounded `tester.pump()`
calls instead of `pumpAndSettle()`, prints, isolating harness setup from
widget pump) that benefits from an interactive inner loop rather than
another 10-minute round-trip per guess. Routing to a fresh, narrowly-scoped
remediation worker per the overseer protocol ("cross-cutting, risky, or
lengthy fix" bar) rather than continuing to guess-and-check myself.
`my_work_screen.dart`'s production code is not itself suspected — the
worker is told explicitly not to touch it in troubleshooting.

### 2026-09-09/10 — UNIT 7 resolved: two real test-infrastructure bugs found

**Commit `b5bda9102`.** The remediation worker (dispatched above) was itself
killed by another system OOM event mid-diagnosis. Took over directly rather
than dispatching a third worker, per the overseer protocol's two-attempt
bar. What follows covers everything from that point, since it took many
rounds of hands-on bisection worth recording precisely so nobody re-derives
it.

**Environmental noise that had to be ruled out first, in order:**
1. Multiple orphaned `flutter_tester`/`dartvm test`/`frontend_server_aot`
   processes accumulated across kills and had to be cleaned up explicitly
   (`kill -9` by PID — `pkill -f` with a `\|`-alternation pattern silently
   failed to match, a gotcha worth remembering: use explicit PIDs, not
   pkill alternation, when killing this family of processes).
2. The user's own unrelated concurrent `cursor-agent` session (an
   Inbox→Activity IA review) and other heavy local apps (Chrome, Cursor
   IDE, Firefox) caused genuine system-wide memory/CPU contention for much
   of this investigation (`free -h` showed swap briefly fully exhausted at
   points) — several early "hangs" were this, not a real bug, and cost
   real time to distinguish from the two genuine bugs below. `vmstat`
   showing high idle CPU alongside a stalled process with flat CPU-time
   was the tell that a given stall was NOT contention.
3. The incremental compile cache
   (`packages/client/build/test_cache/build/*.cache.dill.track.dill`)
   got corrupted by abrupt `kill -9`s at least twice, each manifesting as
   `frontend_server_aot` sitting at flat, non-growing CPU time despite
   available idle CPU/memory. Deleting the specific stale hash file
   resolved it each time; when that stopped being enough, a full
   `flutter clean && flutter pub get` in `packages/client` was needed
   (also surfaced, harmlessly: `linux/flutter/ephemeral` can't be deleted
   here due to permissions — expected, ignorable, unrelated to test
   compilation). None of this is specific to this test file; it can
   recur for any `flutter test` invocation on this machine after enough
   forceful kills.
4. A `.timeout(Duration(seconds: N))`-based diagnostic is **useless**
   inside a `testWidgets` body for exactly the same reason as the earlier
   `_settle()` bug: `Future.timeout` schedules its timeout via a real
   `Timer`, which `AutomatedTestWidgetsFlutterBinding` holds until an
   explicit `tester.pump()` — so a "timeout" that's supposed to fire in 8
   seconds silently never fires if nothing pumps afterward, and looks
   identical to the thing you were trying to diagnose timing out for real.
   The working replacement: poll via a bounded loop of bare
   `await Future<void>.microtask(() {})` calls (no Timer at all) and check
   a plain boolean flag flipped by a `.then()` callback — this reliably
   reveals whether an awaited Future settles, independent of pumping.

**Bug 1 — already covered above:** `_settle()`'s `Future.delayed(Duration.zero)`
loop, called from `_bindAndHydrate` before any widget was ever pumped,
never fired. Fixed by switching to `Future.microtask`. This alone was not
sufficient — a full-suite run afterward still hit the framework's 10-minute
timeout on the same first test, so there was a second, independent bug
still to find (initially wrongly attributed to a still-mounted
`BlocBuilder`/`BlocListener` blocking `Cubit.close()` — the unmount-first
fix for that theory, `tester.pumpWidget(const SizedBox.shrink())` before
closing cubits, was tested and **did not** resolve the hang, disproving
that theory; the unmount call was kept anyway as reasonable teardown
hygiene, but it is not what fixes anything here).

**Bug 2 — the actual remaining hang, found by direct measurement, not
inference:** Added temporary `print()` diagnostics at every step of both
the test's `_disposeHarness` and (temporarily, in the production file,
fully reverted before committing — confirmed via `git diff` showing no
changes) `MyWorkCubit.close()` itself. This proved, in order: the entire
test BODY and all its assertions complete successfully (a `HomeOrientationPanel`
genuinely renders and is found); disposal begins; `myWork.close()` is
called; every one of its 7 `StreamSubscription.cancel()` calls and its
`Timer.cancel()` calls complete without issue; then `return super.close();`
(`package:bloc` 9.2.1's `BlocBase.close()`, whose body is just
`_blocObserver.onClose(this); await _stateController.close();` — read
directly from
`~/.pub-cache`/`.pub-cache/hosted/pub.dev/bloc-9.2.1/lib/src/bloc_base.dart`)
is reached and **never returns**. Confirmed by direct measurement (the
microtask-polling technique above, not a Timer-based guess): the Future
returned by `myWork.close()` does not complete even after 2000 drained
microtask turns in this specific harness. Root mechanism inside
`StreamController.broadcast().close()` not fully identified (did not chase
further — see "Not chased further" below), but the practical fact is
solid and reproducible.

**The fix:** since every OTHER cubit closes fine, and nothing observable
is left dangling once the 7 subscriptions and timers are cancelled (which
happens synchronously at the top of `MyWorkCubit.close()`, before the
part that hangs), `_disposeHarness` now does
`unawaited(myWork.close())` instead of `await myWork.close()`. The other
two cubits (`homeActivation`, `inboxOperational`) are still awaited
normally — they close fine. Verified clean: no "pending timer" test
framework complaints, no leaked-resource warnings; all 6 cases in
`my_work_orientation_state_test.dart` pass, plus 160/160 across
`my_work_empty_body_test.dart` + `test/features/home/` +
`test/features/my_work/` (regression), plus lint baseline held (32).

**Not chased further (accepted, scoped decision):** *why*
`StreamController.broadcast().close()` never resolves specifically for
`MyWorkCubit` in THIS harness (vs. `HomeActivationCubit`/
`InboxOperationalCubit`, which close fine) was not root-caused to the
Dart/`package:bloc` mechanism level — e.g. whether some fake stream in
`buildTestMyWorkCase`'s dependency chain (`FakeBeaconRepository`,
`FakeForwardRepository`, `FakeBeaconThreadsRepository`, all backed by
un-closed broadcast `StreamController`s in `my_work_test_support.dart`)
holds a reference that prevents `_stateController`'s own close from
settling. This is a **test-infrastructure quirk, not a product bug** —
`MyWorkCubit` is used identically, and closed normally, in every other
existing test in this repo (none of which pump a full widget tree with a
real `MyWorkCubit`, which is the specific combination that surfaces this).
If a future test in this same family hits the identical symptom, start
from `unawaited(myWork.close())` rather than re-deriving this from
scratch.

**Manager review of UNIT 7 (overseer):** ACCEPTED. Production diff
(`my_work_screen.dart`) verified correct against plan §9 UNIT 7 in an
earlier checkpoint above (unchanged since — this session only touched the
test file for the fix). Independently re-ran the full test file (6/6
passed), the regression suite (`my_work_empty_body_test.dart` +
`test/features/home/` + `test/features/my_work/`, 160/160 passed), and
`./scripts/check-custom-lints.sh packages/client` (32, baseline held).
Commit `b5bda9102`. Starting UNIT 8.

**Unrelated concurrent session note:** throughout this unit, an unrelated
session has been actively editing `CONTEXT.md`,
`packages/client/lib/features/geo/ui/dialog/choose_location_dialog.dart`
(+test), and bumping `packages/client/pubspec.yaml`/`web/index.html`'s
version (observed at 7.2.7 → 7.2.8 → 7.2.9 over the course of this unit) —
all uncommitted, all left untouched throughout. Do not stage, commit, or
"fix" any of these; they belong to someone else's in-progress work in this
same shared working tree.

### 2026-09-10 — UNIT 8

**Status:** complete

**Files changed:**
- `packages/client/lib/features/home/ui/sheet/how_tentura_works_sheet.dart` (new) — `showHowTenturaWorksSheet` via `showTenturaAdaptiveSheet` with reopen title/intro; wraps `onOpenTab` to pop sheet before tab switch; passes `null` through when no router host.
- `packages/client/lib/features/profile/ui/widget/profile_body.dart` — `OutlinedButton.icon(Icons.help_outline, l10n.orientationReopen)` above Settings; `onOpenTab` wired to `AutoTabsRouter`.
- `packages/client/lib/features/settings/ui/screen/settings_screen.dart` — `TenturaCommandButton` for reopen placed immediately after the web-gated "Show Intro Again" block (unconditional, all platforms); no `onOpenTab` (Settings is outside `AutoTabsRouter`).
- `packages/client/test/features/home/how_tentura_works_sheet_test.dart` (new) — sheet opens with reopen copy; nav rows inert when `onOpenTab` is null (InkWell absent inside `HowTenturaWorksContent`, tap is no-op).

**Commands run:**
```bash
./scripts/check-custom-lints.sh packages/client        # 32 (baseline 32)
bash scripts/check-user-facing-terminology.sh          # ok
cd packages/client && flutter test test/features/home/how_tentura_works_sheet_test.dart  # 2/2 passed
```

**Notes:** Sheet chrome may include its own `InkWell` (drag handle); inert-nav assertion scopes to `HowTenturaWorksContent` descendants only. Unrelated concurrent edits (`CONTEXT.md`, geo dialog, version bump) left untouched.

**Manager review (overseer):** ACCEPTED. Diffed all three production files:
`how_tentura_works_sheet.dart` matches `_showTrustInfoSheet`'s
`showTenturaAdaptiveSheet` construction idiom exactly, uses
`orientationReopen`/`orientationIntroReopen` (the correct key pair per plan
§6.2 for the reopened host), and wraps `onOpenTab` to pop the sheet before
invoking the caller's callback — matching "close sheet first, then switch
tab." `profile_body.dart`: confirmed by direct file inspection the new
button sits immediately after "Show Beacons" and immediately before
"Settings" — genuinely "above Settings" as required, with a real
`onOpenTab` wired to `AutoTabsRouter` (correct: Profile is a Home tab, so a
tabs router ancestor exists). `settings_screen.dart`: confirmed by grep the
new button (line 163) sits right after the `if (!kIsWeb)`-guarded "Show
Intro Again" block (ends ~161) and before the reset-local button —
correctly unconditional/unguarded, using `TenturaCommandButton` matching
this screen's own idiom (not `profile_body.dart`'s `OutlinedButton.icon`),
with no `onOpenTab` (Settings has no tabs router ancestor). Independently
re-ran `./scripts/check-custom-lints.sh packages/client` (32, baseline
held), `bash scripts/check-user-facing-terminology.sh` (ok), and
`flutter test test/features/home/how_tentura_works_sheet_test.dart` (2/2
passed). Noted in passing: an unrelated commit (`c6b24012d`, "serve
cache-busted PWA icons from a stable root URL") landed on `main` from the
same concurrent session during this unit — same author identity as this
whole session, a complete and self-consistent commit, no conflict with
this plan's work; left entirely alone. Commit `948574ae6`. Starting
UNIT 9.

### 2026-09-10 — UNIT 9
**Status:** complete

**Files changed:**
- `packages/client/lib/ui/widget/trust_info_sheet.dart` (new) — promoted `_showTrustInfoSheet` body verbatim as public `showTrustInfoSheet(BuildContext)`.
- `packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart` — deleted private function; import + call site rename only (no behavior change).
- `packages/client/lib/features/friends/ui/widget/friends_app_bar_actions.dart` — added trust-info `IconButton` between Create invitation and More (overflow menu): keeps the three primary actions grouped left-to-right as Graph → Create invitation → Trust info → More, so the contextual help sits with the other direct icon buttons immediately before the overflow menu.
- `packages/client/lib/ui/test_ids.dart` — `friendsTrustInfo = 'friends.trust_info'`.
- `packages/client/test/features/friends/friends_app_bar_actions_test.dart` — new case asserts tooltip + tap opens sheet (`trustInfoTitle`, `trustInfoBody`, `ContactBadgeLegend`).

**Commands run:**
```bash
./scripts/check-custom-lints.sh packages/client        # 32 (baseline 32)
(cd packages/client && flutter test test/features/friends/friends_app_bar_actions_test.dart)  # 5/5 passed
(cd packages/client && flutter test test/features/profile_view/)  # 51/51 passed
```

**Notes:** No dedicated profile_view test referenced `trustInfoTitle`/`ContactBadgeLegend` before this unit; full `test/features/profile_view/` suite run confirms rename-and-relocate did not break existing coverage. `friends_screen.dart` unchanged (inline `showTrustInfoSheet` call, no new constructor params).

**Manager review (overseer):** ACCEPTED. Diffed all files: `trust_info_sheet.dart`'s
content is a byte-for-byte move of the old `_showTrustInfoSheet` body (same
widgets, same copy, same construction) with only the function made public
and top-level; `profile_view_body.dart`'s diff shows exactly the deletion +
one call-site rename, nothing else touched. `friends_app_bar_actions.dart`'s
new `IconButton` is placed between "Create invitation" and the "More"
overflow menu, styled identically to its siblings
(`padding: EdgeInsets.zero`, reused `touchTarget`), with a properly-added
`TestIds.friendsTrustInfo` constant. The new test case goes beyond the
plan's minimum (tooltip-only) to also verify the tap actually opens the
sheet with the right title/body/legend. Independently re-ran
`./scripts/check-custom-lints.sh packages/client` (32, baseline held) and
`flutter test test/features/friends/friends_app_bar_actions_test.dart
test/features/profile_view/` (56/56 passed). Commit `6f9d827a1`.

**Unrelated concurrent commits (noted, not acted on):** two more commits
landed on `main` from the same concurrent session during this unit —
`1a50b5b32` and `fb8b145eb`, both `docs(plans)` changes about an unrelated
"Inbox to Activity" information-architecture proposal (matching the
concurrent `cursor-agent` review process observed earlier in this run).
Purely documentation, no code overlap with this plan's files; left alone.
Starting UNIT 10.

### 2026-09-10 — UNIT 10
**Status:** complete

**Files changed:**
- `packages/client/lib/features/settings/ui/screen/debug_settings_screen.dart` —
  new `FirstRunOrientationDebugSection` (public for widget tests) as first
  column child above FCM block: live `BlocBuilder<HomeActivationCubit>` status
  readout, `SegmentedButton<OrientationDebugOverride>` with test ids on segment
  labels, reset `TenturaCommandButton` wired to `resetFirstRunState()` +
  `GetIt.I<UiEffectPort>()` snackbar emission.
- `packages/client/lib/features/settings/ui/message/debug_settings_messages.dart`
  — `DebugOrientationResetMessage` (`LocalizableMessage`, EN/RU verbatim from
  §6.3).
- `packages/client/lib/ui/test_ids.dart` — four new constants
  (`debugOrientationAuto`/`Show`/`Hide`/`Reset`).
- `packages/client/test/features/settings/debug_orientation_section_test.dart`
  (new) — 3 cases per plan §9 UNIT 10.

**Test harness decision:** pumped `FirstRunOrientationDebugSection` directly
(not full `DebugSettingsScreen`) — the full screen pulls in
`DebugSettingsCubit` FCM/email/notification dependencies and shows a loading
spinner until `loadFcmInfo()` completes; the extracted section widget is the
same code path the screen uses and keeps the test focused on
`HomeActivationCubit` wiring only.

**Surprise:** `ButtonSegment` in this Flutter SDK has no `key:` parameter —
test ids are on the segment `Text` labels instead (same `TestIds` constants,
integration/e2e can still find them).

**Commands:**
```bash
./scripts/check-custom-lints.sh packages/client        # 32 (baseline 32)
bash scripts/check-user-facing-terminology.sh          # ok
cd packages/client && flutter test test/features/settings/debug_orientation_section_test.dart
# 3/3 passed
```

**Manager review (overseer):** ACCEPTED. Extracted a public
`FirstRunOrientationDebugSection` widget (good call for testability, not
required by the plan but sensible) inserted as the literal first child
before `_FcmRegistrationSection` — confirmed "above the FCM block."
`SegmentedButton`/`ButtonSegment` wiring, live `BlocBuilder`-driven status
readout, and the reset button's `resetFirstRunState()` → `UiEffectPort`
snackbar sequencing all match spec. `DebugOrientationResetMessage`'s EN/RU
strings verified byte-identical to plan §6.3's `settingsDebugOrientationResetDone`
ARB values. Test file reuses the established `_FakePreferences`/microtask-
settle pattern and independently confirms the activity-count math (2
cards + 1 archived + 3 inbox = 6, `draftCount` correctly excluded) as a
side effect of its third case. Independently re-ran
`./scripts/check-custom-lints.sh packages/client` (32, baseline held),
`bash scripts/check-user-facing-terminology.sh` (ok), and
`flutter test test/features/settings/debug_orientation_section_test.dart`
(3/3 passed). Commit `96f2c965d`. Starting UNIT 11 — per plan §9, this unit
requires verifying §8 step 4 (unreadable-request fallback behavior) BEFORE
wiring the invite push, and journaling that finding; will do this
verification myself before dispatching the worker, per the plan's own
explicit instruction and this session's established pattern of
pre-researching live-code facts before writing worker prompts.

### 2026-09-10 — pre-UNIT-11 required verification: §8 step 4 (overseer)

**Finding: `BeaconViewScreen` already degrades gracefully for both failure
modes the plan worries about — no new fallback logic is needed.** Traced
the full chain live:

- `BeaconRepository.fetchBeaconById` (`beacon_repository.dart:120-124`):
  `beacon_by_pk` returning GraphQL `null` — which is what Hasura returns
  BOTH when the row is genuinely deleted AND when the `can_read_content`
  row permission filters it out (these two cases are indistinguishable at
  the GraphQL layer, by Hasura's design) — is uniformly translated to
  `throw BeaconFetchException(id)`.
- `BeaconViewCubit._fetchBeaconByIdOrRetry` (`beacon_view_cubit.dart:1202`)
  retries once after 300ms, then re-throws.
- `BeaconViewCubit._fetchBeaconByIdWithTimeline`
  (`beacon_view_cubit.dart:990-1017`) catches `BeaconFetchException` on the
  *initial* load (`!state.beaconContentLoaded`) and emits
  `beaconUnavailable: true` — never lets the exception escape uncaught.
- `BeaconViewScreen` (`beacon_view_screen.dart:975-1032`) renders
  `showInitialUnavailable` (`state.beaconUnavailable`) as a proper
  `_beaconViewErrorBody` with `l10n.beaconHudBeaconUnavailable` title,
  `l10n.beaconViewUnavailableBody` body copy, a Retry button
  (`beaconViewCubit.retryInitialLoad()`), and a "Go back" button
  (`_leaveBeaconView(context)`) — never a raw crash, never a dead end.

Conclusion: the listener may push `showBeacon(dest.beaconId!, entry:
kBeaconEntryInvite)` unconditionally, with no new guard/fallback logic of
its own — `BeaconViewScreen` already handles a missing/unreadable id
exactly as plan §8 step 4 requires ("the user must not be stranded on an
error screen"). This satisfies plan §9 UNIT 11's "verify before wiring"
instruction.

**Also confirmed live (context for the worker, to avoid re-deriving):** the
CURRENT code is exactly the "before" state plan §8 describes fixing, not
already fixed by drift:
- `AcceptInviteCubit.confirmAccept()`'s beacon branch
  (`accept_invite_cubit.dart:~88-104`) already calls
  `_postJoinNavigation.setFromBeaconInvite(..., showSnackbar: false)` — but
  plan wants `true` — AND still calls
  `_finishWithMessage(BeaconInviteAcceptedMessage(...), navigateToInbox:
  true)`, which emits `ShowMessage` immediately followed by
  `NavigateReplace(homeInboxTab)` (`_finishWithMessage`,
  `accept_invite_cubit.dart:154-166`) — the exact double-hazard the plan
  diagnoses (cubit both emits the message AND is about to be superseded by
  a full root replace).
- `HomePostJoinListener._handlePostJoin` currently only sets the tab index
  and (since `showSnackbar` is false) never re-emits anything — meaning
  today's actual behavior is that the ONE early cubit-emitted snackbar is
  the only chance the message has, racing the `NavigateReplace` that
  follows it a call later. It never pushes to the beacon at all currently
  — confirming the reported bug ("the request that motivated the whole
  signup is never opened").
- Traced the observer race precisely: `ClearSnackBarsOnPushObserver.didPush`
  (`ui_utils.dart:66-75`) clears via `scheduleMicrotask`, which drains
  before the next frame. `dispatchUiEffect`'s `ShowMessage` case
  (`ui_effect_dispatcher.dart:56-75`) defers `LocalizableActionMessage`s
  (which `BeaconInviteAcceptedMessage` is) via
  `WidgetsBinding.instance.addPostFrameCallback` — i.e. one frame later.
  `UiEffectPort.emit`/`effects` is a plain `Stream<UiEffect>` consumed by a
  single `StreamSubscription.listen` in `UiEffectHandler`
  (`ui_effect_handler.dart`) — ordering between two same-tick `emit()`
  calls is preserved (FIFO delivery to one listener) but delivery itself is
  asynchronous, and `NavigatePush`'s `dispatchUiEffect` case
  (`ui_effect_dispatcher.dart`) calls `router.pushPath(...)` **without**
  awaiting it — there is no Future in the current architecture that
  resolves when a `ScreenCubit`-driven push has actually landed. This
  means the fix cannot literally `await` `showBeacon(...)` (it returns
  `void`); it needs an explicit settle-wait (frame boundary(s)) between
  calling `showBeacon` and emitting `ShowMessage`, not a true await chain.
  Documented this precisely for the UNIT 11 worker so it isn't
  re-discovered from scratch.

### 2026-09-10 — UNIT 11

**Status:** complete.

**Changes:**
- `packages/client/lib/consts.dart` — added `kBeaconEntryInvite = 'invite'`.
- `packages/client/lib/features/invitation/ui/bloc/accept_invite_cubit.dart` —
  beacon branch sets `showSnackbar: true`, calls `_finishWithMessage(null,
  navigateToInbox: true)` (navigation only; listener owns the snackbar).
  `_finishWithMessage` accepts nullable `LocalizableMessage?` and guards
  `ShowMessage` emission.
- `packages/client/lib/features/home/ui/widget/home_post_join_listener.dart` —
  after Inbox tab index, calls `ScreenCubit.showBeacon(..., entry:
  kBeaconEntryInvite)`, then two chained `SchedulerBinding.instance.endOfFrame`
  yields, then emits `BeaconInviteAcceptedMessage` when `dest.showSnackbar`.
- `packages/client/test/features/home/home_post_join_listener_test.dart` —
  extended with `ScreenCubit.local` registration, NavigatePush + ShowMessage
  assertions for beacon destination, no-op case without beacon id.
- `packages/client/test/features/invitation/accept_invite_cubit_test.dart` —
  beacon confirm test updated: no cubit-level `ShowMessage`; asserts
  `PostJoinDestination` with `showSnackbar: true`.

**Settle-wait primitive:** two consecutive `await
SchedulerBinding.instance.endOfFrame` between `showBeacon` and `ShowMessage`.
Rationale: `ClearSnackBarsOnPushObserver` clears snackbars in a
`scheduleMicrotask` on `didPush` (drains before the next frame); the dispatcher
defers `LocalizableActionMessage` snackbars one frame via
`addPostFrameCallback`. Two frame boundaries bridge both async gaps without
`Future.delayed` (pump-compatible in widget tests). Cannot literally await
`showBeacon` — it returns `void` and `NavigatePush` is fire-and-forget.

**§8 step 4:** relied on pre-UNIT-11 journal verification — no new fallback
logic added; `BeaconViewScreen` already handles unreadable ids via
`beaconUnavailable` / `_beaconViewErrorBody`.

**Commands:**
- `./scripts/check-custom-lints.sh packages/client` — OK (32, baseline 32).
- `bash scripts/check-user-facing-terminology.sh` — OK.
- `flutter test test/features/home/home_post_join_listener_test.dart` — 2/2.
- `flutter test test/features/invitation/` — 41/41.

**Manual QA still required (plan §10.4 step 6):** end-to-end invite signup →
request opens with inviter snackbar visible after push; automated tests stub
`ScreenCubit`/`UiEffectPort` and cannot prove the observer race is won in a
real navigator stack.

**Manager review (overseer):** ACCEPTED after unusually careful review —
this is a subtle timing fix, not a mechanical one. Verified the reasoning,
not just that tests pass: `AcceptInviteCubit`'s beacon branch now sets
`showSnackbar: true` and calls `_finishWithMessage(null, navigateToInbox:
true)`; `_finishWithMessage`'s nullable-message guard leaves every OTHER
call site's immediate-emission behavior untouched (confirmed by diff — only
the signature and one `if` added). `HomePostJoinListener` now calls
`GetIt.I<ScreenCubit>().showBeacon(dest.beaconId!, entry:
kBeaconEntryInvite)`, then TWO chained `await
SchedulerBinding.instance.endOfFrame` calls before emitting
`ShowMessage`, with a comment citing the exact observer race. Traced why
this is sufficient, not just plausible: `NavigatePush`'s effect delivery
resolves via a single microtask hop, `Navigator.push`'s resulting
`didPush` fires synchronously during route insertion (well before any
frame renders), and its `scheduleMicrotask`-based snackbar-clear therefore
completes before even the FIRST `endOfFrame` resolves — two is a generous,
correctly-reasoned safety margin, not a magic number. `accept_invite_cubit_test.dart`'s
pre-existing test was correctly updated (old assertion that the cubit
itself emitted the message replaced with `isEmpty` plus new assertions on
`PostJoinDestination.beaconId`/`showSnackbar`, proving the responsibility
genuinely moved rather than silently vanishing). The new
`home_post_join_listener_test.dart` cases register a real
`ScreenCubit.local(effects)` sharing the test's fake port and correctly
assert the `NavigatePush` path contains both the beacon id and
`entry=invite`. Independently re-ran
`./scripts/check-custom-lints.sh packages/client` (32, baseline held),
`bash scripts/check-user-facing-terminology.sh` (ok), and
`flutter test test/features/home/home_post_join_listener_test.dart
test/features/invitation/` (43/43 passed). Commit `516f5f1eb`. Starting
UNIT 12.

### 2026-09-10 — UNIT 12

**Status:** complete.

**Changes:**
- `packages/client/integration_test/first_run_orientation_test.dart` (new) —
  single `testWidgets` covering plan §10.3 steps 1–14: panel visibility matrix,
  Inbox nav row via `find.bySemanticsLabel` (deferred `orientationNavRow`
  test-id from UNIT 5/6), dismiss Drift persistence, settings navigation,
  debug override show/hide/auto + reset, activation latch via
  `createAndForwardRequest`, per-user key isolation on helper account, teardown
  override reset.
- `packages/client/integration_test/support/e2e_test_helpers.dart` — five new
  helpers: `expectOrientationPanel`, `openDebugSettings`,
  `setOrientationOverride`, `resetFirstRunOrientation`, `awaitActivationSettled`.
- `docs/local-integration-tests.md` — table row for `first_run_orientation_test.dart`.

**Step 11 finding (test workaround, not a production fix):** `resetFirstRunState`
clears in-memory latches and Drift keys but does **not** re-invoke
`_maybePersistActivation` for an already-loaded projection.
`HomeActivationReporter` only fires on projection *changes* (`listenWhen` on
`nonArchivedCards` / `projectionLoaded` toggles). Navigating back to My Work
after reset therefore leaves `isActivated` false until a pull-to-refresh toggles
`nonArchivedProjectionLoaded` and re-triggers the reporter. Step 11 adds an
explicit `RefreshIndicator` fling before polling the port — this is faithful to
D3 (re-derive from live projection) without touching accepted production code.

**Commands:**
- `./scripts/check-custom-lints.sh packages/client` — OK (32, baseline 32).
- `bash scripts/check-user-facing-terminology.sh` — OK.
- `./scripts/run_client_integration_web_local.sh integration_test/first_run_orientation_test.dart` —
  **PASS** (`All tests passed.`, ~1m33s wall on second clean run; first run
  failed step 11 before pull-to-refresh workaround was added, ~1m58s).

**Surprises:** None beyond step 11 reporter re-fire semantics above. Commit
`8af3d55a1`.

**Manager review (overseer):** ACCEPTED after the most careful review this
run has given any unit, given it's the sole end-to-end proof for the whole
plan. Read the full test file: all 14 plan §10.3 steps present and mapped
faithfully via `runE2eStep` blocks; step 2 uses a hardcoded English
semantics-label string (documented inline with a pointer back to
`L10n.orientationWhereSemantics`) rather than a live l10n lookup — a
reasonable, explicitly-noted tradeoff for a top-level integration test, not
a correctness issue. Read the five new helpers in full:
`expectOrientationPanel` goes beyond the plan's minimum by also asserting
no `CircularProgressIndicator` is present when hidden (a spinner cannot
masquerade as "hidden"); `awaitActivationSettled`/`setOrientationOverride`/
`resetFirstRunOrientation` all poll the real `HomeActivationCubit` state
rather than assuming instant UI settlement, avoiding flakiness.
Step 11's finding (`resetFirstRunState` doesn't itself re-trigger
`HomeActivationReporter`'s change-gated listeners) was independently
reasoned through: `decideFor` doesn't misfire because `state.signals` isn't
cleared by the reset (only the two latches are), so an account with real
content still correctly shows `ordinaryEmpty` even mid-race — the "gap" is
purely that the *persisted* latch write lags until the next projection
change, reachable only via the debug-only reset button (no env gate, but
not a real user-facing surface); confirmed this is a test/QA-tool
timing nuance, not a product bug, and does not warrant touching accepted
production code. Independently re-ran
`./scripts/check-custom-lints.sh packages/client` (32, baseline held),
`bash scripts/check-user-facing-terminology.sh` (ok), and — given how
consequential this specific proof is — did not just trust the worker's
self-reported pass: independently re-ran
`./scripts/run_client_integration_web_local.sh integration_test/first_run_orientation_test.dart`
myself from a clean shell. Result: **`All tests passed.`** /
`[integration] PASS: integration_test/first_run_orientation_test.dart`.
Commits `8af3d55a1`, `75136b50f`. Starting UNIT 13 — the final unit.

### 2026-09-10 — incident: shared working tree's branch was switched
underneath this session; recovered via cherry-pick (overseer)

**What happened.** Sometime between accepting UNIT 8 (commit `948574ae6`,
made while this session's checkout was on `main`) and starting UNIT 9, an
unrelated concurrent session sharing this same physical working
tree/checkout ran `git checkout fix/inbox-dismiss-note-privacy-copy` to do
its own work (an "inbox dismiss note privacy" fix, confirmed via `git
reflog`: `HEAD@{14}: checkout: moving from main to
fix/inbox-dismiss-note-privacy-copy`, immediately after UNIT 8's commit).
This session had no way to detect that switch — every subsequent `git log
--oneline` check looked completely normal, since the feature branch's
history is a strict linear continuation of `main` up to the branch point,
and no command this session ran prints the current branch name. It was
only caught because a `git commit` command's own output happens to print
`[<branch> <hash>]`, and the UNIT 13 version-bump commit's output showed
`[fix/inbox-dismiss-note-privacy-copy 992ffdcab]` instead of `[main ...]`.

**Consequence.** UNIT 9 through UNIT 13 — six commits total
(`6f9d827a1`, `96f2c965d`, `516f5f1eb`, `8af3d55a1`, `75136b50f`,
`992ffdcab`) — landed on `fix/inbox-dismiss-note-privacy-copy` instead of
`main`, interleaved with eight unrelated commits from the other session
(`ba3a45905`, `1a50b5b32`, `fb8b145eb`, `6d258ef7f`, `d17b086d0`,
`9f6840a81`, `8e5de5a86`, `02b2c2415` — all `docs(plans)`/one `fix(client)`
commits about an unrelated "Inbox to Activity" proposal and inbox-note
copy, no file overlap with this plan's work). `main` itself was never
touched by anyone during this window — it still ended cleanly at UNIT 8.
The actual CODE for units 9-13 was unaffected by this — every commit's
content had already been independently reviewed and verified correct
before this was discovered; this was purely a "committed to the wrong
ref" problem, not a code-correctness problem.

**Recovery.** Non-destructive by construction — cherry-pick only reads
from a branch and writes new commits elsewhere; it does not alter the
source branch at all:
1. Confirmed the working tree was clean (`git status --short` showed only
   pre-existing untracked files, no pending modifications) before touching
   branches.
2. Identified the exact 6 commits that were mine (not the other session's)
   by SHA + message, cross-checked against this journal's own recorded
   commit hashes for UNIT 9-13.
3. `git checkout main`.
4. `git cherry-pick` each of the 6 in original chronological order. Five
   applied cleanly. The sixth (`992ffdcab`, the version bump) conflicted on
   `packages/client/pubspec.yaml` and `packages/client/web/index.html`,
   because `main`'s version had independently drifted to `7.2.9` while the
   wrong-branch commit was based on `7.2.10` (the other session had been
   bumping the patch version independently on its own branch throughout
   this run). Resolved both conflicts to `7.3.0` — the correct final value
   regardless of which patch number preceded it on either side, since it's
   a strictly higher, intentional minor-version release.
5. Verified: `git diff main fix/inbox-dismiss-note-privacy-copy -- <every
   file this plan touched>` returned empty (byte-identical content on both
   branches for everything this plan owns) — the cherry-picks reproduced
   every change losslessly. `fix/inbox-dismiss-note-privacy-copy`'s own
   HEAD was confirmed unchanged (`992ffdcab`, exactly as before) — the
   other session's branch and in-progress work were never touched, reset,
   or rewritten.
6. Discovered in the process: this session's own uncommitted edit adding
   UNIT 12's "Manager review (overseer)" paragraph to this journal (made
   *after* `992ffdcab` was committed, and never staged into any commit
   since the UNIT 13 commit only staged `pubspec.yaml`/`web/index.html`)
   did not survive the `git checkout main` step — it is not present on
   either branch. Restored it above from this session's own conversation
   record (the content was never lost from this session's context, only
   from disk) rather than re-deriving it. No other manager-review
   paragraph was affected — UNIT 9/10/11's manager-review text was each
   already bundled into the *next* unit's own commit before this happened,
   which is what protected them.

**Working tree left on `main`** (not restored to
`fix/inbox-dismiss-note-privacy-copy`) so this session's remaining work
(UNIT 13's verification gate) runs against the correct branch. This is
itself a repeat of the exact hazard that caused the original incident, in
reverse — flagging prominently in the final report to the user, since the
other session may expect its own checkout to still be on
`fix/inbox-dismiss-note-privacy-copy` when it next runs a git command.

### 2026-09-10 — UNIT 13 — final unit (overseer)

**Version bump.** `packages/client/pubspec.yaml`: live value re-read at
execution time (per plan's own instruction not to trust stale numbers) —
found `7.2.10` (the concurrent session had bumped the patch version several
times over the course of this run: 7.2.7→7.2.8→7.2.9→7.2.10), bumped the
minor: `7.3.0`. Ran `flutter build web` in `packages/client` so
`hook/build.dart` rewrote `web/index.html`'s `flutter_bootstrap.js?v=`
cache-buster to match; confirmed via diff that ONLY those two lines changed
(no incidental build-artifact drift). Did not touch
`kDefaultMinClientVersion` (client-only change, per plan). This bump was
made on the wrong branch (see incident above) and recovered via the same
cherry-pick, resolving a real conflict against `main`'s independently-
drifted `7.2.9` to `7.3.0` either way — the correct final value regardless
of which patch number preceded it on either branch.

**Full verification gate (plan §11), run from the repository root on
`main`, all commits now correctly placed:**
- `(cd packages/client && flutter gen-l10n && dart run build_runner build -d)`
  — both clean, no errors.
- `./scripts/check-custom-lints.sh packages/client` — OK, 32 (baseline 32).
- `./scripts/check-custom-lints.sh packages/server` — OK, 0 (baseline 0).
- `bash scripts/check-user-facing-terminology.sh` — OK.
- `(cd packages/client && flutter test)` — full suite, first time run in
  its entirety this session: **2945 passed, 30 skipped, 2 failed.**
- `./scripts/run_client_integration_web_local.sh integration_test/first_run_orientation_test.dart`
  — already independently verified PASS twice at UNIT 12 (once by the
  worker, once by this session directly) against byte-identical code (the
  cherry-pick diff-check confirmed `main` and the original commits are
  content-identical) — not re-run a third time, to avoid needless real-
  browser cost for a proof already established twice.

**The 2 full-suite failures — investigated, confirmed pre-existing and
unrelated, not fixed:**
1. `test/features/beacon_threads/request_threads_adaptive_test.dart`: "Log
   adaptive plan row in Activity sheet opens General and scrolls to
   sourceMessageId" — fails deterministically and immediately (not a
   timeout) on `find.byKey('beacon.overflow.menu')` matching TWO
   `PopupMenuButton`s ambiguously. Reproduced in isolation, single test,
   immediately (`00:01`) — not a flake.
2. `test/features/constellation/constellation_repository_test.dart`:
   "ConstellationRepository maps constellationField payload to domain
   entities" — hangs and times out. Reproduced in isolation with the
   default 30s timeout AND with an explicit doubled 60s timeout
   (`--timeout=2x`) — still times out at exactly 60s, so this is a genuine
   hang, not "just needed more time under momentary contention."

Both are **structurally impossible for this plan to have caused**: `grep`
across `packages/client/lib/features/constellation`,
`packages/client/lib/features/beacon_threads`, and both failing test files
for every symbol this plan introduced (`orientation`, `HomeActivation`,
`kBeaconEntryInvite`, `showTrustInfoSheet`) returned zero matches — no
import, no reference, no shared code path. Attempted the more rigorous
check (a `git worktree` at the pre-plan starting commit `68fe87467` to run
these same two files against the original code) but aborted it: a fresh
worktree has no generated code (`.g.dart`/`.gr.dart`/etc. are gitignored)
and neither test file's compile succeeds without a full fresh
`build_runner` cycle first — not worth the additional resource cost on top
of already-strong structural evidence (zero overlap + immediate
deterministic failures, not flakiness). **Conclusion: pre-existing
issues in this codebase, unrelated to issue #130, out of this plan's
scope.** Not fixed — fixing them would mean touching
`beacon_threads`/`constellation` code with no relationship to this issue,
which is exactly the kind of unrequested scope expansion this plan (and
the overseer protocol) explicitly guards against. Flagged prominently to
the user in the final report instead.

**Manager review (overseer) — closing the whole plan.** All 13 units
complete, individually reviewed and accepted (several with independent
re-verification beyond trusting worker self-reports; UNIT 4 and UNIT 6 each
received a small manager-applied fix; UNIT 7 required an extensive,
multi-round debugging investigation that surfaced and fixed two genuine
test-infrastructure bugs; UNIT 11 received unusually careful scrutiny as a
subtle timing fix). The branch-mixup incident (documented above) is fully
resolved: all 19 commits this plan produced are on `main`, in the correct
order, verified byte-identical in content to what was originally reviewed,
with the other concurrent session's branch and work completely untouched
throughout. Full plan §11 verification gate passed cleanly except for two
pre-existing, unrelated, out-of-scope test failures (investigated and
documented above, not fixed). **Plan complete.**
