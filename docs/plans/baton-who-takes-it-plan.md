# «Who'll take it?» (internal: baton) — design + implementation steps

Status: rev 1, 2026-10-03. Epic in beads: see §7. Branch: builds on `feature/post-constellation`
(needs `RoomHost` / `RoomCapabilities` and Post rooms; all brd4 server units are already closed, so
migration numbers do not collide).

## 1. What it is

A lightweight way to turn "can someone do this?" in a room into exactly one named person, without
creating a task. The author of a room message asks a few room members privately and in parallel
whether they can help. Answers are visible only to the author. The author picks one person who said
yes, or lets the system pick, at any time. After that the room sees only «Vadim took it.»

It is **not** Ask / Promise / Blocker / task management: no due date, no status after selection, no
obligation in My Work, no sub-request. The state is a small attachment to one room message. If the
work needs its own coordination, people create a sub-request by hand as today.

### 1.1 Decisions (owner, 2026-10-03)

| # | Decision |
|---|---|
| D1 | Any admitted room member may start a baton, **only on their own** non-system message. The "author" below is that message's author (not necessarily the Request/Post author). |
| D2 | Manual override may pick **only candidates who answered «Can help»**. Nobody takes it without saying they are available. |
| D3 | Candidates are told through an **attention receipt** (Activity + push) **and** a private card on the message. The selected person also gets a receipt. |
| D4 | Available in **Requests and Posts** rooms. |
| D5 | Receipts are **not obligations** (`requires_action = false`): "Can help" is availability, not responsibility, so nothing lands in My Work. |
| D6 | One live baton per message. A cancelled baton frees the message for a new one; a taken baton is final. |
| D7 | Candidates: 1–12 admitted members of the room, never the author; priority tiers 1–3 (1 = highest, default 1 for everyone). |
| D8 | The baton never waits: «Choose now» is available as soon as at least one person said «Can help». When everyone has answered, the author is prompted (in-room + one receipt). Nothing is auto-selected. |
| D9 | Candidates may change their answer while the baton is collecting. |
| D10 | Ordinary room members see nothing while collecting. After selection they see a system line «Vadim took it.» and a small chip on the source message. Refusals, unanswered people, tiers and the candidate list are never shown to anyone but the author. |
| D11 | A cancel is silent for the room. Candidates' cards switch to «No longer needed». |

### 1.2 States

```
baton.status:      0 collecting ──select──▶ 1 taken (final)
                        └──────cancel────▶ 2 cancelled (final; message may get a new baton)
candidate.response: 0 waiting ◀──▶ 1 can_help ◀──▶ 2 cant_help   (changeable only while collecting)
```

### 1.3 Selection rule (`BatonSelectionPolicy`)

Eligible = candidates with `response = can_help` who are **still admitted** to the room.
- Auto («Pick for me»): take the lowest tier number among the eligible people, then pick uniformly at random
  among the people in that tier (`Random.secure()` in production, injected `Random` in tests).
- Manual: the chosen user must be eligible, otherwise `BatonTakerNotAvailableException`.
- No eligible person: auto and manual both fail with `BatonTakerNotAvailableException`; the author can
  wait or cancel.

### 1.4 Who sees what (`batonDataJson` on each room message, computed per viewer by the server)

| Viewer | collecting | taken | cancelled |
|---|---|---|---|
| author | `{id,status,viewerRole:"author",candidates:[{userId,title,tier,response,respondedAt}],allAnswered,eligibleCount}` | the same + `taker:{id,title}`, `selectionMode` | `null` |
| candidate | `{id,status,viewerRole:"candidate",myResponse}` | `{id,status,viewerRole:"candidate",myResponse,outcome:"you"\|"someoneElse"\|"closed"}` (+ `taker` **only** if outcome is `you`) | `{id,status,viewerRole:"candidate",outcome:"closed"}` |
| anyone else | `null` | `{id,status,viewerRole:"observer",taker:{id,title}}` | `null` |

`outcome`: `you` = the viewer is the taker; `someoneElse` = the viewer said can_help and was not chosen;
`closed` = everything else (the viewer said cant_help or never answered). A candidate never sees
other candidates, their own tier or how many people were asked. Note: after selection the candidate
whose outcome is `someoneElse` can see the taker in the room's system line like everyone else; the card
itself stays neutral.

