# First-load pattern proposal (#545)

Status: proposal only (sprint lane 1 stretch, 2026-10-22). No code. Needs an
owner decision before implementation.

## Problem

Screens build up piece by piece on open: each cubit slice (offers, room state,
plan, counters, chips) paints as its read returns, so the layout jumps for
~0.3–1.5 s. On dev one open Request issues 20+ reads (see
`realtime-freshness-gaps-2026-10.md` §6), so there are many intermediate
frames. Today 45 feature files draw their own `CircularProgressIndicator`, and
"loaded" is tracked ad hoc (`beaconContentLoaded`/`beaconContextLoaded`,
`projectionLoaded`, `roomParticipantsLoaded`, …).

## Options

| | A. First-load gate | B. Skeleton | C. Hybrid (recommended) |
|---|---|---|---|
| What the user sees | one centred spinner until the screen's "ready" condition, then the final layout | grey placeholder blocks in the final layout's shape, filled as slices arrive | gate on the *primary* slices only (title, status, the list itself), with a short timeout; secondary slices (counters, chips, avatars) fill into reserved space |
| Layout jumps | none | none if placeholders match sizes; drift when they don't | none for primary content; secondary content occupies fixed slots |
| Perceived speed | slowest (waits for the slowest required slice) | fastest | close to B |
| Cost | low: one shared widget + a per-screen `isFirstLoadDone` | high: a skeleton per screen, kept in step with layouts | medium: shared gate + fixed slots for 3–4 secondary elements per screen |
| Risk | one slow or failing secondary read blocks the screen (needs a timeout) | skeletons rot as layouts change; double work in every UI change | needs the primary/secondary split decided per screen |

## Recommendation: C

1. **One design-system widget**, `TenturaFirstLoadGate` (beside
   `ScreenLoadErrorPanel`): shows the shared progress indicator while
   `ready == false`, the error panel on a first-load error, the child
   otherwise. It shows the spinner only after ~150 ms (no flash on fast loads)
   and gives up after a timeout (2.5 s) by rendering the child with what it
   has.
2. **Each screen's cubit exposes one `firstLoadDone` flag** that turns true
   when its primary slices have arrived once and **never goes back** —
   background refreshes (realtime hints, catch-ups) update in place and never
   show the gate again. This matches the existing "retain loaded context on
   background refresh" rule in `BeaconViewCubit`.
3. **Composite screens** (Request: beacon + plan + HUD + room) combine the
   flags of the cubits that own primary content; secondary widgets reserve
   their final height (fixed-size chips/counters, avatar stacks with a known
   count) so late arrival does not shift the layout.
4. **Roll-out order:** Request view, Activity, My Work, People — the four
   screens users open most in sessions; then remove the per-feature spinners
   they replace.
5. **Lint (later):** flag new raw `CircularProgressIndicator` in `features/**`
   outside the gate, like the existing design-system lints.

## Decisions needed from the owner

- Accept C (or A/B).
- Timeout value (proposal: 2.5 s) and spinner delay (150 ms).
- Primary slices per screen for the four screens above (a first cut: Request =
  beacon + status + offers; Activity = list page 1; My Work = cards; People =
  list).
