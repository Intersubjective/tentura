---
status: done
kind: audit
---
# Room / coordination state — architecture audit

Structured assessment of whether Tentura’s beacon **Room** implements coordination semantics vs. generic chat. Complements the product spec in [`features/beacon_room.md`](../features/beacon_room.md) and the beacon-detail QA matrix in [`docs/audits/beacon-detail-qa-audit.md`](beacon-detail-qa-audit.md).

**Date:** 2025-06-24  
**Scope:** Client + server code paths for Room, coordination items, activity log, access control, blockers, and next-move framing.

---

## Criteria (source)

| # | Criterion |
|---|-----------|
| 1 | Room / coordination state, if enabled |
| 2 | Room is beacon-scoped, not generic chat |
| 3 | Only involved users can access the Room |
| 4 | Semantic actions are explicit: update plan; mark blocker; need info; mark done |
| 5 | No automatic AI state mutation |
| 6 | State-changing actions are attributed |
| 7 | State-changing actions appear in Activity |
| 8 | Blockers require explicit resolution |
| 9 | “Next expected move” is framed as request / promise / wait-state, not managerial assignment |

**Anti-pattern to flag:** Room becomes just Telegram inside Tentura (unstructured messenger dominates; coordination state only updates when users opt into structured actions).

---

## Executive summary

Tentura implements a **beacon-scoped coordination Room**, not a global chat product. Every room message, participant row, coordination item, and activity event is keyed by `beaconId`. Access is gated by beacon lifecycle (`BeaconStatus.allowsCoordination`) and **room admission** (`beacon_participant.room_access == admitted`, plus author/steward bypass). There is no LLM/AI path that mutates room or coordination state.

The architecture deliberately splits **messenger UX** from **coordination semantics**. The Room tab/surface is built on `BasicChatBody` (free text, attachments, reactions, polls, mentions, edit/delete). Structured actions—update plan, mark blocker, need info (ask), mark done, promises—flow through GraphQL mutations into `coordination_item` rows and `beacon_activity_event` audit rows, with room timeline rows linked via `linkedItemId` / `linkedEventKind`. The Items tab, HUD (NOW/YOU), and Log tab carry most coordination framing; the Room itself is described in code as “chat only.”

**Telegram-risk: Medium–High.** The primary interaction model is still a full-featured chat thread. Coordination is opt-in via message promote sheets, overflow menus, and separate tabs. Several design constants (`BeaconRoomSemanticMarker.blocker|needInfo|updatePlan`, `BeaconActivityEventTypeBits.planUpdated`, participant `next_move_*` writes) exist in schema/UI but are **not fully wired on the server**, which weakens semantic enforcement inside the chat stream itself.

---

## Criterion matrix

| # | Criterion | Status | Gap severity |
|---|-----------|--------|--------------|
| 1 | Room / coordination state, if enabled | **Partially met** | Med |
| 2 | Room is beacon-scoped, not generic chat | **Met** | — |
| 3 | Only involved users can access the Room | **Partially met** | Med–High |
| 4 | Semantic actions explicit (plan / blocker / need info / done) | **Partially met** | Med |
| 5 | No automatic AI state mutation | **Met** | — |
| 6 | State-changing actions are attributed | **Met** | Low |
| 7 | State-changing actions appear in Activity | **Partially met** | Med |
| 8 | Blockers require explicit resolution | **Met** | Low |
| 9 | Next expected move as request / promise / wait-state | **Partially met / not fully implemented** | Med |
| — | Anti-pattern: Room as Telegram | **Partially present** | **High** |

---

## Criterion-by-criterion analysis

### 1. Room / coordination state, if enabled

**Status:** Partially met

**Evidence**

| Layer | Location |
|-------|----------|
| DB | `beacon_room_state` — `currentLine`, `openBlockerId` (legacy column), `lastRoomMeaningfulChange`, `updatedBy` (`packages/server/lib/data/database/table/beacon_room_states.dart`) |
| Client entity | `BeaconRoomState` (`packages/client/lib/domain/entity/beacon_room_state.dart`) |
| Server projection | `BeaconRoomCase.beaconRoomStateGet` merges state + open coordination blocker (`packages/server/lib/domain/use_case/beacon_room_case.dart`) |
| Gating | `BeaconStatus.allowsCoordination` (`lib/domain/entity/beacon_status.dart`); client `canCoordinateInBeaconRoom` / `canNavigateBeaconRoom` (`packages/client/lib/features/beacon_view/ui/bloc/beacon_view_state.dart`) |

**Gaps**

- “Enabled” is implicit (beacon status + admission), not a dedicated feature flag.
- `openBlockerId` on `beacon_room_state` was decoupled in migration `m0076`; open blocker is now derived from `coordination_item` kind=blocker.
- `lastRoomMeaningfulChange` / `updateParticipantNextMoveFields` appear underused (no callers for next-move writes).

