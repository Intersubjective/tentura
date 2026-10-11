# Budding a Request from a Post — step-by-step implementation plan

**Status:** rev 3 (2026-10-11). Rev 2 applied the second review (25 findings, §9); rev 3 applies the
third review (17 findings, §10). Reviewers: independent Opus subagents, standing in for Astra, whose
codex quota ran out.
**Baseline:** `main` at `e46d59b7f` (latest migration `m0236`). The plan docs live on branch
`docs/post-request-budding`.
**For:** an implementer (human or model) who follows units literally, test-first, one unit at a time.
Each unit lists its goal, files, the tests to write **first**, the steps, and "done when".

**Sources of truth (read before any unit):**
1. [`post-request-budding-architecture.md`](post-request-budding-architecture.md) rev 2.2. "Arch §N" points there.
2. [`post-request-budding-design.md`](post-request-budding-design.md): owner decisions D1–D7 and N1–N6 (in Russian).
3. [`post-implementation-steps.md`](post-implementation-steps.md) **§0 (rules for every unit) applies verbatim.** It covers:
   - conventions;
   - migrations: one new migration per unit, next free number, an upgrade-path test;
   - transactions, exceptions and policies;
   - the V2 mutation pattern and the Hasura two-test rule;
   - the client schema, design system, l10n and mocks;
   - wrapped serial test runs (§0.2) and the definition of done (§0.3).

If a step contradicts the architecture, stop and report; do not guess. Line numbers are from
2026-10-11. If a quoted line has drifted, search for the named symbol. If the symbol is gone, stop.

---

## 0. Deltas to the shared rules

- **Lock order (Arch §4.1).** Every new path takes locks in this order and re-validates mutable state **after** locking:
  1. the global hierarchy lock;
  2. the Post: advisory lock `4242` + Post row (`PostLockPort.lockForPostMutation`);
  3. the child: advisory lock `4242` + child row;
  4. invite rows `FOR UPDATE`, ordered by `id`;
  5. recipient availability locks;
  6. trust pair locks.
- **Feature gate.**
  - `packages/client/lib/consts.dart` gets `const kPostBuddingEnabled = false;` (unit D0).
  - Every client entry point that starts a bud checks it. Unit E3 flips it.
  - Server paths are not gated, with one exception: §7 closure routing reads env `TRUST_BUD_ROUTE_CREDIT_ENABLED` (default `true`) as a kill switch.
- **No permanent Alloy gate tests.** Tests that check counts, SHAs, plan text or subprocess reruns do not land on `main`. Every test in this plan is behavioural.
- **No new Drift table classes.** Bud tables and the forward-edge flag are reached through raw SQL, the same way `post_first_response` and the `contact_*` columns already are.
- **SQL function redefinitions.** `CREATE OR REPLACE FUNCTION` resets attributes it does not restate.
  - Every redefinition copies the **latest** body from the newest migration that defines it (`grep -rn "FUNCTION public.<name>" packages/server/lib/data/database/migration/` and take the highest number).
  - It restates `COST`, `STABLE`, `SECURITY DEFINER` and `search_path`.
  - It adds a pg test that asserts the attribute in `pg_proc` where one was set (for example `beacon_can_read_content` `COST 1000`, m0227).
- **One outcome enum.**
  - `PostBudInviteOutcome { invited, notEligible, alreadyInvited, recipientPaused, blocked }`. Server and client use these names.
  - SQL `reason smallint`: 0 eligible, 1 notMember, 2 blocked, 3 notVisible, 4 recipientPaused, 5 alreadyInvited.
- **Russian copy** (use it verbatim; English is a faithful translation):