### 1.5 Copy (en / ru; ru is canonical)

| Key (suggested) | en | ru |
|---|---|---|
| `batonActionStart` | Who'll take it? | Кто возьмётся? |
| `batonCreateTitle` | Who'll take it? | Кто возьмётся? |
| `batonCreateHint` | Ask a few people privately. Only you will see their answers. | Спросите нескольких человек лично. Ответы увидите только вы. |
| `batonCreateTiersToggle` | Set priority | Задать приоритет |
| `batonTierLabel` | Priority {n} | Приоритет {n} |
| `batonCreateSubmit` | Ask | Спросить |
| `batonCandidatePrompt` | Can you help? We're waiting for your response. | Сможете помочь? Мы ждём вашего ответа. |
| `batonCandidateCanHelp` | Can help | Могу помочь |
| `batonCandidateCantHelp` | Can't help | Не могу |
| `batonCandidateAvailabilityNote` | "Can help" means you're available, not that you've taken it yet. If several people can help, one person will be selected. | «Могу помочь» значит, что вы свободны, а не что вы уже взялись. Если помочь смогут несколько человек, выберут одного. |
| `batonCandidateAnswered` | Your answer: {answer}. You can change it. | Ваш ответ: {answer}. Его можно изменить. |
| `batonOutcomeYou` | You took it. | Вы взялись за это. |
| `batonOutcomeSomeoneElse` | Someone else was selected. Thanks for offering. | Выбрали другого человека. Спасибо, что откликнулись. |
| `batonOutcomeClosed` | No longer needed. | Больше не нужно. |
| `batonAuthorTitle` | Who'll take it: answers | Кто возьмётся: ответы |
| `batonStatusCanHelp` | can help | может помочь |
| `batonStatusWaiting` | waiting | ждём ответа |
| `batonStatusCantHelp` | can't help | не может |
| `batonChooseNow` | Choose now | Выбрать сейчас |
| `batonAllAnswered` | Everyone answered. Choose who takes it. | Все ответили. Выберите, кто возьмётся. |
| `batonNobodyYet` | Nobody can help yet. | Пока никто не может. |
| `batonPickForMe` | Pick for me | Выбрать за меня |
| `batonPickForMeHint` | One person from the highest priority, at random. | Один человек из самого высокого приоритета, случайно. |
| `batonCancel` | Cancel | Отменить |
| `batonTookIt` (system line + chip) | {name} took it. | Берёт на себя: {name}. |
| receipt `batonAsked` | {author} asks if you can help | {author} спрашивает, сможете ли вы помочь |
| receipt `batonTaken` | You took it: {excerpt} | Вы взялись: {excerpt} |
| receipt `batonAllAnswered` | Everyone answered your «Who'll take it?» | Все ответили на ваше «Кто возьмётся?» |

The ru takeover line avoids gendered past tense on purpose (cf. the «позвал(а)» review note in brd4.36).

## 2. Architecture

### 2.1 Storage (m0219, raw SQL; no Drift table classes, no Hasura tracking)

```sql
CREATE TABLE public.beacon_room_baton (
  id text PRIMARY KEY,                         -- generated server-side like polling ids
  message_id text NOT NULL REFERENCES public.beacon_room_message(id) ON DELETE CASCADE,
  beacon_id  text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  author_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  status smallint NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
  taker_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  selection_mode smallint NULL CHECK (selection_mode IN (1, 2)),   -- 1 auto, 2 manual
  all_answered_notified_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz NULL,
  CHECK (status <> 1 OR (selection_mode IS NOT NULL AND resolved_at IS NOT NULL))
);
CREATE UNIQUE INDEX beacon_room_baton_live_per_message ON public.beacon_room_baton(message_id) WHERE status <> 2;
CREATE INDEX beacon_room_baton_beacon ON public.beacon_room_baton(beacon_id);

CREATE TABLE public.beacon_room_baton_candidate (
  baton_id text NOT NULL REFERENCES public.beacon_room_baton(id) ON DELETE CASCADE,
  user_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tier smallint NOT NULL DEFAULT 1 CHECK (tier BETWEEN 1 AND 3),
  response smallint NOT NULL DEFAULT 0 CHECK (response IN (0, 1, 2)),
  responded_at timestamptz NULL,
  PRIMARY KEY (baton_id, user_id)
);
CREATE INDEX beacon_room_baton_candidate_user ON public.beacon_room_baton_candidate(user_id);
```