**Flow:** Beacon view loads cue via `BeaconViewCubit._refreshBeaconRoomCue` → `BeaconRoomCase.fetchBeaconRoomState` → GQL `BeaconRoomStateGet` → server `_canUseRoom` + `_findOpenCoordinationBlocker`.

---

### 2. Room is beacon-scoped, not generic chat

**Status:** Met

**Evidence**

- All room tables FK `beacon_id`: `beacon_room_message`, `beacon_participant`, `beacon_room_state`, `beacon_activity_event`, `coordination_item`
- `BeaconRoomMessages.threadItemId` scopes item discussion threads to a coordination item (`packages/server/lib/data/database/table/beacon_room_messages.dart`)
- Routes: `BeaconRoomScreen(@PathParam('id') beaconId)`, `ItemDiscussionScreen(beaconId, itemId)`
- UI comment: `BeaconRoomSurface` — “Room surface embedded under beacon detail (chat only)” (`packages/client/lib/features/beacon_view/ui/widget/beacon_room_surface.dart`)

**Gaps:** None material — no cross-beacon or DM room found.

---

### 3. Only involved users can access the Room

**Status:** Partially met

**Evidence**

- Server `_canUseRoom`: author OR steward OR `roomAccess == admitted` (`packages/server/lib/domain/use_case/beacon_room_case.dart`)
- Enforced on: `listMessages`, `createMessage`, `beaconRoomStateGet`, `listActivityEvents`, `listParticipants`, mark-seen, semantic done
- Admission: `beaconRoomAdmit`, help-offer coordination responses, author direct-forward auto-admit (client `hasRoomAdmission`)
- Item threads: `_canAccessThread` allows item participants (creator/target/acceptor) even without full room access
- Coordination drafts/mutations (plan): `ensureCanCoordinateOnBeacon` (`packages/server/lib/domain/use_case/coordination_item/coordination_room_access.dart`)

**Gaps / risks**

- **TODO** in `BeaconRoomCase`: “tighten permissions with visibility / forward graph”
- **`MarkBlockerCase`, `MarkAskCase`, `CreatePromiseCase` do not call `ensureCanCoordinateOnBeacon`** — only `allowsCoordination` on beacon. Any authenticated user who can hit the mutation could create items without admission check (GraphQL auth still applies, but room membership is not verified).
- Activity visibility filters public vs room for non-members in My Work (`beacon_room_repository.dart`), but full activity list requires room access.

**Flow:** Client `canNavigateBeaconRoom` → Room APIs → server `_canUseRoom` → 401 `UnauthorizedException`.

---

### 4. Semantic actions are explicit

**Status:** Partially met

| Action | Server use case | GQL mutation | Client entry |
|--------|----------------|--------------|--------------|
| Update plan | `UpdatePlanCase` → `publishRootPlan` | `updatePlan` | Promote sheet, current-line sheet, HUD |
| Mark blocker | `MarkBlockerCase` → `coordination_item` kind=3 | `markBlocker` | Promote sheet (`beacon_room_body.dart`) |
| Need info | `MarkAskCase` → kind=2 (ask) | `markAsk` | Promote sheet + dedicated need-info dialog |
| Mark done | `BeaconRoomCase.roomMessageMarkSemanticDone` | `RoomMessageMarkSemanticDone` | Message action → sets `semanticMarker=done` |

Constants: `BeaconRoomSemanticMarker` (`packages/server/lib/consts/beacon_room_consts.dart`).

**Gaps**

- No inference from chat text for done (explicit mutation only) — good.
- Promote flows require user to open a sheet from a message; free-text send has no semantics.
- Server sets `semanticMarker` only for **done, poll, pin-fact** — not for blocker/needInfo/plan. Those use **`linkedItemId` + coordination item snapshots** on room messages instead (`coordination_item_repository._emitCreatedRoomNotify`).
- UI still handles legacy semantic markers for blocker/needInfo/plan labels (`room_message_tile.dart`) but server rarely/never sets them today.

**End-to-end (mark blocker from message):** UI `_showMarkBlockerSheet` → `RoomCubit.markBlockerFromMessage` → `CoordinationItemCase.markBlocker` → GQL → `MarkBlockerCase` → `CoordinationItemRepository.create` → room notify row + `beacon_activity_event` type `301` (3×100+1).

---

### 5. No automatic AI state mutation

**Status:** Met

**Evidence:** No LLM/OpenAI/Anthropic/generative-AI integrations found under `packages/server` or `packages/client` touching room/coordination paths.

**Gaps:** None observed.

---

### 6. State-changing actions are attributed

**Status:** Met (with nuance)

**Evidence**