| Key (suggested) | RU | Where |
|---|---|---|
| `postBudAction` | Оформить запрос | message action, ⋯ menu |
| `postBudPickMessageTitle` | Из какого сообщения оформить запрос? | non-author source picker |
| `postBudInviteTitle` | Кого позвать | invite step |
| `postBudInviteExplanation` | Позванные получат приглашение и сами решат, участвовать ли. Остальные участники поста увидят запрос и смогут предложить помощь сами. | invite step |
| `postBudInviteVia` | через {name} | invite step, for a member the budder may not know |
| `postBudInviteManyWarning` | Каждый отмеченный получит просьбу. Отмечено: {count} | above N = 5 |
| `postBudInviteNoteHint` | Почему зовёте (необязательно) | per-invitee note |
| `postBudClosePost` | Закрыть пост и продолжить в запросе | checkbox |
| `postBudDiscoverableWarning` | Пост видели только его участники. Если сделать запрос видимым для всех, его увидят и другие. | discoverable toggle |
| `postBudForwardingWarning` | В посте пересылка была выключена. Запрос можно пересылать. | when the Post's forward policy is off |
| `postBudNotInvitedSnack` | Не удалось позвать: {names} | after submit |
| `roomBudNotice` | {name} оформил(а) запрос «{title}» и позвал(а) {count, plural, one{# человека} few{# человек} many{# человек} other{# человека}} | Post room notice |
| `roomBudNoticeNoInvites` | {name} оформил(а) запрос «{title}» | Post room notice, count 0 |
| `roomPostClosedNotice` | Пост закрыт. Разговор продолжается в запросе «{title}». | closed Post |
| `postClosedMarker` | закрыт | Разговоры |
| `beaconGrewFromPost` | Вырос из поста | child parent link |
| `inviteCardTitle` | {name} зовёт вас помочь | Activity card |
| `inviteAccept` | Принять | Activity card |
| `inviteDecline` | Не смогу | Activity card |
| `inviteAction` | Позвать | child People tab (snapshot observers) |
| `inviteStatusPending` | приглашён(а) | child People tab |
| `inviteStatusDeclined` | не сможет | child People tab |
| `inviteWithdraw` | Отозвать приглашение | child People tab |

## 1. Unit map (execution order)

| Unit | Title | Depends on |
|---|---|---|
| A1 | Promotion source may detach (source-delete fix) | — |
| A2 | Shared admission operation (refactor, no behaviour change) | — |
| A3 | Remove `BeaconRoomAdmit` (#283) | — |
| B1 | Schema: observers, invites, bud columns on child commands, sweep exemption, closed Post status, indexes | — |
| B2 | Effective Post members `E(P)` and invite facts (SQL + port) | B1 |
| B3 | Read wall: snapshot contextChild, no Post contextAncestor | B1 |
| B4 | Hierarchy realtime recipients for Post children | B3 |
| B5 | Contact sweep exemption + `contact_resolve_without_evidence` | B1 |
| C1 | Post-parent branch in the child pipeline (`createChildUnderPost`) | B2 |
| C2 | Attention catalog: invite events and settlement | — |
| C5 | Closed Post (`PostCloseOperation`, guards, lists) | B1 |
| C3 | `beaconBudFromPost` + `postBudInviteCandidates` | C1, C2, C5, B3, B5 |
| C4 | Invite lifecycle: create (later invites), accept, decline, withdraw, supersede, expiry | A2, C3 |
| C6 | Invite read projections + «Для вас» card data | C4 |
| C7 | Route credit provenance | C4 |
| C8 | Constellation: `parentBeaconId`, anchor inheritance sweep | C3 |
| C9 | Concurrency suite | C3–C5 |
| D0 | Gate + client schema/gql/data layer | C3–C8 |
| D1 | Bud flow UI | D0 |
| D2 | Post room: notice, footer, closed state; Разговоры marker | D0, C5 |
| D3 | Activity invite card | D0, C6 |
| D4 | Child Request: parent link, People-tab invites | D0, C4, C6 |
| D5 | Field `grewFrom` edge | D0, C8 |
| E1 | Remove conversion (client and server in one unit) + kind immutability | D1 |
| E2 | Repair Requests that break I1 (#284; also historical `BeaconRoomAdmit` admits) | A3, C4, E1 |
| E3 | Flip gate, full suites, docs | all |

Units A1–A3 and B1–B5 can land on `main` before anything is user-visible.

---

## 2. Prerequisites

### A1 — Promotion source may detach

**Goal (Arch §10.3).** Deleting a message that sourced a **published** child no longer violates `beacon_promotions_source_general_ck`.

Today the check is `(source_message_id IS NOT NULL) OR (published_at IS NULL)` (m0193:5267). The FK is `ON DELETE SET NULL` (m0193:7588), and unpublished NULL rows are legal today (m0158 nulls them in bulk, m0193:2357).

**Files:** a new migration (next free number, expected `m0237`) and `test/data/database/m0237_promotion_source_detach_pg_test.dart`.

**Tests first (pg):**
1. Publish a child from a Request message, then hard-delete the source message. The delete succeeds. `source_message_id IS NULL`, `published_at` is kept, and the child's `parent_beacon_id` is unchanged.
2. A draft promotion's source can still be deleted (the source becomes NULL). `publishDraft` then throws `BeaconPromotionSourceInvalidException` (`beacon_child_create_case.dart:316-318`).
3. Upgrade path through `0236`.

**Steps:**
- `ALTER TABLE public.beacon_promotions DROP CONSTRAINT beacon_promotions_source_general_ck;` and add nothing in its place. The consistency trigger (m0193:1121) still validates non-null sources.
- Client: `isRedundantChildCreatedNotice` and the footer must tolerate a missing source. Widget test: a notice whose source message was deleted renders without crashing.

**Done when:** the pg test and the footer tests under `test/features/beacon_threads/` pass.

### A2 — Shared admission operation

**Goal (Arch §5.3).** One implementation of "admit with both confirmations". `acceptHelpOffer` delegates to it and its behaviour does not change.

**Files:**
- `lib/domain/use_case/admission_operation.dart` (new; a domain service over ports).
- Ports: add actor-explicit methods.
- `coordination_repository.dart`.
- `beacon_room_repository.dart`: extract the body of `inviteOfferUserToBeaconRoom` (:1277-1342, author-scoped at :1284) into an actor-explicit internal that takes `confirmingAuthorId`.
- `commitment_repository.dart` (:51): record with an explicit actor and no nested `withMutatingUser`.
- `coordination_case.dart`.

**Tests first:**
1. **Row-set characterization (pg)**, `test/domain/use_case/admission_row_set_pg_test.dart`.
   - Run offer → `acceptHelpOffer`.
   - Collect rows from `beacon_help_offer`, `beacon_commitment_event`, `beacon_help_offer_coordination`, `beacon_help_offer_admission_event`, `beacon_participant`, the room-joined activity row and `trust_evidence` (approval).
   - Compare on kind, user, actor and role columns only. Exclude ids and timestamps.
   - **Attention receipts are out of scope** for this comparison: offer+accept creates and settles `helpOfferSubmitted` and sends `offerAccepted`, and invite accept will differ.
   - Write it against the current code first. It must fail if any one of the listed rows is missing; prove this with a deliberately broken run in your scratch branch, not in the committed test.
2. Steward case: a steward accepts → the same row set with `author_user_id = steward`.
3. Calling the operation with actor = helper and `confirmingAuthorId = author`, inside one `withMutatingUser(helper)` unit, produces the same row set. It must not raise `Nested mutating actor mismatch` (`tentura_db.dart:256-263`).
4. Existing suites keep passing: `coordination_case_test.dart`, `help_offer_case_test.dart`, `beacon_room_admission_matrix_test.dart`, and the closure tests that read commitment facts.

**Steps:**
- Add `AdmissionOperation.admitWithConfirmations({beaconId, helperId, confirmingAuthorId, actorId, attention})`. In order:
  - (a) ensure an active offer and an `offered` event, only if no offer is active;
  - (b) coordination `useful` with `author_user_id = confirmingAuthorId`;
  - (c) room admission (role helper, committed, admitted; join reason `accept`);
  - (d) admission event `accept`;
  - (e) under `closure.lockRequest`: the `acknowledged` event if this is a transition, then `applyMembershipEvent`;
  - (f) `recordApprovalEdge`;
  - (g) settle the author's `helpOfferSubmitted` obligation if one exists;
  - (h) emit the attention intent the **caller** supplies (`offerAccepted` for `acceptHelpOffer`; `authorInviteAccepted` for C4).
- It is **not idempotent**: step (d) only appends, exactly as today (`coordination_repository.dart:151-157`). Callers own idempotency (C4 locks the invite row and short-circuits on `status = 1`).
- `CoordinationCase.acceptHelpOffer` keeps its pre-checks (`_prepareAdmissionAction`, :163-191) and delegates with `confirmingAuthorId = actorUserId` (author **or steward**, as `:363-367` allows). The approval edge keeps `beacon.author.id`. Step (a) is a no-op there.

**Done when:** the characterization test and the listed suites pass.

### A3 — Remove `BeaconRoomAdmit` (#283)

**Goal.** No admission path exists without both confirmations. The client has no caller: `BeaconThreadsCase.admit` (`beacon_threads_case.dart:301`) is unused.

**Files:**
- Server:
  - the `beaconRoomAdmit` mutation (`mutation_beacon_room.dart:235`);
  - `BeaconRoomCase.admit` and `BeaconRoomRepository.admitParticipant`;
  - the port and the mocks;
  - the `admitParticipant` fakes in `beacon_room_mutation_kind_table_test.dart:302`;
  - `general_only_boundary_inventory_test.dart`.
- Client:
  - `beacon_room_admit.graphql` and its `_g` files;
  - `BeaconThreadsCase.admit` and the repository method;
  - `build_client.dart:314`;
  - `schema.graphql`.

**Tests first:** an admission-matrix case asserting that the `beaconRoomAdmit` field is absent from the V2 schema. Delete tests that only covered `admit`.

**Done when:**
- the server non-pg tests, the pg admission tests and `test/features/beacon_threads/` on the client pass;
- `grep -rn "admitParticipant\|beaconRoomAdmit\|BeaconRoomAdmit" packages --include=*.dart --include=*.graphql` finds nothing outside generated history.

The commit closes #283.

## 3. Schema and access

### B1 — Schema

**Files:** a new migration (next free number), `_migrations.dart`, and a pg test. No Drift classes (§0).

**SQL (Arch §2):**
- `beacon_bud_observer(beacon_id, user_id, created_at)`:
  - PK `(beacon_id, user_id)`; FK to beacon `ON DELETE CASCADE`; FK to user `ON DELETE CASCADE` (users are hard-deleted, `user_repository.dart:898`);
  - index `(user_id, beacon_id)`.
- `beacon_author_invite` as in Arch §2.2:
  - `source_post_id` is **nullable** (repair invites in E2 have none);
  - FKs: `beacon_id`, `inviter_id`, `invitee_id` `ON DELETE CASCADE`; `resolved_by ON DELETE SET NULL`; `forward_edge_id ON DELETE SET NULL`; `arrival_post_edge_id` has **no FK** (it is immutable provenance; an FK `SET NULL` would collide with the immutability trigger);
  - CHECK `status BETWEEN 0 AND 5`;
  - partial unique indexes `(inviter_id, invitee_id, source_post_id) WHERE status = 0 AND source_post_id IS NOT NULL` and `(beacon_id, invitee_id) WHERE status = 0`;
  - indexes `(invitee_id) WHERE status = 0`, `(beacon_id, status)` and `(forward_edge_id)`;
  - a BEFORE UPDATE trigger that rejects changes to `beacon_id, inviter_id, invitee_id, source_post_id, arrival_post_edge_id, warm`.
- `beacon_child_commands` (m0193:4932) gets `bud_result jsonb NULL` and `anchor_inherited_at timestamptz NULL`, plus a partial index `(created_at) WHERE bud_result IS NOT NULL AND anchor_inherited_at IS NULL`. This is the one idempotency table (Arch §2.6). There is no separate bud table and no second hash column: the bud hash goes into the existing `normalized_input_hash` with a `bud:` prefix, which `findCommand` and `recordCreateOutcome` already compare (`beacon_hierarchy_command_repository.dart:84-90`), so a `clientCommandId` reused across the two endpoints conflicts naturally.
- `beacon_forward_edge.contact_sweep_exempt boolean NOT NULL DEFAULT false`.
- `beacon_post_shape_ck`: Post statuses `{0, 2, 3, 6}`.
- No Hasura tracking for the new table and columns. Add `beacon_bud_observer` and `beacon_author_invite` to the "untracked tables" architecture test list (`test/architecture/hasura_metadata_closure_tables_untracked_test.dart`).

**Tests first (pg):**
- N5 uniqueness;
- immutable provenance;
- the status check;
- the shape check accepts 6 for Posts and still rejects 1, 5, 7 and 8;
- the indexes exist (`pg_indexes`);
- upgrade path.

### B2 — `E(P)` and invite facts

**Files:** a same-unit migration with the SQL functions, `lib/domain/port/post_bud_port.dart`, `lib/data/repository/post_bud_repository.dart`, and pg tests.

**SQL** (no `mr_*` calls; visibility stays in Dart, per Astra rev-2 finding 6 and `person_visibility_repository.dart:97-109`):
- `post_effective_members(p_post text) RETURNS TABLE(user_id text)`:
  - the author, plus participants with `room_access = 3` that pass `beacon_effective_admission`;
  - minus `block_hides(post_author, u)`.
- `post_bud_invite_facts(p_post text, p_budder text) RETURNS TABLE(user_id, warm boolean, reason smallint, has_written boolean, via_user_id text)`, computed over `E(P) \ {budder}`:
  - `warm` = the user is in `post_first_response` or is the Post author;
  - `reason` is one of 0, 2, 4 or 5 (§0 enum). Visibility is not decided here;
  - `has_written` = the user authored a non-system message in the Post;
  - `via_user_id` = the sender of the user's latest active inbound forward edge on the Post.
- `post_bud_pretick(p_post, p_budder) RETURNS TABLE(user_id)` (D5): users the budder @mentioned in the Post (`beacon_room_message.mentions` on the budder's messages), plus authors of messages whose `reply_to_message_id` points at a budder message.

**Port:** `PostBudPort.inviteCandidates(post, budder)` combines `post_bud_invite_facts` with `PersonVisibilityRepositoryPort.personVisiblePeerIds(budder, coldIds)`:
- a cold user who is not visible → `notVisible`;
- eligible = `reason = 0` and (warm or visible).

**Tests first (pg):**
- a member blocked with the Post author is excluded;
- a member blocked with the budder gets `blocked`;
- access 0 (cancelled forward) is excluded;
- left (5) is excluded;
- the author is included without a participant row;
- warm/cold classification;
- `has_written`, `via_user_id`, pretick.

Use bond or reciprocal-explicit-trust fixtures for the positive cold case and a no-relation fixture for the negative one. Neither needs MeritRank.

### B3 — Read wall

**Files:**
- a new migration redefining `beacon_can_read_content`, `beacon_access_reasons` and `beacon_readable_ids` (latest bodies: m0193 / m0227 COST / m0226);
- `lib/domain/beacon_access_policy.dart` plus `BeaconAccessFacts`;
- tests.

**Change (Arch §3.2):**
- **contextChild** (bit 64; `cand` in readable_ids): when the immediate parent has `kind = 1`, require `EXISTS beacon_bud_observer(child, viewer)` instead of live parent membership. The parent must still not be in status 2 or 3, and `NOT block_hides(post_author, viewer)` applies (today's contextChild applies the parent-author block, m0193:683). In `beacon_readable_ids` the `cand` CTE has no parent kind (m0226:14-18): join `beacon parent ON parent.id = c.parent_beacon_id` for this branch.
- **contextAncestor** (bit 128): the **target** must be a Request.
  - In `beacon_can_read_content` and `beacon_access_reasons`, add `b.kind = 0` to the ancestor branch (the `a.ancestor_id = b.id` join, m0193:451-470).
  - In `beacon_readable_ids` (m0226), add `kind` to `cand` and require `c.kind = 0` in the `member_ancestors` branch.
- Re-apply `ALTER FUNCTION public.beacon_can_read_content(...) COST 1000` (m0227) and keep the other attributes.
- `BeaconAccessFacts` gets `parentIsPost` and `isBudObserver`. `BeaconAccessPolicy` mirrors the SQL.

**Tests first (pg leak matrix, `post_bud_read_wall_pg_test.dart`):**
- a snapshot observer reads the child;
- a member who joined the Post after the bud cannot;
- a blocked observer cannot;
- a Request helper or forward recipient of the child **cannot** read the Post;
- Request-parent shared context is unchanged (the existing #146 tests pass);
- `beacon_readable_ids` agrees with `beacon_can_read_content` on every row of the matrix;
- `pg_proc.procost = 1000` for `beacon_can_read_content`;
- a `BeaconAccessPolicy` unit test mirrors the matrix.

Also run the existing readable-ids consistency and perf tests.

### B4 — Hierarchy realtime recipients

**Files:** a migration redefining the hierarchy recipient function (m0193:3925-3990, CTE `parent_linked` at :3950-3970), and a pg test.

**Change.** When the **owner's** parent has `kind = 1`, replace `parent_linked` with the owner's `beacon_bud_observer` rows minus `block_hides(owner_author, u)`. The observer CTE keeps `parent.status NOT IN (2,3)`, matching the read wall. The block path passes former recipients through the existing `p_extra_user_ids` (m0193:2557). The parent-deletion path passes no extras today (m0193:2668-2676); this is an **accepted gap** (former observers refetch on their next read and the wall answers) — pin it with a test. Emits whose owner is the Post itself (m0193:2613, 2643) are unchanged.

**Tests first (pg):**
- a later Post member gets no child hint;
- a snapshot observer who left the Post still gets it;
- a blocked observer gets only the invalidation.

### B5 — Contact sweep exemption + resolve without evidence

**Files:** `forward_edge_repository.dart` `claimIgnoredContacts` (:508-542), a migration with `contact_resolve_without_evidence(p_edge text)`, and pg tests.

**Change:**
- The sweep adds `AND NOT f.contact_sweep_exempt` **inside the inner subquery `f`** (the one with the deadline `ORDER BY` and `LIMIT $1`, `forward_edge_repository.dart:514-526`). On the outer `e` the never-resolved exempt rows would keep filling the LIMIT and starve the sweep.
- The new function resolves an unresolved contact edge the way `contact_edge_on_cancel` does (resolved, outcome NULL) and writes no evidence.

**Tests first (pg):**
- an exempt edge past its deadline → no noisy evidence;
- exempt edge + help offer → engaged;
- exempt edge + inbox decline → declined;
- the resolve function on a past-deadline edge before the sweep → the sweep skips it;
- more than `limit` old exempt rows plus one younger non-exempt row → the non-exempt row is swept.

## 4. Server use cases

### C1 — Post-parent branch in the child pipeline

**Files:**
- `beacon_child_create_case.dart`:
  - `createChild` :57; replay :133-161; `_assertParentCreateAllowed` :464-487; description override :177-181;
  - publish :267/:293; notice + attention :406-449.
- `beacon_repository.dart` `createChildBeacon` (:323).
- `beacon_hierarchy_command_repository.dart` `insertChildCreationNotice` (:397-450).
- Hierarchy delivery attention (`attention_intent_case.dart:692-745`).
- Exceptions: `postChildRequiresBud`, `budSourceNotOwnMessage`, `postNotOpen`.

**Behaviour:**
- **`createChild` with a Post parent** throws `PostChildRequiresBudException` **before** any status check. Update the order in `post_request_only_audit_pg_test.dart:324-336` accordingly.
- **New case method `createChildUnderPost(...)`.** It shares the internals of `createChild` and is the only Post entry point; C3 calls it. It:
  - runs the Post asserts (Arch §3.1): parent `kind = 1, status = 0`; actor ∈ `E(P)`; `sourceMessageId` required; `source.author_id = actor`;
  - calls `PostLockPort.lockForPostMutation(post)` right after `lockMutationScope` and **before** `_lockCreateScope` (`beacon_child_create_case.dart:164`; advisory xact locks are re-entrant, so the repeated global lock is harmless);
  - **keeps the client's title and description** (no override from the source body);
  - accepts `isDiscoverable` (default `false`; `createChildBeacon` gains the parameter, because the column default is `true`, m0193:857). This parameter is part of the input hash;
  - accepts a `PostParentStage` callback that runs inside the transaction after publish (C3 supplies it).
- **Notice and attention.** For a Post parent the `childCreated` notice payload adds `title` (a snapshot) and `invitedCount`, and **no** attention receipts are emitted. Hierarchy lifecycle deliveries whose **target** has `kind = 1` insert the notice row but emit **no** attention.
- **Replay** for `createChildUnderPost` happens right after the global lock and **before** any parent assert. It returns the stored `bud_result`, so it also works after `closePost`. The already-promoted path (`_recordAndReturnAlreadyPromoted`, `result_state = 2`, :195-205, :357-377) also stores a `bud_result`: `{outcome: alreadyPromoted, childBeaconId: <id if readable, else null>, invitees: []}`.

**Tests first (pg):**
- each guard through `createChildUnderPost`;
- `createChild` on a Post → `PostChildRequiresBud`;
- the client description is kept;
- `isDiscoverable = false` is persisted;
- child cancel → the Post-room lifecycle notice is present with zero receipts;
- Request-parent behaviour is unchanged (existing hierarchy tests).

### C2 — Attention catalog

**Files:**
- `attention_models.dart` (`AttentionEventType` and `assertDeclared` :18-61);
- `attention_policy.dart` and `notification_kind.dart`;
- `docs/contracts/updates-event-contract.json` (bump the schema);
- client `attention_event_classification.dart`, the client mirrors and their mirror tests.

**Events:**
- `authorInviteReceived` → the invitee. Optional update, Activity, collapse key per beacon; push allowed, as for `relayReceived`.
- `authorInviteAccepted` → the inviter. Optional update, no push.
- `authorInviteDeclined` → the inviter. Optional update, no push.
- Accept, decline, withdraw, supersede, expiry and block cleanup **clear** the invitee's `authorInviteReceived` receipt. That is not a visible event and has no copy. The port today only settles `helpOfferSubmitted` obligations (`attention_system_settlement_port.dart:1-27`), and optional receipts are governed by `cleared_at` (`attention_dismissible_sql.dart:94-95`): add `AttentionSystemSettlementPort.clearAuthorInviteReceived(beaconId, inviteeId)`, which sets `cleared_at` and `seen_at`. C4's use cases call it; the C4 expiry trigger clears in SQL.
- **No duplicate card.** In «Для вас» the `authorInviteReceived` receipt folds into the pinned inbox row for the same beacon; the D3 card is the only visible row.

**Tests first:** the catalog and contract tests fail on undeclared kinds; policy unit tests check recipients and `requiresAction = false`.

### C5 — Closed Post

**Files:**
- `post_case.dart` leave/return (:156-200);
- `beacon_room_case.dart`: send, edit, react, poll, message delete;
- `ForwardCase._checkForward`;
- a migration that **drops and recreates** `post_my_posts` (m0215:6-14) with status 6 and a `status` column (the return type changes);
- `beacon_repository.dart:74` `postSummary` and the server `PostSummary` type;
- `system_message_kind = 5` "postClosed" with payload `{childBeaconId, title}`, mirrored on the client;
- `PostCloseOperation`.

**Behaviour:**
- **`PostCloseOperation.closeForBud(post, child, title)`.** Sets status 6 (= `BeaconStatus.closed`) through `recordBeaconStatusTransition` **without** `recordEligibleSourceTransition` (otherwise the child would get a «parent closed» notice), then inserts the kind-5 notice.
- **Most writes are already rejected for status 6:** send, edit, react, poll, baton and fact cards (`beacon_room_lifecycle_write_policy.dart:10`, `polling_case.dart:78`), and forward via `allowsForward` (`forward_case.dart:375`). These get tests only.
- **New guards only for:** leave/return, budding, and deleting non-root messages.
- **Root delete on a closed Post.** Today `deleteMessage` runs `_guardMessageMutation` (`beacon_room_case.dart:1313`) before the Post-root branch (:1314-1320), so it would be refused. Move the Post-root branch **above** the lifecycle guard, for `kind = 1` only. The author can then delete the Post (6→2, `beacon_status_transition.dart:62`); the child survives.
- `PostSummary.status` maps to `BeaconStatus`.

**Tests first:**
- `closeForBud` tested directly;
- every write path on a closed Post → a typed error;
- reads still work for members;
- `post_my_posts` returns the Post with status 6;
- the field query (`constellation_field_snapshot_reader.dart:238`) excludes it;
- the child gets no lifecycle notice from the close;
- a kind-agnostic status audit: each switch has a test or a written "not affected" reason in the commit. Covers client status menus, inbox, constellation status sets and lifecycle effects.

### C3 — `beaconBudFromPost` + `postBudInviteCandidates`

**Files:**
- `lib/domain/use_case/post_bud_case.dart`;
- `lib/api/controllers/graphql/mutation/mutation_post_bud.dart` (+ `_mutations_all.dart`) and a query `postBudInviteCandidates(postId)` (+ the query aggregator);
- input/result types and ports;
- `ForwardEdgeRepository.createBatch`, which gains `bool Function(String recipientId)? sweepExemptFor`;
- an inbox re-pin repository method;
- exceptions.

**Query `postBudInviteCandidates(postId)`** (caller ∈ `E(P)`):
- returns `[{userId, warm, outcome, pretick, viaUserId, hasWritten}]`, writers first;
- `viaUserId` is returned only when it is not the caller.

**Mutation input/result:** Arch §4.2. Result: `{outcome, childBeaconId, invitees: [{userId, outcome: PostBudInviteOutcome}]}`.

**Steps** (one `runAction(actor = budder)` transaction, through `createChildUnderPost` with a `PostParentStage`):
1. Global lock.
2. Replay (stored `bud_result`; a hash mismatch → the existing `BeaconChildCommandConflictException`).
3. Post locks, then the Post asserts.
4. Create and publish the child: client content; `isDiscoverable` default `false`.
5. `PostParentStage` runs:
   - (a) the observers snapshot: `post_effective_members` minus the budder, minus users blocked with the budder;
   - (b) per invitee, via `PostBudPort.inviteCandidates`, which must return eligible:
     - `createBatch` author → U on the child, no parent edge, `sweepExemptFor(U) = warm`. The invite note is **not** copied into the edge note;
     - re-pin the inbox (`status = 0`, `tombstone_dismissed_at = NULL`);
     - `arrival_post_edge_id` = U's latest active inbound edge on the Post (NULL for the Post author);
     - insert the invite and emit `authorInviteReceived`;
   - (c) the notice with `title` and `invitedCount`;
6. If `closePost`: `PostCloseOperation.closeForBud`.
7. Store `bud_result` (the hash goes into `normalized_input_hash` with the `bud:` prefix). `anchor_inherited_at` stays NULL. After commit, nudge the C8 sweep (same pattern as `_publisher.nudge()`). No anchor work inside the bud transaction (C8).

**Tests first (pg, real attention dispatch):**
- the happy path writes: child parent; observers; invites; edges with per-recipient exempt flags; the inbox row pinned in «Для вас» (`eligiblePinned`); one notice with title and count; zero receipts to non-invited members;
- replay returns an identical result with no new rows;
- replay after `closePost` works;
- a different input under the same `clientCommandId` → conflict;
- per-invitee failures with their outcomes;
- a non-author budder from their own message;
- a budder from someone else's message is rejected;
- a closed Post is rejected;
- the candidates query: ordering, `viaUserId` hidden for self, non-member forbidden.

### C4 — Invite lifecycle

**Files:**
- `lib/domain/use_case/author_invite_case.dart`;
- mutations `beaconAuthorInviteCreate`, `beaconAuthorInviteAccept`, `beaconAuthorInviteDecline`, `beaconAuthorInviteWithdraw`;
- hooks in `HelpOfferCase.offerHelp` and `CoordinationCase.acceptHelpOffer` (supersede);
- block cleanup;
- a migration with the expiry trigger.

**Behaviour (Arch §5):**
- **Create (later invites, Arch §3.3).**
  - Child author only. Takes `PostLockPort` on `source_post_id` (lock-order step 2) before the child, so N5 cannot race a concurrent bud from the same Post.
  - The target must be a snapshot observer and eligible under the B2/§3.3 rules.
  - Forward edge author → U via `createBatch`. It does not return the id of an edge it reused (`forward_edge_repository.dart:144-157`), so call `findActiveEdge` afterwards and set `forward_edge_id` to it.
  - If warm: `UPDATE … SET contact_sweep_exempt = true` on that edge (a reused ordinary edge is not exempt; otherwise I8 breaks).
  - Re-pin the inbox row; insert the invite with `INSERT … ON CONFLICT DO NOTHING` on the N5 index predicate — no row inserted → `alreadyInvited`; `authorInviteReceived`.
- **Accept.**
  - Locks, then re-validate.
  - `AdmissionOperation.admitWithConfirmations(actor = invitee, confirmingAuthorId = inviter, attention = authorInviteAccepted)`.
  - The invite becomes accepted; the receipt is cleared. Idempotent: the locked invite with `status = 1` returns the accepted result without calling the operation again.
- **Decline.** The inbox decline path (`status = 2`), the invite becomes declined, the receipt is cleared, `authorInviteDeclined`.
- **Withdraw** (author).
  - The invite becomes withdrawn and the received receipt is settled.
  - Cancel the edge only if `ForwardCase` cancel rules allow (`forward_case.dart:82`); otherwise it stays as an ordinary forward.
- **Supersede.**
  - In `offerHelp`, **before** the offer insert, a pending invite for (beacon, helper) branches to `admitWithConfirmations(attention = authorInviteAccepted)`; no `helpOfferSubmitted` obligation is created; the invite becomes accepted.
  - The author accepts an ordinary offer from a pending invitee → the invite becomes superseded and is settled.
- **Expiry: one place.** An `AFTER UPDATE OF status ON beacon` trigger fires when a `kind = 0` beacon goes **terminal**: `NEW.status IN (1, 2, 6) AND OLD.status NOT IN (1, 2, 6)`. In the same transaction it:
  - expires the beacon's pending invites;
  - calls `contact_resolve_without_evidence` on their edges;
  - clears their `authorInviteReceived` receipts (`cleared_at`).

  **Review (status 5) does not expire invites**, because review can reopen (5→0/7/8 re-pins inbox rows, `m0213.dart:106-121`). Accept re-validates `isOpenFamily` and returns a typed error while the Request is in review.
- **Block cleanup.** Pending invites between the pair become withdrawn.

**Tests first:**
- row-set equality between invite accept and offer+accept, reusing the A2 comparison helper (**I7**);
- accept after cancel → a typed error and no rows;
- double accept is idempotent;
- decline → no evidence;
- withdrawing a read edge leaves the edge, and the invite can no longer be accepted;
- supersede, both directions;
- 0→5→7 keeps the invite pending; accept during review → a typed error;
- expiry through each terminal entry point (`closure_case.dart:150`, `closure_finalize_case.dart:101`, `beacon_case.dart:905` cancel, `beacon_case.dart:1048` delete, `user_erasure_case.dart:72`) → pending invites expired, receipts cleared, and no noisy evidence after the sweep (**I8**);
- a later invite that reuses an ordinary edge makes it exempt when warm;
- supersede via `offerHelp` creates no author obligation;
- after accept, Cancel and Delete are refused (`everAcknowledged`);
- a later invite after a decline re-pins the inbox row.

### C6 — Invite read projections

**Files:**
- V2 query `myPendingAuthorInvites` (for the invitee: invite id, beacon summary, inviter, note, created_at);
- V2 query `beaconAuthorInvites(beaconId)` (author only: invitee, status, note);
- attention SQL so that a «Для вас» row whose inbox item has a pending invite carries `inviteId` (a join, no new inbox column).

**Tests first:**
- the invitee sees their own invite and note;
- the author sees every invite on their child;
- an observer or anyone else gets an empty result or forbidden;
- the metadata test shows no Hasura select on the table.

### C7 — Route credit provenance

**Files:** `closure_repository.dart` (`selectArrivalEdge` :785, `routingSource` :905, attribution :931), `closure_case.dart:860-886`, `closure_finalize_case.dart:238-261`, `forward_causal_graph_builder.dart` (root rule :42-49, inbound traversal :74), and the env knob.

**Scope.** Only invites with `source_post_id IS NOT NULL`. E2 repair invites (NULL source) keep today's `selectArrivalEdge` and routing, so no existing credit is lost.

**Input change.** `RoutingInput` today has one `authorId`, one edge list and one `seedOfferAt` per helper (`closure_finalize_case.dart:250-260`), and the builder accepts a root only when `senderId == authorId` (`forward_causal_graph_builder.dart:42-47`). Extend it with per-helper `extraSegments: [{edges, attributionByBatch, rootSenderId, cutoffAt}]`. The builder accepts a segment root when `senderId == rootSenderId`; the segment is settled inside the **same** `rho*B` budget (state this in a code comment and pin it with a test).

**Behaviour (Arch §7).** For a helper with an **accepted** Post invite:
- **Approval arrival** = `arrival_post_edge_id`.
- **Closure causal input** for that helper:
  - one `extraSegment`: walk `parent_edge_id` from the arrival edge inside the Post, keeping edges created before the child's `published_at` (`cutoffAt`) and not cancelled before it, with attributions from the Post's batches; `rootSenderId` = the **Post** author;
  - the helper's child-side chain, as usual.
- The delivery edge is sent by the Request author, so it already earns nothing; no flag is needed.
- **Superseded** invites (status 5) do not use the Post arrival: the helper arrived through an ordinary offer.
- With the flag off, behaviour is today's.

**Tests first (pg + unit):**
- A→B→C in the Post, C is invited and accepts → approval credit to B; closure routed evidence for A→B and B→C only;
- an unrelated Post path to C (D→C) earns nothing;
- a cancelled Post edge is excluded;
- C forwards the child onward to E and E helps → the chain via the delivery-edge root works, and the delivery edge earns nothing (**I9**);
- the budder sits in the Post chain (non-author bud) → the budder earns nothing as the sender of the delivery;
- the shared budget: a helper with a Post segment gets the same total as without one;
- an E2 repair invitee keeps today's credit;
- flag off → no cross-beacon credit.

### C8 — Constellation

**Files:**
- Server:
  - `constellation_field_snapshot_reader.dart` + `custom_types.dart`: `ConstellationRequest.parentBeaconId`, set only when the parent is a Post readable by the viewer;
  - `constellationRequestSelectColumns`;
  - `AnchorInheritOperation`;
  - a periodic sweep in `task_worker_case.dart` (same pattern as the contact sweep at :228-237, throttle 10 s).

**Behaviour:**
- **`AnchorInheritOperation.inherit(child, post, viewer)`.** Insert-if-absent of a child anchor at the Post's anchor coordinates: offset by a fixed vector if the Post is open, the same position if it is closed. It calls the existing `applyBatch`, which runs its own viewer-scoped transaction through the constellation scheduler (`constellation_anchor_repository.dart:32-40`), with op id `bud:<child>:<viewer>`.
- **Nothing runs inside the bud transaction.** A synchronous call would hold the global hierarchy lock while waiting on the scheduler (max 2 concurrent, 10 s queue deadline). The budder is handled by the sweep like every other viewer; C3 nudges the sweep after commit.
- **The sweep, without a long-lived row lock** (a held claim transaction would make each per-viewer `applyBatch` nest under a different actor and throw, `tentura_db.dart:256-263, 295-297`):
  1. select up to N rows with `bud_result IS NOT NULL AND result_state = 0 AND anchor_inherited_at IS NULL`, no lock (B1 partial index);
  2. for each row, iterate viewers in `viewer_id` order who have a live Post anchor and can read the child (budder included), each in its **own** transaction; repeating is safe, because the op log replays `bud:<child>:<viewer>`;
  3. a final short transaction sets `anchor_inherited_at` `WHERE anchor_inherited_at IS NULL`.

**Tests first (pg):**
- after one sweep run, both the budder's and another viewer's anchors exist;
- an already-promoted command row (`result_state = 2`) is never swept;
- two concurrent sweep runs produce one anchor per viewer;
- a viewer who already anchored the child keeps theirs;
- a second sweep run is a no-op;
- a non-reader gets nothing;
- `parentBeaconId` is NULL for a viewer who cannot read the Post.

### C9 — Concurrency suite

`post_bud_concurrency_pg_test.dart`:
- bud ∥ bud on the same source message → one child, `alreadyPromoted`;
- bud ∥ bud with the same `clientCommandId` → one child, the second call replays;
- accept ∥ child cancel;
- accept ∥ child delete;
- accept ∥ block;
- bud ∥ block(budder, invitee);
- bud ∥ the invitee leaves the Post;
- bud ∥ Post close;
- withdraw ∥ accept;
- later invite ∥ bud from the same Post (N5).

No deadlocks (with a statement timeout set). Invariants I1, I2 and I6 hold after each race.

## 5. Client

### D0 — Gate, schema, data layer

- `kPostBuddingEnabled = false`.
- Fetch the schema (§0 rule) or hand-edit `schema.graphql`.
- `.graphql` documents:
  - `post_bud_from_post`, `post_bud_invite_candidates`;
  - `author_invite_create`, `author_invite_accept`, `author_invite_decline`, `author_invite_withdraw`;
  - `my_pending_author_invites`, `beacon_author_invites`.
- Domain entities `AuthorInvite`, `PostBudInviteCandidate`, `PostBudResult`, and the `PostBudInviteOutcome` enum.
- Port + repository + use case: `PostBudCase` and `AuthorInviteCase`.
- Exception-code mirrors.
- `PostSummary.status`.
- The `ConstellationRequest.parentBeaconId` mapper.

**Tests:** repository wire tests (variables, mapping, exception mapping).

### D1 — Bud flow UI

Invoke the `material-3-flutter` skill first.

- **Entry points.**
  - Room message action «Оформить запрос» on the user's own messages. `RoomCapabilities.post()` is a `const` constructor (`room_host.dart:37`), so add a bool flag `childPromotionOwnOnly`; the message tile evaluates `isOwnMessage`. Use secondary-tap plus a visible action, never long-press alone.
  - Post ⋯ menu entry: the author goes to the root; others go to a source picker listing their own eligible messages.
- **`BeaconCreateScreen` in child mode with a Post parent.** Reuse `BeaconCreateRoute(parentBeaconId:, sourceMessageId:)`; the cubit detects a Post parent.
  - Prefill via the generalised `PostConversionCase.prefill`, renamed to `MessagePrefillCase` (update both callers; the conversion flow still uses it until E1): title = first line, description = the rest. No cover suggestion, because the pipeline takes no cover.
  - The invite step uses `postBudInviteCandidates`:
    - writers first; ineligible members hidden; pretick applied; «через X» from `viaUserId`;
    - a warning above 5 ticked; a per-invitee note.
  - «Закрыть пост…» defaults to on iff every eligible member is ticked or `E(P)` has at most 2 members.
  - Discoverable defaults to off, with the warnings.
  - Submit calls `beaconBudFromPost` with a stable `clientCommandId` per screen session, so repeated taps are safe (pattern: `request_publish_repeat_tap_test.dart`).
- **Result.** Navigate to the child. If some invitees were not invited, show `postBudNotInvitedSnack`.

**Tests:**
- cubit tests: prefill, pretick, default of the close checkbox, payload, repeat tap;
- widget tests: entry visibility for own vs others' messages; gate off hides everything; invite-step ordering; «через X»; warnings.

### D2 — Post room and Разговоры

- **Bud notice.** For Post rooms, the `childCreated` notice renders `roomBudNotice` / `roomBudNoticeNoInvites` from the payload `title` + `invitedCount`. It is **never** treated as redundant (`isRedundantChildCreatedNotice`, `basic_chat_body.dart:42-50`, is bypassed for Post rooms).
- **Footer** on the source message: the existing widget.
- **Closed Post.** The kind-5 notice, a disabled composer and hidden write actions.
- **Разговоры.** Closed Posts sit in «Затихли» with `postClosedMarker`.

**Tests:**
- the notice shows while its source message is loaded;
- a non-observer sees the payload title;
- the closed state hides reactions, forward and leave;
- the marker shows in Разговоры.

### D3 — Activity invite card

A «Для вас» row with `inviteId` renders the invite card (inviter, note, «Принять» / «Не смогу»).
- **Accept** calls `AuthorInviteCase.accept`. The row leaves the pinned zone (the Request is now in scope) and appears on My Work.
- **Decline** uses the existing decline UX.

**Tests:** cubit + widget tests; optimistic state rolls back on typed errors (invite expired or withdrawn).

### D4 — Child Request

- **Parent link.** «Вырос из поста» via `BeaconHierarchyParentLink`, shown only when the parent is readable; otherwise the generic reference.
- **People tab, for the author:**
  - an invites section (status, note, withdraw);
  - an «Позвать» action on snapshot observers (`beaconAuthorInviteCreate`).

**Tests:** widget tests for author vs non-author.

### D5 — Field `grewFrom`

- `ConstellationEdgeKind.grewFrom` (`constellation_scene_controller.dart:26`).
- Add it to both exhaustive switches (`constellation_scene_controller.dart:506-545`, `ui/utils/constellation_edge_style.dart:61-111`) and to the legend (`graph_legend_content.dart`).
- Call `addEdge(srcId: parentBeaconId, dstId: childId)` when both nodes are present.

**Tests:** a scene-controller unit test (the edge is present iff both nodes are) and a style test.

## 6. Removal, repair, ship

### E1 — Remove conversion + kind immutability

One unit for client and server together, so `main` never has a client calling a removed mutation.

- **Server:** the Arch §10.1 list.
- **Migration:** replace `beacon_kind_policy_guard` with a version that rejects **any** kind change and **keeps** the one-way forward-policy clause (m0209:35-37).
- **Client:** the Arch §9 "Removed" row. `_ConvertedToRequestNotice` stays, because `batonTaken` uses it.

**Tests:**
- delete the conversion tests from the research inventory: 6 server files plus partials, 10 client files plus partials. Adjust the partial ones; do not delete them;
- pg: any `UPDATE beacon SET kind` → an error (**I5**);
- pg: forward policy on → off → still an error;
- a historical kind-4 row still renders.

### E2 — Repair Requests that break I1 (#284)

**Scope.** Every open-family `kind = 0` beacon with an admitted non-author, non-steward participant who has no `acknowledged` commitment event. That covers converted Requests (kind-4 row) and historical `BeaconRoomAdmit` admits. Beacons in status 5 or terminal are **not modified** and are only listed in the report.

**Classes:**
- **Offer without an ack.** Keep the offer and revert room access to the ordinary pending state. The author obligation is kept if present (a migration cannot create one).
- **No own confirmation.**
  - Remove room access. For role-6 (addressee) rows **delete** the participant row; otherwise `inviteOfferUserToBeaconRoom` would keep role 6 on accept (`beacon_room_repository.dart:1287-1330`).
  - Insert a pending `beacon_author_invite`: `inviter_id` = the beacon author, `source_post_id` NULL, `arrival_post_edge_id` NULL, `warm = true`.
  - `forward_edge_id` = the person's latest active inbound edge on the beacon. **If none exists, insert one author → U with `contact_sweep_exempt = true`.** Without it the person cannot read the (non-discoverable) beacon, `eligiblePinned` (requires `beacon_can_read_content`, `attention_dismissible_sql.dart:73`) hides the invite forever, and the invite holds the `(beacon_id, invitee_id)` slot.
  - The forward-insert trigger creates or updates the inbox row; set its `status = 0`.
  - **No notification**: a migration cannot dispatch attention. The «Для вас» pin is the only surface.
- **Acknowledged at least once.** Untouched.

Write a report (`RAISE NOTICE` with counts per class plus the list of skipped review/terminal beacons).

**Tests first (pg):** fixtures for each class and for status 5 / closed; a repaired invitee with no prior edge can read the beacon, sees the pinned row, and accepting yields role helper. After the migration the I1 audit passes over all open-family `kind = 0` beacons.

The commit closes #284.

### E3 — Ship

- Flip `kPostBuddingEnabled`.
- Run all suites serially (§0.2 of the shared rules) and the custom lints.
- Update the docs:
  - `CONTEXT.md`: Post children, budding, author invite, the observers snapshot, the two-confirmation rule, closed Post;
  - `.cursor/rules/terminology.mdc`: no new nouns; the «Оформить запрос» copy;
  - `docs/Tentura_current_status_quo.md`;
  - mark the Q10 / A7 amendments in `post-and-constellation-composer-plan.md`;
  - close #250 with a link to the design.
- Local e2e: the budding happy path on the local stack (`local-debug` skill, QA login, the email OTP sink).

## 7. Invariant → test map

| Invariant (Arch §11) | Unit / test |
|---|---|
| I1 committers acknowledged | A3, E2 audit pg test |
| I2 two confirmations | A2, A3, C4 |
| I3 no Post via contextAncestor | B3 |
| I4 snapshot observers | B2, B3, B4 |
| I5 kind immutable | E1 |
| I6 one pending invite | B1, C3, C4 |
| I7 identical row sets | A2, C4 |
| I8 warm / expired → no noisy | B5, C4 |
| I9 route credit chain only | C7 |
| I10 bud replay | C1, C3, C9 |
| I11 realtime snapshot | B4 |

## 8. Revision history

- rev 1 (2026-10-11): initial plan from architecture rev 2.
- rev 2 (2026-10-11): second review applied (§9).
- rev 3 (2026-10-11): third review applied (§10).

## 9. Second review — disposition

The reviewer was an independent Opus subagent, used as the fallback because Astra (codex) hit its quota.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | blocker | C3 ↔ C5 dependency cycle | C5 depends on B1 only and runs before C3; `closeForBud` is tested directly |
| 2 | blocker | A1 check inverted; could fail on live unpublished NULL rows | A1 drops the check; test the draft-source delete + `BeaconPromotionSourceInvalidException` |
| 3 | major | No after-commit task mechanism (`TaskRepository` supports only image hash) | C8: synchronous for the budder + a durable sweep over `beacon_child_commands.anchor_inherited_at` |
| 4 | major | Pipeline overwrites the description; `is_discoverable` defaults to true | C1: keep client content for Post parents; `isDiscoverable` parameter in the hash; D1 drops the cover |
| 5 | major | Two idempotency tables; replay after the parent assert | B1 extends `beacon_child_commands`; C1/C3 replay before asserts; replay-after-close test |
| 6 | major | MR-dependent visibility in SQL | B2 SQL without visibility; Dart `personVisiblePeerIds`; MR-free fixtures |
| 7 | major | No server owner for the candidates query; «через X» missing | C3 `postBudInviteCandidates` with `viaUserId`, `hasWritten`, `pretick` |
| 8 | major | Later invites missing | C4 `beaconAuthorInviteCreate`; D4 «Позвать» |
| 9 | major | N6 notice hidden as redundant; no title in the payload | C1/C5 payload `title`; D2 never redundant in Post rooms |
| 10 | major | Child lifecycle notices notify live Post members | C1 suppresses attention for hierarchy deliveries targeting `kind = 1` |
| 11 | major | B4 mis-specified | B4 targets the `parent_linked` CTE when the owner's parent is a Post |
| 12 | major | Row-set comparison underspecified | A2 step (h) is caller-supplied attention; the comparison excludes receipts and ids |
| 13 | major | Expiry hooks not enumerated | C4: one `AFTER UPDATE OF status` trigger; a test per entry point |
| 14 | major | E2 audit fails on data outside scope; repair invite fields undefined | E2 covers all open-family violators; fields and inbox upsert defined; no notification |
| 15 | major | COST reset; wrong alias in the ancestor guard | §0 redefinition rule; B3 exact clauses + `procost` test; `BeaconAccessFacts` fields |
| 16 | major | No indexes for the new read paths | B1 indexes |
| 17 | minor | C1 guards unreachable via the API | `createChildUnderPost`; exception order fixed |
| 18 | minor | C5 gaps (drop/recreate, transition without notice, delete rules) | C5 specifies all three |
| 19 | minor | C7 root rule and superseded invites | Post-author root; superseded invites don't use the Post arrival; budder-in-chain test |
| 20 | minor | Per-recipient sweep exemption; edge note | `sweepExemptFor`; the note stays on the invite |
| 21 | minor | Drift classes not used for such tables | §0: raw SQL only |
| 22 | minor | Stale refs (baseline, enum name, line, A3 files, outcome names) | Fixed; one outcome enum in §0 |
| 23 | minor | E1 must keep the forward-policy rule | E1 keeps it + test |
| 24 | minor | C2 withdraw as settlement; C9 races | C2 settlements; C9 two more races |
| 25 | minor | A3 doesn't need A2 | Dependency removed |

## 10. Third review — disposition

The reviewer was an independent Opus 5.5 subagent (read-only).

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | blocker | C8 sweep held a row lock while running per-viewer mutating units (nested actor mismatch) | C8: unlocked select → per-viewer own transaction (op-log replay) → final marker transaction; B1 partial index |
| 2 | major | Synchronous budder anchor waits on the constellation scheduler under the global hierarchy lock | Removed from C3; the sweep handles the budder; nudge after commit |
| 3 | major | Expiry on 0→5 is wrong: review can reopen | C4 trigger on terminal `{1, 2, 6}` only; accept refused during review; tests |
| 4 | major | The settlement port only handles `helpOfferSubmitted`; no owner for clearing receipts | C2 `clearAuthorInviteReceived`; callers enumerated; no duplicate card |
| 5 | major | Root delete on a closed Post is blocked by the lifecycle guard; many guards already exist | C5 moves the Post-root branch above the guard; new guards only where missing |
| 6 | major | The exempt filter on the outer alias starves the sweep | B5 filter inside subquery `f`; starvation test |
| 7 | major | The already-promoted outcome has no bud result; the sweep could anchor someone else's child | C1 stores an alreadyPromoted `bud_result`; C8 filters `result_state = 0`; hash in `normalized_input_hash` |
| 8 | major | `RoutingInput` can't express per-helper Post segments | C7 `extraSegments` with their own root sender and cutoff, shared budget; scoped to Post invites |
| 9 | major | E2 invitees without an inbound edge can't read, see or accept | E2 inserts an exempt author → U edge; role-6 rows deleted; obligation "kept if present" |
| 10 | major | A2 "idempotent" contradicts today's behaviour; steward accept | A2 not idempotent (C4 owns it); `confirmingAuthorId = actor`; steward test |
| 11 | major | Later-invite edge reuse, warm flag, N5 race | C4 `findActiveEdge`, exempt when warm, Post lock, `ON CONFLICT DO NOTHING`; C9 race |
| 12 | minor | C1 lock order unstated | `lockForPostMutation` after `lockMutationScope`, before `_lockCreateScope` |
| 13 | minor | FKs on hard-deleted users; immutable column with an FK | B1 FK actions; `arrival_post_edge_id` without FK |
| 14 | minor | B3/B4 details (cand join, author block, deletion extras) | Spelled out; parent-deletion extras are an accepted, tested gap |
| 15 | minor | The architecture contradicts the plan in five places | Arch rev 2.2 |
| 16 | minor | Supersede via `offerHelp`: attention unspecified | Branch before the offer insert; no obligation; test |
| 17 | minor | `RoomCapabilities` is const; the prefill rename breaks conversion | A flag + tile check; update both callers |
