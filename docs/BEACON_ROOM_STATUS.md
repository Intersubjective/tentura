# Beacon Room implementation status

The full specification lives in [`features/beacon_room.md`](features/beacon_room.md).

## Done in repo (incremental)

- **Journal:** [`beacon-room-implementation-journal.md`](beacon-room-implementation-journal.md)
- **Migrations:** `m0036` (room/participant/state/messages/reactions/attachments + `notify_entity_change` for `room_message`/`participant` + migration from commitments + seeds), `m0037` (drop legacy `comment`/`vote_comment`)
- **Server Drift:** new tables wired in [`packages/server/lib/data/database/tentura_db.dart`](../packages/server/lib/data/database/tentura_db.dart); legacy `Comments` removed
- **Removed legacy comment stack (server):** repository, mapper, mocks, OG `C` preview (`SharedViewController` / `SharedViewDocument`)
- **Server runtime:** [`BeaconRoomRepository`](../packages/server/lib/data/repository/beacon_room_repository.dart), [`BeaconRoomCase`](../packages/server/lib/domain/use_case/beacon_room_case.dart) (`@Singleton`)

## Required next steps (ordering)

1. **V2 GraphQL:** register operations (`RoomMessageCreate`, `RoomMessageList`, `BeaconParticipantList`, `BeaconParticipantOfferHelp`, `BeaconRoomAdmit`, `BeaconStewardPromote`, `RoomMessageReactionToggle`, …), add resolver classes under `api/controllers/graphql/` and [`custom_types.dart`](../packages/server/lib/api/controllers/graphql/custom_types.dart), wire [`_mutations_all.dart`](../packages/server/lib/api/controllers/graphql/mutation/_mutations_all.dart) / [`_queries_all.dart`](../packages/server/lib/api/controllers/graphql/query/_queries_all.dart)
2. **Client:** `InvalidationService` branches `room_message` / `participant`, Ferry `.graphql`, `build_client.dart` `_tenturaDirectOperationNames`, `features/beacon_room/*`, `BeaconRoomRoute`, `BeaconViewScreen` integration, Peoples tab rename, remove client `features/comment`
3. **Hasura [`metadata.json`](../hasura/metadata.json):** untrack `comment` / `vote_comment`; track `beacon_participant` / `beacon_steward` / `beacon_room_state` with row permissions — run apply script per skill
4. **PG:** optional trigger on `beacon_room_message_reaction` to fan-out invalidations (or refetch reactions without WS)
5. **Phases 2–6:** per plan — additional migrations (`public_status`, facts, blockers, `activity_event`, unread), notifications, Inbox/My Work/Forward/Activity wiring
