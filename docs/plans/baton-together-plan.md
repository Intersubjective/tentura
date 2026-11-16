# «Who'll take it?» together: «I'll take it with …» (internal: baton pair)

Status: draft spec, 2026-11-16, awaiting owner answers in §6. No code yet. Issue: #1304.
Builds on: `docs/plans/baton-who-takes-it-plan.md` (rev 1 + rev 2 §0), `docs/plans/notification-identity-spec.md` (#1303, epic `tentura-ocvk`).
Vocabulary: user-facing **Request** / «запрос», **Post** / «пост», **discussion** / «обсуждение», **Chat** / «Чат»; the feature is **Who'll take it?** / «Кто возьмётся?». Code keeps `beacon_*`, `room_*`, `baton`. The words "pair", "partner" and "co-taker" are internal only. User copy says «together» / «вместе».

## 0. Owner request

A person who was asked «Who'll take it?» can answer «I'll take it together with <a specific participant>». Newcomers may be shy to take work alone. This gives them a legitimate way to ask for joint participation.

## 1. Today's baton (verified in code, 2026-11-16)

| Aspect | Today | Where |
|---|---|---|
| Object | A baton is its own room message (semantic marker 13). The baton row hangs off that message. It is created from the attach menu, or from any message's actions as a reply. | `RoomBatonCase.create` (`packages/server/lib/domain/use_case/room_baton_case.dart`) |
| Who answers | Only the **asked people** (1–12 admitted members, tiers 1–3, never the author). They answer `can_help` or `cant_help` and may change the answer while it is `collecting`. | `beacon_room_baton_candidate` (m0219), `BatonSelectionPolicy.validateCandidates` |
| Candidate pool | `listAdmittedMentionParticipants`: `roomAccess == admitted`. Blocks are **not** filtered. | `beacon_room_repository.dart:1283` |
| Selection | The author picks one person who said `can_help` and is still admitted, or uses «Pick for me» (lowest tier, then random). The pick is final. It writes a marker-12 system line with payload `{batonId, sourceMessageId, takerUserId}` and sends the taker a `batonTaken` receipt. | `RoomBatonCase.select`, `BatonSelectionPolicy` |
| After selection (#479, D9) | The author is offered «Create a plan step with {name}?». The step has **one** assignee (`beacon_plan.assigneeId`). | `room_baton_plan_step_sheet.dart`, `BatonPlanStepOffer` |
| Who sees what | Per viewer `batonDataJson` with roles author, candidate and observer. Only the author sees candidates, tiers and answers. A candidate sees only their own answer and outcome. Everyone else sees «Looking for someone…», «{name} took it.» or «Cancelled.». | `_batonDataJsonByMessageIds` (`beacon_room_repository.dart:722`), client `RoomBatonData` (`lib/domain/entity/room_baton_data.dart`) |
| Realtime | `room_baton` goes to the author and the candidates only, never the whole room. | `notify_room_baton_change`, `notify_room_baton_candidate_change` (m0219) |
| Archived Post guard | `beacon_post_write_guard` triggers on both baton tables, with an **explicit column list**. | m0271 lines ~167-177 |
| Notifications | `batonAsked`, `batonTaken`, `batonAllAnswered`. All have `requires_action = false`: no obligation and nothing in My Work. `batonAsked` can be personal. | `attention_models.dart`, `attention_policy.dart` (`canBePersonal`) |
| Rate limits | `create` uses the room message rate limit. `respond` has none. | `room_message_rate_limit.dart` |
| Card | `RoomBatonCard` has candidate, observer and author bodies. The bubble may also carry a pinned-fact ribbon or a quoted fact (`room_baton_card_in_fact_bubble_test.dart`, 375×667 RU). Under R7 a baton message itself cannot become a fact. | `room_baton_card.dart`, `room_message_tile.dart:674` |
| Downstream | `taker_id` is read **only** by the baton projection and the marker-12 line. Nothing else uses it: no MeritRank, no closure "who helped", no admission, no My Work, no limits. | grep of `taker_id` / `takerUserId` |
| Doc drift | `docs/features/beacon_room.md` § «Who'll take it?» still describes rev 1: "on their own message", "observers see nothing while collecting". Fix it in the docs unit. | |

Binding constraints carried over: nobody takes it without saying they are available (D2). Receipts are not obligations (D5). There are no personal chats, so private text rides only on the baton card and receipts. There is no legacy-client support (web only, one release). Reuse and extend existing widgets; no parallel widgets. Never use long-press alone for gestures. Follow the terminology rules.

## 2. Design

### 2.1 User flow

**Asked person A (the shy one).** A's existing candidate card («Can you help?» [Can help] [Can't help]) gets a third, quieter action: **[Together with…]** / «[Вместе с кем-то…]» (TextButton, gated by `kBatonTogetherEnabled`).
1. A tap or click opens the **existing** single-select people sheet `showPlanPersonPicker` (`features/beacon_plan/ui/widget/plan_person_picker.dart`), with the title «Who will you take it with?» / «С кем возьмётесь?». It lists the room's admitted participants except A and the baton's author, with avatars, in the participant order the create sheet already uses. Rows are ordinary `ListTile`s, so touch, mouse and keyboard all work. No long-press is involved.
2. A picks X. The client calls `roomBatonRespond(batonId, canHelp: true, partnerUserId: X)` and updates the card optimistically, as the vote and respond paths already do.
3. A's card shows «Your answer: can help together with X. Waiting for X.» with [Change] (the same three buttons). A can change the answer at any time while the baton is collecting.

