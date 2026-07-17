---
status: active
kind: plan
---
# Cross-screen beacon state sync — implementation instructions

**Audience:** an LLM/engineer implementing the fix.
**Status:** fact-checked against the codebase on 2026-06-29. File/line references are
real; verify they still hold before editing.

---

## 1. Problem in one sentence

When the current user mutates room/coordination state (send message, update plan,
mark/resolve blocker, mark ask, set beacon status, coordination response), the
**My Work** and **Inbox** list cards stay stale until a full manual refresh,
because those screens never learn the beacon's operational state changed.

## 2. Why it happens (verified)

The server intentionally **suppresses the WebSocket echo to the originating user**.
This is documented and deliberate — `DEV_GUIDELINES.md` § "Echo suppression":

> When a V2 mutation modifies a trigger-carrying table, the originating user
> should **not** receive the invalidation signal back (the client already handled
> the change locally).

Suppression is keyed on the **user**, not the session/screen
(`notify_entity_change()` removes `tentura.mutating_user_id` from `user_ids`
before `pg_notify`). So **every other screen belonging to the same user is also
starved** of the invalidation. The originating client is therefore responsible for
publishing its own local event after a successful mutation — and today it only does
so for *some* entity types.

The app already proves this pattern works for beacons, forwards and help offers:

| Mechanism | Local emit on own write? | Who consumes |
|---|---|---|
| `BeaconRepository.changes` (`RepositoryEvent<Beacon>`) + `refreshAndNotify(id)` | ✅ create/update/delete/publish + close/cancel/reopen | `MyWorkCubit._onBeaconChanged` |
| `ForwardRepository.helpOfferChanges` (`HelpOfferEvent`) | ✅ `offerHelp` → `HelpOfferCreated`, `withdraw` → `HelpOfferWithdrawn` | `MyWorkCubit`, `InboxCubit` |
| `ForwardRepository.forwardCompleted` (`String beaconId`) | ✅ after `forwardBeacon` | `MyWorkCubit`, `InboxCubit` |
| `RoomReadWatermarkStore.changes` | ✅ on local read-through | `MyWorkCubit` (via `MyWorkCase.readWatermarkChanges`) |

Reference: `features/beacon/data/repository/beacon_repository.dart:46-48,287-292`;
`features/forward/data/repository/forward_repository.dart:77-87,135-141,435-460`.

The **room/coordination layer is the gap.**

## 3. Verified ground truth — do NOT re-derive, this was checked

Read this before trusting the original proposal; several of its premises are
slightly wrong.

1. **`BeaconRoomRepository`** (`features/beacon_room/data/repository/beacon_room_repository.dart`)
   - Owns `beaconRoomRefresh` (`Stream<String>` of beaconId), but it emits **only**
     from *remote* invalidations (`_roomInvSub`, lines 43-53), filtered to
     `roomMessage | participant | coordinationItem`.
   - Local mutations — `createMessage` (329), `editMessage` (381),
     `deleteMessage` (399), `participantOfferHelp` (420), `admit` (434),
     `promoteSteward` (448), `toggleReaction` (462), `createPoll` (478) — emit
     **nothing**. ⬅ this is the core hole.

2. **`CoordinationItemRepository`** (`features/coordination_item/data/repository/coordination_item_repository.dart`)
   - Pure remote wrapper, **no change stream** — *correct* in the original doc.

3. **`CoordinationItemRoomSync` ALREADY EXISTS** — the original doc missed this.
   (`features/beacon_room/domain/coordination_item_room_sync.dart`) A `@lazySingleton`
   exposing `Stream<CoordinationItem> changes` + `notifyItemUpdated(item)`. But:
   - Its only producer is `ItemActionsCubit._runItemMutation`
     (`features/coordination_item/ui/bloc/item_actions_cubit.dart:72`) — i.e. the
     **dedicated item-thread screen**, not the main room mutations.
   - Its only consumer is `RoomCubit` (`room_cubit.dart:53`) to patch the timeline.
   - It is **not** consumed by My Work or Inbox, and **not** produced by
     `RoomCubit`'s own coordination mutations.

4. **`RoomCubit`'s own coordination mutations throw the result away.**
   `BeaconRoomCase.updateRoomPlan/markAskFromMessage/markBlockerFromMessage/`
   `createPromise/resolveCoordinationBlocker` each call the coordination case and
   discard the returned `CoordinationItem` with `.then((_) {})`
   (`features/beacon_room/domain/use_case/beacon_room_case.dart:194-211,275-333`).
   So even the *existing* `CoordinationItemRoomSync` bus is never fed by these.

