# Item Discussion Unread — Implementation Journal

Plan: `/home/vader/.claude/plans/beacon-screen-items-tab-memoized-blanket.md`

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Migration **m0070** (not m0069) | `m0069.dart` already exists for `coordination_item.stale_at`. |
| D2 | `CoordinationItemWithCounts` on server | Port `listByBeacon` returns row + `messageCount`, `unreadCount`, `lastSeenAt` instead of overloading Drift `CoordinationItem`. |
| D3 | My Desk via **V2 batch query** | Client `MyWorkInit` is Hasura-only (`my_work_fetch.graphql`). No server `my_work_init` resolver. Add `myWorkCoordinationItemActivity(beaconIds)` on V2; merge in `MyWorkRepository.fetchInit`. |
| D4 | `lastCoordinationItemMessageAt` on `MyWorkCardViewModel` | Fold into `newStuffActivityEpochMs` only (no new `MyWorkNewStuffReason` enum) — matches plan: dot lights via epoch max vs `myWorkLastSeenMs`. |
| D5 | Mutation maps stay count-free | `_coordinationItemToMap` in mutations unchanged; counts only on `coordinationItemsByBeacon` query. |
| D6 | Client `CoordinationItem` entity gets count fields | `@Default(0)` for counts; mutation `toEntity()` paths keep defaults. Only `CoordinationItemListModel` parses GraphQL counts. |
| D7 | `mark_item_seen` access check | Mirror `BeaconRoomCase._canUseRoom`: author, steward, or admitted participant on item's beacon. |

## Surprises / blockers

- **vexp/Grep blocked** in workspace — use `rg` in shell or direct `Read` instead.
- **Plan path `m0069_coordination_item_user_seen`** — wrong number; use m0070.
- **Plan `query_my_work.dart`** — does not exist; My Work is Hasura + separate V2 enrichment query.
- **`mark_room_seen_case.dart`** — not found; pattern is `BeaconRoomCase.beaconParticipantRoomSeen` + client `markRoomSeenIfAllowed`.

## Progress checklist

### Server
- [x] Table `coordination_item_user_seen.dart`
- [x] Migration `m0070.dart` + register in `_migrations.dart`
- [x] Register table in `tentura_db.dart`
- [x] Port + repository: `markItemSeen`, `listByBeacon` → `CoordinationItemWithCounts`
- [x] `mark_item_seen_case.dart`
- [x] GraphQL: `gqlTypeCoordinationItemRow` fields, query map, `markCoordinationItemSeen` mutation
- [x] V2 query `myWorkCoordinationItemActivity` + repo method
- [x] `dart run build_runner` server (analyze: fix TypedValue wrap)

### Client
- [x] GraphQL: list fields, mark_seen mutation, my_work activity query + schema.graphql
- [x] `build_client.dart` V2 operation names
- [x] Entity, model, repository, case
- [x] Item discussion state/cubit/screen
- [x] `TenturaCountBadge`, `item_card`, items tab cubit/state, beacon_view badges
- [x] My work view model + repository merge
- [x] `build_runner` client; analyze: errors fixed (surfaceMuted → surfaceContainerHighest)

### Tests (plan optional)
- [ ] `item_discussion_cubit_unread_test.dart` — deferred

## Current subtask

**DONE** — run migration on dev DB when deploying; manual E2E per plan verification section.

## Notes for next reads

- `RoomState` unread getters: `packages/client/lib/features/beacon_room/ui/bloc/room_state.dart` L37–73
- `RoomCubit.markSeenNowIfNeeded`: L117–129; sendMessage reset L359–361
- Items tab badge index: `badges[0]` = Items (`kBeaconTabItems = 0`), line ~1096 `beacon_view_screen.dart`
- Active item statuses: open(0), accepted(1) per `coordination_item_consts.dart`
- `_BadgeBubble` in `tentura_underline_tabs.dart` ~L302 — extract to `TenturaCountBadge`

## Open todos

1. After server codegen: verify `coordination_item_user_seen` in generated drift schema.
2. Register `MarkItemSeenCase` in injectable (annotate `@Singleton` — codegen picks up).
3. Wire `myWorkCoordinationItemActivity` in `_queries_all.dart`.
4. Update `derive_my_work_cards` / cubit if cards need `lastCoordinationItemMessageAt` passed from fetch types.