Realtime (template: `m0196.dart` `notify_room_seen_peer_change`): new entity kind `room_baton`, id =
`beacon_id`.
- `beacon_room_baton` AFTER INSERT / UPDATE OF status → user_ids = author + all candidates.
- `beacon_room_baton_candidate` AFTER UPDATE OF response → user_ids = author + that candidate.
- Room members outside the baton learn about selection through the marker-12 system message
  (`room_message`), which triggers the normal room refetch. **Never** send `room_baton` to
  non-candidates (it would leak that a baton exists).

### 2.2 Server domain

- Entities `RoomBaton`, `RoomBatonCandidate`, enums `BatonStatus`, `BatonResponse`, `BatonSelectionMode`
  (`lib/domain/entity/room_baton.dart`).
- `BatonSelectionPolicy` (pure, `lib/domain/policy/baton_selection_policy.dart`): `pick(candidates, {Random})`
  plus `validateCandidates(authorId, candidates, admittedIds)` for D7.
- Exceptions (codes append from 1322): `BatonNotFoundException`, `BatonNotAuthorException`,
  `BatonNotCandidateException`, `BatonNotCollectingException`, `BatonInvalidCandidatesException`,
  `BatonAlreadyActiveException`, `BatonTakerNotAvailableException`, `BatonMessageNotEligibleException`.
- `RoomBatonRepositoryPort` / `RoomBatonRepository` (raw SQL via `customStatement`/`customSelect`).
- `RoomBatonCase` (`lib/domain/use_case/room_baton_case.dart`): `create`, `respond`, `select`, `cancel`.
  Each runs in `TransactionalAttentionCase.runAction(actorUserId:)`, takes
  `pg_advisory_xact_lock(hashtextextended(@beaconId, 4242))` (`PostLockPort.lockForPostMutation` covers
  both kinds), loads the baton `FOR UPDATE`, and checks the room-write gate that room messages use
  (`BeaconRoomLifecycleWritePolicy`) plus admission of the actor.
- Attention (D3/D5): `AttentionEventType.batonAsked` (→ each candidate, reason `batonCandidate`),
  `batonTaken` (→ taker, reason `batonTaker`), `batonAllAnswered` (→ author, reason `batonAuthor`, once,
  guarded by `all_answered_notified_at`). All `requires_action = false`, placement primary; no
  logical-task key. Receipts carry only beacon id, message id and the source message excerpt, never
  other candidates.

### 2.3 Read path and API (V2 only)

- `beacon_room_repository.dart` attaches `batonDataJson` per message for the viewer (§1.4), shaped like
  `_pollDataJsonByMessageIds`; the field joins `pollDataJson` in `custom_types.dart`.
- Mutations (new `mutation_room_baton.dart`, registered in `_mutations_all.dart`):
  `roomBatonCreate(messageId, candidates:[{userId, tier}]) → batonDataJson`,
  `roomBatonRespond(batonId, canHelp: Boolean!) → batonDataJson`,
  `roomBatonSelect(batonId, userId: String) → batonDataJson` (null userId = «Pick for me»),
  `roomBatonCancel(batonId) → Boolean`.
- Marker 12 `batonTaken` system message: `system_payload = {batonId, sourceMessageId, takerUserId}`,
  empty body, author = the baton author; thread-preview mapping in
  `coordination_item_repository.dart`.

### 2.4 Client

- `kBatonEnabled = false` in `lib/consts.dart` gates the **start** action only (viewing and answering
  need no gate). Unit V flips it.
- `RoomBatonData.tryParse` (`lib/domain/entity/room_baton_data.dart`), `RealtimeEntityKind.roomBaton`
  → room invalidation, marker 12 mirror, exception-code mirror.
- `RoomCubit`: `batonCreate`, `batonRespond` (optimistic like the poll vote), `batonSelect`,
  `batonCancel`.
