# Beacon Room implementation journal

Plan: see workspace plan `beacon_room_implementation_54f2f85e.plan.md` (do not edit).

## 2026-04-28 — Phase pre-0.1 — Plan locked

**Decision:** Execute the attached full plan (Phases 1–6) with journal entries before/after non-trivial choices; `m0035` already used for `need_summary` / `success_criteria` — new DB work starts at `m0036`.

**Rationale:** Repo `m0035.dart` is the need-first columns migration, not room tables. Room DDL is appended as `m0036+` to avoid renumbering shipped migrations.

**Alternatives considered:** Renumber (rejected — would break applied DBs).

**Files touched:** `docs/beacon-room-implementation-journal.md`

**Open follow-ups:** Drift + Hasura must follow SQL migrations; client V2 op names in `build_client.dart`.

## 2026-04-28 — Phase 1.1 / 1.9 (partial) — Server DB + scaffold

**Decision:** Implemented `m0036` (new room/participant/state/message/reaction/attachment tables, `notify_entity_change` branches, triggers, beacon author + commitment migrate), `m0037` (drop legacy `vote_comment` + `comment`). Removed server `Comments` drift table + `CommentRepository` + OG shared-view preview for `id=C*` (now `IdWrongException`). Added drift tables + `BeaconRoomRepository` + `BeaconRoomCase` (minimal permissions).

**Rationale:** Unblocks subsequent V2 GraphQL + client wiring; aligns with plan scaffold-from-comment then delete legacy path.

**Alternatives considered:** Keep `comment` table until client shipped — rejected; dropping in migration matches plan Phase 1 cleanup.

**Files touched:** `packages/server/lib/data/database/migration/m003[6-7].dart`, `_migrations.dart`, `tentura_db.dart`, `table/beacon_*`, deleted `comments.dart`/comment repo/mapper/mock/entities, shared view edits, `beacon_room_repository.dart`, `beacon_room_case.dart`, consts bits.

**Open follow-ups:** Register V2 operations (`RoomMessageCreate`, `RoomMessageList`, …) in graphql schema + `mutation_*` / `query_*` + `_mutataions_all` / `_queries_all` + client Ferry + `_tenturaDirectOperationNames`; Hasura metadata remove `comment` tracking + track `beacon_participant`/steward/room_state; reaction table missing `notify_entity_change` trigger (invalidate room on reaction); phases 2–6 migrations (`public_status`, fact cards, blockers, `activity_event`, unread); full client Beacon UI + Peoples tab rename; `MIN_CLIENT_VERSION` if required.

## 2026-04-28 — Phase 1.2 / 1.3 / 1.x client slice (continued)

**Decision:** V2 GraphQL: `RoomMessageList`, `BeaconParticipantList`, mutations `RoomMessageCreate`, `BeaconParticipantOfferHelp`, `BeaconRoomAdmit`, `BeaconStewardPromote`, `RoomMessageReactionToggle`; `custom_types` rows `RoomMessageRow`, `BeaconParticipantRow`. `BeaconRoomCase` refactored `_canUseRoom` (author / steward / admitted) for messages, list, reactions, and new `listParticipants`. Hasura: track `beacon_participant`, `beacon_room_state`, `beacon_steward` with `_or` permissions; removed `comment` / `vote_comment` and comment relationships on `beacon`, `user`, `edge`, `mutual_score`. Client: `InvalidationService` `beaconRoomInvalidations`; `BeaconRoomRepository` + `BeaconRoomCase`; `RoomCubit` / `RoomState`; `BeaconRoomScreen` + `BeaconRoomRoute` (`$kPathBeaconRoom/:id`); “Room” entry on `BeaconView`; l10n keys; `labelCommitments` → People / Люди; `schema.graphql` extended for new V2 ops + row types.

**Rationale:** Participant list stays V2-only to avoid large Hasura introspection churn; Hasura still tracks summary tables for permissions/relationship graph. Room access check unified on server.

**Files touched:** Server `mutation_beacon_room.dart`, `query_beacon_room.dart`, `beacon_room_case.dart`, `custom_types.dart`, `_mutations_all`, `_queries_all`; Hasura `metadata.json`; client `build_client.dart`, `invalidation_service.dart`, `schema.graphql`, `features/beacon_room/**`, `beacon_view_screen.dart`, `root_router.dart`, `consts.dart`, `app_en.arb`, `app_ru.arb`.

**Open follow-ups:** Phase 1.9 delete legacy `features/comment` + comment GraphQL + `Comment` entity / likable usages; Ferry `BeaconFetchById` fragments still reference removed Hasura fields until regenerated from live schema; Phases 2–6 remain; reaction NOTIFY; `schemas.md` / CI schema sync.

## 2026-04-28 — Phase 1.9 (partial) — Remove legacy comments on client

**Decision:** Deleted `features/comment/`, `comment_model`/GraphQL fragments, comment-based deep link (`id=C…`) and `BeaconViewRepository` (replaced by direct `_fetchBeaconByIdWithTimeline` only). Removed `Comment` from `LikeRemoteRepository`. Dropped `like_comment_by_id`, `beacon_fetch_by_comment_id`, `beacon_fetch_by_id_with_comments`, `updated_comments_take`, mocks for `CommentRepository`/`BeaconViewRepository`.

