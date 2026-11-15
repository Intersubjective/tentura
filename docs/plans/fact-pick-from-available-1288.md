# Facts: global search in every fact picker, «Pick from available» in Add fact — plan (#1288)

**Status:** shipped (2026-11-16). Was: draft for Alloy (2026-11-15, rev 2: owner scope change — global search on every surface that offers a
choice of a fact). Builds on [fact-continuity-architecture.md](fact-continuity-architecture.md) (rev 4, shipped as
epic tentura-zzla; ADR [0014](../adr/0014-fact-continuity.md)). D1–D20 and R1–R6 there stay binding.
Path shorthand: `S/` = `packages/server/lib`, `C/` = `packages/client/lib`.

## 1. What we build

- One server search over every fact the viewer may read (not a global index).
- One shared picker: `FactPickerSheet` with a **scope switch** — «In this Request» / «In this Post», «★ Saved»,
  «All my facts» — and an always-visible search field. The old rule «search only when more than 5 rows» goes.
- Every surface that offers a choice of a fact uses it (inventory, §2). Picking a fact from another episode always
  goes through the existing copy path (`BeaconFactCardCopy`: provenance, marker-20 line, «Already there» dedupe).
- The Facts lists' «Add fact» offers «New fact» (the existing composer) and «Pick from available» (the picker in
  bring-here mode).

## 2. Surface inventory (client, verified 2026-11-15)

