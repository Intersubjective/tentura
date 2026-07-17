---
status: done
kind: audit
---
# Beacon detail — QA audit

Structured assessment of whether beacon detail answers the coordination questions users need at a glance. Complements the product spec in [`features/beacon_room.md`](../features/beacon_room.md) and HUD copy rationale in [`beacon-status-line-rationale.md`](../beacon-status-line-rationale.md).

**Date:** 2025-06-25  
**Primary surface:** `BeaconViewScreen` (`packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart`)

## Questions beacon detail must answer

| # | Question |
|---|----------|
| 1 | What is needed? |
| 2 | Who started it? |
| 3 | What is happening now? |
| 4 | What does this mean for me? |
| 5 | Who is involved? |
| 6 | Who forwarded it to whom? |
| 7 | Who committed? |
| 8 | What is still unresolved? |
| 9 | What changed recently? |
| 10 | What can I do next? |

**Stated blocker:** important state is buried in chat-like chronology.

---

## Product surface map (as shipped)

```
Beacon detail (BeaconViewScreen)
├─ App bar
│ ├─ Identity: title + phase/status line (BeaconViewAppBarTitle + beaconViewStatusSlots)
│ ├─ Room toggle (when admitted) + unread badge
│ └─ Overflow: share, lifecycle, forward, offer help, close, etc.
├─ Surface A — Operational (default)
│ ├─ Orientation strip (pinned, scrolls with content)
│ │ ├─ People / schedule / location avatars (BeaconCompactMetadataStrip)
│ │ ├─ NOW — current line + blocker subline (1 line, truncated)
│ │ ├─ YOU — viewer responsibility (conditional)
│ │ └─ Action rail — Offer help / Forward / Update status / Watch
│ ├─ Tabs (pinned segment bar)
│ │ ├─ Items (default)
│ │ │ ├─ Active coordination items (asks, promises, blockers)
│ │ │ ├─ Closed items
│ │ │ ├─ My drafts
│ │ │ ├─ Facts carousel
│ │ │ └─ Definition accordion — need, done-when, tags, description
│ │ ├─ People
│ │ │ ├─ Active helpers / Willing / Not fitting / Withdrawn
│ │ │ └─ Forwards (lazy-load button → chain list)
│ │ └─ Log
│ │ └─ Coordination event chronology (newest first)
│ └─ Lineage parent link (when forked)
└─ Surface B — Room (full-screen swap)
 └─ Chat thread only (“NOW/YOU lives on Items tab” per code comment)
```

### Code map

| Layer | Path |
|-------|------|
| Screen | `packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart` |
| Cubit / state | `ui/bloc/beacon_view_cubit.dart`, `beacon_view_state.dart`, `items_tab_cubit.dart` |
| Use case | `domain/use_case/beacon_view_case.dart` |
| Operational layout | `ui/widget/beacon_operational_scroll_view.dart` |
| Header HUD | `ui/widget/beacon_operational_header_card.dart` → `ui/widget/beacon_hud_metadata_composer.dart` |
| Tabs | `items_tab.dart`, `beacon_people_tab_body.dart`, `activity_list.dart` |
| Room surface | `ui/widget/beacon_room_surface.dart` → `beacon_room/ui/widget/beacon_room_body.dart` |
| Domain entities | `packages/client/lib/domain/entity/beacon.dart`, `coordination_item.dart` |

**Note:** Legacy `BeaconOverviewTab` / `BeaconStatusDashboard` (`ui/widget/overview/beacon_overview_tab.dart`) exists but is **not wired** into the live screen (tests only).

---

## Criterion matrix

| # | Criterion | Surfaced? | Where in UI | Data available? | Gap severity |
|---|-----------|-----------|-------------|-----------------|--------------|
| 1 | **What is needed?** | Partial | `BeaconDefinitionBody` inside collapsed **Definition** accordion on Items tab; NOW row may fall back to `needSummary` when no room line | Yes — `beacon.needSummary`, `needs`, `successCriteria`, `description`, `context` | **High** — primary need text is below active-item folds, not in header |
| 2 | **Who started it?** | Partial | Author is first avatar in HUD people strip; author star on People tiles; creation event in cubit-built `timeline` but not shown | Yes — `beacon.author`, `beacon.createdAt`; `TimelineCreation` in state | **Med** — no explicit “Started by …” label; creator buried in avatar pile |
| 3 | **What is happening now?** | Partial | App bar phase line; HUD **NOW** row + blocker subline; `BeaconNowDetailSheet` built but never opened from live UI | Yes — `beaconRoomCue.currentLine`, `openBlockerTitle`, `beacon.status`, phase derivation | **Med** — strong signals exist but NOW is one truncated line; detail sheet unwired |
| 4 | **What does this mean for me?** | Partial | HUD **YOU** row when `isBeaconYouMetadataVisible`; header CTAs; inbox stance drives watch/stop | Yes — `youResponsibility`, `inboxStatus`, phase + blocker cues | **Med** — YOU row hidden for many states; no persistent “your role” badge |
| 5 | **Who is involved?** | Partial | HUD face pile (max 3 + overflow); People tab lens folds; `roomParticipants` on tiles when room access | Yes — `helpOffers`, `roomParticipants`, author | **Med** — full roster requires People tab + accordion expand; pile omits non-offerers |
| 6 | **Who forwarded it to whom?** | Partial | People tab bottom: **Forwards (N)** after lazy `loadForwards()`; viewer-scoped edges only | Yes — `viewerForwardEdges`, `myForwards`, `forwardProvenance`, `inboxLatestNotePreview` in state | **High** — lazy + scroll; `forwardProvenance` / `inboxLatestNotePreview` never rendered; no global forward graph |
| 7 | **Who committed?** | Partial | Items tab **Active** fold — `ItemCard` for promises and accepted asks; People tiles show coordination response, not formal commitments | Yes — coordination items with `creatorId`, `targetPersonId`, `responsibleUserId`, statuses | **High** — no commitments summary; promises mixed in item list; help-offer ≠ commitment |
| 8 | **What is still unresolved?** | Partial | NOW blocker subline; open items in Items **Active** accordion; YOU counts; People tab badges | Yes — `openCoordinationBlocker`, open items via `ItemsTabCubit`, `youResponsibility` | **High** — no aggregate “open: 2 asks, 1 blocker” in header; must scan folds |
| 9 | **What changed recently?** | Partial | **Log** tab — `BeaconActivityList` with `roomActivityEvents` only; legacy `timeline` passed as `const []` | Yes — `roomActivityEvents`; full `timeline` built in cubit but suppressed | **High** — recent social/coordination history split; no “last event” HUD row |
| 10 | **What can I do next?** | Yes | HUD action rail; Items tab coordination CTAs; app bar overflow; YOU line hints | Yes — role/status-derived affordances | **Low** — actions exist but depend on discovering header/tab affordances |

