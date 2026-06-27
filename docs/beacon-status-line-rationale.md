# Beacon coordination status line — rationale

## For product/UX

### Theory

Coordination surfaces must **never show an empty status**. Readers should instantly sense *what the situation is waiting for* without inferring from scattered cues.

### Harrison C. White — ambiguity vs ambage

| Concept | Meaning | Row that kills it |
|---------|---------|-------------------|
| **Ambiguity** | Unclear what the shared situation *means* | **STATUS** — identical phase verb for every viewer in a visibility tier |
| **Ambage** | Unclear *who* should act | **YOU** — personal obligation counts / blocked segment |

**STATUS is never personalized and never imperative.**

### Latane & Darley — diffusion of responsibility

Readers move through: **notice → interpret → assume responsibility → know what to do → act**.

| Row | Audience | Role |
|-----|----------|------|
| **STATUS** | identical per tier | Shared phase + slot2 cue |
| **NOW** | identical | Author broadcast + blocker title subline |
| **YOU** | reader only | Personal obligation |
| **ACT** | reader only | One primary CTA (gated by capability) |

Avoid copy that points responsibility at everyone (e.g. “group's move”) — it recreates diffusion. Blocked STATUS uses **“clearing needed”**, not the blocker title.

---

## For implementers

### Clean Architecture layer map

```
UI adapters (thin)
  beacon_anchor_status, my_work_status_line, inbox_item_tile
       ↓ PhaseInput assembly
Presenters
  beacon_phase_presenter — l10n + TenturaTone only
       ↓
Domain
  deriveBeaconCoordinationPhase — priority ladder, rowHarmony, tiers
  OpenBlockerCue, beaconHasUnreviewedOffers
       ↓
Data / Server
  InboxRoomContextBatch — blocker raiser fields (no UI strings)
```

| Rule | Enforcement |
|------|-------------|
| `dep-inward-only` | `lib/domain/**` — no Flutter, l10n, features, ui |
| `adapt-presenter-formats` | All status strings in `beacon_phase_presenter.dart` |
| `adapt-controller-thin` | Adapters: build input → derive → format → widget |

---

## Phase ladder (coordination tier)

| Priority | Phase | Slot2 | Trigger |
|----------|-------|-------|---------|
| 1 | blocked | clearing needed | open + open blocker |
| 2 | wrappingUp | review countdown | reviewOpen |
| 3 | offersAwaitingAuthor | freshness | unreviewed offers |
| 4 | needsMoreHelp | freshness | open-family beacon status = more help needed |
| 5 | enoughHelpInMotion | freshness | open-family beacon status = enough help in motion |
| 6 | coordinating | freshness | reviewed / room asks |
| 7 | lookingForHelpers | no offers yet | open + 0 offers |
| terminal | closed / cancelled | lifecycle ended at | lifecycle terminal |
| floor | draft / open | — | gap |

Ordering aligns with product status quo section 8.2: new offers remain reviewable even when the beacon has enough help in motion.

**Public tier** maps from `beacon.publicStatus` — never exposes `Offers awaiting author`.

---

## Anti-redundancy (`BeaconPhaseRowHarmony`)

| Flag | Effect |
|------|--------|
| `suppressNowPlaceholder` | NOW row skips “no current line” placeholder |
| `suppressYouAwaitingAuthor` | YOU hides duplicate author-awaiting copy; never map author to `Waiting on others` |
| `preferBlockedYouSegment` | YOU shows generic blocked segment when viewer is personally responsible |
| `showBlockedTitleInNowSubline` | Blocker title in NOW only, not STATUS |

Blocked YOU: generic copy + raiser avatar + elapsed time — **only when `responsibleUserId` matches viewer**.

---

## File index

| Layer | Path |
|-------|------|
| Domain types | `packages/client/lib/domain/entity/beacon_coordination_phase.dart` |
| Open blocker VO | `packages/client/lib/domain/entity/open_blocker_cue.dart` |
| Derivation | `packages/client/lib/domain/coordination/derive_beacon_coordination_phase.dart` |
| Presenter | `packages/client/lib/ui/presenter/beacon_phase_presenter.dart` |
| Input builders | `packages/client/lib/ui/presenter/beacon_phase_input_builders.dart` |
| CTA gating | `packages/client/lib/ui/presenter/beacon_phase_cta.dart` |
| HUD status | `packages/client/lib/features/beacon_view/ui/widget/beacon_anchor_status.dart` |
| My Work status | `packages/client/lib/features/my_work/ui/widget/my_work_status_line.dart` |
| YOU line | `packages/client/lib/ui/widget/beacon_you_responsibility_line.dart` |
| Server batch | `packages/server/lib/domain/use_case/beacon_room_case.dart` |

---

## Tests

- `test/domain/coordination/derive_beacon_coordination_phase_test.dart` — ladder, tiers
- `test/domain/coordination/beacon_coordination_phase_boundary_test.dart` — import boundaries
- `test/ui/presenter/beacon_phase_presenter_test.dart` — l10n, blocked copy, CTA gating
