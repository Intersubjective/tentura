# Fact continuity across Requests and Posts — architecture plan

**Status:** shipped (2026-11-14; epic tentura-zzla; last revision: rev 4, 2026-11-12). Owner decisions D1–D20 confirmed. Rev 2 applied a first independent code review
(5 blockers, 10 majors, 5 minors); rev 3 applies a second one (2 blockers, 10 majors, 8 minors); rev 4 applies a third (2 blockers, 6 majors, 7 minors, all text corrections). Review-driven decisions R1–R6 approved by the owner (2026-11-12). Shipped as epic tentura-zzla.
**Related:** [ADR 0004](../adr/0004-beacon-lineage-fork.md) (fork), [post-ttl-design.md](post-ttl-design.md),
[post-request-budding-architecture.md](post-request-budding-architecture.md), [features/beacon_room.md](../features/beacon_room.md).

Path shorthand: `S/` = `packages/server/lib`, `C/` = `packages/client/lib`.

## 1. What we build

A fact stays local to its episode (a Request or a Post, `beacon`). A member can **copy** a fact into another
episode. The copy is a new, independent fact that remembers which fact and which revision it came from.
Nothing is ever synchronised between a fact and its copies.

Four user-visible additions:

1. **Push:** a fact action «Use in another Request or Post» with a destination picker.
2. **Pull:** a personal list of **saved facts** (pointers, like saved stickers); the chat's fact picker gets a
   «Saved» tab, and picking a saved fact brings it into the current episode.
3. **Checklists:** fork and Post budding let the user tick facts to bring.
4. **Facts on Posts:** pinning, editing and listing facts works in a Post.

Product principle: facts belong to episodes; provenance connects episodes; nothing is canonical.

## 2. Decisions

| # | Topic | Decision |
|---|---|---|
| D1 | History of a copy | The copy starts at **revision 1** holding only the copied text and images. Source revisions are **not** duplicated. Earlier history is reachable only through the origin link. |
| D2 | Who may copy | Anyone who can read the fact now, by the single access rule of §4.4. |
| D3 | Source room | Learns nothing: no chat line, no event, no notification, no counter in the source. |
| D4 | Visibility of a copy | Always lands **discussion-only**. Widening is the existing «Make public» action in the destination. |
| D5 | Facts on a Post | One visibility. Stored as discussion-only (`visibility = 1`). No «Make public / private» on a Post. |
| D6 | Origin line | Generic text «Brought from another Request» / «…Post». No source title, no source names. Shown to every reader of the copy. |
| D7 | Tapping the origin line | Opens the source fact if the viewer may read it; otherwise «The original isn't available to you». The same answer for hidden, unpinned and deleted sources. |
| D8 | Arrival at the source | Everyone sees the source's **current** text. If it changed since the copy, a note says so. Only members of the source discussion get «See the copied version» (opens history at that revision). |
| D9 | Chain | One hop at a time. A copy stores only its direct origin. No recursive query exists. |
| D10 | Duplicates | At most **one live copy per source fact per destination**. A second attempt answers «Already there» and returns the existing copy. After the copy is unpinned the fact can be copied again. |
| D11 | Images | Each image is re-stored as a new blob owned by the copier. All or nothing per fact. This **overrides** ADR 0004 decision 2 for facts (that decision duplicates images only when the forker is the source author). |
| D12 | Push destinations | Published episodes the actor may write facts in, **plus the actor's own drafts** (Requests and Posts). No «New Request / New Post» rows in the picker. |
| D13 | Drafts | A fact copied into a draft exists at once (snapshot fixed). No chat line until publish; publish writes one grouped line. |
| D14 | Fork | The fork sheet gets a «Facts to bring» checklist, nothing ticked. |
| D15 | Budding | The bud form gets the same checklist, nothing ticked. Works from an archived Post. |
| D16 | Chat line | New system line «X brought a fact from another Request», grouped for several facts. |
| D17 | Post UI | Facts are pinned and picked in the Post's Chat and **listed in the Post info sheet**. See R6: there is no facts strip in any room today. |
| D18 | Saved facts | A saved fact is a **pointer** (user id + fact id). The list shows the fact's current text, checked against the viewer's current rights. Unreadable, unpinned or deleted rows show «No longer available». |
| D19 | Picking a saved fact | Copies it into the current episode (D4, D10 apply) and attaches it to the message being written as a quote. |
| D20 | Managing saved facts | «Save to my facts» / «Remove from my facts» in the fact actions sheet; the «Saved» tab is the only list. Cap 200. No separate screen. |

Defaults chosen without asking (unchanged from rev 1):

- A copy takes the source's head revision **as read by the prepare step** and records that `seq`. The client sends no revision number.
- `pinned_by` of a copy is the copier. The copier has no special rights.
- No "used in N places" indicator anywhere.

Review-driven decisions, **approved by the owner 2026-11-12**:

| # | Question raised by the review | Decision |
|---|---|---|
| R1 | A ticked fact is unavailable when fork or bud runs. | Skip it; never fail the fork or bud. This includes a fact whose image copy hits the daily upload cap. `BeaconFactCardCopy` (one fact) still throws. |
| R2 | A fact's image row is already gone, or the attachment is not an image. | Drop that attachment from the copy; copy the rest. |
| R3 | A Post message pinned as a fact is rejected as a bud source today (`BeaconPromotionEligibilityPolicy`), including the root message. | Relax the rule for Post parents: on a Post the source is prefill only and binds nothing. |
| R4 | Saved row whose source was hard-deleted vs unpinned. | No foreign key on the saved fact id, so both show «No longer available» (no distinguishable signal). |
| R5 | Fact writes on a draft (pin, edit, restore, visibility) already write chat lines into an unpublished room. | Reject them on a draft. A draft accepts only copy-in and remove. |
| R6 | D17 was chosen on a mockup with a facts strip at the top of the Chat. No such strip exists. | No new strip. Post facts are reached from the info sheet list, the pinned-message mark, and the fact picker. |

## 3. Conflicts and holes