- All mutations run under `db.withMutatingUser(actorId, …)` (`coordination_item_repository.dart`, `beacon_room_repository.dart`)
- Activity events store `actorId`, optional `targetUserId` (`beacon_activity_events` table)
- Mark done stores `system_payload.semanticActorId` (`markRoomMessageSemanticDone`)
- Room messages store `authorId`; promoted sources merge `lastStatusEvent.actorId` into `system_payload`
- Client displays actor on mark-done row and log entries (`room_message_tile.dart`, `beacon_activity_event_presenter.dart`)

**Gaps**

- Ordinary chat messages are attributed to authors but are not “coordination state changes.”
- Some notification pushes use `actorUserId` but that’s push, not authoritative state.

---

### 7. State-changing actions appear in Activity

**Status:** Partially met

**Evidence**

- Table `beacon_activity_event` with typed taxonomy (`packages/server/lib/consts/beacon_activity_event_consts.dart`)
- Created on: coordination item create/status (`CoordinationItemRepository`), fact pin/visibility (`beacon_fact_card_repository.dart`), mark done (`BeaconRoomCase.roomMessageMarkSemanticDone`), beacon lifecycle (`beacon_repository.dart`, `evaluation_repository.dart`)
- Client Log tab: `BeaconActivityList(coordinationLogOnly: true)` filters `BeaconActivityEvent.isCoordinationLogEvent` (`activity_list.dart`, `beacon_operational_scroll_view.dart`)
- Real-time: PG triggers → `entity_changes` → WS invalidation → `BeaconViewCubit._refreshRoomActivityEvents`

**Gaps**

- **Free-form chat, reactions, polls (except poll marker message) do not emit activity events.**
- Coarse types `planUpdated=1`, `blockerOpened=10`, `needInfoOpened=12` are defined and referenced in My Work filters but **insert path uses encoded types `kind*100+eventKind`** (e.g. plan create = `101`, blocker create = `301`). Presenter handles both, but `planUpdated=1` appears **never inserted**.
- Plan updates supersede prior plan items; activity shows supersede/created events, not a dedicated “plan updated” coarse event.

---

### 8. Blockers require explicit resolution

**Status:** Met

**Evidence**

- Blockers are `coordination_item` kind=3; legacy `beacon_blocker` table dropped in `m0076`
- Creation: `MarkBlockerCase` / `createDraftBlockerCase` + publish
- Resolution: `ResolveBlockerCase` requires kind=blocker, status=open, then `updateStatus` → resolved (`resolve_blocker_case.dart`)
- Client: `ItemActionsCubit.resolveBlocker`, Items tab, phase CTA `resolveBlocker`, room promote flows
- **Mark done explicitly does not resolve blockers** (server comment in `beacon_room_case.dart`)

**Gaps**

- `ResolveBlockerCase` does not enforce *who* may resolve (only item existence/kind/status) — authorization gap for resolution actor.

---

### 9. “Next expected move” as request / promise / wait-state

**Status:** Partially met / not fully implemented

**Evidence**

- Schema: `beacon_participant.next_move_text`, `next_move_status`, `next_move_source` with enums `BeaconNextMoveStatusBits`, `BeaconNextMoveSourceBits` (`beacon_room_consts.dart`)
- **Promises** (`coordination_item` kind=5): create → target accepts → resolve lifecycle; UI `showBeaconRoomPromiseSheet`, overflow “create promise”
- **Asks** (kind=2) model need-info with required `targetPersonId` (`MarkAskCase`)
- HUD displays `nextMoveText` read-only (`beacon_hud_derivation.dart`, `help_offer_tile.dart`)

**Gaps**

- **`updateParticipantNextMoveFields` has no callers outside the repository** — no API/use case to set next move on participants.
- `BeaconRoomSemanticMarker.participantStatusChanged` is never set on server.
- UX mixes “promise/ask/blocker” coordination items with passive `nextMoveText` display; no dedicated “assignment” language found, but also no complete next-move write path.

---

### Anti-pattern: Room as Telegram inside Tentura

**Status:** Partially present (medium–high risk)

**Evidence for messenger dominance**

- `BasicChatBody` — “Shared chat surface: scroll + message list + composer” with attachments, reactions, polls, mentions (`packages/client/lib/ui/widget/basic_chat_body.dart`)
- Room composer hint `beaconRoomMessageHint`; edit/delete messages; reaction picker; poll creation
- `BeaconRoomSurface` explicitly defers NOW/YOU to Items tab

**Evidence against pure Telegram**

- Promote sheet maps messages → coordination items (blocker, ask, plan, promise)
- Items tab lists open coordination items with structured cards (`items_tab.dart`)
- Log tab shows coordination-only activity
- Fact cards, pinned NOW line, phase CTAs (`derive_beacon_coordination_phase.dart`)
- Item discussion threads reuse room machinery but scoped to coordination items