- Widgets: `room_baton_create_sheet.dart`, `room_baton_card.dart` (candidate / author / observer
  variants), `room_baton_choose_sheet.dart`, marker-12 system line in `room_message_tile.dart`.
- Message action «Who'll take it?» in `beacon_room_body.dart` `_onMessageActionsPressed`, shown when:
  `kBatonEnabled`, the viewer authored the message, it is not a system/semantic message, there is no live
  baton on it, and the room is writable. Long-press, secondary-tap and the hover button all reach it
  (existing wiring).
- Activity: render the three receipt types; tap opens the room and scrolls to the source message.

## 3. Rules for every unit

Same as `docs/plans/post-implementation-steps.md` §0 (repository conventions, wrapped serial test
runs, REQUIRED-mode pg tests, definition of done). In short:

- Read `AGENTS.md`, `.cursor/rules/architecture.mdc`, `.cursor/rules/terminology.mdc` once. Domain does
  not import data/api/ui; repositories return domain entities; use cases take ports.
- Never edit generated files; regenerate (`dart run build_runner build --delete-conflicting-outputs`;
  client also `flutter gen-l10n`).
- One new migration per unit, next free version (m0219 is expected for B1). Never edit a shipped
  migration. Every new SQL function gets a pg test; migration tests also check the upgrade path
  (`setUpDisposablePgWriter(target:, lastInclusiveVersion: '<previous>')` → `migrateDbSchema`).
- Baton tables are **not** tracked in Hasura. Do not touch `hasura/metadata.json`.
- New attention event types follow unit S7 of the Post plan exactly (`attention_models.dart`,
  every exhaustive switch in `attention_policy.dart`, `AttentionIntentCase`, `NotificationKind` +
  copy builder + recipient resolver, `docs/contracts/updates-event-contract.json`, the client mirror
  `attention_event_classification.dart`, and the contract tests listed there).
- Client UI: design system only (`context.tt`, `TenturaText.*`); invoke the `material-3-flutter` skill
  before writing UI; never long-press alone. Users see Request / Post / Chat; code keeps `beacon_*`.
- l10n in both `app_en.arb` and `app_ru.arb`, copy from §1.5 verbatim.
- Tests: mockito + hand-written fakes; no `bloc_test`; no golden tests.
- Run tests only through `scripts/run_with_test_cleanup.sh`, one at a time; pg tests with
  `TENTURA_PG_TESTS_REQUIRED=1`. A skipped pg test never counts as green.
- Done = new tests written first and failing for the expected reason, now green; touched files analyze
  clean; `scripts/check-custom-lints.sh` for the touched package passes (baseline only goes down); one
  commit `feat(baton): <unit> <title>`.

## 4. Unit map

| # | Unit | Title | Depends on | Pkg |
|---|---|---|---|---|
| 1 | B1 | Schema m0219: baton tables, realtime triggers, erasure | — | server |
| 2 | B2 | Domain: entities, `BatonSelectionPolicy`, exceptions | — | server |
| 3 | B3 | Attention event types `batonAsked` / `batonTaken` / `batonAllAnswered` | — | server+client mirror |
| 4 | B4 | `RoomBatonCase.create` + `respond` (repository, receipts) | B1, B2, B3 | server |
| 5 | B5 | `RoomBatonCase.select` + `cancel` (marker 12 system line) | B4 | server |
| 6 | B6 | Per-viewer `batonDataJson` projection | B5 | server |
| 7 | B7 | V2 mutations + realtime `room_baton` fan-out | B6 | server |
| 8 | C1 | Client data layer: schema, entity, repository, realtime, mirrors, flag | B7 | client |
| 9 | C2 | Start flow: message action + create sheet with tiers | C1 | client |
| 10 | C3 | Candidate card + observer chip + «X took it» system line | C1 | client |
| 11 | C4 | Author card: live answers, Choose now, choose sheet, cancel | C1 | client |
| 12 | C5 | Activity / push rendering of baton receipts + deep link | C1 | client |
| 13 | V | Release: flag on, version bump, docs, full checks | all | manual |

Critical path: B1 → B4 → B5 → B6 → B7 → C1 → C4 → V (B2, B3 run alongside B1).

## 5. Units

### B1 — Schema m0219: baton tables, realtime triggers, erasure

