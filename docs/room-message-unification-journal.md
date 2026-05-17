# Room message unification — implementation journal

Plan: `~/.claude/plans/reflective-gliding-star.md`

## Goal
Collapse `coordination_item_message` into `beacon_room_message` via `thread_item_id`. Unified `beacon_room_seen`. Hard cut.

## Progress log

### 2026-05-17 — Implemented (pending migrate + manual QA)
- [x] §3 Server Drift schema (`thread_item_id`, `beacon_room_seen`, drop legacy tables)
- [x] §4 Migration m0072 + `_migrations.dart` (includes draft-item fan-out from m0068)
- [x] §5 Server repo/case/GraphQL (thread filters, `MarkBeaconRoomSeen`, removed item-message endpoints)
- [x] §6–7 Client GraphQL, `RoomMessage.threadItemId`, `RoomCubit` thread mode, `ItemActionsCubit`
- [x] §8 Client UI (`BeaconRoomBody` thread mode + `ItemDiscussionScreen` composition)
- [x] §9 Invalidation (`coordinationItemMessage` removed)
- [x] §10 `build_runner` server + client
- [ ] §12 `make migrate` on dev DB + manual scenarios

## Notes
- m0072 `notify_entity_change` keeps m0068 draft coordination_item creator-only fan-out.
- Client `schema.graphql` updated for V2 (`MarkBeaconRoomSeen`, `threadItemId` on room ops); removed `CoordinationItemMessage*` types.
- Main room seen: `BeaconParticipantRoomSeen` → `markBeaconRoomSeen(threadItemId: null)`; threads use `MarkBeaconRoomSeen`.
- Deleted `item_discussion_cubit_unread_test.dart` (was tied to removed entity); extend `room_cubit_unread_test` for thread unread if needed.
- **Follow-up:** run `make migrate`, verify backfill counts, smoke item thread (reactions, attachments, mentions, reply).