**Net read:** five of ten criteria still depend on scrolling, tab-switching, or expanding folds. Only criterion 10 is clearly met.

---

## Blocker assessment

**Verdict:** the blocker is real but nuanced — state is split across tabs, accordions, and lazy sections, not primarily buried in room chat.

### What works (explicit state UI)

- **Pinned operational header** above tabs: phase status (app bar), NOW, YOU, people strip, primary CTAs (`beacon_operational_scroll_view.dart`).
- **Items tab** is structured (not chat): active/closed/drafts/facts/definition accordions with `ItemCard` rows.
- **Room surface is intentionally chat-only** — comment in `beacon_room_surface.dart`: *“NOW/YOU coordination context lives on the beacon Items tab.”*

### Where chronology or fragmentation still wins

| State | Explicit UI? | Buried how | Evidence |
|-------|-------------|------------|----------|
| Need / definition | Collapsed accordion at bottom of Items | Scroll past active items; default open fold is **Active**, not Definition | `beacon_accordion_sections.dart`; `_BeaconDefinitionSection` in `items_tab.dart` |
| Forwards chain | Lazy section at bottom of People tab | Extra tap “Show forwards” + scroll below people folds | `beacon_people_tab_body.dart` |
| Inbox forward provenance | Not shown | Data in state only | `forwardProvenance`, `inboxLatestNotePreview` in `beacon_view_state.dart` |
| Help-offer / status timeline | Not shown on Log tab | Cubit builds `timeline` but Log passes `timeline: const []` | `beacon_view_cubit.dart`; `beacon_operational_scroll_view.dart` |
| Forward events on timeline | Not implemented | TODO in `activity_list.dart` | — |
| Situation detail (status + blocker + last change) | Sheet exists, unwired | `showBeaconNowDetailSheet` only referenced in its own file + tests | `beacon_now_detail_sheet.dart` |
| Legacy overview dashboard | Dead code | `BeaconStatusDashboard` had need-first + coordination counts; not mounted | `beacon_overview_tab.dart` |
| Commitments | Per-item cards only | No header roll-up of open promises/asks | `items_tab.dart` Active fold |
| Recent change | Log tab only | Requires tab switch; excludes legacy timeline | `activity_list.dart` |

**Room chat risk:** secondary — only when user toggles to Room surface. The dominant gap is **operational tab fragmentation** (Items default + collapsed definition + lazy forwards + Log without full timeline).

---

## Prioritized recommendations (UX / IA only)

1. **Restore a tap-to-expand “Situation” summary at the HUD NOW row** — wire existing `BeaconNowDetailSheet` (status, blocker, last change) or port `BeaconStatusDashboard` / `_SituationPanelBody` patterns from `beacon_overview_tab.dart`. Addresses criteria 3, 8, 9 without scrolling.

2. **Promote need + author to always-visible header fields** — surface `needSummary` (and optional “Started by {author}”) in HUD or app bar subtitle; keep full definition in accordion as secondary. Addresses 1, 2.

3. **Add an unresolved-state strip in the HUD** — aggregate counts: open asks / promises / blockers / unanswered help offers (data already in `ItemsTabCubit` + `BeaconViewState`). Tapping jumps to filtered Active fold. Addresses 7, 8.

4. **Auto-load and elevate forwards for inbox entrants** — render `forwardProvenance` + `inboxLatestNotePreview` in header or top of People tab; drop lazy-load gate for viewers with inbox rows. Addresses 6.

5. **Fix Log tab completeness** — merge cubit `timeline` into `BeaconActivityList` or add HUD “Last event” row (pattern from `buildMyWorkHudMetadataEntries` → `MyWorkLastEventBody` in `beacon_hud_metadata_composer.dart`). Addresses 9; reduces reliance on chronological scanning.

---

## Related docs

- [`features/beacon_room.md`](../features/beacon_room.md) — shipped product spec (Items / People / Log)
- [`beacon-status-line-rationale.md`](../beacon-status-line-rationale.md) — STATUS / NOW / YOU / ACT copy theory
- [`Tentura_current_status_quo.md`](../Tentura_current_status_quo.md) — inbox, My Work, coordination philosophy
