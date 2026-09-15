# Issue #184 — Request Now tab null-check after Send and complete

**GitHub:** [Intersubjective/tentura#184](https://github.com/Intersubjective/tentura/issues/184)  
**Sentry:** [TENTURA-CLIENT-2V](https://vadim-bulavintsev.sentry.io/issues/TENTURA-CLIENT-2V)  
**Related:** [#143](https://github.com/Intersubjective/tentura/issues/143), [#162](https://github.com/Intersubjective/tentura/issues/162)  
**Example request:** `B678bc1ca1d1e` (same trail as #143 close/review loop)

## Symptom

- After **Recognize contribution** (`ReviewContributionsRoute`, `draft: false`), tap **Send and complete** (`evaluation.submit` / `EvaluationCubit.finalize` path).
- Navigate away (Home → Inbox), then open the same request from **My Work** on the **Now** tab (`BeaconViewOperationalRoute` → `BeaconNowSurface` / `BeaconOperationalHeaderCard`).
- Sentry records a **fatal** `TypeError: Null check operator used on a null value` (~3s after navigation), culprit `BeaconViewRoute`, library `scheduler` (semantics flush). Locale `ru-RU`, release `tentura@7.8.0`, WASM/minified stack.

## User-facing expectation

- Now tab must tolerate nullable / stale coordination and review-window fields after evaluation submit.
- Missing data should use existing empty or error UI — no fatal.

## Root cause (client)

**Primary null-check (reproduced in tests):** `BeaconYouResponsibilityLine._buildBlockedSegment` (`packages/client/lib/ui/widget/beacon_you_responsibility_line.dart` ~143) executes `final cue = openBlocker!` when `shouldShowBlockedYouSegment` is true.

`shouldShowBlockedYouSegment` (`packages/client/lib/ui/utils/beacon_you_presentation.dart` ~74–87) returns true when:

1. `phaseResult.rowHarmony.preferBlockedYouSegment == true`, and  
2. `blockerOpenTargetsViewer` (`packages/client/lib/ui/presenter/beacon_phase_input_builders.dart` ~140–151) is true — including when `CoordinationResponsibility.blockerOpen > 0` **without** requiring a non-null `OpenBlockerCue`.

So stale **YOU** responsibility counts (blocker still “open” in counts) combined with a **missing** open-blocker cue still enter the blocked segment builder, which force-unwraps `openBlocker` and throws the same Sentry message during widget build / semantics.

**Why this shows up after Send and complete on the #143/#162 trail:** Close/review loop on `B678bc1ca1d1e` can leave **reviewOpen** with submitted packages (#162) while room/coordination snapshots are partial or stale (#143 failed close). Re-opening the request triggers Now-tab metadata (`buildBeaconViewHudMetadataEntries` → `BeaconYouResponsibilityLine`) on a scheduler frame; any frame where harmony says “prefer blocked YOU” but the cue is null crashes.

**Secondary hazard (not fatally thrown in cubit catch, but brittle):** `BeaconViewCubit._fetchBeaconByIdWithTimeline` (`beacon_view_cubit.dart` ~971–1006) uses `results[n]!` on `Future.wait` enrichment results; a null list from the wire would throw the same `TypeError` if it escaped the cubit `catch`.

**Not the failing path in the current widget repro:** `BeaconChildRequestsSection` `capabilities!` is guarded by `canListChildren`, which is false when `capabilities` is null.

## Relevant code

| Area | Path | Notes |
|------|------|--------|
| Now surface | `packages/client/lib/features/beacon_view/ui/widget/beacon_now_surface.dart` | Operational header + hierarchy bootstrap |
| Header | `packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart` | Review window banner, author HUD ACT |
| HUD metadata | `packages/client/lib/ui/widget/beacon_hud_metadata_composer.dart` | `buildBeaconViewHudMetadataEntries` |
| YOU line | `packages/client/lib/ui/widget/beacon_you_responsibility_line.dart` | `_buildBlockedSegment` → `openBlocker!` |
| Blocked gate | `packages/client/lib/ui/utils/beacon_you_presentation.dart` | `shouldShowBlockedYouSegment` |
| Blocker targeting | `packages/client/lib/ui/presenter/beacon_phase_input_builders.dart` | `blockerOpenTargetsViewer` |
| Review submit | `packages/client/lib/features/evaluation/ui/screen/review_contributions_screen.dart` | `evaluation.submit` → `finalize` |
| Enrichment | `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart` | `_fetchBeaconByIdWithTimeline` `results[n]!` |

## Failing tests (TDD — expected red)

**File:** `packages/client/test/features/beacon_view/issue_184_now_tab_after_evaluation_submit_test.dart`

| Test | Result |
|------|--------|
| `YOU row does not throw when blocker counts outlive open blocker cue` | **FAIL** — `TypeError: Null check operator used on a null value` (matches Sentry) |
| `operational header survives semantics flush (post-submit reviewOpen author)` | **PASS** — static `reviewOpen` post-submit snapshot does not hit blocked YOU segment in isolation |

**Command (from `packages/client`):**

```bash
../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/beacon_view/issue_184_now_tab_after_evaluation_submit_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

**Observed (2026-09-15):** `+1 -1` on the group above. Log: `/tmp/issue-184-test.log`.

## Expected behavior (fix acceptance)

- Now tab build never uses `!` on nullable open-blocker or review-window fields after evaluation submit.
- When `blockerOpen > 0` but `openBlocker` is missing, show empty/error YOU copy (or hide blocked segment), not a fatal.
- Repro manual: Send and complete → My Work → same request → Now tab stable (ru-RU desktop acceptable).
- Green the failing widget test; optionally add integration test pumping full `BeaconNowSurface` once composer state matches production stale snapshot.

## Recommended fix (for implementer)

1. **`BeaconYouResponsibilityLine._buildBlockedSegment`:** Guard `openBlocker == null` → return null segment (or fallback copy), never `!`.
2. **`blockerOpenTargetsViewer`:** Require non-null blocker cue (or title) when treating `blockerOpen > 0` as “blocked YOU”, **or** align counts with room fetches on beacon reload after evaluation events.
3. **`BeaconViewCubit` enrichment:** Replace `results[n]!` with null-coalescing to empty lists / safe defaults where product allows.
4. **Regression:** Keep `issue_184_now_tab_after_evaluation_submit_test.dart` green; consider cubit test when stale responsibility is injected via future `youResponsibility` fetch.

Do **not** change production code in the TDD-only pass; tests stay red until fix lands.

## Codex / agent edit boundaries

**May touch (fix phase):**

- `packages/client/lib/ui/widget/beacon_you_responsibility_line.dart`
- `packages/client/lib/ui/presenter/beacon_phase_input_builders.dart`
- `packages/client/lib/ui/utils/beacon_you_presentation.dart`
- `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart` (enrichment null-safety)
- `packages/client/test/features/beacon_view/issue_184_now_tab_after_evaluation_submit_test.dart`

**Do not touch:**

- Generated `*.g.dart` / `*.freezed.dart`
- Unrelated uncommitted tests (`constellation_body_test`, `home_tab_branch_routing_test`)
- Server #143 fix unless explicitly scoped

## Architecture / product notes

- User-facing **Request** / **discussion** copy only in l10n values; internal **Beacon** routes unchanged.
- Client fix is user-visible → semver bump + web cache-buster when shipping (Codex fix pass).