| # | Conflict | Resolution |
|---|---|---|
| X1 | §7 of the task says a copy's history continues the parent's. Acceptance 1 says it begins at revision 1. §6 forbids leaking source revisions and participants. | D1. |
| X2 | Task §5 «or create a new episode». | D12, D14, D15. |
| X3 | Request-visible vs discussion-only has no meaning on a Post. | D5. |
| X4 | ADR 0004 decision 8: the parent is a link, never a title. | D6. |
| X5 | ADR 0004 decision 2: fork never copies room content, and copies images only for the source author. | ADR amendment: ticked facts are copied; a non-admitted forker is offered request-visible facts only; fact images are always duplicated for the copier (D11). |
| X6 | «Provenance identifies an immutable revision» vs history being members-only. | D8. |
| X7 | Saved facts vs «a fact belongs to exactly one episode». | D18: pointers only. |
| X8 | The fact edit rate limit counts every revision by the actor (pins included), window 60 s, max 20. | Copy revisions (`kind = 4`) are excluded from that count. |
| X9 | The daily upload cap can refuse an image copy. Compensation does **not** refund the quota. | Single copy: fails with «Daily upload limit reached». Fork and bud: that fact is skipped (R1). |
| X10 | **Existing hole:** `history()` authorises the `beaconId` argument but queries by `fact_card_id` only, so any member of any room reads any fact's revisions and editor names. | Block P fixes it before anything else ships. |
| X11 | **Existing hole:** `BeaconFactCardCorrect` stores client attachment JSON unvalidated. With copy, a forged `imageId` makes the server re-store any image under the copier. | Block P validates it. |
| X12 | `loadRoomAccess.can_use_room` ignores block pairs on Posts and is true on deleted beacons. | One SQL access function, §4.4, deliberately stricter than `RoomAccessPolicy.canUseRoom`. Consequence: a blocked but admitted Request participant, who reads room messages today, loses fact history and fact writes (consistent with `_rejectIfBlockedFromBeaconAuthor` on message writes). |
| X13 | Post writes are serialised with archiving by DB triggers (m0271) on messages, reactions, polls, batons. Fact tables have none. | A dedicated guard on `beacon_fact_card`, §4.5. |
| X14 | A Post lives ≤ 72 h; its facts become read-only at expiry. | Intended. They stay readable and copyable; budding carries them on. |
| X15 | Fact chat lines (markers 2, 3, 10, 11, 20) have an empty body and no `system_message_kind`. On a Post they would become the "last message" (blank excerpt) and count as unread in the Posts list (`post_my_posts`, m0306). | Exclude them there, §5.1 item 7. They still count as member activity in `participantActivitySql`; accepted. |

## 4. Data model

**One migration per block** (next free numbers after `m0310`; never edit a shipped migration): block P → §4.4;
block A → §4.1, §4.2; block B → §4.5 and the `post_my_posts` change (§5.1 item 7); block D → §4.3.
Hand-written `migrant` SQL in `_migrations.dart`. Mirror every change in the Drift table classes and regenerate `tentura_db.g.dart`.

### 4.1 `beacon_fact_card` — three new columns

```sql
ALTER TABLE public.beacon_fact_card
  ADD COLUMN origin_fact_card_id text,
  ADD COLUMN origin_revision_seq integer,
  ADD COLUMN origin_beacon_kind  smallint,
  ADD CONSTRAINT beacon_fact_card_origin_ck CHECK (
    (origin_fact_card_id IS NULL AND origin_revision_seq IS NULL AND origin_beacon_kind IS NULL)
    OR (origin_fact_card_id IS NOT NULL
        AND origin_revision_seq IS NOT NULL AND origin_revision_seq >= 1
        AND origin_beacon_kind IS NOT NULL AND origin_beacon_kind IN (0, 1))
  );

CREATE UNIQUE INDEX beacon_fact_card_one_live_copy_idx
  ON public.beacon_fact_card (beacon_id, origin_fact_card_id)
  WHERE origin_fact_card_id IS NOT NULL AND status IN (0, 1);
```

- **No foreign key** on `origin_fact_card_id`: provenance must survive deletion of the source.
- `origin_beacon_kind` (0 Request, 1 Post) feeds the origin line without a join. Beacon kind is immutable (m0247, m0308).
- A `BEFORE UPDATE` trigger raises when any of the three columns changes. No existing UPDATE touches them.

### 4.2 `beacon_fact_card_revision.kind`

Drop the existing inline CHECK on `kind` (unnamed in m0199, so PostgreSQL names it
`beacon_fact_card_revision_kind_check`; confirm, and use `DROP CONSTRAINT IF EXISTS`) and add one allowing
`(0, 1, 2, 3, 4)`. `BeaconFactCardRevisionKindBits.copied = 4` in the server and client consts.
Revision 1 of a copy has `kind = 4`, `actor_id = copier`.

### 4.3 `user_saved_fact`

```sql
CREATE TABLE public.user_saved_fact (
  user_id      text NOT NULL REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  fact_card_id text NOT NULL,                       -- no FK, see R4
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, fact_card_id)
);
CREATE INDEX user_saved_fact_user_idx ON public.user_saved_fact (user_id, created_at DESC);
```

No NOTIFY trigger. Not in Hasura metadata (facts are not there either). Add a Drift table class.

### 4.4 One access function

`public.beacon_fact_access(p_beacon_id text, p_user_id text)` returns one row:

| Column | Meaning |
|---|---|
| `beacon_exists` | the beacon row exists |
| `kind`, `status` | as stored |
| `is_draft` | `status = 3 OR (kind = 1 AND status = 0 AND post_root_message_id IS NULL)` (a closed Post without a root message is **not** a draft) |
| `is_expired_post` | `kind = 1 AND status = 0 AND expires_at IS NOT NULL AND expires_at <= now()` (identical to `beacon_hierarchy_repository.dart` `isExpiredPost`) |
| `can_read` | `beacon_can_read_content(p_beacon_id, p_user_id)` |
| `can_use_room` | `can_read` AND the beacon is not deleted AND (author OR steward OR participant with `room_access = 3`) |