**Files touched:** Deleted paths above; `beacon_view_case.dart`, `beacon_view_cubit.dart`, `beacon_view_state.dart`, `like_remote_repository.dart`, `client_repository_mocks.dart`.

**Follow-up:** Regenerate/track `packages/client/lib/data/gql/schema.graphql` vs live Hasura (still contains obsolete `comment` types until refreshed); Phases 2–6 unchanged.

## 2026-04-28 — Phase 2.1–2.x (incremental)

**Decision:** Migration `m0038` adds `beacon.public_status` (smallint default 0) and `last_public_meaningful_change` (nullable text). **`beacon_commitment` drop deferred:** forward/coordination and Hasura `commitments` still depend on the table; Phase 2.1 drop requires migrating commit flows to `beacon_participant` + coordinating repo refactors first.

**Rationale:** Public status surfaces on Hasura-backed `BeaconModel`/`Beacon` immediately; committing table removal without replacing forward-graph reads would break prod.

**Implementation:** Server: Drift columns on `beacons`; `BeaconRepositoryPort.updatePublicStatus` (author or steward); V2 mutations `BeaconPublicStatusUpdate`, `BeaconRoomStatePlanUpdate`; query `BeaconRoomStateGet`; system room message `semantic_marker = BeaconRoomSemanticMarker.updatePlan` on plan upsert; `RoomMessageRow.semanticMarker`. Client: Ferry ops + `_tenturaDirectOperationNames`; `Beacon.publicStatus` / `lastPublicMeaningfulChange`; `BeaconRoomState` / `fetchBeaconRoomState` / `updateRoomPlan`; `BeaconViewCase`/`BeaconViewCubit.updatePublicStatus`; room screen shows current coordinated plan snippet; Hasura beacon `select` columns extended.

**Files touched:** Server `m0038.dart`, `_migrations.dart`, `table/beacons.dart`, `beacon_repository*.dart`, `beacon_mapper.dart`, `beacon_entity.dart`, `beacon_public_status.dart`, `beacon_room_consts.dart`, `beacon_room_repository.dart`, `beacon_room_case.dart`, GraphQL beacon/room mutations+queries; client `schema.graphql`, `beacon_model.graphql`, `beacon_model.dart`, `beacon_room/**`, `beacon_repository.dart`, `build_client.dart`; `hasura/metadata.json`.

**Follow-up:** Dedicated migration to drop `beacon_commitment` after forward/commit paths use participants only; Overview/Forward/Inbox **strips** using `publicStatus` (UI polish); optional `beacon_order_by` / filters if Hasura complains on new columns.

## 2026-04-28 — Phase 5.4 guardrails + Phase 6 propagation close-out

**Phase 5.4 (mark-done / no-AI):** The room “Mark done” sheet pre-selects resolving the linked blocker when the message is tied to exactly one open blocker, but the user can still switch to “mark message done only” — confirmation is never skipped. Public `beacon.public_status` is **not** changed when a private blocker resolves; only explicit `BeaconPublicStatusUpdate` updates it.

**Phase 6.1 (unread / inbox):** `last_seen_room_at` on `beacon_participant` ships in migration **`m0042`** (plan draft called this `m0044_room_unread`; numbering stayed 0042). Server `InboxRoomContextBatch` + client hints drive inbox card second-line room context and unread counts.

**Phase 6.2–6.3:** My Work cards use room hints for an optional subtitle; Forward screen adds public fact multi-select and “Include public note” for room members only (private state never auto-included).

**Phase 6.4 (FCM):** `BeaconRoomPushService` covers: room admission, need-info (target), **help offer** (beacon author + stewards), **plan updated** (all admitted except actor), **blocker opened / resolved** (affected/resolver participants when set; else author + stewards for open; opened-by + involved for resolve), **next move updated** (when author/steward sets another user’s move), **fact pinned** (public → all `beacon_participant` user IDs; private → admitted only). Payload uses existing `data.link` with `dest=room` for room destinations. Still out of scope for this slice unless specified later: @-mention detection in chat bodies, pushes for beacon lifecycle (closed / review opened), and configurable “correct fact” pushes.

**Phase 6.5:** Before release, manually walk the **16 acceptance rows** in `docs/features/beacon_room.md` and record results in QA notes. Bump server env **`MIN_CLIENT_VERSION`** only if a deploy strictly requires a newer client per `versioning.mdc` (optional UI-only inbox/forward changes usually do not force a gate bump).

**Test fix:** `forward_beacon_page_test` scope row expects **unseen / involved** tabs (not legacy “best” chip scope).

**Files touched (this slice):** `beacon_room_repository.dart` (notify-target helpers), `beacon_room_push_service.dart`, `beacon_room_case.dart`, `beacon_fact_card_case.dart`, `forward_beacon_page_test.dart`, this journal.