**Files:** create `packages/server/lib/data/database/migration/m0219.dart` (next free version), register
it in `_migrations.dart`. SQL from §2.1: both tables, constraints, indexes, the two realtime trigger
functions + triggers (template `m0196.dart`, emit through `emit_realtime_entity_change`), entity kind
`room_baton`. Add `room_baton` to the account-erasure path if it enumerates tables explicitly (follow what
S7 did for `post_first_response`; CASCADE / SET NULL may be enough — prove it in the test).
**Tests (write first, pg):** `test/data/database/m0219_room_baton_pg_test.dart`:
- upgrade path from the previous version creates both tables;
- a second live baton on the same message violates `beacon_room_baton_live_per_message`; after setting
  the first to status 2 a new one inserts;
- tier 0 / 4, response 3, status 1 without `selection_mode` are rejected by CHECKs;
- inserting a baton notifies `entity_changes` with entity `room_baton` and user ids = author + candidates
  only; updating one candidate's response notifies author + that candidate only (listen like
  `beacon_room_seen_peer_notify_pg_test.dart`);
- erasing a candidate's account removes their candidate row; erasing the taker nulls `taker_id`.

**Done when:** the test is green in REQUIRED mode.

### B2 — Domain: entities, `BatonSelectionPolicy`, exceptions

**Files:** `lib/domain/entity/room_baton.dart`, `lib/domain/policy/baton_selection_policy.dart`,
exceptions in `lib/domain/exception.dart` + codes appended to `BeaconExceptionCode` (from 1322).
**Tests (write first, no pg):** `test/domain/policy/baton_selection_policy_test.dart`:
- auto pick returns only can_help + admitted people from the lowest non-empty tier (tier-1 cant_help,
  tier-2 can_help ⇒ tier 2 picked);
- with a seeded `Random`, 1000 picks over three equal tier-1 candidates each get > 250;
- manual pick of waiting / cant_help / non-admitted user throws `BatonTakerNotAvailableException`;
- no eligible ⇒ throws; validateCandidates rejects 0 or > 12 candidates, duplicates, the author, a
  non-admitted user, tier outside 1–3;
- exception codes are unique and ≥ 1322.

**Done when:** the test file is green and server custom lints pass.

### B3 — Attention event types

**Files:** per §3 attention rule (S7 template). Event types `batonAsked`, `batonTaken`,
`batonAllAnswered`; reasons `batonCandidate`, `batonTaker`, `batonAuthor`; `requires_action` false for
all three; no logical-task key; `AttentionIntentCase.batonAsked/batonTaken/batonAllAnswered` taking
`beaconId`, `messageId`, `recipientId`, `actorUserId` and an excerpt; `NotificationKind` entries + push
copy (copy builder must not name other candidates); contract JSON; client mirror classification.
Producers are wired later (B4, B5); list them in the contract with `producerTests` pointing at
`test/domain/use_case/room_baton_case_pg_test.dart` (created in B4).
**Tests (write first):** `test/domain/attention/baton_attention_policy_test.dart` (each type: recipient
reason, `requiresAction == false`, `logicalTaskKey == null`, destination = the room message); existing
`attention_policy_test.dart`, `test/architecture/updates_event_contract_test.dart`,
`updates_event_coverage_test.dart`; client `test/architecture/updates_event_contract_test.dart` and
`test/features/inbox/attention_event_classification_test.dart`. If the coverage test requires the
producer test file to exist, create it with a single skipped placeholder group that B4 replaces.
**Done when:** listed tests green (server + client).

### B4 — `RoomBatonCase.create` + `respond`

**Files:** `lib/domain/port/room_baton_repository_port.dart`, `lib/data/repository/room_baton_repository.dart`,
`lib/domain/use_case/room_baton_case.dart` (Injectable), DI regen.
- `create(actorId, messageId, candidates)`: message exists, is in a General room, `author_id = actor`,
  not a system/semantic message (`semantic_marker` and `system_message_kind` null, `linked_polling_id`
  null) ⇒ else `BatonMessageNotEligibleException`; room writable + actor admitted; candidates via
  `BatonSelectionPolicy.validateCandidates`; no live baton (`BatonAlreadyActiveException`); insert baton +
  candidates; `batonAsked` intent per candidate. Returns `RoomBaton`.