`beacon_can_read_content` already starts with `block_hides(author, viewer)` for every kind (m0309), so no
extra block term is needed. This rule is **intentionally stricter** than `RoomAccessPolicy.canUseRoom`:
blocks apply on Requests as well as Posts, deleted beacons are denied, and a draft is author-only.

**Fact access rule, used everywhere:** a request-visible fact needs `can_read`; a discussion-only fact and
every write need `can_use_room`. History stays `can_use_room` whatever the fact's visibility. `loadRoomAccess` is rewritten to call this function and to return `kind`,
`isDraft`, `isExpiredPost` as well (five test fakes and `beacon_fact_room_access_test.dart` construct `BeaconFactRoomAccess` and need the new fields).
`SavedList` and `CopyDestinations` call the same function.

### 4.5 Post archive guard on `beacon_fact_card` (block B)

The m0271 function `beacon_post_related_write_guard()` cannot simply be attached: it switches on
`TG_TABLE_NAME` with no `ELSE`, so an unknown table raises on every write. Write a **dedicated** function and trigger:

- Function body: `IF NOT public.beacon_post_write_allowed(NEW.beacon_id, 'no_key_update') THEN RAISE EXCEPTION
  'post_archived' USING ERRCODE = 'check_violation'; END IF;` — the existing m0271 predicate, which also takes the
  row lock that serialises with archiving. `isReadOnlyWriteError` matches the message text `post_archived`.
  Keep the `discussion_internal_fixture_allowed()` bypass that m0271 uses.
- Trigger: `BEFORE INSERT OR UPDATE OF beacon_id, fact_text, visibility, status, revision_seq, last_edited_at,
  other_editor_count, history_truncated ON public.beacon_fact_card`.
- **Never** list `pinned_by`, `last_edited_by` or `source_message_id`: they change through `ON DELETE SET NULL`
  when a user is erased or a message deleted, and that must keep working on an archived Post.
- No trigger on `beacon_fact_card_revision`: every revision insert shares a statement with a guarded fact write.
- Reading is unaffected, so copy-out from an archived Post still works.

### 4.6 Constants

- `BeaconRoomSemanticMarker.factsBrought = 20` in **both** `beacon_room_consts.dart` files.
- Activity events: reuse `factPinned` (type 2).

## 5. Server

All work stays in the existing fact stack: `BeaconFactCardCase`, `BeaconFactCardRepositoryPort`,
`BeaconFactCardRepository`, `MutationFactCard`, `query_fact_card.dart`. Two exceptions: the publish-time announce helper lives in `beacon_repository.dart` (§5.5), and the Posts unread SQL changes (§5.1 item 7). Follow the `clean-architecture` skill.

### 5.0 Prerequisites (block P; ship before any copy code)

1. **History scoping (X10).** In `BeaconFactCardRepository.history`, join
   `beacon_fact_card f ON f.id = $factCardId AND f.beacon_id = $beaconId`. Return "fact is in this beacon" as a
   **separate column** of the same statement (an empty page past the cursor end must not look like "not found");
   false → `IdNotFoundException`. Pass `beaconId` down from the use case.
2. **Attachment validation (X11).** In `BeaconFactCardCase.correct`, match each client attachment **by its `id`**
   against the attachments of **every revision of this fact** (one SELECT scoped by `fact_card_id` and `beacon_id`;
   `imageId` is empty for file attachments and for images whose row is gone, so it cannot be the key, and "Save mine"
   after a conflict resends entries from an older revision). For a match, store the server's object with only
   `position` taken from the client's order. An unmatched entry must be `kind = image` with an image row owned by the actor. At most `kMaxRoomMessageAttachments`. Anything
   else → `BeaconCreateException`. Revisions stored before this fix may hold forged ids; accepted (image ids are
   unguessable UUIDs), no audit. `beacon_fact_card_case_edit_rt_pg_test.dart` asserts an exact statement count and needs a new number
   (the history test stays at 2 statements).
3. **Access function (§4.4)** and the rewrite of `loadRoomAccess`.

### 5.1 Facts on Posts

In `BeaconFactCardCase`:

1. `_ensureWritableRoomAccess`: delete the `BeaconKindPolicy.requireRequest` call and the nullable
   `_beaconRepository` lookup. This is the only kind guard on a fact path; none of the `_requireRequest` calls in
   `beacon_room_case.dart` concerns facts. The existing test `request_only_guards_test.dart` asserts the Post
   rejection and must change.
2. Use the extended `loadRoomAccess` result: reject when `!canUseRoom`, when the lifecycle blocks writes, and when
   `isExpiredPost` (throw `kRoomReadOnlyException`).
3. **R5:** `pin`, `correct`, `restore`, `setVisibility` and `uploadAttachment` also reject when `isDraft`.
   `remove` does **not** use this guard on a draft: draft → the actor must be the author → hard-delete path
   (§5.4), for copied and for older ordinary facts alike; otherwise the normal guard.
4. `pin`: on a Post, force `visibility = room` whatever the client sent. `setVisibility`: on a Post, throw `BeaconNotRequestException`.
5. Keep the `BeaconHierarchyRepositoryPort` as a field (the field and the wrap around copy ship in **block A**; block B wraps the other writes) (today the constructor discards it) and wrap pin, correct,
   restore, setVisibility, remove and copy in its `translateRoomWriteError`, so a write that loses a race with
   archiving surfaces as `kRoomReadOnlyException`.
6. **R3:** `BeaconPromotionEligibilityPolicy.isEligible` gets an `allowLinkedFact` parameter. Pass `true` only from
   `_loadOwnBudSource` (the Post path); `_loadEligibleSourceFacts` (the Request path) stays strict. Test both.