**Risk:** Users can coordinate entirely via unstructured chat without ever using semantic actions; structured state won't update unless they promote or use Items/HUD.

---

## Code path map

```
Beacon View (operational UI)
├── Items tab
│   ├── ItemsTabCubit → CoordinationItemRepository.list
│   ├── ItemCard / composer sheets → draft/publish mutations
│   └── resolveBlocker → ResolveBlockerCase
├── People tab → help offers, admit (beaconRoomAdmit), stewards
├── Log tab
│   └── BeaconActivityEventList → CoordinationItemRepository activity + lifecycle
├── HUD NOW/YOU
│   ├── BeaconRoomStateGet (currentLine, open blocker)
│   └── CoordinationResponsibilityCase
└── Room tab / BeaconRoomScreen
    └── RoomCubit
        ├── fetchMessages → RoomMessageList (server _canUseRoom)
        ├── createMessage → RoomMessageCreate (free chat)
        ├── promote actions → CoordinationItemCase (markBlocker/markAsk/updatePlan)
        ├── markMessageSemanticDone → RoomMessageMarkSemanticDone
        └── invalidation → InvalidationService → refetch

Server coordination write path (shared)
CoordinationItemRepository.create / updateStatus
├── coordination_item row
├── beacon_room_message notify (linkedItemId, linkedEventKind)
├── beacon_activity_event (type = kind*100 + eventKind)
└── optional push (BeaconRoomPushService)

Access control layers
├── Room read/write: BeaconRoomCase._canUseRoom (author|steward|admitted)
├── Coordination mutate (plan/drafts): ensureCanCoordinateOnBeacon
└── Item thread: _canAccessThread (room OR item participant)
```

---

## Key file index

| Area | Paths |
|------|-------|
| Room access | `packages/server/lib/domain/use_case/beacon_room_case.dart`, `coordination_room_access.dart` |
| Room state | `packages/server/lib/data/database/table/beacon_room_states.dart`, `packages/client/lib/domain/entity/beacon_room_state.dart` |
| Messages | `packages/server/lib/data/database/table/beacon_room_messages.dart`, `packages/client/lib/domain/entity/room_message.dart` |
| Coordination items | `packages/server/lib/data/repository/coordination_item_repository.dart`, `packages/server/lib/consts/coordination_item_consts.dart` |
| Activity | `packages/server/lib/data/database/table/beacon_activity_events.dart`, `packages/client/lib/features/beacon_view/ui/widget/activity_list.dart` |
| Client Room UI | `packages/client/lib/features/beacon_room/ui/widget/beacon_room_body.dart`, `basic_chat_body.dart`, `room_message_tile.dart` |
| GQL | `packages/server/lib/api/controllers/graphql/query/query_beacon_room.dart`, `mutation/mutation_beacon_room.dart`, `mutation/mutation_coordination_item.dart` |
| Constants | `packages/server/lib/consts/beacon_room_consts.dart`, `beacon_activity_event_consts.dart` |

---

## Recommendations (evidence-backed)

| Priority | Recommendation | Moves criterion |
|----------|----------------|-----------------|
| High | Add `ensureCanCoordinateOnBeacon` (or equivalent) to `MarkBlockerCase`, `MarkAskCase`, `CreatePromiseCase`, and `ResolveBlockerCase`; close the TODO on forward-graph visibility in `BeaconRoomCase` | #3 |
| High | Define and enforce who may `resolveBlocker` (creator, target, author/steward, admitted member) | #8 |
| Med | Wire or remove dormant schema: implement next-move mutations (`updateParticipantNextMoveFields`) with `participantStatusChanged` room lines, or document/remove unused columns/markers | #9 |
| Med | Emit consistent activity types: on plan publish insert `BeaconActivityEventTypeBits.planUpdated` (or stop advertising type `1` in filters); align blocker/ask creation with coarse types `10`/`12` if My Work depends on them | #7 |
| Med | When promoting messages, set `semanticMarker` on source/notify rows (blocker/needInfo/updatePlan) so the timeline is self-describing without parsing `linkedItemId` | #4 |
| Product | Reduce Telegram drift: require coordination item creation for certain HUD transitions, or surface promote actions more prominently than raw composer; optionally restrict polls/attachments in main room | Anti-pattern |

---

## Related docs

- [`features/beacon_room.md`](../features/beacon_room.md) — product spec (as shipped)
- [`docs/audits/beacon-detail-qa-audit.md`](beacon-detail-qa-audit.md) — beacon detail information architecture QA
- [`beacon-status-line-rationale.md`](../beacon-status-line-rationale.md) — STATUS/NOW/YOU copy theory
- [`Tentura_current_status_quo.md`](../Tentura_current_status_quo.md) — product direction and axioms