- `respond(actorId, batonId, canHelp)`: actor is a candidate (`BatonNotCandidateException`), status
  collecting (`BatonNotCollectingException`), actor still admitted; update response + `responded_at`;
  when no candidate is waiting and `all_answered_notified_at` is null ⇒ set it and record
  `batonAllAnswered` for the author (once per baton, even if answers change later).

**Tests (write first, pg, real attention dispatch per `help_offer_obligation_settlement_pg_test.dart`):**
`test/domain/use_case/room_baton_case_pg_test.dart` (replace the B3 placeholder):
- create on own message ⇒ rows + one `batonAsked` receipt per candidate, none for the author or other
  members; receipts carry no other candidate's id;
- create on someone else's message / a poll message / with the author as candidate / with a
  non-admitted user / twice on one message ⇒ the matching exception, no rows;
- create in a closed room ⇒ rejected like posting a message; works in a Post room (kind 1) and a
  Request room (kind 0);
- respond by a non-candidate ⇒ `BatonNotCandidateException`; candidate can switch can_help → cant_help;
- last answer ⇒ exactly one `batonAllAnswered` for the author; switching an answer afterwards ⇒ no
  second one;
- two candidates answering concurrently (10 rounds) ⇒ exactly one `batonAllAnswered`.

**Done when:** the test file is green in REQUIRED mode; DI generated; lints clean.

### B5 — `RoomBatonCase.select` + `cancel`

**Files:** `room_baton_case.dart`, repository, `BeaconRoomSemanticMarker.batonTaken = 12`
(`lib/consts/beacon_room_consts.dart`), marker-12 message insert (empty body, author = baton author,
`system_payload {batonId, sourceMessageId, takerUserId}`), thread-preview mapping in
`coordination_item_repository.dart`. Inject `Random` (default `Random.secure()`).
- `select(actorId, batonId, userId?)`: author only (`BatonNotAuthorException`), collecting only, pick
  via `BatonSelectionPolicy` (manual if `userId` given), set status 1, taker, mode, `resolved_at`;
  insert marker-12 message; `batonTaken` intent for the taker.
- `cancel(actorId, batonId)`: author only, collecting only ⇒ status 2, `resolved_at`; no room message,
  no receipts.

**Tests (write first, pg):** `test/domain/use_case/room_baton_select_pg_test.dart`:
- «Pick for me» with tier-1 {A can_help, B cant_help}, tier-2 {C can_help} ⇒ A; with an injected
  `Random` and tier-1 {A, D both can_help} it picks the seeded one;
- manual pick of C (tier 2, can_help) works while A is waiting (never blocks on unanswered);
- manual pick of a waiting or cant_help person, or a can_help person who left the room ⇒
  `BatonTakerNotAvailableException`;
- non-author select / cancel ⇒ `BatonNotAuthorException`; select after select or after cancel ⇒
  `BatonNotCollectingException`; respond after select ⇒ `BatonNotCollectingException`;
- select writes exactly one marker-12 message whose payload has only `batonId`, `sourceMessageId`,
  `takerUserId`; one `batonTaken` receipt for the taker, none for others;
- cancel writes no message and no receipt; a new baton can then be created on the same message;
- select ∥ cancel (10 rounds) ⇒ exactly one wins; at most one marker-12 message.
- `beacon_room_consts` client/server mirror test still green (add 12 to both sides here).

**Done when:** the test file and `test/domain/entity/beacon_room_consts_post_mirror_test.dart` (client)
are green.

### B6 — Per-viewer `batonDataJson` projection

**Files:** `beacon_room_repository.dart` (a `_batonDataJsonByMessageIds(viewerId, messageIds)` next
to `_pollDataJsonByMessageIds`, output key `'batonDataJson'`), repository port if needed. Shape and
rules exactly §1.4. Titles come from the user table as poll voters do.
**Tests (write first, pg):** `test/data/repository/room_baton_projection_pg_test.dart` — one baton with
author Au, candidates A (tier 1, can_help), B (tier 2, cant_help), C (tier 1, waiting), observer O:
- collecting: Au sees 3 candidates with tiers/responses, `allAnswered false`; A sees only
  `{id,status,viewerRole:"candidate",myResponse:"can_help"}` — assert the JSON keys are exactly these
  and that A's serialized `batonDataJson` contains no user id of B or C; O gets `null`;