| # | Surface | Where | Today | In this epic |
|---|---|---|---|---|
| I1 | Chat composer «Fact» (quote) — **Request chat** | `C/features/beacon_threads/ui/widget/beacon_room_body.dart` `onPickFact` → `showFactPickerSheet` (host chain: `beacon_view/ui/widget/beacon_room_surface.dart` → `ThreadDetail` → `BeaconRoomBody`) | tabs «In this Request» + «Saved» (writable room only); search only when > 5 rows | scope switch with «All my facts»; pick from elsewhere = copy here + quote (§6.3 path, `RoomCubit.quoteFactFromElsewhere`) |
| I2 | Chat composer «Fact» (quote) — **Post chat** | same `BeaconRoomBody` via `post_view/ui/screen/post_view_screen.dart` → `BeaconRoomSurface`; `isPost: true` | as I1, first tab «In this Post» | as I1 |
| I3 | Request Facts sheet «Add fact» | `C/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart` (button `TestIds.beaconFactsAdd`); opened from `beacon_now_surface.dart`, `beacon_view_screen.dart` | composer only | menu: «New fact» / «Pick from available» (bring-here mode) |
| I4 | Post Facts list | `C/features/post_view/ui/widget/post_info_sheet.dart` `_Facts` (the Post's only fact list, R6) | list only, hidden when empty, no Add | heading + the same «Add fact» menu when the Post room is writable, also with zero facts |
| X1 | Fork «Facts to bring» | `C/features/beacon_plan/ui/widget/plan_copy_sheet.dart` → `C/ui/widget/facts_to_bring_checklist.dart` | checklist of the **source** Request's facts | **not changed** — see §7 Q1 |
| X2 | Bud «Facts to bring» | `C/features/beacon_create/ui/widget/info_tab.dart` → `FactsToBringChecklist` | checklist of the **source** Post's facts | **not changed** — see §7 Q1 |

Not fact choices (checked): the questions lobby chat (`beacon_lobby_chat.dart`, `RoomCapabilities.questions()`
has `composerTools = false`, so no fact pick); `fact_copy_destination_sheet.dart` (chooses a destination, not a
fact); fact display in `room_message_tile.dart`, `beacon_hud_pinned_block.dart`, `beacon_operational_header_card.dart`,
`beacon_now_surface.dart` (open the Facts sheet, choose nothing).

## 3. Decisions

| # | Topic | Decision |
|---|---|---|
| P1 | Search scope (not a global index) | Candidate facts live in a beacon the viewer **belongs to** — author, steward, or a `beacon_participant` row with `room_access <> 5` (left) — **or** are in the viewer's `user_saved_fact`. Nothing else is scanned. |
| P2 | Access rule | Each candidate passes the plan §4.4 rule exactly as `SavedFactRepository.list` applies it: `status <> removed`; draft → author only; request-visible needs `can_read`, discussion-only needs `can_use_room`; `beacon_fact_access` computed **once per distinct beacon** (MATERIALIZED CTE). Blocks come in through `beacon_can_read_content` (m0309). |
| P3 | No text for unreadable facts | Rows failing P2 are dropped, never returned as «unavailable». The search never errors for a hidden fact; its only errors are auth and rate limit. |
| P4 | Matching | Same fold and word rule as Field search (`S/domain/use_case/field_visibility_case.dart` `_fold`/`_words`; SQL `_matches` in `S/data/repository/field_search_reader.dart`): lower-case, ё→е, every word must occur, `strpos` (so `%`/`_` are literal). Matched against the head text (`COALESCE(r.fact_text, c.fact_text)` as in the saved list). Fewer than 2 folded runes → empty list, no DB call, no rate-limit charge. |
| P5 | Ranking and cap | Saved matches first (`user_saved_fact.created_at DESC`), then the rest by `beacon_fact_card.updated_at DESC, id`. At most `kMaxFactSearchResults = 30` (new const in `S/consts/beacon_fact_card_consts.dart`). |
| P6 | Destination exclusion | Optional `excludeBeaconId` drops facts of that beacon (the picker shows them under «In this Request/Post»; copy would refuse them as same-episode, `prepareCopies` step 3). Narrowing only, so no authorisation needed. |
| P7 | Rate limit | In-memory per-user sliding window, new `FactSearchRateLimiter` in `S/domain/policy/` (shape of `debug_send_rate_limiter.dart`). Env `FACT_SEARCH_RATE_MAX` (default 30) per `env.factEditRateWindow` (60 s). Over it → existing `BeaconFactCardRateLimitedException` (client already words it). Per isolate, so the effective cap is `isolatesCount ×` that; accepted — a DB counter would write a row per search (SSD write budget). |
| P8 | Copy rules | Unchanged. Every cross-episode pick calls `BeaconFactCardCopy`; read-only/closed sources stay copyable (X14); destinations follow §5.3; the copy rate limit applies. |
| P9 | One picker | `FactPickerSheet` is the only picker. A shared controller (`FactPickerCubit`, `C/features/beacon_threads/ui/bloc/`) owns scope, query, saved list, server results (300 ms debounce, stale responses dropped) and the pick outcome. One row builder renders all three scopes (★ on saved rows). |
| P10 | Scopes and search | Search field always visible. «In this …» and «★ Saved» filter locally with the P4 fold; «All my facts» queries the server (≥ 2 chars; before that a hint). Quote mode (I1, I2) opens on «In this …»; bring mode (I3, I4) has no «In this …» scope and opens on «★ Saved». In a read-only room, quote mode shows only «In this …» (copy is impossible), as today. Saved rows of this very episode: quote mode quotes them in place (today's behaviour); bring mode hides them. |
| P11 | Pick behaviour | Quote mode: a fact of this episode → quote; from elsewhere → copy here, reload, quote the copy (`RoomCubit.quoteFactFromElsewhere`, `alreadyThere` the same). Bring mode: copy here → host refresh (`onBrought`) → close → snackbar «Fact added» or the existing «Already there». Failures via `factCopyFailureText`; unavailable → that row re-renders «No longer available». |
| P12 | Add-fact menu | One shared widget (`FactAddMenuButton`, `C/features/beacon_threads/ui/widget/`) used by I3 and I4: M3 `MenuAnchor` + two `MenuItemButton`s (pointer and keyboard; no long-press). Shown only where «Add fact» is allowed today (Request: `canCoordinateInBeaconRoom`; Post: `RoomState.canWriteDiscussion`). |

## 4. Server

No migration: the candidate set is index-bounded (`beacon_participant_user_beacon_idx`, `beacon_fact_card_beacon_idx`,
`user_saved_fact` PK). If a bead finds one necessary, the next free number is **m0315** (latest is `m0314`).

- `S/domain/port/saved_fact_repository_port.dart` + `S/data/repository/saved_fact_repository.dart`:
  `search({required String userId, required List<String> words, String? excludeBeaconId, required int limit})`
  → `List<Map<String, Object?>>`. One statement: candidates (P1) → text match (P4) → per-beacon access (P2) →
  order + limit (P5). Row: `factCardId, beaconId, beaconKind, factText, attachmentsJson, saved` (all non-null).
- `S/domain/use_case/saved_fact_case.dart`: `search({userId, query, excludeBeaconId})` — fold/split (move
  `_fold`/`_words` out of `field_visibility_case.dart` into a shared util; do not copy them), short-query
  short-circuit, rate limit (P7), repository.
- GraphQL V2 (facts are not in Hasura metadata, so no Hasura change): `BeaconFactCardSearch(query: String!, excludeBeaconId: String)`
  → `[BeaconFactCardSearchRow!]!` in `S/api/controllers/graphql/query/query_saved_fact.dart`; type
  `gqlTypeBeaconFactCardSearchRow` in `custom_types.dart`, registered beside `gqlTypeBeaconFactCardSavedRow`.
- `S/env.dart`: `factSearchRateMax` (`FACT_SEARCH_RATE_MAX`).

## 5. Client

- Data: `C/data/gql/schema.graphql` (`BeaconFactCardSearch`, `v2_BeaconFactCardSearchRow`), new
  `C/features/beacon_threads/data/gql/beacon_fact_card_search.graphql`, `build_runner`;
  `BeaconFactCardRepository.search({query, excludeBeaconId})` → `List<BeaconFactSearchHit>`
  (`factCardId, beaconId, beaconKind, factText, attachmentsJson, saved`); `BeaconThreadsCase.searchAvailableFacts`.
- Controller: `FactPickerCubit` (P9) over `BeaconThreadsCase` (`savedFacts`, `searchAvailableFacts`, `copyFact`,
  `unsaveFact`); no `RoomCubit` dependency, so I3 (which has only `BeaconViewCubit`) can use it.
- Sheet: `FactPickerSheet` takes a mode — quote (needs the `RoomCubit`, as today) or bring
  (`beaconId`, `isPost`, `onBrought`) — and renders scopes, search and rows from `FactPickerCubit`. Entry points:
  the existing `showFactPickerSheet` (I1, I2) and a new `showFactPickFromAvailableSheet` (I3, I4).
- Strings (EN/RU, added with the widget that first needs them): «All my facts» / «Все мои факты», «★ Saved» reuses
  `beaconRoomFactPickerTabSaved`, «New fact» / «Новый факт», «Pick from available» / «Выбрать из доступных»,
  «Pick a fact» / «Выберите факт», search hint «Search facts» / «Поиск фактов», «Type 2 or more letters» /
  «Введите хотя бы 2 буквы», «Nothing found» / «Ничего не найдено», «Fact added» / «Факт добавлен».
  Users see Request/Post/Chat, never beacon/room/episode.
- Layout: phone 375×667 in EN and RU — the three scope labels, menu items and rows do not overflow
  (`TenturaUnderlineTabs` does not scroll: shorten labels if they do not fit).

## 6. Beads (one epic, in this order)

Server query → use case + GraphQL → client data → `FactPickerCubit` → `FactPickerSheet` scopes → surface wiring
(I1+I2 chat quote picker, I3 Request Add fact, I4 Post Add fact) → L10n pass (RU/EN wording + 375×667 overflow
across all surfaces) → web integration scenario → docs → ship.

## 7. Tests

| Bead | Test (paths relative to the package) |
|---|---|
| Server query | `test/data/repository/saved_fact_search_pg_test.dart`: member sees both visibilities; a stranger to a public Request gets nothing (not global); requested participant gets request-visible only; block pair hides; removed and another user's draft excluded, own draft included; saved fact of a left Request: request-visible kept, discussion-only dropped; saved first; limit; `excludeBeaconId`; ё/е and `%` literal; multi-word AND. |
| Use case + GraphQL | `test/domain/use_case/saved_fact_search_case_test.dart`, `test/api/controllers/graphql/beacon_fact_card_search_endpoint_pg_test.dart`. |
| Client data | `test/features/beacon_threads/fact_search_repository_test.dart`. |
| Controller | `test/features/beacon_threads/fact_picker_cubit_test.dart`. |
| Sheet | `test/features/beacon_threads/fact_picker_scopes_test.dart` (+ existing `fact_picker_sheet_test.dart`, `fact_picker_saved_tab_test.dart`, `issue_481_fact_picker_empty_test.dart` updated). |
| I1+I2 | `test/features/beacon_threads/fact_picker_chat_all_scope_test.dart`. |
| I3 | `test/features/beacon_view/beacon_pinned_facts_add_menu_test.dart`. |
| I4 | `test/features/post_view/post_info_sheet_add_fact_test.dart`. |
| L10n | `test/features/beacon_threads/fact_pick_available_strings_test.dart` (RU/EN keys, terminology, 375×667 RU/EN overflow for picker + menu). |
| Web | `integration_test/fact_pick_from_available_test.dart`, run `scripts/run_client_integration_web_local.sh integration_test/fact_pick_from_available_test.dart` unwrapped. |

## 8. Open questions

- **Q1 (owner):** fork and bud «Facts to bring» checklists (X1, X2) choose among the source's facts, and the server
  binds them to the source (`prepareCopies(requiredSourceBeaconId: …)`, plan §5.6/§5.7, R1 skip rule). Adding
  global search there needs server changes to fork and bud, so this epic leaves them out. Say if they should get
  a follow-up epic.
- P1 counts any non-left participant row (requested, invited, muted) as belonging; the access rule still limits
  them to request-visible facts. Narrow to admitted-only if preferred.