7. **Posts list (X15):** `CREATE OR REPLACE` `post_my_posts` (m0306) so messages with `semantic_marker IN (2, 3, 10, 11, 20)`
   are skipped when choosing the latest message and when counting unread. Add a test: pinning a fact in a Post
   changes neither its excerpt, nor `last_message_is_root`, nor its unread count. Apply the same marker filter
   (`AND (m.semantic_marker IS NULL OR m.semantic_marker NOT IN (2, 3, 10, 11, 20))`) to `postUnreadMessageSql` in
   `S/data/database/sql/post_unread_sql.dart`, which feeds the Field unread flag and the pinned-item projection;
   extend the test to the Field flag.

`list` and `history` gain the block rule through §4.4; no other change.

### 5.2 Copy: two phases

Blob duplication is slow and must never run inside a transaction that holds the hierarchy or Post lock.

```dart
class PreparedFactCopy {
  String originFactCardId; int originRevisionSeq; int originBeaconKind;
  String factText; String attachmentsJson;   // already points at the new blobs
  List<String> newImageIds;                  // for compensation and hash tasks
}
```

**`prepareCopies({sourceFactCardIds, actorUserId, destinationBeaconId?, requiredSourceBeaconId?, skipUnavailable})`** (use case):

- `destinationBeaconId` is null for fork and bud (the destination does not exist yet); the two destination checks below are then skipped.
- `requiredSourceBeaconId` is the fork source or the Post for fork and bud; null for a single copy.

1. Precondition: the caller has already run the destination check and, for `BeaconFactCardCopy`, the copy rate limit (order in §5.4). `prepareCopies` is a public method of `BeaconFactCardCase`, injected into `BeaconCase` and `BeaconChildCreateCase`.
2. De-duplicate the ids. Load each source fact with beacon id, status, visibility, head `revision_seq`, head text, head attachments (one SELECT).
3. A fact is unavailable when it is missing, removed (`status = 2`), not in `requiredSourceBeaconId`, lives in
   `destinationBeaconId`, or fails the §4.4 rule.
   `skipUnavailable = false` → throw `FactCopySourceUnavailableException`, the **same** exception for every cause.
   `skipUnavailable = true` (fork, bud) → drop it silently.
4. With a destination: skip a fact that already has a live copy there; report it as `alreadyThere` with the existing id. Only reached after the destination check passed; no blob work is done for it.
5. Attachments (R2): keep only entries with `kind = image` and a syntactically valid `imageId`. `ImageRepositoryPort` has no existence
   check and `get` throws an untyped `StateError` on a missing row, so the source-load SELECT of step 2 returns, per
   attachment, whether `public.image` has the row; no row → drop that attachment. A storage failure in `get` for
   an existing row is **not** treated as missing: it goes to step 9.
6. For each kept image: `get` → `put(authorId: actor)`. New attachment JSON: new `id` (`generateId('A')`), new
   `imageId`, `imageAuthorId = actor`, other fields kept.
7. Daily upload cap (`RateLimitedException` from `put`): `skipUnavailable = false` → compensate and rethrow.
   `skipUnavailable = true` → compensate **that fact's** blobs, drop the fact, and stop copying images for the rest of
   the call (later facts with images are dropped too; text-only facts continue).
8. Limits: more than 20 ids → `BeaconCreateException` in every mode. The 41st image: `skipUnavailable = false` → `BeaconCreateException`; `true` → drop that fact and later facts with images.
9. On any other exception, `compensateOrphanedUpload` every blob created so far, then rethrow.

Returns `({List<PreparedFactCopy> prepared, Map<String, String> alreadyThere})`; the map is source fact id → existing copy id.

**`insertPreparedCopies({destinationBeaconId, actorUserId, prepared})`** (repository):

1. Runs inside `withMutatingUser(actorUserId, …)`. In fork and bud it must **join the ambient transaction**; that
   works only for the same actor (`tentura_db.dart` throws otherwise).
2. `SELECT status, kind, post_root_message_id FROM beacon WHERE id = $dest FOR NO KEY UPDATE`. No row, or a deleted
   beacon → `UnauthorizedException` (the same one as §5.3). Derive `announce = NOT is_draft` from this row, not
   from the earlier check.
3. Insert facts (`visibility = 1`, `pinned_by = actor`, `source_message_id = NULL`, origin columns) with
   `ON CONFLICT (beacon_id, origin_fact_card_id) WHERE origin_fact_card_id IS NOT NULL AND status IN (0, 1) DO NOTHING RETURNING id`
   (a conflict target cannot name an index), and revision 1 (`kind = 4`) inserted from that `RETURNING`.