5. **`BeaconActivityEventRepository` already has `changes`** (`Stream<String>`),
   but remote-only (subscribes to invalidations). Activity events are
   server-generated side effects — there is no local "create activity" mutation, so
   remote-only is acceptable. The original doc implied this stream must be created.

6. **`BeaconFactCardRepository` has no change stream.** Fact mutations
   (`pin/correct/remove/setVisibility`, called from `RoomCubit`) emit nothing.

7. **`MyWorkCubit`** (`features/my_work/ui/bloc/my_work_cubit.dart:23-38`) listens to
   exactly four streams: `beaconChanges`, `helpOfferChanges`, `forwardCompleted`,
   `readWatermarkChanges`. **The net-missing inputs are: room-slice changes and
   coordination-item changes.** (The original doc's longer "to-merge" list is
   misleading — beacon/help/forward/watermark are already wired.)

8. **`InboxCubit`** (`features/inbox/ui/bloc/inbox_cubit.dart:33-44`) listens to
   `helpOfferChanges`, `forwardCompleted`, `inboxCase.localMutations`. Same two
   missing inputs (room + coordination), *if* Inbox cards render room hints — and
   they do: `InboxCubit._withResolvedRoomUnread` + `item.roomHints`
   (`inbox_cubit.dart:142-154`).

9. **Beacon-level holes — confirmed real:**
   - `BeaconViewCase.setBeaconStatus` (`beacon_view_case.dart:192-198`) delegates to
     `CoordinationRepository.setBeaconStatus` and does **not**
     `refreshAndNotify`. Contrast with `beaconClose/Cancel/Reopen/CloseNow/`
     `ExtendReview/publishBeacon`, which all correctly call `refreshAndNotify`
     (lines 109-140, 312-315).
   - `BeaconViewCase.setCoordinationResponse` (178-190) delegates only; it changes
     room participants (invite/remove) **and** help-offer/beacon status, yet emits
     no event. `CoordinationRepository.setCoordinationResponse` already returns the
     new `BeaconStatus` (`coordination_repository.dart:77-103`) — usable for an
     optimistic patch.

## 4. Corrections to the original proposal

Apply the fix, but **do not** follow the original design literally:

- **Do NOT invent a new `BeaconClientEvent` sealed hierarchy with
  `BeaconChangeOrigin` / `BeaconChangeScope`.** It duplicates types that already
  exist: `BeaconRoomInvalidation` + `BeaconRoomEntityType { roomMessage,
  activityEvent, participant, factCard, blocker, coordinationItem }`
  (`features/beacon_room/domain/entity/beacon_room_invalidation.dart`). Reuse it.
- **Drop the `origin` enum for Phase 1.** No consumer needs to distinguish "local
  confirmed" from "remote invalidated" — both just trigger a silent refetch.
  Adding origin now is speculative complexity. Only introduce it in Phase 2 *if* a
  consumer genuinely needs to suppress its own optimistic echo.
- **Reuse `CoordinationItemRoomSync` (or generalize it), don't add a parallel
  coordination stream.** The bus already exists; the work is (a) feed it from the
  missing producers and (b) add the missing consumers.

## 5. Recommended design — "own writes emit the same events as remote writes"

The invariant (keep this exact wording in code comments):

> Every successful local mutation that changes beacon-visible room/coordination
> state emits the same `BeaconRoomInvalidation`-shaped event that a remote WS
> invalidation would have produced. List/detail screens subscribe to one merged
> stream and silently refetch the affected beacon.

Concrete shape (minimal new surface):

1. **One injectable local event bus** carrying `BeaconRoomInvalidation`. Either
   generalize the existing `CoordinationItemRoomSync` into a
   `BeaconRoomLocalChangeBus` (preferred — single bus, typed by `entityType`), or
   add a sibling singleton. It must be writable from **both**
   `BeaconRoomRepository` and `CoordinationItemRepository` (they live in different
   features), so it belongs in a shared location both can import — keep it under
   `features/beacon_room/domain/` as today, or move to `lib/domain/` if the lint
   layering forbids `coordination_item → beacon_room`. **Check the import-direction
   lints first** (`tentura_lints`; see AGENTS.md design-system/layering invariants)
   and place it where neither feature imports "up".