- after select(A): O sees `{…observer, taker A}` only; B sees `outcome:"closed"` and no `taker`; C
  sees `outcome:"closed"`; A sees `outcome:"you"` + taker; a second can_help candidate D (add one) sees
  `someoneElse` and no `taker`;
- after cancel: O and Au get `null`; candidates get `outcome:"closed"`;
- messages without a baton keep `batonDataJson` null; existing `pollDataJson` unchanged.

**Done when:** the test is green in REQUIRED mode.

### B7 — V2 mutations + realtime fan-out

**Files:** `lib/api/controllers/graphql/mutation/mutation_room_baton.dart` (pattern
`mutation_beacon_room.dart` / `mutation_notification_preferences.dart`), register in
`_mutations_all.dart`; input type `RoomBatonCandidateInput {userId: String!, tier: Int!}`; the
`batonDataJson` field on the room message type in `custom_types.dart` (register any new custom type —
see the alloy lesson on `custom_types.dart`); `room_baton` in `_forwardedExtrasByKind` /
`websocket_path_entity_changes.dart` if extras are needed (ids only) and in `realtime_consts.dart` if
echo applies; update `beacon_room_mutation_kind_table_test.dart` / `general_only_public_contract_test.dart`
if they enumerate room mutations.
**Tests (write first):** `test/api/controllers/graphql/mutation_room_baton_test.dart` (non-pg, mocked
case, pattern `mutation_availability_test.dart`): each mutation passes `getCredentials(args).sub` as the
actor and maps arguments; `roomBatonSelect` with null `userId` calls auto; exceptions surface with their
codes. Plus `test/api/controllers/websocket/room_baton_fanout_test.dart`: a `room_baton` notification
reaches only the listed users' sessions.
**Done when:** both tests green; the existing GraphQL table tests green.

### C1 — Client data layer

**Files:** `packages/client/lib/data/gql/schema.graphql` (from the server SDL; schema_fetcher or by hand
— say which in the commit), `features/beacon_threads/data/gql/room_baton_*.graphql` (create, respond,
select, cancel), `batonDataJson` added to `room_message_list.graphql`; `lib/domain/entity/room_baton_data.dart`
(`RoomBatonData.tryParse`, viewer-role sealed variants); `RoomMessage.baton`; repository methods in
`beacon_threads_repository.dart`; `RealtimeEntityKind.roomBaton` ('room_baton') mapped to the room
invalidation; client mirror of marker 12 (if B5 did not already) and exception codes 1322+;
`const kBatonEnabled = false;` in `lib/consts.dart`.
**Tests (write first):** `test/domain/entity/room_baton_data_test.dart` (parses all §1.4 shapes; unknown
keys ignored; malformed ⇒ null), `test/features/beacon_threads/room_baton_repository_test.dart`
(mutation variables and mapping), `test/data/service/invalidation_service_room_baton_test.dart`
(pattern `invalidation_service_room_seen_peer_test.dart`).
**Done when:** the three tests green; build_runner output committed state compiles; client lints pass.

### C2 — Start flow: message action + create sheet

**Files:** `beacon_room_body.dart` `_onMessageActionsPressed` (new `ListTile` «Who'll take it?» per
§2.4 conditions), `ui/widget/room_baton_create_sheet.dart`, `RoomCubit.batonCreate`, l10n.
Sheet: admitted room participants except me (existing participant fetch), multi-select with checkboxes;
«Set priority» toggle reveals a 1/2/3 segmented control per selected person (default 1); «Ask» is
enabled with 1–12 selected; errors map to snack bars.
**Tests (write first):** `test/features/beacon_threads/room_baton_create_sheet_test.dart`: action shown
only on own non-system message with no live baton and `kBatonEnabled` (inject the flag through the
widget/cubit, not by editing the const in tests); not shown on others' messages; sheet excludes me;
Ask disabled at 0 and at 13; tiers hidden until the toggle; submit calls `batonCreate` with
`[{userId, tier}]`. Also reachable through secondary tap (existing tile wiring) — one assertion.
**Done when:** test green; lints clean.