4. When `announce`: one chat line (marker 20) built from the rows **actually inserted**, and one `factPinned`
   event per inserted fact (visibility `room`, `source_message_id` = the line's id, as `pinFact` does); event `diff` = `{factCardId, factText}`, also as `pinFact`. The line's `author_id` is the actor.
   Zero inserted rows → no line, no event.
5. For each copy that was not inserted, read the winning live copy's id in a **separate statement after** the
   insert (inside the insert statement the concurrent row is invisible). No winner found (it was unpinned meanwhile) → `FactCopySourceUnavailableException`.
6. The use case wraps the call in `translateRoomWriteError`.
7. Return per prepared copy: the new id, or the winner's id.

After the transaction: the use case compensates the blobs of every copy that was not inserted (race lost,
or the transaction threw), and schedules `TaskCalculateImageHashDetails` for the inserted ones (after commit,
as `_scheduleHashTaskNonFatal` does).

Chat line payload: `{"factCardIds": [...], "count": n, "originBeaconKind": 0|1|null, "factText": "<first 160 chars, only when count = 1>"}`.
`originBeaconKind` is null when the facts came from both kinds.

### 5.3 Destination check

`_ensureCopyDestination(beaconId, actor)` from the extended `loadRoomAccess`:

| Destination | Rule |
|---|---|
| Draft (`isDraft`) | the actor is the author |
| Published | `canUseRoom`, lifecycle allows writes, not an expired Post |

Errors: "not found", "another user's draft" and "not a member" all throw the **same** `UnauthorizedException`,
so beacon ids cannot be probed. `kRoomReadOnlyException` is thrown only after membership passed.
**Blocks A and B refuse every `isDraft` destination with the same `UnauthorizedException`; block C lifts this.
Block A also refuses `kind = post` the same way; block B lifts that.** `BeaconFactCopyDestinations` applies the same block gates.

### 5.4 Entry points

| API (V2 GraphQL) | Behaviour |
|---|---|
| `BeaconFactCardCopy(sourceFactCardId, destinationBeaconId)` → `{factCardId, outcome}` | Order: (1) `_ensureCopyDestination`; (2) copy rate limit; (3) `prepareCopies` (`skipUnavailable = false`); (4) `insertPreparedCopies`. A destination failure is thrown **before the source is loaded**, so a non-member never learns whether a destination holds a copy. `outcome`: `created` / `alreadyThere`. Rate limit: `FACT_COPY_RATE_MAX` (default 60) `kind = 4` revisions by the actor per `factEditRateWindow`; over it → `BeaconFactCardRateLimitedException`. Fork and bud are not checked against it, but their `kind = 4` revisions count toward the window. |
| `beaconFork(..., factIds)` | See §5.6. |
| bud mutation `(..., factIds)` | See §5.7. |
| `BeaconFactCardOrigin(beaconId, factCardId)` → `{available, beaconId, factCardId, beaconKind, changedSinceCopy, canSeeCopiedRevision, copiedRevisionSeq}` | The fact must belong to `beaconId` and the caller must pass the §4.4 rule for it. Then resolve the origin with the same rule. Origin missing, removed or unreadable → only `{available: false}`. `canSeeCopiedRevision = can_use_room` on the source. One hop. Fact not in `beaconId`, or the caller fails §4.4 for it → `FactCopySourceUnavailableException`. `changedSinceCopy = source.revision_seq > origin_revision_seq`. `copiedRevisionSeq` is null unless `canSeeCopiedRevision`. |
| `BeaconFactCopyDestinations(sourceFactCardId)` → list | Authorise the source first (`FactCopySourceUnavailableException`). Then the candidate set — beacons the caller authored, stewards, or participates in with `room_access = 3` — filtered by §5.3, excluding the source's beacon (block A: Requests only). Fields: `id, kind, title, isDraft, expiresAt`. A Post has no title: use the root-message excerpt (`postRootExcerpts`), or the draft's description excerpt; it may be empty. Order by `beacon.last_activity_at DESC`, limit 100. |
| `BeaconFactCardSave(beaconId, factCardId)` / `BeaconFactCardUnsave(factCardId)` | Save: the fact must belong to `beaconId` and pass the §4.4 rule (`FactCopySourceUnavailableException` otherwise); fewer than 200 rows. A removed fact is refused like an unreadable one. At 200 rows → new `SavedFactLimitException`. Both idempotent. |
| `BeaconFactCardSavedList` → list | One query, ordered by `created_at DESC`. Compute `beacon_fact_access` **once per distinct beacon** (not per row), then join. Readable rows: `factCardId, beaconId, beaconKind, factText, attachmentsJson`. Every other row (unreadable, removed, dangling id): `factCardId, available: false` and nothing else. |

Changes to existing code:

- `listForBeacon` returns `originBeaconKind` and `savedByMe` (LEFT JOIN `user_saved_fact` on the viewer). It never returns `origin_fact_card_id`.
- `history`: besides §5.0, exclude the type-2 (`factPinned`) event when the fact has an origin; the `kind = 4` revision row tells that story.
- `_runEdit`: add `AND r.kind <> 4` to the `rate_ok` count.
- `remove` on a draft (guard: §5.1 item 3): delete the fact row; no line, no event. Delete image blobs **only when the fact has an origin** (an ordinary fact pinned from a message shares its image ids with that message), using `_imageObjectGc.enqueue` + `deleteOwnedRow` as the draft branch of `deleteById` does.
- `BeaconCase.deleteById`, draft branch: also delete the blobs of the draft's copied facts.
- `S/data/repository/coordination_item_repository.dart` `_previewKindForSemanticMarker`: add marker 20 (it **throws** on an unknown marker and would break the Requests list). Add the preview kind to `S/domain/entity/beacon_thread_record.dart`. The preview's `factTitle` comes from `linked_fact_card_id` or `system_payload->>'factText'`, so it is null for a grouped line (`count > 1`); the client must render that case from `count`. Add `factCount` (int, nullable) to `ThreadMessagePreviewRecord`, filled from `(lm.system_payload->>'count')::int` for marker 20, to the GraphQL preview type and to the client `request_thread.dart` entity; add the new kind to `_isFactKind`.
- `S/data/repository/people_list_meta_sql.dart`: markers 1, 2, 3 are excluded from "last spoke"; add marker 20 to that exclusion.
- `S/data/repository/room_message_snapshot_lookup.dart`: marker 20 falls back to refetch; that is intended.

### 5.5 Announcing at publish

Facts copied into a draft are announced once, when the draft becomes visible:

- **Requests:** one repository helper in `S/data/repository/beacon_repository.dart`, called from `publishDraft`
  and `publishChildDraft` (the only draft → open writers) **only in the branch that flips draft → open**,
  immediately after `_insertBeaconPublishedEvent`. Both methods return early for a non-draft, and
  `publishChildDraft` also runs for buds whose child is created already open; the helper must not run there.
  Skip `kind = post`.
- **Posts:** publish is two-phase (`S/domain/use_case/post_case.dart`). Call the helper in phase 2, after
  `setPostRootMessage`, so the line follows the root message.

The helper writes one marker-20 line and the `factPinned` events for the beacon's live facts that have an origin. The line's `author_id` is the publishing actor; payload as §5.2.

### 5.6 Fork

- `BeaconCase.fork` gains `factIds`. Facts must belong to the fork source; others are skipped (R1).
- Prepare before creating the draft (`destinationBeaconId = null`, `requiredSourceBeaconId = source`).
- Today the transaction is skipped when `!copyPlan || plan == null || attention == null`. New condition: enter
  `attention.runAction` when `attention != null && ((copyPlan && plan != null) || prepared.isNotEmpty)`.
  Insert inside it. The draft gets no line (§5.2 insert step 2).
- When `attention == null` (test wiring) and copies were prepared: compensate their blobs and create the draft without facts.
- On any throw, compensate the prepared blobs together with the fork's own image compensation.
- The mutation's return type does not change. The client compares the draft's fact list with its selection to report skipped facts.

### 5.7 Budding

The mutation is `beaconBudFromPost` (`mutation_post_bud.dart`) → `PostBudCase.budFromPost` (`post_bud_case.dart`), which builds `budInput` and calls `BeaconChildCreateCase.createChildUnderPost`. All three gain `factIds`:

1. Put `factIds` (de-duplicated, sorted) into `budInput` — and so into the `bud:` hash — **only when non-empty**, so commands recorded before deploy still match.
2. Before prepare, do an unlocked `findCommand`. A hit → skip prepare entirely; the locked replay path returns the stored result as today.
3. Prepare (`skipUnavailable = true`, `destinationBeaconId = null`, `requiredSourceBeaconId = postId`) **before** `_attention.runAction`.
4. Inside the action, after `_publishChildInTransaction`: `insertPreparedCopies` into the child. The child is live, so the line is written. Bud does not report skipped facts to the client.
5. Wrap `runAction` in try/catch: on any throw, on `_PromotionRaceLost`, and on a `replayed` outcome, compensate all prepared blobs.

Lock order stays global → Post → child; the copy insert locks only the child row.

### 5.8 Concurrency and failure

| Case | Outcome |
|---|---|
| Retry, double tap, two members copying the same fact | The unique index lets one insert win; the other returns `alreadyThere` and its blobs are compensated. |
| Source edited while copying | The copy holds the head the prepare step read, and records that `seq`. |
| Source unpinned or deleted after the copy | The copy is untouched. Its origin resolves to «not available». |
| Copier later loses access to the source | Same. |
| Source author deletes their account | Source images vanish; the copy keeps its own blobs. |
| **Copier** deletes their account | The copy's images vanish (`deleteAllOf`); its text stays. |
| Destination closes between check and insert | `kRoomReadOnlyException`; blobs compensated. |
| Draft is published between check and insert | The locked row says "published", so the line is written. |
| Bud retry | No second copy, no second blob set. |
| Daily upload cap hit during fork or bud | That fact and later facts with images are skipped; the fork or bud succeeds. |
| Destination deleted between check and insert | `UnauthorizedException`; blobs compensated. |
| User who pinned a fact in an archived Post is erased | Works: the guard ignores `pinned_by` / `last_edited_by`. |
| Copy fails after blobs were written | Blobs compensated; daily quota is not refunded. |

### 5.9 Realtime

`beacon_fact_card_notify` fires on insert and already routes discussion-only facts to room recipients.
The marker-20 line uses the normal room message path. Saved facts need no realtime.

### 5.10 API plumbing (easy to forget)

- `S/api/controllers/graphql/custom_types.dart` (`BeaconFactCardRow` fields and the new result types),
  `_queries_all.dart`, `_mutations_all.dart`.
- `S/domain/exception_codes.dart`: codes for `FactCopySourceUnavailableException` and the saved-fact limit, plus the client mapping.
- `C/data/gql/schema.graphql`, new `.graphql` operation files, a `build_runner` run.

## 6. Client

Follow the `material-3-flutter` skill and `.cursor/rules/terminology.mdc`. Extend the existing widgets; add no
parallel fact card, sheet or picker. Strings below are EN drafts; add RU in the ARB files.

### 6.1 Fact card and actions sheet

`BeaconFactCard` gets `int? originBeaconKind` and `bool savedByMe`.

```
Fact actions                          origin line under FactProvenanceLine
────────────────────────────────      ────────────────────────────────
 ✎ Edit                               📌 Key is under the mat, blue door
 🌐 Make public   (Request only)         Bob · edited · 2h
 ↺ History                               ↗ Brought from another Request
 ❝ Quote in chat
 ☆ Save to my facts / ★ Remove from my facts
 ↗ Use in another Request or Post
 💬 Jump to source message
 ⧉ Copy text
 📌 Unpin
```

- `showFactActionsHostSheet` gets `onSave`, `onUseElsewhere`, `isPost`. Save and Use are shown to every reader (not gated by `canMutate`). Visibility tiles are hidden when `isPost`.
- New widget `FactOriginLine` (in `beacon_threads/ui/widget/`), shown when `originBeaconKind != null` in: the actions sheet header, `beacon_view/…/beacon_pinned_facts_sheet.dart`, the Post info sheet list.
- Tap → `BeaconFactCardOrigin`. Not available → snackbar «The original isn't available to you». Available → navigate to the source episode and focus the fact (reuse `pendingFactsFocusFactId` in `RoomCubit`; for a non-member of a Request open its facts sheet).
  `pendingFactsFocusFactId` is set today only inside `RoomCubit` after a pin: add a `focus_fact` route query param on the Request and Post room routes; the room cubit sets `pendingFactsFocusFactId` after its first fact load.
- On arrival with `changedSinceCopy`: a note «Changed since it was copied», rendered in the actions sheet under `FactOriginLine`; with `canSeeCopiedRevision` also «See the copied version», which opens `showFactHistorySheet` with a new optional `highlightSeq`. History pages hold 50 entries, newest first: load pages until the revision appears, at most 10 pages; beyond that open the sheet at the top without a highlight.

### 6.2 Destination picker (push)

New `fact_copy_destination_sheet.dart`, opened by «Use in another Request or Post».

```
Use in another Request or Post
────────────────────────────────
 ❝ Key is under the mat ❞   🖼 1
 🔒 It will be visible in that discussion only.

 🔍 Search                      (when more than 5 rows)
 ── Open ──────────────────────
 ▢ Garden day, autumn
 ◎ Post: Who has a ladder?  3h left
 ── Your drafts ───────────────
 ✎ Tool shed rota (draft)
 ✎ Untitled Post (draft)
────────────────────────────────
 ✓ Copied to Garden day   [Open]
```

Tap copies at once. `alreadyThere` → snackbar «Already there [Open]» (known only after the tap). Empty list → «You have no open Request or Post to copy into».

Copy failures (here and in §6.3) each map to a snackbar: source unavailable → «This fact is no longer available»;
`UnauthorizedException` → «You can't add facts there»; read-only, rate limit and daily upload cap → the existing
strings for those errors. In §6.3 a saved row that fails as unavailable is re-rendered as «No longer available».

In block A Posts are refused, so the action is titled «Use in another Request»; block B renames it to «Use in another Request or Post».

### 6.3 Fact picker with «Saved» tab (pull)

Extend `FactPickerSheet` with `TenturaUnderlineTabs`.

```
Fact                              ✕
────────────────────────────────
 [ In this Request ]  [ ★ Saved ]
 🔍 Search
 ★ Key is under the mat, blue…  ⋮
 ★ Shed code 4471        🖼 1   ⋮
 ☆ No longer available          ✕
```

- Tap a saved fact that lives in this episode → quote it (existing behaviour).
- Tap a saved fact from elsewhere → `BeaconFactCardCopy` into this episode → reload facts → set the returned fact as the pending quoted fact. `alreadyThere` behaves the same.
- `⋮` → «Remove from saved». Unavailable rows only offer remove.
- The tab is hidden when the room is read-only.

### 6.4 Fork and bud checklists

```
Create from this Request              Оформить запрос (from a Post)
────────────────────────────────      ────────────────────────────────
 ☑ Copy the plan (5 steps)             Title  [ Fix the north fence ]
                                       Invite [ Anna ✕ ] [ Boris ✕ ]
 Facts to bring        Select all
 ☐ Key is under the mat     🔒         Facts to bring        Select all
 ☐ Bring gloves                        ☐ Meet at the north gate
 ☐ Shed code 4471           🔒         ☐ Bring gloves
 🔒 = discussion-only in the original
          [ Cancel ] [ Continue ]                [ Cancel ] [ Create ]
```

- One shared `FactsToBringChecklist` widget fed by the existing fact list query for the source. Hidden when the source has no readable facts. At most 20 ticks. «Select all» ticks the first 20 and says so when there are more.
- **Fork is lazy on the client.** The editor opens on a local copy; the server fork runs at the first edit or autosave
  (`C/features/beacon/ui/util/beacon_lineage_overflow_actions.dart`, `beacon_create_cubit.dart`). Therefore:
  - today the fork action shows `showPlanCopySheet` only when the source has plan steps (`beacon_lineage_overflow_actions.dart`); **extend that sheet** with the checklist and show it when the source has a plan **or** at least one readable fact (no plan → the plan row is absent);
  - carry the ticked ids in a new `fork_facts` query param (beside `fork_from`, `fork_plan`) and in the create cubit's state;
  - pass them to `beaconFork` when the cubit performs the fork.

### 6.5 Draft create screen

```
 Facts you're bringing (2)
  📌 Key is under the mat      ✕
  📌 Bring gloves              ✕
```

- Before the server fork has run there is no draft id: render the section from the local `fork_facts` selection; `✕` edits the selection.
- After the fork (and for any draft that received facts by push): render from the fact list query on the draft id; `✕` calls the remove mutation.
- After the fork, if fewer facts arrived than were ticked, show once «N facts could not be brought».
- No add control here.

### 6.6 Posts

- Post rooms hide facts through `RoomCapabilities.post()` (`facts: false`, `C/features/beacon_threads/domain/room_host.dart`). Set `facts: true`. The `_isPostRoom` branches in `beacon_room_body.dart` concern the root-message strip and stay as they are.
- The only `RoomFactAuthoring` implementation wraps `BeaconViewCubit` (`beacon_view/…/beacon_fact_composer_sheet.dart`), which a Post host lacks. Add a Post implementation over the room's own cubit; its form has no visibility choice.
- D5 on the client: when the room is a Post, hide the public / chat-only ribbon (`room_pinned_fact_visibility_mark.dart`) and all visibility wording; the picker's first tab reads «In this Post».
- R3 on the client: `RoomMessage.isPromotionEligible` (`C/domain/entity/room_message.dart`, used in `beacon_room_body.dart`) mirrors the server rule and would keep hiding the bud action on pinned messages. Give it the same `allowLinkedFact` switch; the Post room passes `true`.
- `post_info_sheet.dart`: a «Facts» section listing the Post's facts (reuse the fact row widget; tap opens the actions sheet). This is the Post's only fact list (R6).
- Archived Post: the list stays; actions are History, Save, Use in another, Copy text.

### 6.7 Chat line and history

- `room_message_tile.dart` + `ui/message/beacon_room_fact_messages.dart`: render marker 20. One fact: «Bob brought a fact from another Request» + quoted text; tap opens the fact. Several: «Bob brought 3 facts from another Request»; mixed kinds: «Bob brought 3 facts».
- `C/features/beacon_threads/domain/entity/request_thread.dart`: the preview kind for marker 20 (Requests list last-message line); add it to the `ThreadMessagePreviewKind.values` set there. For a grouped line the server sends no `factTitle`: render «brought N facts» from `count`.
- History: `_mapHistoryRow` in the client fact repository maps unknown kinds to "created". Add a sealed subclass for `kind = 4` in `C/domain/entity/beacon_fact_history_entry.dart`; `fact_history_sheet.dart` renders it as «Bob brought this here». For a copy, a footer row «Earlier history lives where this fact came from [Open]» uses the §6.1 origin tap.

## 7. Rollout (five blocks, never interleaved)

| Block | Migration | Contents | Acceptance scenarios |
|---|---|---|---|
| **P. Prerequisites** | §4.4 | §5.0: history scoping, attachment validation, access function + `loadRoomAccess` rewrite. Ships alone; fixes two live holes. | — |
| **A. Request → Request** | §4.1, §4.2 | §5.2, §5.3 (**published Request destinations only**), Copy / Origin / CopyDestinations, `originBeaconKind` in the list (not `savedByMe`), the history change of §5.4, keeping the hierarchy port as a field and wrapping copy in `translateRoomWriteError` (§5.1 item 5), rate-limit change, marker-20 touch points (preview switch and `factCount`, people list, consts), §5.10. Client §6.1 (without Save), §6.2 (without drafts and Posts), §6.7. | 1, 2, 3, 4, 5, 7 |
| **B. Facts on Posts** | §4.5, `post_my_posts` | All of §5.1, **including R5 and the draft `remove` path** (a pin into a half-published Post would otherwise precede its root message). Published Post destinations allowed (drafts still refused). Client §6.6; update `room_capabilities_test.dart`, which asserts a Post room never lists facts. All four copy directions through push. | 6 |
| **C. Drafts, fork, bud** | — | Draft destinations, `deleteById` blob cleanup, §5.5, §5.6, §5.7. Client §6.2 drafts group, §6.4, §6.5. ADR 0004 amendment (X5). | — |
| **D. Saved facts** | §4.3 | Save / Unsave / SavedList, `savedByMe`. Client Save action, §6.3. | — |

Each block is shippable with the earlier blocks in and the later ones absent. Between B and C a draft can hold
only pre-existing ordinary facts; `remove` already hard-deletes them.

Server beads of a block land before its client beads. Each block ends with the docs it changes:
`CONTEXT.md` (vocabulary: copy, origin, saved fact), `docs/features/beacon_room.md` § Fact visibility,
`docs/Tentura_current_status_quo.md`, and a new ADR recording D1–D20 and R1–R6.

## 8. Tests

| Layer | Must cover |
|---|---|
| Block P | History with a foreign `factCardId` → not found. `correct` with a foreign `imageId` refused. Access function: blocked Post member, **blocked admitted Request participant (→ false)**, deleted beacon, leaver (`room_access = 5`), draft author, stranger. Update the five fakes and `beacon_fact_room_access_test.dart` that build `BeaconFactRoomAccess`, and the edit statement-count pg test. A kept attachment round-trips through validation; a reordered one keeps the server object with the new position. |
| Postgres repository | `insertPreparedCopies`: rows, revision kind 4, origin columns; line and events from inserted rows only; none on a draft; unique-index race returns the winner; origin columns reject UPDATE; half-filled origin columns rejected by the CHECK; closed destination → read-only error; deleted destination → unauthorized. Post archive guard: a fact write on an archived Post raises `post_archived`; **erasing a user who pinned a fact in an archived Post succeeds**; deleting the source message succeeds. |
| Use case (fakes) | Destination errors identical for not-found / foreign draft / non-member; block A refuses a Post destination. Read matrix: request-visible × discussion-only × member / reader / stranger / blocked Post member. Destination matrix: member, non-member, read-only Request, expired Post (block B); own draft, another user's draft, open Post without root message (block C; refused in A and B). Destination failure is thrown before the source is loaded. One exception for missing / removed / unreadable source. Blob compensation on every failure path. Same-episode rejected. Dangling and non-image attachments dropped. |
| Use case | Post: pin forces `room`; `setVisibility` refused; expired refused. Draft: pin, edit, restore, visibility, upload refused; remove by the author hard-deletes and removes blobs; remove by anyone else refused. Posts list unchanged by fact lines (X15). `request_only_guards_test.dart` updated. Eligibility: fact-linked message accepted on the Post path, still refused on the Request path. Upload cap during fork or bud skips the fact. Fork with `factIds` and no plan runs in a transaction; unavailable fact skipped. Bud: replay copies nothing and creates no blob; old command without `factIds` still replays; fact-linked message accepted as source. |
| Use case | Publish announces once for standalone, child and Post drafts (Post line after the root message). `Origin`: `available: false` carries no other field. Saved list: unavailable rows carry no text; dangling id handled. Cap 200. |
| Use case / pg (new rules) | Copy rate limit and the `kind <> 4` exclusion from the edit limit. 20-fact and 40-image limits in both modes. Re-copy after unpin; `alreadyThere` does no blob work. History omits the type-2 event for a copy. `deleteById` on a draft removes copied-fact blobs; draft `remove` leaves an ordinary fact's shared blobs. Marker 20 in the preview switch (`factCount`) and in the people-list exclusion. `changedSinceCopy`, `canSeeCopiedRevision`, null `copiedRevisionSeq`. CopyDestinations contents, block gates and order. Save idempotency, removed fact refused, `savedByMe`. |
| Client widget | Actions sheet tiles per role and kind; destination picker states; Saved tab pick → quote; checklist and `fork_facts` carrier; marker-20 line and list preview; history kind 4. Narrow and wide layouts. |
| Web integration | Scenario 1 → 4 end to end: copy A → B, edit both, unpin the source, copy B → D, walk the origin links as a member and as an outsider. |

Run commands: `AGENTS.md` § Verify (wrap with `scripts/run_with_test_cleanup.sh`).

## 9. Still unverified

1. Whether a member may leave a Post after it is archived (a leaver cannot list or copy; members admitted at expiry keep access).
2. The realtime path for fact hints on Posts: the WebSocket entity-change handler and the client invalidation;
   `realtime_room_recipients` does not filter blocked Post members (existing behaviour).
3. Whether any room UI exists for drafts today (R5 assumes none).
4. Internals of the client widgets in §6.1–6.3, 6.5, 6.7 beyond their existence; Hasura metadata and DI wiring.
5. The cost of `beacon_fact_access` for a saved list spanning many beacons (§5.4 computes it once per beacon).
6. Whether fact lines bump `beacon.last_activity_at` and so reorder the Posts list.
7. The cost of `beacon_fact_access` over a large candidate set in `BeaconFactCopyDestinations`.
8. Whether `beacon_fact_card_list_pg_test.dart` asserts `loadRoomAccess` behaviour that the stricter rule changes.
9. All three reviews' findings were taken from the reviewers' reading of the code; each bead author must open the cited file before relying on it.

Checked and clear (second review): complaints and moderation read no facts; no push or attention exists for
fact events; neither facts nor room messages are search-indexed; there is no export path.