2. **Producers emit after success.** In each local mutation, after the network
   call resolves, push `BeaconRoomInvalidation(beaconId, entityType)`:
   - `BeaconRoomRepository.createMessage/editMessage/deleteMessage` → `roomMessage`
   - `participantOfferHelp/admit/promoteSteward` → `participant`
   - `toggleReaction` → `roomMessage` (or skip; reactions don't change desk cards)
   - `BeaconFactCardRepository.pin/correct/remove/setVisibility` → `factCard`
   - `CoordinationItemRepository` mutations that return a `CoordinationItem`
     (`markBlocker/resolveBlocker/markAsk/createPromise/updatePlan/...`) →
     `coordinationItem`. Also keep feeding the existing
     `CoordinationItemRoomSync.notifyItemUpdated(item)` for RoomCubit timeline
     patching, **or** fold both into the one bus and have RoomCubit derive the item
     from a refetch.

3. **Fix the result-discarding use cases.** In `BeaconRoomCase`, stop dropping the
   returned `CoordinationItem` in `updateRoomPlan/markAskFromMessage/`
   `markBlockerFromMessage/createPromise/resolveCoordinationBlocker`; route it to
   the bus (directly or by letting the repository emit — emitting in the repository
   is cleaner because it covers *all* callers including `ItemActionsCubit`).

4. **`beaconRoomRefresh` merges local + remote.** Make
   `BeaconRoomRepository.beaconRoomRefresh` (consumed by `RoomCubit`) also surface
   the local bus, so the room screen keeps working unchanged and gains
   self-consistency for free. (If the bus lives outside the repo, merge with
   `Rx.merge` in `BeaconRoomCase.beaconRoomRefresh`.)

5. **Expose a merged "desk-relevant" stream and consume it.**
   - `MyWorkCase`: add `Stream<String> get deskRelevantChanges` = merge of the
     local/remote room bus (mapped to beaconId) + coordination changes. (beacon /
     help / forward / watermark are *already* wired in `MyWorkCubit` — do not
     duplicate them.)
   - `MyWorkCubit`: subscribe and `unawaited(fetch(showLoading: false))`,
     **debounced per beaconId** (see §8).
   - `InboxCase` / `InboxCubit`: same, since inbox cards show room hints + unread.

6. **Patch the beacon-level holes (independent, do first — smallest, safest):**
   - `BeaconViewCase.setBeaconStatus`: `await _beaconRepository.refreshAndNotify(beaconId)`
     after the mutation (mirror `beaconClose`). Optionally patch the returned status
     optimistically.
   - `BeaconViewCase.setCoordinationResponse`: after success, emit a help-offer
     event (it changes offer/coordination state) **and** a `participant` room event
     (invite/remove), and `refreshAndNotify(beaconId)` (status may change).

## 6. Server-derived state: invalidate, don't recompute

Much beacon state is **computed on the server** (status transitions, responsibility
counts, derived room cues live behind the server's `beacon_repository_port` /
`coordination_repository_port` / evaluation use cases). Echo suppression can look
like it forces the client to reproduce that logic locally — it does **not**, *if*
this rule is followed. The guideline phrase "the client already handled the change
locally" is imprecise: the originating client never re-derives server state. It
obtains the result one of two ways, both of which keep the server as the single
source of truth:

- **(a) Refetch — the pattern in this repo.** After the mutation the originating
  screen re-pulls the affected projection and reads back the server-computed value.
  See `beacon_view_cubit.dart:337-409`: both `setBeaconStatus` and
  `setCoordinationResponse` `await _fetchBeaconByIdWithTimeline()`; neither computes
  the new status. Same idea as `BeaconRepository.refreshAndNotify`.
- **(b) In-band return.** The mutation response already carries the server result —
  `CoordinationRepository.setBeaconStatus` / `setCoordinationResponse` return
  `({BeaconStatus status, DateTime? updatedAt})`. The server did the derivation and
  handed it back; the caller may apply that directly instead of refetching.

Echo suppression is safe precisely because, for the originating user, the WS echo
would be **redundant** with (a)/(b) — not because the client computes anything.

What suppression actually breaks is **reach, not correctness**: it is keyed on the
*user*, so the return value and the refetch only update the **one screen that
issued the mutation**. My Work / Inbox on the same device get neither — and they
must not recompute the derived value (they would be guessing). That is exactly the
gap this refactor closes: the originating screen broadcasts a local *invalidation*;
the other screens **refetch** the server truth. Still zero duplication.

Two hard constraints follow — keep them as code-review gates:

1. **The local bus carries invalidations (id + entity type), never derived state.**
   `BeaconRoomInvalidation` is deliberately just an id and an enum. Putting a
   computed `status` (or count, or cue) on the bus would re-create the duplication
   trap — two places would then "know" the value. Each consumer refetches through
   its own use case. (This is also the `dep-data-crossing-boundaries` point: ship an
   id, not a rich object.)
2. **Optimistic patches (Phase 2 / step 7) are allowed only for fields the client
   authored verbatim — never for server-derived fields.** `setCoordinationResponse`
   already models the discipline: it optimistically patches only what it knows
   exactly — the `responseType` it just sent and room-access add/remove
   (`applyCoordinationRoomParticipantPatch`) — and leaves the **beacon status** to
   the refetch. Patchable: plan-line text, message body, the chip the user clicked.
   Refetch-only: status transitions, responsibility counts, anything the server
   computes. A contributor "optimizing" by guessing a status locally is the failure
   mode this section exists to prevent.

## 7. Step order (each step independently shippable)

1. **Beacon-level holes** (§5.6) — tiny, no new types, immediate user-visible win.
2. **Local emission in repositories** (§5.2) using existing `BeaconRoomInvalidation`.
3. **Stop discarding results in `BeaconRoomCase`** (§5.3).
4. **Merge into `beaconRoomRefresh`** (§5.4) — verify RoomCubit still behaves.
5. **`MyWorkCase.deskRelevantChanges` + `MyWorkCubit` subscription** (§5.5).
6. **Inbox** equivalent.
7. *(Optional, later)* per-action optimistic patches — **only for client-authored
   fields, never server-derived ones** (§6): plan line and blocker *title* are OK;
   the beacon **status chip is not** (refetch it). Only after the silent-refetch
   version is proven. The original doc's Phase-3 normalized `BeaconProjectionStore`
   is **out of scope**; do not start there.

## 8. Pitfalls (verified, easy to get wrong)

- **One semantic action fans out server-side.** e.g. `markBlockerFromMessage`
  creates a coordination item *and* a system room message *and* an activity event.
  The latter two are **echo-suppressed**, so the client never receives them as
  local events. Therefore the consumer must **refetch enough to capture derived
  state**, not try to patch from the single event it saw. For My Work/Inbox a full
  `loadDeskInit` / `fetch` per affected beacon already re-pulls room hints
  (`MyWorkCase._enrichDeskCards` → `_roomHints.fetchByBeaconIds`), so one debounced
  refetch is correct.
- **Debounce per beaconId.** Multiple local emits for one action will otherwise
  trigger N refetches. Remote invalidations are already debounced 500ms in
  `InvalidationService` (`bufferTime`), but the **local bus is not** — add the
  debounce in the bus or in the cubit (`MyWorkCubit` already has `_fetchSeq`
  guarding stale completions; add a short per-beacon coalescing window on top).
- **Don't double-fire.** If you both (a) emit the local event and (b) the server
  ever stops suppressing for cross-session, you'd refetch twice — acceptable
  (idempotent refetch) but watch for loading flicker; always use
  `fetch(showLoading: false)`.
- **Layering lints.** `coordination_item` importing `beacon_room` (or vice-versa)
  may trip `tentura_lints`. Put the shared bus where the dependency direction is
  legal; verify with `cd packages/tentura_lints && dart test` (the CLI
  `flutter analyze` does **not** run the custom rules here — see the project memory
  note on the lints CLI caveat).
- **Dispose every new subscription/controller.** Match existing `@disposeMethod`
  patterns; cancel new `StreamSubscription`s in cubit `close()`.
- **No forbidden mechanisms.** Do not introduce GraphQL subscriptions, HTTP polling
  timers, `Navigator.pop(result: true)` refresh hooks, or WS parsing outside
  `InvalidationService` — all explicitly rejected by `DEV_GUIDELINES.md`.

## 9. Tests

- Unit: each repository mutation emits exactly one event of the right
  `entityType` on success and **none** on failure (mirror existing
  `ForwardRepository` offer/withdraw tests).
- `BeaconRoomCase`: the result-forwarding change actually pushes the returned item.
- Cubit: a fake bus emission triggers exactly one `fetch(showLoading: false)` after
  debounce; verify `MyWorkCubit`/`InboxCubit` patch the right card fields
  (`roomCurrentLine`, `roomOpenBlockerTitle`, unread).
- Regression: `RoomCubit` and `ItemActionsCubit` still receive coordination
  snapshots after the bus refactor (don't break the existing Room↔Room sync at
  `room_cubit.dart:53` / `item_actions_cubit.dart:72`).
- Run `build_runner` after any DI (`@injectable`/`@singleton`) change; the
  generated `app/di/di.config.dart` is gitignored and must be regenerated.

## 10. Acceptance

Mutate room/coordination state on one screen, navigate to My Work / Inbox without
manual refresh, and the card reflects the change (current line, open blocker,
unread, beacon status) within one debounce window — with no GraphQL subscription,
no polling timer, and no navigation-result plumbing.