### C3 — Candidate card, observer chip, «X took it» system line

**Files:** `ui/widget/room_baton_card.dart` (candidate + observer variants), `room_message_tile.dart`
(render under the message when `message.baton` is non-null; marker 12 system line using
`batonTookIt`), `RoomCubit.batonRespond` with optimistic update (poll vote pattern ~:1355), l10n.
Candidate collecting: source context is the message itself (card sits under it), prompt, Can help /
Can't help buttons, availability note; after answering: chosen answer highlighted + «You can change
it». Outcomes `you` / `someoneElse` / `closed` per §1.5. Observer: chip «{name} took it.» only.
**Tests (write first):** `test/features/beacon_threads/room_baton_card_candidate_test.dart`: prompt +
both buttons + note visible; no other names, no tier, no counts in the widget tree; tapping Can help calls
`batonRespond(true)` and shows the answered state immediately; each outcome renders its copy;
observer sees only the chip; marker-12 message renders «{name} took it.» and no list of refusals.
**Done when:** test green.

### C4 — Author card: live answers, Choose now, choose sheet, cancel

**Files:** `room_baton_card.dart` (author variant), `ui/widget/room_baton_choose_sheet.dart`,
`RoomCubit.batonSelect` / `batonCancel`, l10n.
Author card: one row per candidate «Name — can help / waiting / can't help» (tier shown as a small label
only when tiers > 1 exist); «Choose now» enabled when ≥ 1 can_help, otherwise «Nobody can help yet»;
when `allAnswered` a highlighted prompt «Everyone answered. Choose who takes it.»; «Cancel» (confirm
dialog). Choose sheet: «Pick for me» (calls select with null) + can_help people grouped by tier for manual
pick. After selection the card collapses to «{name} took it.» Live updates arrive through the
`room_baton` invalidation (C1).
**Tests (write first):** `test/features/beacon_threads/room_baton_card_author_test.dart`: rows show the
four example states; Choose now disabled with no can_help and enabled with one while others wait;
all-answered prompt appears; choose sheet lists only can_help people; Pick for me ⇒ `batonSelect(null)`;
tap a name ⇒ `batonSelect(userId)`; Cancel confirm ⇒ `batonCancel`; taken state shows only the taker.
Cubit test `test/features/beacon_threads/room_cubit_baton_test.dart` (fakes in `room_cubit_fakes.dart`):
select/cancel call the repository and refetch; errors surface.
**Done when:** both tests green.

### C5 — Activity / push rendering of baton receipts

**Files:** Activity cell copy for `batonAsked`, `batonTaken`, `batonAllAnswered` (where
`activity_stream_view.dart` `_ActivityStreamCell` maps event types), tap ⇒ open the room (Request or
Post route host) and scroll to / highlight the source message (reuse the existing open-at-message
path used by mention receipts; if none exists, open the room and report the gap), l10n.
**Tests (write first):** `test/features/inbox/baton_receipt_cell_test.dart`: each type renders its §1.5
copy with author name / excerpt; no other candidate names appear; tapping navigates with the beacon id +
message id.
**Done when:** test green.

### V — Release (manual)

`kBatonEnabled = true`; client semver bump in `pubspec.yaml` + `web/index.html ?v=` sync (no
`kDefaultMinClientVersion` raise needed unless the server wire changed incompatibly — it did not);
`docs/features/beacon_room.md` gains a «Who'll take it?» section (what users see, privacy rules §1.4,
not-a-task note); run all suites from `AGENTS.md` § Verify, both custom-lint runs,
`bash scripts/check-user-facing-terminology.sh`, `dart run tool/verify_web_version_consistency.dart`;
manual smoke on web with three QA users (create, answer, Choose now with one waiting, observer view).

## 6. Out of scope

Deadlines/reminders for unanswered candidates; re-opening a taken baton; reassigning the taker;
showing baton stats on profiles or trust; batons on system/poll messages; auto-creating sub-requests;
Hasura access to baton tables; item threads.

## 7. Beads

Epic + 13 child beads, `plan_unit` metadata = the unit id above; labels `baton` + package. The epic is
tracking only — never run alloy on it. V is labelled `manual` and has no recipe.