**Named participant X.** X gets an Activity receipt and a push (`batonPartnerAsked`). In the room, the baton bubble shows X a card: «{A} wants to take this on together with you.» [Join] [Can't]. It carries the same availability note as candidates («this is not taking it yet; the author chooses»).
- **Join**: the pair is confirmed. A gets the receipt «{X} will take it with you» (`batonPartnerAnswered`, accepted). X's card says «You'll take it together with {A}. You can change your mind while it's open.» [Can't after all].
- **Can't** (or a later withdrawal): A's answer goes back to *waiting*, and A's card shows «{X} can't join. Can you help?» with the three buttons. A gets a receipt (`batonPartnerAnswered`, declined). The author never sees this decline (default for Q3).
- If X is also an asked candidate, X's card shows their own answer block and, under it, A's invitation. Joining makes X's own answer «can help together with A» (a mutual pair).

**Author.** The author's answers list shows a confirmed pair as **one row**: two mini-avatars and «A and X», status «can help together» / «могут вместе». A pending pair reads as «waiting» for A. «Choose now» is enabled when at least one solo `can_help` or confirmed pair exists. The choose sheet lists confirmed pairs as one entry («A and X», subtitle «together»), grouped by tier like solo people. «Pick for me» counts a pair as one entry in its tier.

**Room after selection.** The system line and taker line read «{A} and {X} took it.» / «Берут на себя: {A} и {X}». Both A and X get `batonTaken`. Other candidates' outcomes are unchanged (`someoneElse` / `closed`).

### 2.2 Card states

| Viewer | Pending (X not answered) | Accepted | Declined / X withdrew | A withdrew (changed answer) | Baton taken by the pair | Taken by someone else | Cancelled |
|---|---|---|---|---|---|---|---|
| A (candidate) | «Your answer: can help together with X. Waiting for X.» | «Your answer: can help. Together with you: X.» | «X can't join. Can you help?» + buttons (A is *waiting*) | their new answer | «You and X took it.» | «Someone else was selected. Thanks for offering.» | «No longer needed.» |
| X (named) | «A wants to take this on together with you.» [Join] [Can't] | «You'll take it together with A.» [Can't after all] | (after declining) observer view | observer view («Looking for someone to take it.») | «You and A took it.» | «Someone else was selected. Thanks for offering.» if accepted, else observer | «No longer needed.» if accepted or pending, else nothing |
| Author | A shows «waiting» | one row «A and X — can help together» | A shows «waiting» | A's new answer | «A and X took it.» | taker line | author view as today |
| Others | «Looking for someone to take it.» | same | same | same | «A and X took it.» | taker line | «Cancelled.» |

### 2.3 Data model: extend the answer row (one migration)

```sql
ALTER TABLE public.beacon_room_baton_candidate
  ADD COLUMN partner_user_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD COLUMN partner_response smallint NULL CHECK (partner_response IN (0, 1, 2)), -- 0 pending, 1 accepted, 2 declined
  ADD COLUMN partner_responded_at timestamptz NULL,
  ADD COLUMN partner_invites smallint NOT NULL DEFAULT 0 CHECK (partner_invites BETWEEN 0 AND 3),
  ADD CONSTRAINT baton_candidate_partner_not_self CHECK (partner_user_id IS DISTINCT FROM user_id),
  -- pending/accepted only on a can_help answer; a declined marker only on a waiting answer
  ADD CONSTRAINT baton_candidate_partner_state CHECK (
    partner_response IS NULL
    OR (partner_response IN (0, 1) AND response = 1)
    OR (partner_response = 2 AND response = 0));
CREATE INDEX beacon_room_baton_candidate_partner ON public.beacon_room_baton_candidate(partner_user_id)
  WHERE partner_user_id IS NOT NULL;
CREATE UNIQUE INDEX beacon_room_baton_candidate_one_accepted_partner
  ON public.beacon_room_baton_candidate(baton_id, partner_user_id) WHERE partner_response = 1;

ALTER TABLE public.beacon_room_baton
  ADD COLUMN co_taker_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD CONSTRAINT baton_co_taker_only_when_taken CHECK (
    co_taker_id IS NULL OR (status = 1 AND co_taker_id IS DISTINCT FROM taker_id));
```

Migration also needs to:
- `CREATE OR REPLACE` `notify_room_baton_change`, so that `user_ids` = author + candidates + every non-null `partner_user_id` of the baton. The baton trigger must also fire on `co_taker_id`.
- `CREATE OR REPLACE` `notify_room_baton_candidate_change`, so it fires on `response`, `partner_user_id` or `partner_response` changes. Its `user_ids` = author + `NEW.user_id` + `OLD.partner_user_id` + `NEW.partner_user_id`. Recreate the trigger with `AFTER UPDATE OF response, partner_user_id, partner_response`.
- Recreate the two m0271 `beacon_post_write_guard` triggers so their column lists include the new columns. Otherwise an archived Post accepts partner writes.
- Do not change Hasura metadata or Drift tables (raw SQL, as for the existing baton).
- Erasure relies on the foreign keys. If the partner is erased, `partner_user_id` becomes NULL while `partner_response` stays set. The projection reads that state as «the partner is gone» and shows A as *waiting* with the declined note; prove it in the pg test.

`partner_invites` counts the distinct partners A has named on this baton (cap 3; see the rate limit below).

### 2.4 Server rules (`RoomBatonCase`, under the existing post lock and room-write gate)

Pure core: `BatonPairPolicy` (`lib/domain/policy/baton_pair_policy.dart`) takes the baton's rows plus the actor and the request, and returns the row mutations and receipts to emit. The use case only loads, locks, applies and records. `BatonSelectionPolicy` becomes pair-aware.

`respond(actorId, batonId, canHelp, partnerUserId?)`:
- These checks are unchanged: the actor is a candidate, the baton is collecting, the actor is still admitted.
- `partnerUserId` is set only with `canHelp == true` (otherwise `BatonPartnerInvalidException`).
- The partner must be admitted to the room (same set as candidates), and is not the actor or the baton author. `block_hides(actor, partner)` is false in both directions. A failure raises `BatonPartnerInvalidException` with one generic description, so a block is not revealed.
- Naming a new partner (different from the current one) increments `partner_invites`. A 4th distinct partner raises `BatonPartnerInvalidException('limit')`. The receipt key is `baton_partner_asked:{batonId}:{actorId}:{partnerId}`. Re-naming the same person after a decline shows the invitation on the card again but sends no second push (anti-nagging).
- Mutual pairs: if the partner's own candidate row already names the actor as pending, both rows become accepted. No new receipt goes to the partner. A gets `batonPartnerAnswered(accepted)` from the partner's side.
- One confirmed pair per person: if the actor or the partner is already in another accepted pair on this baton, joining this one releases the old pair. The released inviter's row goes back to *waiting* with the declined marker, and they get `batonPartnerAnswered(declined)`. The client asks for confirmation first («This replaces taking it with {Y}»).
- Changing away from a partner (to solo, can't help or another person) clears the old partner fields. A withdrawn invitation sends no receipt; X's card falls back to the observer view.

`partnerRespond(actorId, batonId, inviterUserId, accept)` (new):
- A row (`baton_id`, `user_id = inviter`, `partner_user_id = actor`) must exist with `partner_response IN (0, 1)`, otherwise `BatonNotPartnerException`. The baton must be collecting (`BatonNotCollectingException`). The actor must still be admitted, and must not be blocked with the inviter.
- Accept → `partner_response = 1`. If the actor is also a candidate, their row becomes `can_help` + partner = inviter + accepted (mutual), and any other accepted pair of theirs is released as above.
- Decline or withdraw → the inviter's row gets `response = 0`, `partner_response = 2`, `responded_at = NULL`. `all_answered_notified_at` is cleared, so a new round can notify the author once more, as the edit path already does.
- Both paths record `batonPartnerAnswered` for the inviter (fact `accepted`), then run the shared all-answered check.

All-answered: a candidate counts as answered when `response <> 0` and `partner_response IS DISTINCT FROM 0`. The check runs after `respond` and `partnerRespond`, with the same per-round key as today.

`select(actorId, batonId, userId?)`:
- Eligible entries are solo `can_help` rows plus accepted pairs; a mutual pair is deduplicated into one entry. Both members of a pair must be admitted now.
- The pair's tier is the inviter's tier; for a mutual pair it is `min` of the two.
- Manual select with `userId` = either member of an accepted pair selects the pair. The **taker is the asked person**; for a mutual pair it is the row with the earlier `responded_at`. The co-taker is the other member.
- A pending pair or a pair with a member who left raises `BatonTakerNotAvailableException`.
- The update sets `taker_id`, `co_taker_id`, the mode and `resolved_at`. The marker-12 payload adds `coTakerUserId` (only when present). `batonTaken` goes to both, each with the fact `withUserId` = the other.

`update` (author edit): removing candidate A deletes A's row, which drops A's invitation (silent). Adding X as a candidate while X is someone's partner is allowed: X then has both views. `cancel`: unchanged; partners with pending or accepted invitations get the outcome `closed`.

Exceptions: append `BatonPartnerInvalidException` and `BatonNotPartnerException` after the last code in `exception_codes.dart`. Mirror both on the client with RU/EN in `server_error_copy.dart`.

### 2.5 Per-viewer projection (`batonDataJson`)

Viewer roles in precedence order: author > candidate > partner > observer.

| Role | Added keys |
|---|---|
| author | `candidates[].partner: {id, title}` **only when accepted**. A pending pair is projected as `response: "waiting"`. `pairs: [{takerId, partnerId, tier}]` lists the deduplicated confirmed pairs. `eligibleCount` counts solo + pairs. Once taken: `coTaker: {id, title}`. |
| candidate | `myPartner: {id, title, status: "pending"\|"accepted"\|"declined"}`, `partnerInvites: [{fromUserId, title, status: "pending"\|"accepted"}]` (others who named me), `coTaker` when the outcome is `you` |
| partner (new; named by someone, not a candidate) | `{id, status, viewerRole: "partner", partnerInvites: [...], outcome}`. `outcome`: `you` (my pair was taken), `someoneElse` (I had accepted, another entry was taken), `closed` (cancelled while pending/accepted, or taken while I was pending). Present only while at least one row still names the viewer. |
| observer | `coTaker` alongside `taker` once taken |

A partner never sees other candidates, tiers, counts or other pairs. An inviter sees only their own partner.

### 2.6 Notifications (per `notification-identity-spec.md` §2, §5)

New event types follow the B3/S7 recipe: `attention_models.dart`, every exhaustive switch, `AttentionIntentCase`, `NotificationKind`, the recipient resolver, `docs/contracts/updates-event-contract.json`, the client mirror `attention_event_classification.dart` and the contract tests. All have `requires_action = false` and no logical-task key. The destination is the baton message. `batonPartnerAsked` joins `canBePersonal` with the new reason `batonPartner` in `personalRecipientReasons`.

| presentation_key | Recipient (reason) | H (EN / RU) | L (EN / RU) | Facts |
|---|---|---|---|---|
| `baton_partner_asked` | X (`batonPartner`) | Take it on together? / Взяться вместе? | {A} wants to take it on together with you: {x} / {A} предлагает взяться вместе: {x} | excerpt (the ask, or the replied-to text, as `batonAsked`) |
| `baton_partner_answered` (accepted) | A (`batonCandidate`) | Together / Вместе | {X} will take it on with you: {x} / {X} возьмётся вместе с вами: {x} | `accepted: true`, excerpt |
| `baton_partner_answered` (declined) | A (`batonCandidate`) | Can't join / Не сможет присоединиться | {X} can't join you. Answer again: {x} / {X} не сможет присоединиться. Ответьте ещё раз: {x} | `accepted: false`, excerpt |
| `baton_taken` (pair) | A and X (`batonTaker`) | You took it / Вы взялись | You and {B} took it: {x} / Вы и {B} взялись: {x} | `withUserId` → name via `NotificationIdentityPort` (a second `IdentityRequest`, same block gate). Hidden or blocked → today's solo sentence. |

The entity label {E} (Request title or Post label) goes in the push title, per N2/N4. RU names stay nominative (N7): «Вы и {B} взялись» uses a plural verb, so it is gender-neutral. «Берут на себя: {A} и {B}» puts the names after a colon. No «с {name}» constructions. If the renderer unit `tentura-ocvk.5` has not landed when these units run, they wait for it (epics in blocks).

### 2.7 What counts as «taker» downstream

- **The baton**: a pair is **one** selection (one final state, one marker-12 line, `eligibleCount` counts it once, «Pick for me» gives it one draw). It has **two** people for receipts and for display.
- **Plan-step offer (#479)**: steps have one assignee. Default (Q6): offer one step assigned to the taker (the asked person), with the prompt «Create a plan step with {A}? {X} takes it on together with them.». `BatonSelected` gains `coTaker`.
- **Help offers, commitments, admission, forwarding, MeritRank, closure, My Work**: no change. A baton never admits anyone; both people must already be admitted. Nothing counts takers, so there are no limits to adjust.

### 2.8 Edge cases

| Case | Behaviour |
|---|---|
| X names someone else (X is a candidate) | Independent. A's invitation to X stays pending until X answers it. If X's own pair with Y is confirmed, A's invitation auto-declines (one pair per person) and A is told. |
| Both choose each other | Auto-accepted mutual pair. One author row, one choose entry, tier = min. |
| Three-way chain (A→X, X→Y, Y→A) | No trios. Each confirmed pair releases the other invitations of its members, which auto-decline with receipts. At most one pair per person at any time; asserted by a property test over random action sequences. |
| X answered «can't help» earlier (as a candidate) | The invitation still shows. Joining switches X's own answer to «together with A». |
| X already in a confirmed pair with Y | Joining A asks for confirmation, then releases Y's pair. Y's inviter is reset and told. |
| X leaves the Request / loses admission | The pair is not selectable (select checks admission now). The author row stays «can help together», and the choose sheet omits it. X's later `partnerRespond` is rejected. |
| X erased | The partner foreign key goes NULL; A is shown as *waiting* with the note. |
| X blocks A (or the reverse) after inviting | `partnerRespond` is rejected. The pair is not selectable (select re-checks `block_hides`). The author sees A as waiting. |
| Baton taken or cancelled | All pair mutations raise `BatonNotCollectingException`. Cards show the outcomes in §2.2. |
| Author edits and removes A | A's row and the invitation go silently; X falls back to the observer view. |
| Archived Post | The m0271 guard (with the new columns) rejects writes, like every baton write. |
| Partner is the baton author or self | Rejected (`BatonPartnerInvalidException`). The picker does not list them. |
| Spam | At most 3 distinct partners per answer per baton, and one push per (baton, A, X). |

## 3. Work breakdown

Rules: the baton plan §3 applies (tests first and failing for the expected reason; pg tests in REQUIRED mode; wrapped serial runs; touched files analyze clean; custom lints ratchet; one commit per unit). Migrations take the next free version (no numbers here). The whole server block lands before the client block. This epic starts after the #1303 epic `tentura-ocvk` ships (epics in blocks).

### Server block

| # | Unit | Cx | Side | Deps | Acceptance (test-assertable) |
|---|---|---|---|---|---|
| S1 | Migration: partner columns, `co_taker_id`, CHECKs, indexes; realtime trigger functions and triggers; m0271 guard column lists | medium | server | – | pg test: upgrade from the previous version adds the columns. CHECKs reject partner = self, pending on `cant_help`, declined on `can_help`, and `co_taker_id` while collecting. A second accepted row for the same (baton, partner) violates the unique index. Updating `partner_response` notifies `room_baton` to exactly {author, A, X}. A baton status change includes partners in `user_ids`. A partner write on an archived Post raises `post_archived`. Erasing X nulls `partner_user_id` and keeps `partner_response`. |
| S2 | Domain: entity fields, `BatonPartnerResponse` enum, pure `BatonPairPolicy`, pair-aware `BatonSelectionPolicy`, two exceptions + codes | medium | server | – | Unit tests: mutual auto-accept; one-pair-per-person release; the 4th distinct partner is rejected; a pending pair is not eligible; a pair tier = min for mutual; with a seeded `Random`, `pick` treats a pair as one entry; `pickManual` by either pair member returns (taker = asked / earlier, coTaker); a property test over 500 random action sequences keeps «≤1 accepted pair per user»; exception codes are unique and appended. |
| S3 | Attention: `batonPartnerAsked`, `batonPartnerAnswered`; reason `batonPartner`; `batonTaken` fact `withUserId`; `canBePersonal`; contract JSON; client classification mirror; renderer rows (EN/RU) in `NotificationCopyRenderer` | medium | server (+ client mirror) | S2, `tentura-ocvk.5` | Policy test per type: recipient reason, `requiresAction == false`, `logicalTaskKey == null`, destination = baton message. The renderer table test has exact strings for the 4 rows × {en, ru} × {readable, unreadable}. The leak test: blocked or hidden co-taker → solo sentence, no name. The RU test: no `с {name}` pattern. The server and client updates-event contract and coverage tests are green. |
| S4 | `RoomBatonCase.respond(partnerUserId?)` + `partnerRespond` + shared all-answered rule + receipts + caps | complex | server | S1, S2, S3 | pg (`room_baton_pair_case_pg_test.dart`): naming X writes the row and one `batonPartnerAsked` to X and none to others; X's receipt carries no other candidate id. Rejected: partner not admitted, partner = author, partner blocked either way (same code, generic description). Re-naming X after a decline sends no second receipt. X accepting → A gets `accepted`. X declining → A is *waiting* with the marker and gets `declined`, and the all-answered stamp is cleared. A mutual answer auto-accepts with no partner push. A third pair releases the first with a receipt. `partnerRespond` by a non-invited user → `BatonNotPartnerException`. After select or cancel → `BatonNotCollectingException`. The last pending partner answer triggers exactly one `batonAllAnswered`. 10 concurrent accept-vs-withdraw rounds end in a consistent state. |
| S5 | `select` / auto pick with pairs, `co_taker_id`, marker-12 `coTakerUserId`, `batonTaken` to both; `update` / `cancel` interplay | medium | server | S4 | pg: a manual pick by either member of an accepted pair sets taker = asked person and co_taker = partner. The marker-12 payload has exactly `batonId`, `sourceMessageId`, `takerUserId`, `coTakerUserId`. There are two `batonTaken` receipts with `withUserId`. A pending pair, a pair whose partner left and a blocked pair → `BatonTakerNotAvailableException`. «Pick for me» with tier-1 {pair} and tier-2 {solo} picks the pair. An edit removing A drops the invitation (X gets no role). Cancel gives no receipts. A solo select still writes no `coTakerUserId`. |
| S6 | Per-viewer projection: author `partner`/`pairs`/`coTaker`, candidate `myPartner`/`partnerInvites`, new `partner` role, observer `coTaker` | medium | server | S5 | pg projection test with author Au, A (pending → X), B (accepted pair with Y, Y not a candidate), C solo, observer O. Au sees A as `waiting` with no `partner` key, B with partner Y, `pairs` of length 1 and `eligibleCount == 2`. X sees role `partner` with one pending invite and no candidate ids (asserted on the serialized JSON). Y sees an accepted invite. A sees `myPartner.status == "pending"`. After select(B): O sees `taker` B + `coTaker` Y; Y's outcome is `you`; X's role is gone (falls to observer). After cancel: Y's outcome is `closed`. A message without a baton → null. |
| S7 | GraphQL: `roomBatonRespond(partnerUserId: String)`, new `roomBatonPartnerRespond(batonId, inviterUserId, accept)`; websocket fan-out | simple | server | S6 | A mocked-case mutation test: the actor is `getCredentials(args).sub`; arguments map; an empty `partnerUserId` → null; exception codes surface. A fan-out test: a `room_baton` notification reaches A, X and the author's sessions only. Existing room-mutation table tests are green. |

### Client block

| # | Unit | Cx | Side | Deps | Acceptance |
|---|---|---|---|---|---|
| C1 | Data layer: schema SDL, `room_baton_respond.graphql` var, `room_baton_partner_respond.graphql`, `RoomBatonData` (author `partner`/`pairs`/`coTaker`, candidate `myPartner`/`partnerInvites`, new `RoomBatonPartnerData`, observer `coTaker`), repository + `BeaconThreadsCase` + `RoomCubit.batonRespond(partnerUserId)` / `batonPartnerRespond` (optimistic), marker-12 `coTakerUserId` parse, exception mirror + `server_error_copy` RU/EN, `kBatonTogetherEnabled = false` | medium | client | S7 | `room_baton_data_test`: every new shape parses; unknown keys are ignored; an unknown role → null. Repository test: mutation variables. A real-path test from a recorded GraphQL response through the repository and cubit to state (`RoomMessage.baton` is a `RoomBatonPartnerData`). A cubit test: an optimistic pending state, and rollback plus a snackbar on `BatonPartnerInvalid`. |
| C2 | Candidate card: [Together with…] → reuse `showPlanPersonPicker` (no new picker; if it moves to `ui/widget/`, every caller is updated in the same commit) with admitted participants except self and author; pending / accepted / declined copy; invitations-to-me block; confirm when replacing a pair | medium | client | C1 | Widget tests: the button is shown only with the flag and while collecting. The picker lists the participants minus self and minus the author. A pick calls `batonRespond(true, partnerUserId)`. Each state shows its §4 copy. With no other candidate names in the tree. The replace-pair confirm appears only when the viewer is already in an accepted pair. Reachable by tap and by keyboard (Enter on the focused button). |
| C3 | Partner card variant (`RoomBatonCard` gets a `_PartnerBody`, no new card widget): [Join] [Can't] / [Can't after all], outcomes | simple | client | C1 | Widget test: «{A} wants to take this on together with you» plus both buttons. Join → `batonPartnerRespond(accept: true)`, Can't → false. No candidate list, tier or count. Each outcome renders its copy. |
| C4 | Author card pair row + choose sheet pair entry + `BatonSelected.coTaker` + plan-step offer prompt with the partner name | medium | client | C1 | `room_baton_card_author_test` extension: a pair row shows two avatars and «A and X — can help together»; a pending pair shows «waiting». Choose now is enabled with only a pair. The choose sheet lists the pair once under its tier. Tapping it → `batonSelect(A)`. The plan-step sheet prompt names both. The extended `room_baton_card_in_fact_bubble_test`: a pair row with two long RU names stays on one line with an ellipsis at 375×667. |
| C5 | Taken lines + receipts: marker-12 line and `_StatusLine` «{A} and {X} took it» (+ ask variant); Updates/Activity rows for `batonPartnerAsked` / `batonPartnerAnswered` and the pair `batonTaken` (`updates_receipt_display_copy.dart`, `attention_mini_card.dart`, `activity_stream_view.dart`), tap → room at the baton message | medium | client | C1 | Tests: the marker-12 payload with `coTakerUserId` renders both names. Without it, solo copy (regression). Each receipt type renders EN and RU copy with names. Tapping navigates with the beacon id + message id (fake `AppNavigator`). `issue_736_event_headline_coverage_test` covers the new types. |
| C6 | L10n pass: every §4 key in `app_en.arb` + `app_ru.arb`, terminology script, 375×667 RU check of the candidate, partner and author cards | simple | client | C2–C5 | `request_terminology_contract_test` and `check-user-facing-terminology.sh` are green. An ARB parity test: no new key missing in RU. RU widget test at 375×667 for each card variant with no overflow. |
| W | Web integration scenario `baton_together_journey_test.dart` (pattern `request_lifecycle_offer_admit_chat_test.dart`): the author asks A; A answers «Together with…» X; X joins; the author sees one pair row, Choose now → the pair; the observer sees «A and X took it.»; X's Activity has the receipt | medium | client | C2–C5 | It runs green in `scripts/run_client_integration_web_local.sh` (`TENTURA_WEB_CHROME_NO_SANDBOX=1` in the sandbox). It asserts the visible text per user at each step, including RU for one user. |

### Docs and ship

| # | Unit | Cx | Side | Deps | Acceptance |
|---|---|---|---|---|---|
| D | Docs: commit this spec as `docs/plans/baton-together-plan.md` (decisions filled in); rewrite `docs/features/beacon_room.md` § «Who'll take it?» to rev 2 + together (fixes the rev-1 drift); add a rev-3 note to `baton-who-takes-it-plan.md` §0; update `docs/client-ui-inventory.md` if a picker moved | simple | docs | C6 | The terminology script is green. A `repo-files` test asserts that the feature section mentions «Together with» and the partner-privacy rule. |
| V | Ship: flip `kBatonTogetherEnabled`; client version bump; raise `kDefaultMinClientVersion` (new viewer role); `server-gates` + `server-pg` + `client-gates` + `client-affected`; manual smoke with 4 QA users; Codex review before push | medium | both | all | All suites are green. The smoke steps of W pass on the local stack. Push screenshots in RU and EN are attached to the bead. |

Order: S1 ∥ S2 → S3 → S4 → S5 → S6 → S7 → C1 → (C2, C3, C4, C5) → C6 → W → D → V.

## 4. Copy (RU canonical)

| Key | en | ru |
|---|---|---|
| `batonTogetherAction` | Together with… | Вместе с кем-то… |
| `batonTogetherPickTitle` | Who will you take it with? | С кем возьмётесь? |
| `batonTogetherPending` | Your answer: can help together with {name}. Waiting for {name}. | Ваш ответ: могу помочь вместе. Ждём ответа: {name}. |
| `batonTogetherAccepted` | Your answer: can help. Together with you: {name}. | Ваш ответ: могу помочь. Вместе с вами: {name}. |
| `batonTogetherDeclined` | {name} can't join. Can you help? | {name} не сможет присоединиться. Сможете помочь? |
| `batonPartnerPrompt` | {name} wants to take this on together with you. | {name} предлагает взяться за это вместе с вами. |
| `batonPartnerJoin` | Join | Возьмусь вместе |
| `batonPartnerCant` | Can't | Не смогу |
| `batonPartnerJoined` | You'll take it together with {name}. You can change your mind while it's open. | Вы согласились взяться вместе. Вместе с вами: {name}. Пока выбор не сделан, это можно изменить. |
| `batonPartnerCantAfterAll` | Can't after all | Всё-таки не смогу |
| `batonPartnerNote` | This is not taking it yet: the author chooses who takes it. | Это ещё не значит, что вы взялись: выбирает автор. |
| `batonPartnerReplaceConfirm` | This replaces taking it with {name}. | Тогда вы больше не берётесь вместе с другим человеком: {name}. |
| `batonStatusCanHelpTogether` | can help together | могут вместе |
| `batonPairNames` | {a} and {b} | {a} и {b} |
| `batonPairSubtitle` | together | вместе |
| `batonTookItPair` | {a} and {b} took it. | Берут на себя: {a} и {b} |
| `batonTookItPairAsk` | {a} and {b} took it: {ask} | Берут на себя: {a} и {b} — {ask} |
| `batonOutcomeYouTogether` | You and {name} took it. | Вы взялись. Вместе с вами: {name}. |
| `batonPlanStepPromptBodyPair` | {name} takes it on together with them. | Вместе с исполнителем: {name}. |
| receipt `batonPartnerAsked` | {author} wants to take it on together with you | {author} предлагает взяться вместе |
| receipt `batonPartnerAccepted` | {name} will take it on with you | {name} возьмётся вместе с вами |
| receipt `batonPartnerDeclined` | {name} can't join you. Answer again | {name} не сможет присоединиться. Ответьте ещё раз |
| receipt `batonTakenTogether` | You and {name} took it: {excerpt} | Вы и {name} взялись: {excerpt} |

Names are always nominative, after a colon or as the subject. There are no gendered past-tense verbs.

## 5. Out of scope

Groups larger than two; volunteering without being asked (the baton stays author-initiated); two plan steps for one pick; showing pairs on profiles or trust; reopening or reassigning a taken baton; any Hasura access to baton tables.

## 6. Open questions for the owner (recommended default in bold)

- **Q1. Who can be named?** Any admitted participant of the Request/Post except the baton's author and yourself, or only other people the author asked? **Default: any admitted participant.** A newcomer usually wants an experienced person, who may not have been asked.
- **Q2. Must the named person confirm?** **Default: yes.** Nobody takes it without saying they are available (D2). Until X confirms, the pair cannot be chosen.
- **Q3. What does the author see before confirmation?** **Default: only confirmed pairs.** A pending pair reads as «waiting», and a decline never reaches the author; it stays between A and X. The alternative is to show «A, together with X, waiting for X».
- **Q4. Pair size.** **Default: exactly two.** No trios and no chains; one confirmed pair per person per ask.
- **Q5. «Pick for me».** **Default: a pair is one entry in its tier** (the asked person's tier, or the better of two for a mutual pair), with no extra weight.
- **Q6. Plan-step offer after picking a pair (#479).** **Default: one step assigned to the asked person; the prompt names the partner.** The alternative is two steps, one each.
- **Q7. Can the author pick just one person of a confirmed pair?** **Default: no.** The pair is atomic, because A answered on the condition of having company. A can always change to a solo answer.
