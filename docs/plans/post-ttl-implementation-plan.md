# Post lifetime (≤ 72 h) and read-only archive — implementation plan

**Status:** rev 3 (2026-10-23). Rev 2 applies the Astra review (codex gpt-6-astra, high; 13
findings, §6). Rev 3 applies the round-2 review (independent Opus subagent standing in for Astra,
whose codex quota ran out; 6 findings, §7).
**Baseline:** `main` at `0275957bc` (latest migration `m0260`, client `7.49.0`,
`kDefaultMinClientVersion = '7.46.0'`).
**For:** an implementer (human or model) who follows units literally, test-first, one unit at a time.
Each unit lists its goal, files, the tests to write **first**, the steps, and "done when".

**Sources of truth (read before any unit):**
1. [`post-ttl-design.md`](post-ttl-design.md) rev 1.1 — owner decisions D1–D10 (in Russian). "D*N*" points there.
2. [`post-implementation-steps.md`](post-implementation-steps.md) **§0 (rules for every unit) applies
   verbatim**: conventions, one migration per unit, transactions, exceptions, policies, V2 mutation
   pattern, the Hasura two-test rule, client schema / design system / l10n / mocks, wrapped serial
   test runs (§0.2), definition of done (§0.3).

If a step contradicts the design, stop and report; do not guess. Line numbers are from 2026-10-23.
If a quoted line has drifted, search for the named symbol. If the symbol is gone, stop.

---

## 0. Deltas to the shared rules

- **Lock order** is unchanged (global hierarchy lock → Post advisory `4242` + row via
  `PostLockPort.lockForPostMutation` → child → invite rows → availability → trust pairs). Every new
  status-changing path takes the Post lock first and re-validates `status` / `expires_at` after it.
- **Time.** The server's truth is Postgres `now()` (transaction start). Dart guards compare with
  `DateTime.timestamp()`; pg tests make a Post expired by `UPDATE beacon SET expires_at = now() - interval '1 second'`,
  never by sleeping. The client uses its injectable `clock` (as `PostsCubit` does).
- **"Expired"** means `kind = 1 AND status = 0 AND expires_at <= now()` — an open row the sweeper
  has not closed yet. Every write guard treats it exactly like `status = 6`. One shared predicate:
  `BeaconPostLifetime` (unit S1) on the server, `Beacon.isPostArchivedAt(now)` / `PostSummary.isArchivedAt(now)`
  on the client (unit C0).
- **Write-guard model (two layers).**
  1. **Database (truth, race-free).** One SQL function `public.beacon_post_write_allowed(p_beacon text, p_lock text)`
     returns false for a Post that is closed (6), deleted, or `status = 0 AND expires_at <= now()`
     (true for Requests and for open, unexpired Posts). It reads the beacon row **with a row lock
     that conflicts with the closer's `FOR UPDATE`** (`PostLockRepository.lockForPostMutation`), so a
     write and a close serialize and the guard sees the committed state:
     - `beacon_room_message`: `FOR NO KEY UPDATE` — the same lock the existing AFTER INSERT
       `beacon_room_message_bump_activity` (m0209) already takes on the beacon row, only earlier in
       the statement; no new lock class.
     - `beacon_room_message_reaction`: `FOR NO KEY UPDATE` too — its bump trigger (m0254) upgrades
       to that lock anyway.
     - every other table: `FOR KEY SHARE`. This is a **new** lock for tables without a foreign key
       to `beacon` (attachment, `polling_act`, baton candidate); it conflicts with the closer's
       `FOR UPDATE`, so a blocked writer re-reads the committed row (READ COMMITTED) and is refused.
     Triggers are declared `BEFORE INSERT OR UPDATE OF <user-editable columns>` — **never** listing
     a foreign-key column that an `ON DELETE SET NULL` cascade nulls
     (`beacon_room_message.reply_to_message_id`, `beacon_room_message_attachment.image_id`
     `m0193.dart:~7613`, `beacon_room_baton.taker_id` `m0219.dart:~21`; S5a re-greps every FK with
     `SET NULL` / `CASCADE` into these tables). Cascades from account erasure and image deletion
     therefore never reach the guard. They are installed on: `beacon_room_message` (redefine the existing
     `beacon_room_message_lifecycle_write_guard`), `beacon_room_message_reaction`,
     `beacon_room_message_attachment`, `polling` / `polling_variant` / `polling_act` (room-backed
     polls; resolve the beacon through the poll's message), `beacon_room_baton`,
     `beacon_room_baton_candidate`, `vote_beacon` (Hasura lets role `user` insert/update it directly,
     `hasura/metadata.json:~1384-1422`). `polling` / `polling_variant` have no `beacon_id` and are
     inserted before their message, so they pass; the guarded message insert covers them.
     Exemptions: system / authorless messages and `discussion_internal_fixture_allowed()`. Deletes
     are not guarded. The guard raises `RAISE EXCEPTION 'post_archived' USING ERRCODE = 'check_violation'`
     (a distinct message: other CHECKs share the SQLSTATE).
     The existing `beacon_room_message_lifecycle_write_guard` gets the same `UPDATE OF` column list,
     which also fixes today's latent bug where deleting a replied-to message in a closed Request
     fails on the reply's SET NULL.
  2. **Domain (friendly errors).** Use cases check the same predicate up front and throw the
     exception that path already throws for a closed Post: room and baton writes keep today's
     `BeaconCreateException('Discussion is read-only …')` (`beacon_room_case.dart:405`,
     `room_baton_case.dart:44`); Post lifecycle, forward and invite paths use `PostNotOpenException`
     or their existing forward refusal. A DB refusal is mapped by the message `post_archived` /
     `discussion_read_only` only, never by SQLSTATE alone.
     Upload I/O happens **before** the transaction; when the guarded insert is then refused, the
     uploaded object is deleted (compensation).
  No **new** writer takes `lockForPostMutation` (its first step is the global hierarchy lock);
  baton and delete paths that already take it keep it. A writer must not touch
  `beacon_participant` after a guarded insert in the same transaction: that table's statement
  trigger takes the global hierarchy lock (`m0193.dart:~6976`) and would invert the order against
  the sweeper (hierarchy held, waiting on the beacon row).
- **Write-path matrix** (every user-reachable way to change a Post or its room; each row has a test):

| Path | Allowed in archive? | Guard | Unit |
|---|---|---|---|
| message create / edit, poll create, poll vote, reaction, attachment | no | DB trigger + domain | S5a, S5b |
| `roomMessageMarkSemanticDone` | Request-only today (`_requireRequest`, `beacon_room_case.dart:1442`) — stays refused for every Post | existing | S5b (negative test) |
| Baton create / update / respond / select / cancel | no | DB trigger + domain | S5a, S6 |
| `vote_beacon` (Hasura insert / upsert / update) | no | DB trigger | S5a |
| forward, invite create / accept / accept-as-existing, `openForwarding` | no | domain (under Post lock) | S7 |
| new-account signup through a Post invite (`UserRepository.createInvited`, `createInvitedWithCredential`) | no | `_requireInviteIssuerMayForward` (`user_repository.dart:~151-180`) | S7 |
| `beaconStageImage`, `beaconSetMedia` | no | domain | S7 |
| delete own message (incl. baton message) | **yes** | trigger exemption + domain | S8 |
| author deletes the Post (root) | **yes** | existing | S8 |
| leave / return | **yes** | domain | S8 |
| pin / unpin, mute, archive (`beacon_pinned`, `beacon_archived`) | **yes** (personal) | none | — |
| bud a Request | **yes** (D1) | domain | S11 |
| shorten / close now | open only, author only | domain (under Post lock) | S10 |

- **Close reasons.** `BeaconLifecycleChangeReason` (`consts/beacon_activity_event_consts.dart:47-62`)
  gains `postExpired` and `postClosedByAuthor`; budding keeps `directClose`. The Post room's
  closed notice (system kind `postClosed = 5`) gains a `reason` key in `system_payload`:
  `'budded' | 'expired' | 'closedByAuthor'`. A payload without `reason` means `'budded'` (existing rows).
- **No feature gate.** There are no legacy clients (web-only, no users to keep compatible): server units may
  change behaviour on `main`; **do not deploy dev/prod between S1 and E1**. Unit E1 raises
  `kDefaultMinClientVersion`.
- **No permanent Alloy gate tests.** Every test in this plan is behavioural; nothing pins counts,
  SHAs, plan text or migration numbers.
- **Exceptions.** New ones go to `domain/exception.dart` with codes appended to
  `BeaconExceptionCode` (next free wire code: read the enum, take max + 1). Mirror on the client next
  to the existing `PostNotOpenException` mirror.
- **Russian copy** (verbatim; English is a faithful translation):

| Key (suggested) | RU | Where |
|---|---|---|
| `postLifetimeLabel` | Сколько живёт пост | composer |
| `postLifetime6h` / `postLifetime24h` / `postLifetime3d` | 6 часов / 24 часа / 3 дня | composer segmented button |
| `postLifetimeHint` | Потом пост уйдёт в архив. Продлить нельзя, сократить можно. | composer |
| `postRemainingDays` | осталось {days} д | rows, header, info, forward |
| `postRemainingHours` | осталось {hours} ч | same |
| `postRemainingMinutes` | осталось {minutes} мин | same |
| `postArchivedMarker` | в архиве | rows, header, info (replaces «закрыт» for Posts) |
| `postsTabArchive` | Архив | «Разговоры» section (replaces «Затихли») |
| `postActionShorten` | Сократить срок | ⋮ (author, open) |
| `postShortenTitle` | Когда закрыть пост? | shorten sheet |
| `postShortenIn1h` / `postShortenIn6h` / `postShortenIn24h` | Через час / Через 6 часов / Через 24 часа | shorten sheet (only options earlier than the current end) |
| `postActionCloseNow` | Завершить сейчас | ⋮ (author, open), shorten sheet |
| `postCloseNowConfirmTitle` | Завершить пост? | confirm |
| `postCloseNowConfirmBody` | Пост уйдёт в архив, писать в него будет нельзя. Отменить это нельзя. | confirm |
| `roomPostExpiredNotice` | Срок поста истёк. Пост в архиве. | room notice, reason `expired` |
| `roomPostClosedByAuthorNotice` | Автор завершил пост. Пост в архиве. | room notice, reason `closedByAuthor` |
| `postArchivedComposerHint` | Пост в архиве — писать нельзя. Продолжить разговор можно в запросе. | read-only composer |
| `postExpiringPushTitle` | Пост скоро закроется | push / For You (author) |
| `postExpiringPushBody` | Ваш пост уйдёт в архив через 3 ч. Чтобы продолжить разговор, оформите запрос. | same |

`roomPostClosedNotice` («Пост закрыт. Разговор продолжается в запросе «{title}».») stays for `budded`.

---

## 1. Unit map (execution order)

| Unit | Title | Depends on |
|---|---|---|
| S1 | Schema: `expires_at`, `expiry_warning_eligible`, backfill (D7), publish sets +72 h | — |
| S2 | Hasura: `expires_at` readable by `user` | S1 |
| S3 | Publish with lifetime; `PostSummary.expiresAt` | S1 |
| S4 | `PostCloseOperation`: expire / closeByAuthor / reason payload | S1 |
| S5a | DB write guard: `beacon_post_write_allowed` + triggers | S1 |
| S5b | Domain room guards: messages, reactions, attachments, polls | S5a |
| S6 | Baton domain guards | S5a |
| S7 | Forward, invitation, `openForwarding`, media guards | S1 |
| S8 | Archive personal actions: leave / return / delete own message | S4, S5b |
| S9 | Expiry sweeper | S4 |
| S10 | `postShorten` / `postClose` mutations | S4 |
| S11 | Bud from an archived Post (D1) | S4 |
| S12 | Expiry warning to the author (D5) | S1 |
| S13 | Read projections: constellation feed + For You lifecycle predicate | S1, S12 |
| C0 | Client schema, entities, data layer, `PostExpiryClock` | S2, S3, S10, S12, S13 |
| C1 | «Разговоры»: Сейчас / Архив, remaining time | C0 |
| C2 | Composer lifetime picker | C0 |
| C3 | Post view: header, info sheet, shorten / close now | C0 |
| C4 | Archived room: expiry propagation, notices, read-only CTA, bud, personal actions | C0, S8, S11 |
| C5 | Forward screen remaining time | C0 |
| C6 | Constellation: expiry-based presence and fade | C0 |
| C7 | Expiry warning on the client | C0 |
| E1 | Ship: version, min client version, docs, dead code | all |

Every unit compiles and passes on its own: no unit deletes a symbol another unit still uses
(`PostsCubit.quietAfter`, `kConstellationPostActiveWindow` and the old ARB keys are deleted in E1 only).

---

## 2. Server

### S1 — Schema: `expires_at`, `expiry_warning_eligible`, backfill, publish sets +72 h

**Goal:** design §4.1, D7, D8. About 40 existing pg test files insert open Posts directly without
`expires_at`, so S1 installs a defaulting trigger together with the CHECK; nothing that creates an
open Post today breaks.

**Files**
- new migration `m0261.dart` (next free number), registered in `_migrations.dart`.
- `data/database/table/beacons.dart` (+ regenerate `tentura_db.g.dart`), server `Beacon` entity and
  its mapper (`expiresAt`).
- `lib/domain/entity/beacon_post_lifetime.dart` (root shared package, used by server and client):
  `abstract final class BeaconPostLifetime { static const max = Duration(hours: 72); static const warnBefore = Duration(hours: 3); static bool isExpired({required BeaconKind/int kind, required BeaconStatus status, required DateTime? expiresAt, required DateTime now}); }`
- `data/repository/beacon_repository.dart:832-874` (`publishDraft`): for `kind = post` set
  `expires_at = published_at + 72h` and `expiry_warning_eligible = true` in the same update
  (S3 makes the 72 h configurable). `createBeacon` (`:~236-258`) and direct test inserts are
  covered by the defaulting trigger below.
- test: `test/data/database/post_expires_at_migration_pg_test.dart`,
  `test/domain/entity/beacon_post_lifetime_test.dart`; extend
  `test/domain/use_case/post_case_publish_pg_test.dart`.

**Tests (write first, pg, REQUIRED mode, upgrade path from `0260`):**
- backfill: an open Post published 10 h ago gets `expires_at = published_at + 72h`; one published
  100 h ago gets `expires_at ≈ now() + 24h` (grace, D7); `published_at IS NULL` falls back to
  `created_at`; all backfilled open Posts get `expiry_warning_eligible = true`;
- draft Posts, closed Posts and every Request keep `expires_at IS NULL`;
- inserting an open Post without `expires_at` gets `coalesce(published_at, now()) + 72h` and
  `expiry_warning_eligible = true` from the defaulting trigger; so does a draft Post updated to
  open; an explicit `expires_at` is kept; a Request with non-null `expires_at` fails the CHECK;
- publishing a draft Post through `PostCase.publish` sets `expires_at = published_at + 72h` exactly
  and `expiry_warning_eligible = true`;
- `BeaconPostLifetime.isExpired` truth table: Request → false; draft → false; open + future → false;
  open + past/equal → true; closed → false (closed is not "expired", it is closed).

**Steps**
1. `ALTER TABLE public.beacon ADD COLUMN expires_at timestamptz, ADD COLUMN expiry_warning_eligible boolean NOT NULL DEFAULT false;`
2. Backfill: `UPDATE public.beacon SET expires_at = greatest(coalesce(published_at, created_at) + interval '72 hours', now() + interval '24 hours'), expiry_warning_eligible = true WHERE kind = 1 AND status = 0;`
3. `ADD CONSTRAINT beacon_post_expires_at_ck CHECK ((kind = 1 OR expires_at IS NULL) AND (kind <> 1 OR status <> 0 OR expires_at IS NOT NULL))`.
   **No** DB upper-bound check against `published_at + 72h`: grace rows exceed it, and Postgres
   re-checks constraints on every later update of those rows. The 72 h cap lives in S3/S10.
4. Defaulting trigger `beacon_post_expires_at_default` (`BEFORE INSERT OR UPDATE OF status ON public.beacon`):
   when `NEW.kind = 1 AND NEW.status = 0 AND NEW.expires_at IS NULL`, set
   `expires_at = coalesce(NEW.published_at, now()) + interval '72 hours'` and
   `expiry_warning_eligible = true`. Named so it sorts **before** any other BEFORE trigger on
   `beacon` that could read `expires_at`.
5. Partial index: `CREATE INDEX beacon_open_post_expires_at_idx ON public.beacon (expires_at) WHERE kind = 1 AND status = 0;`
6. Drift columns + entity field; publish path (above).

**Done when:** tests green; the whole server pg suite (`--tags pg --exclude-tags mr`) green.

### S2 — Hasura: `expires_at` readable by `user`

**Goal:** the client's `beacon_model.graphql` can fetch `expires_at`.

**Files:** `hasura/metadata.json` (beacon select permission columns for role `user`), tests per §0
Hasura two-test rule: `test/architecture/hasura_metadata_beacon_expires_at_test.dart` (JSON shape)
and `test/api/hasura_beacon_expires_at_pg_test.dart` (`IsolatedHasuraSession`, a Post member reads
`expires_at` of the Post; `assertMetadataConsistent()`).

**Done when:** both tests green.

### S3 — Publish with lifetime; `PostSummary.expiresAt`

**Goal:** D8, D9 (publish side).

**Files**
- `api/controllers/graphql/mutation/mutation_post.dart:79-129` (`postPublish`): new optional
  argument `lifetimeHours: Int` (default 72).
- `domain/use_case/post_case.dart:75-157` (`publish`) → `BeaconCase.publishDraft` →
  `BeaconRepository.publishDraft` (`data/repository/beacon_repository.dart:832-874`): the +72 h from S1
  becomes `+ lifetime`; `expiry_warning_eligible = lifetime > BeaconPostLifetime.warnBefore`
  (D5: «не слать, если до истечения при публикации < 3 ч»). The flag never changes afterwards.
- `PostLifetimeInvalidException` (`lifetimeHours` outside 1…72).
- `post_my_posts` (m0244; redefine in a new migration, copying the **latest** body and attributes per
  the §0 SQL-function rule) and `gqlTypePostSummary` (`api/controllers/graphql/custom_types.dart:1958`):
  add `expiresAt` (nullable DateTime) to the summary and to `postSummary(id)`.
- tests: `test/domain/use_case/post_publish_lifetime_pg_test.dart`,
  extend the existing `postPublish` mutation test.

**Tests (write first):**
- publish without `lifetimeHours` → `expires_at = published_at + 72h` exactly;
- `lifetimeHours: 6` → `+6h`, eligible true; `lifetimeHours: 3` → eligible false; `0`, `73`, `-1` → `PostLifetimeInvalidException`, the draft stays a draft;
- idempotent re-publish (`_publishedPostOrValidateDraft` returns early) does not move `expires_at`;
- `myPosts` / `postSummary` return `expiresAt`.

**Done when:** tests green; existing post publish tests green.

### S4 — `PostCloseOperation`: expire / closeByAuthor / reason payload

**Goal:** D10, design §4.5 (closing side).

**Files**
- `domain/use_case/post_close_operation.dart`: keep `closeForBud`; add
  `expire({required String postId})` (actor `null`, reason `postExpired`) and
  `closeByAuthor({required String postId, required String actorId})` (reason `postClosedByAuthor`).
  All three run inside the caller's unit after the caller took the Post lock and re-check
  `kind == post && status == open`.
- `consts/beacon_activity_event_consts.dart`: the two reasons.
- `BeaconRepositoryPort.postClosedMessage` / `beacon_repository.dart:608-624`: take a `reason` and
  optional `childBeaconId` / `title`; write `reason` into `system_payload`.
- `closeByAuthor` and `expire` also set `expires_at = least(expires_at, now())` so "when did it end"
  is readable from the row.
- test: `test/domain/use_case/post_close_operation_pg_test.dart` (extend if it exists).

**Tests (write first):**
- `expire` on an open Post: status 6, lifecycle event `diff.reason = postExpired`, actor null, one
  `postClosed` system message with `reason = expired` and no `childBeaconId`;
- `closeByAuthor`: same with `postClosedByAuthor` / `closedByAuthor`, `expires_at <= now()`;
- `closeForBud`: payload now has `reason = budded` plus the old keys;
- each on an already-closed Post → `PostNotOpenException`, no second notice (S11 changes this for
  `closeForBud` only);
- no `statusChanged` room line is written for Posts (existing `kind = 0` filter in
  `_insertStatusChangedRoomLine`).

**Done when:** tests green.

### S5a — DB write guard: `beacon_post_write_allowed` + triggers

**Goal:** §0 write-guard model, layer 1. Race-free: a write and a close serialize on the beacon row.

**Files**
- new migration: `public.beacon_post_write_allowed(p_beacon text, p_lock text)` (`p_lock` ∈
  `'no_key_update' | 'key_share'`; two `SELECT … FOR …` branches, no dynamic SQL), the redefinition of
  `beacon_room_message_lifecycle_write_guard()` (copy the **latest** body, `m0193.dart:1177-1203`,
  keep the existing `status IN (1, 2, 6)` rule for Requests and add the Post rule via the function
  with `'no_key_update'`; re-declare the trigger `UPDATE OF` user-editable columns), and new
  triggers with the lock strengths and `UPDATE OF` column lists of §0 on the tables listed there. Every new function gets a pg test that calls it (§0 rule). Read each table's
  definition first to find its path to `beacon_id` (polls and batons may hang off a message or have
  a nullable beacon; a poll / baton that is not room-backed is not guarded).
- cascade safety comes from the `UPDATE OF` column lists (§0); grep every FK into the guarded
  tables (`REFERENCES public.beacon_room_message`, `…_attachment`, `…_baton`, `public.image`,
  `public."user"`) and keep each `SET NULL` column out of the lists.
- tests: `test/data/database/post_write_guard_pg_test.dart`,
  `test/data/database/post_write_guard_race_pg_test.dart`,
  `test/api/hasura_vote_beacon_post_guard_pg_test.dart` (IsolatedHasuraSession, role `user`).

**Tests (write first, pg, REQUIRED mode):**
- for each guarded table: an authored INSERT (and UPDATE where the table allows it) into an
  expired-but-open Post and into a closed Post fails with `check_violation`; the same into an open,
  unexpired Post succeeds; Requests unchanged (closed Request message still refused by the old rule,
  a reaction on a closed Request still allowed if it is allowed today — assert today's behaviour);
- system messages still insert into a closed Post;
- deleting a message that has a reply from another member, in a closed Post and in a closed
  Request: the reply survives with its reply reference NULL; an ordinary UPDATE of that reply's body
  is still refused;
- **erasure:** `UserErasureCase` erases (a) a member with an image attachment in a closed Post,
  (b) a Post author whose own Post it deletes, with attachments in it, (c) a baton taker in a
  closed Post — all succeed; deleting an owned image used in a closed Post's attachment succeeds;
- **race:** connection A opens a transaction and takes `lockForPostMutation` + sets status 6 but does
  not commit; connection B inserts a message / reaction / attachment (blocks); A commits; B fails
  with `post_archived` and leaves no row. Detect that B is blocked by polling `pg_stat_activity` for
  B's pid with `wait_event_type = 'Lock'` (never query `pg_locks` unscoped — the migration advisory
  lock shows up there); template `post_lock_order_pg_test.dart`. No sleeps;
- Hasura as role `user`: `vote_beacon` insert and on-conflict update on an expired Post fail; on an
  open Post succeed; `session.assertMetadataConsistent()`.

**Done when:** tests green; existing room, poll, baton and vote pg tests green.

### S5b — Domain room guards: messages, reactions, attachments, polls

**Goal:** §0 write-guard model, layer 2 (typed errors), and upload compensation.

**Files**
- `domain/use_case/beacon_room_case.dart`: `_rejectOrdinaryUserWritesForLifecycle` (`:405`) and
  `_guardMessageMutation` (`:419`) load `kind`, `status`, `expires_at` (extend
  `_hierarchyRepository.loadBeaconStatus` or add `loadBeaconWriteState`) and also reject when
  `BeaconPostLifetime.isExpired`. Covers `createMessage` (`:658`), `createPoll` (`:2217`),
  `reactionToggle` (`:1723`), `addMessageAttachment` (`:1795`), `editMessage` (`:1902`).
  `deleteMessage` is S8's.
- `addMessageAttachment` and any message create with files: when the DB guard refuses the insert
  after the upload, delete the uploaded object (use the image/file repository's existing delete).
- `domain/use_case/polling_case.dart:64-84` (`_guardRoomBackedPollMutation`): same check.
- map a DB refusal with message `post_archived` / `discussion_read_only` (never by SQLSTATE alone)
  to today's read-only `BeaconCreateException` where it surfaces (race case).
- test: `test/domain/use_case/post_room_expiry_guard_pg_test.dart`.

**Tests (write first):** on an expired-but-open Post each of create message, edit, reaction toggle,
add attachment (the uploaded object is gone afterwards), create poll, vote → today's read-only
`BeaconCreateException`; a reaction with an invalid emoji on an open Post still gets its own error
(not mapped to read-only); on an open Post they succeed. `roomMessageMarkSemanticDone` is refused for an open, an
expired and a closed Post (Request-only, `_requireRequest` `:1442`), and works on an open Request
(positive control).

**Done when:** test green; existing `beacon_room_case` / polling tests green.

### S6 — Baton domain guards

**Goal:** design §3 (Baton frozen), typed errors on top of S5a.

**Files:** `domain/use_case/room_baton_case.dart` — `_rejectIfRoomNotWritable` (`:44`) also rejects
expired Posts; call it in `respond` (`:172`), `select` (`:232`) and `cancel` (`:394`) after their
existing Post lock (today they check only `baton.status`). Test:
`test/domain/use_case/room_baton_post_expiry_pg_test.dart`.

**Tests (write first):** create / update / respond / select / cancel on a closed Post and on an
expired-but-open Post → today's read-only `BeaconCreateException`; on an open Post → succeed; Requests unchanged.

**Done when:** test green; existing baton tests green.

### S7 — Forward, invitation, `openForwarding`, media guards

**Goal:** design §3 (no forward / invites in archive, including the author); §0 matrix rows.

**Files**
- `domain/use_case/forward_case.dart` (`_checkForward` `:431`, under the Post lock),
  `domain/use_case/invitation_case.dart` (`createForBeacon`, `_requireIssuerCanForward` `:134`,
  `_acceptBeaconInviteOnly` `:429`): reject expired Posts like closed ones (closed is already refused
  via `allowsForward`).
- `domain/use_case/beacon_case.dart:968-989` (`openForwarding`): also refuse an expired Post.
- new-account signup through a Post invite: `data/repository/user_repository.dart`
  `_requireInviteIssuerMayForward` (`:~151-180`, already under the Post lock), used by
  `createInvited` (`:~206-293`, via `AuthCase._createInvitedUser`) and `createInvitedWithCredential`
  (`:~380-470`, via `CredentialAuthCase`): refuse an expired Post before
  `_materializeBeaconInviteForward`.
- `beacon_case.dart:~595` (`beaconStageImage`) and `:~645` (`beaconSetMedia`): first check whether
  any client path uses them for Posts (Post images ride on the root message). If none does, refuse
  `kind = post` outright; otherwise refuse closed / expired Posts.
- test: `test/domain/use_case/post_expiry_forward_invite_pg_test.dart`.

**Tests (write first):** on an expired-but-open Post: author forward, member forward, invite create,
invite accept, accept-as-existing, new-account signup via both auth paths, `openForwarding`,
stage image, set media → refused, no edges / participants / users-in-Post / images created (a
signup with an expired invite must not leave a half-created account — assert whatever today's
closed-Post signup behaviour is, and match it); on an open Post forward / invite / `openForwarding` work.

**Done when:** test green; existing forward / invitation / media tests green.

### S8 — Archive personal actions

**Goal:** design §3: «Не интересно» / «Вернуть», delete own message, author deletes the Post — all
allowed in a closed or expired Post.

**Files**
- `domain/use_case/post_case.dart:203-232` (`_addresseeAction`): allow `status ∈ {open, closed}` for
  Posts (still refuse draft / deleted).
- `domain/use_case/beacon_room_case.dart:1815-1866` (`deleteMessage`): for a Post that is closed or
  expired, let the message's **author** delete their own non-root message, baton messages included
  (root keeps today's path: author deletes the whole Post). `deleteMessage` calls
  `_guardMessageMutation` (`:~1863`), which S5b taught to refuse expired Posts: skip that guard
  **only** for this case (Post, closed or expired, own non-root message). Other writes stay refused. Delete is a
  hard `DELETE` (`beacon_room_repository.dart:1151`); replies are updated by `ON DELETE SET NULL`,
  which S5a's referential-cleanup exemption allows.
- test: `test/domain/use_case/post_archive_personal_actions_pg_test.dart`.

**Tests (write first):** closed Post: member leaves → `room_access = left`, inbox status 2; returns
→ restored; member deletes own message that has another member's reply → gone, reply survives with a
NULL reference; member deletes own baton message → gone; member deletes someone else's → refused;
author deletes root → Post deleted (status 2); same set on an expired-but-open Post; Request rooms
unchanged (closed Request: delete still refused).

**Done when:** test green.

### S9 — Expiry sweeper

**Goal:** design §4.4.

**Files**
- `domain/use_case/post_expiry_sweep_case.dart`: `runDue()` selects up to 100 ids
  `kind = 1 AND status = 0 AND expires_at <= now()` ordered by `expires_at` (port method on the
  beacon repository), then per id: `_uow.run(actorUserId: null)` → `PostLockPort.lockForPostMutation`
  → re-read → if still open and expired, `PostCloseOperation.expire`. Errors are logged per row and
  do not stop the batch (template: `ClosureFinalizeSweepCase.run`, `closure_finalize_sweep_case.dart:34-56`).
- `domain/use_case/task_worker_case.dart`: register with a `_lastPostExpirySweep` throttle of 30 s
  (pattern `:315-321`).
- tests: `test/domain/use_case/post_expiry_sweep_pg_test.dart`.

**Tests (write first):** two expired open Posts + one future Post + one Request with a past `end_at`
→ `runDue` closes exactly the two (status 6, reason `postExpired`, one notice each); a second
`runDue` changes nothing; a Post shortened to the past between select and lock is closed once; a
Post budded-closed between select and lock is skipped without error.

**Done when:** test green; existing task-worker tests green.

### S10 — `postShorten` / `postClose` mutations

**Goal:** D9 (after publish), design §4.2.

**Files**
- `domain/use_case/post_case.dart`: `shorten({userId, beaconId, expiresAt})` and
  `close({userId, beaconId})`, both under `lockForPostMutation`, author-only, open and not expired.
  `shorten` requires `now() < expiresAt < current expires_at` and updates the column; `close` calls
  `PostCloseOperation.closeByAuthor`.
- `api/controllers/graphql/mutation/mutation_post.dart`: `postShorten(id, expiresAt)` and
  `postClose(id)` (pattern of `postLeave`), registered in `_mutations_all.dart`.
- `PostLifetimeExtendException` (new value ≥ current), reuse `PostLifetimeInvalidException` for
  `expiresAt <= now()`.
- tests: `test/domain/use_case/post_lifetime_change_pg_test.dart`, mutation test like
  `mutation_availability_test.dart`.

**Tests (write first):** author shortens 72 h → 6 h: column updated, status open; extend → refused,
column unchanged; non-author → refused; shorten on closed / expired → `PostNotOpenException`;
`postClose` → status 6 with reason `postClosedByAuthor`; second `postClose` → `PostNotOpenException`;
shortening leaves `expiry_warning_eligible` unchanged.

**Done when:** tests green.

### S11 — Bud from an archived Post (D1)

**Goal:** members may bud a Request from a closed or expired Post.

**Files**
- `domain/use_case/beacon_child_create_case.dart:598-614` (`_assertPostParentBudAllowed`): accept
  Post `status ∈ {open, closed}` (refuse draft / deleted). Membership check unchanged.
- `domain/use_case/post_bud_case.dart:261-268` + `post_close_operation.dart` (`closeForBud`): when
  the Post is already closed, skip the transition and the `postClosed` notice (the child-creation
  notice from `insertChildCreationNotice` is still written). When the Post is expired-but-open and
  `closePost = true`, close it with reason `budded` (directClose) as today.
- `BeaconRoomCase`/trigger: the child-creation notice is a system message, already exempt.
- test: `test/domain/use_case/post_bud_from_archive_pg_test.dart`.

**Tests (write first):** member buds from a closed Post (`closePost` true and false) → child created
under the Post, invitations created, one child-creation notice in the Post, Post stays status 6 with
its original close reason; buds from an expired-but-open Post with `closePost: true` → Post closed
with `reason = budded`; non-member → refused; deleted Post → refused.

**Done when:** test green; existing post-bud tests green.

### S12 — Expiry warning to the author (D5)

**Goal:** one author-only notice 3 h before expiry, for Posts whose lifetime at publication was
longer than 3 h (`expiry_warning_eligible`, S1/S3). Shortening does not change eligibility: a
shortened eligible Post is warned once, as soon as it is within 3 h.

**Files**
- `domain/attention/attention_models.dart`: `AttentionEventType.postExpiringSoon`,
  `NotificationKind.postExpiringSoon`; wire every switch the analyzer flags
  (`attention_policy.dart:98,181,239,305,396,501`, `beacon_notification_copy_builder.dart`,
  `beacon_notification_recipient_resolver.dart`, `notification_category.dart`) **and** the
  string-keyed maps the analyzer cannot see: grep the server and the client for `'deadlineReminder'`
  and add a `'postExpiringSoon'` entry next to each (client:
  `lib/domain/attention/attention_event_classification.dart:~224`; shared event contract in the root
  package if one lists event names).
- `domain/use_case/attention_intent_case.dart`: `postExpiringSoon(...)` modelled on `_deadlineIntent`
  (`:367-432`) but explicit about every Post fact the deadline intent leaves at its Request default
  (`AttentionDispatchIntent.beaconKind` defaults to Request, `attention_models.dart:~465`):
  `beaconKind: BeaconKind.post`, recipient = author only with the author relationship reason used by
  `postFirstResponse`, presentation key `post_expiring_soon`, the Post delivery category,
  `sourceEventKey = 'post_expiring:<postId>'`, collapse key none.
- `domain/use_case/post_expiry_warning_sweep_case.dart`: candidates
  `kind = 1 AND status = 0 AND expiry_warning_eligible AND expires_at > now() AND expires_at <= now() + interval '3 hours'`;
  per id `_attention.runAction(actorUserId: null)` → Post lock → re-check → `record(intent)`.
  Registered in `task_worker_case.dart` with a 1-minute throttle.
- tests: `test/domain/use_case/post_expiry_warning_sweep_pg_test.dart` with real
  `AttentionDispatchRepository` (pattern of `help_offer_obligation_settlement_pg_test.dart`).

**Tests (write first):**
- Post expiring in 2 h (eligible) → one occurrence for the author, none for members; second run →
  still one (dedupe);
- not eligible (published with 3 h) → none; closed → none; expiring in 4 h → none;
- eligible 72 h Post shortened to 2 h left → warned on the next run; shortened again after the
  warning → no second warning;
- the author's receipt as read through the receipt-feed projection the client uses has
  `beaconKind = 1`, event type `postExpiringSoon`, presentation key `post_expiring_soon`, and the
  outbox row for push has the Post id for navigation. C7 copies these literal values into its
  fixtures.

**Done when:** test green; existing attention policy tests green.

### S13 — Read projections: constellation feed + For You lifecycle predicate

**Goal:** design §3 last paragraph: expired / closed Posts leave the field (unless pinned) and
For You.

**Files**
- `data/repository/constellation_field_snapshot_reader.dart:327-370` (post feed SQL): replace the
  `last_activity_at > now() - interval '72 hours'` window with
  `(b.status = 0 AND b.expires_at > now()) OR pinned`, widen `b.status = 0` to `b.status IN (0, 6)`
  for the pinned branch only, and select `b.expires_at` and `b.status` into
  `ConstellationPostRecord`; expose both on the V2 constellation `posts` type.
- `data/repository/attention_dismissible_sql.dart`: new `postLifecycleExcluded(alias)` —
  a receipt whose beacon is a Post (`kind = 1`) is eligible only while `status = 0 AND expires_at > now()`.
  AND it into the shared kind-aware eligibility predicate (`relayShellExcluded`, `:~185`) that
  grouping, previews, counts, the dot and sweeps already share. **No exemption** for
  `postExpiringSoon`: after closure / expiry the warning goes too. Then grep every receipt query
  in `attention_repository.dart` (incl. `:~1196`, `:~1271`) and `attention_*_repository.dart` for
  places that do **not** use the shared predicate, and route them through it. History / archive
  reads (the Post room itself, «Разговоры») are not filtered.
- tests: extend the constellation field reader pg test and the attention receipt-feed / count pg
  tests.

**Tests (write first):** field: open Post with future expiry present with `expiresAt`; expired-but-
open absent; closed unpinned absent; closed pinned present with `status = 6`; old
`last_activity_at` + future `expires_at` → present. For You: the author has a `postExpiringSoon`
receipt and a member reply receipt on a Post → both grouped and counted (dot on) before expiry; after
`expires_at` passes (no sweep) → row, preview, count and dot gone; after the sweep closes it → still
gone; Request receipts unchanged.

**Done when:** tests green.

---

## 3. Client

All client units: design system only (`material-3-flutter` skill), l10n RU/EN from §0, never edit
generated files, wrapped `flutter test` per §0.2.

### C0 — Schema, entities, data layer

**Files**
- `lib/data/gql/schema.graphql` (fetch from the running server per §0, else hand-edit and say so):
  `v2_PostSummary.expiresAt`, `postPublish(lifetimeHours)`, `postShorten`, `postClose`,
  constellation post `expiresAt` / `status`, Hasura `beacon.expires_at`.
- `features/inbox/data/gql/post_summary_fields.graphql` (+ `expiresAt`),
  `features/inbox/domain/entity/post_summary.dart` (`DateTime? expiresAt`, `isArchivedAt(now)` =
  closed or `BeaconPostLifetime.isExpired`), `posts_repository.dart:36-54`.
- `lib/data/gql/beacon_model.graphql` + `lib/data/model/beacon_model.dart:70` +
  `lib/domain/entity/beacon.dart` (`expiresAt`, `isPostArchivedAt(now)`).
- `features/beacon/data/gql/post_publish.graphql` (`$lifetimeHours: Int`),
  `post_publish_repository.dart:24-62`, `PostPublishPort`/`PostPublishCase` (`lifetime` param).
- new `post_shorten.graphql`, `post_close.graphql` + repository/port/use-case methods next to
  `allowForwarding` in the post_view feature.
- constellation: `constellation_field_fetch.graphql:54-61`, `constellation_field_mapper.dart:50-60`,
  `ConstellationPost` (`expiresAt`, `status`).
- exception mirrors for `PostLifetimeInvalidException` / `PostLifetimeExtendException`.
- shared formatter `features/post_view/ui/post_remaining_label.dart`:
  `String postRemainingLabel(L10n, Duration)` (≥ 24 h → days rounded down, ≥ 1 h → hours, else
  minutes, min 1).
- `lib/ui/utils/post_expiry_clock.dart` (or the nearest shared ui utility folder): `PostExpiryClock`
  — given the injectable `clock` and a set of `DateTime` deadlines, emits a tick at the nearest
  future deadline and once per minute while any deadline is < 1 h away (countdown refresh); re-armed
  whenever the deadline set changes; also ticks on app resume (`AppLifecycleListener`). One instance
  per consumer, disposed with it. Consumers: C1, C3, C4, C6.

**Tests (write first):** `PostExpiryClock` with a fake clock/`fakeAsync`: ticks at the deadline,
re-arms after the set changes, minute ticks inside the last hour, ticks on resume, no timers after
dispose; mapper tests for each entity; `isArchivedAt` truth table;
`postRemainingLabel` boundaries (72 h → «осталось 3 д», 23 h 59 m → «осталось 23 ч», 59 m →
«осталось 59 мин», 10 s → «осталось 1 мин»); repository passes `lifetimeHours`.

### C1 — «Разговоры»: Сейчас / Архив

**Files:** `features/inbox/ui/bloc/posts_cubit.dart` (`_arrange` `:88-116`): pinned → `pinned`
(D4, any status); `!isArchivedAt(now)` → `active`; else → `archive` (rename `quiet` in
`posts_state.dart`). Keep today's sort (`lastActivityAt` desc; do not sort by `expiresAt` — anti-feed rule A5). Keep `quietAfter` in place (C3 still
reads it until it migrates; E1 deletes it). A `PostExpiryClock` over **all** listed open Posts'
`expiresAt` — pinned ones included — re-runs `_arrange` on each tick, so a Post moves to «Архив» and
countdowns refresh with no network event and no sweeper update; re-armed after every fetch.
`posts_tab_view.dart`: `postsTabArchive`.
`post_conversation_row.dart`: open → `postRemainingLabel`; archived → `postArchivedMarker` (also for
pinned archived rows); keep the relative age of the last activity.

**Tests (write first):** cubit with a fake clock: open/expired/closed/pinned-closed land in the
right lists; advancing the clock past `expiresAt` (no refetch) moves an unpinned Post to archive and
flips a pinned Post's row to the archived marker; row shows remaining / archived marker.

### C2 — Composer lifetime picker

**Files:** `features/beacon_create/ui/screen/post_create_screen.dart`: a `SegmentedButton` (6 ч / 24 ч
/ 3 дня, default 3 дня) with label and hint, placed directly above the «Можно пересылать» switch
(`:323-335`); `_send()` (`:169-185`) → `BeaconCreateCubit.publishPost` (`:1565`) passes
`lifetimeHours`.

**Tests (write first):** widget test: default 72 sent; choosing 6 h sends 6; the hint text is shown.

### C3 — Post view: header, info sheet, shorten / close now

**Files**
- `features/post_view/ui/screen/post_view_screen.dart`: `_Title` (`:276-342`) adds the remaining
  label or the archived marker to the members line; `_Overflow` (`:383-483`) for the author of an
  open, non-expired Post adds `shorten` and `closeNow` (new `PostAction` values); `_run` dispatch.
- shorten bottom sheet (pattern of `_MuteChoice` `:26-36`): only options strictly earlier than the
  current end, plus «Завершить сейчас»; close-now confirm dialog (pattern `_confirmDelete`).
- `features/post_view/ui/bloc/post_view_cubit.dart`: `shorten(Duration)`, `closeNow()`.
- `features/post_view/ui/widget/post_info_sheet.dart:175-186,268-279`: `_activityLine` → remaining
  label / archived marker; drop the `PostsCubit.quietAfter` reference.
- header and ⋮ re-evaluate on `PostExpiryClock` ticks for the open Post (countdown, actions vanish
  at expiry).

**Tests (write first):** author sees both actions on an open Post, a member does not, nobody sees
them on an archived Post or once the clock passes `expiresAt`; with 5 h left the sheet offers «Через час» only (6 h and 24 h hidden);
confirm → cubit calls `postClose`; header shows «осталось 5 ч».

### C4 — Archived room

**Files**
- **Expiry propagation.** `expiresAt` travels with status everywhere the room learns about its host:
  `RoomHost` / `ThreadHostCubit` state, `post_view_scope.dart:~55-75` (the `BlocListener` that
  today forwards only status changes — trigger on status **or** `expiresAt`), the room factories, and
  the rebuild predicates in `beacon_room_body.dart:~308`. A remote shorten (status still open) must
  reach an open room.
- **One writability rule.** A single `roomWritableAt(now)` (status allows writes **and** the Post is
  not expired) used by `room_state.dart:98` (`canWriteDiscussion`), by the `RoomCubit` command guard
  (`room_cubit.dart:~159`), and for clearing a started reply / closing an open message sheet when it
  flips to false. A `PostExpiryClock` on the Post's `expiresAt` flips it at expiry without a
  network event.
- `beacon_threads/ui/widget/beacon_hierarchy_notice.dart:50-59`: render the `postClosed` notice by
  payload `reason` (`budded` → existing copy with the child link; `expired` / `closedByAuthor` → new
  copy, no link); `room_message_hierarchy_payload.dart:31` parses `reason` (missing → `budded`).
- `beacon_room_body.dart:453-457`: an archived Post room shows `postArchivedComposerHint` plus an
  «Оформить запрос» button (when `kPostBuddingEnabled`), which opens the same flow as the ⋮ action.
- `post_view_screen.dart:403-404` (`canBud`): open **or** archived (not deleted).
- **Message menus in the archive.** Ordinary message sheet (`beacon_room_body.dart:754-760`): the
  bud action on an eligible own message no longer requires `canWrite` for Posts; delete-own is shown.
  Baton message menu (`beacon_room_body.dart:~1093`): delete-own is shown; respond / select / cancel
  stay hidden. Reply, react, edit stay hidden everywhere.
- personal actions (S8): «Не интересно» / «Вернуть» on archived Posts (`post_info_sheet.dart:246`,
  ⋮ `leave`).

**Tests (write first):** each notice reason renders its copy; archived room: hint + bud button, no
composer, no reactions; a remote `expiresAt` update (status still open) to the past closes the
composer and drops a started reply; the clock passing `expiresAt` does the same with no update;
ordinary sheet on own message → delete + bud, on another member's → neither; baton sheet on own
baton message → delete only, on another's → nothing; ⋮ «Оформить запрос» on an archived Post.

### C5 — Forward screen remaining time

**Files:** `features/forward/ui/widget/forward_recipient_picker.dart:676-693` — for Posts the
subtitle's lifecycle part becomes `postRemainingLabel` (D3). No blocking.

**Tests (write first):** forwarding a Post with 2 h left shows «осталось 2 ч»; Requests unchanged.

### C6 — Constellation: expiry-based presence and fade

**Files**
- `constellation/domain/constellation_anchor_composition.dart:185,254-275,332,343` and
  `constellation_visibility.dart:322-331,375-381`: a Post is active iff open and `expiresAt > asOf`;
  inactive + pinned + anchored → dormant (as today); else dropped. Stop using
  `kConstellationPostActiveWindow` (E1 deletes it).
- `constellation_post_fade.dart`: fade from remaining time — 1.0 while ≥ 24 h left, linear to
  `kConstellationPostFadeFloor` at 0 left.
- `constellation_cubit.dart:~656` recomposes with `state.loadedAt ?? field.loadedAt` as `asOf`;
  for Post presence and fade use the current `clock` time instead, and recompose on
  `PostExpiryClock` ticks over the field's Post `expiresAt` set (fade refresh in the last 24 h at
  the clock's minute ticks is enough).
- `constellation_cubit.dart:2722` (`postsForPerson`): keep `lastActivityAt` ordering.

**Tests (write first):** update the existing post projection / fade tests to the new rule:
`lastActivityAt` 100 h ago but `expiresAt` in 10 h → active, fade ≈ 0.25 + 0.75·10/24; expired
pinned anchored → dormant; expired unpinned → absent; with no refetch, advancing the clock past a
Post's `expiresAt` removes it from the composed scene.

### C7 — Expiry warning on the client

**Files:** notification kind mapping (wherever `deadlineReminder` maps on the client: push tap →
route, For You card variant), `features/inbox/ui/widget/post_attention_row.dart`
(`postAttentionVariantOf`): variant `expiringSoon` with `postExpiringPushTitle` / body and an
«Оформить запрос» action opening the bud flow.

Add `'postExpiringSoon'` to `attention_event_classification.dart` and every other string-keyed
map that lists `'deadlineReminder'`.

**Tests (write first):** fixtures use the literal receipt / push values asserted by S12's test
(`beaconKind = 1`, `postExpiringSoon`, `post_expiring_soon`, the Post id) — not invented ones; the
receipt renders the variant with the action; the push payload routes to the Post. End-to-end proof
is E1's local-stack check.

---

## 4. Ship

### E1 — Ship

- client `7.50.0` in `packages/client/pubspec.yaml:5` **and** `web/index.html:146`;
  `kDefaultMinClientVersion = '7.50.0'` (`packages/server/lib/env.dart:94`).
- delete leftovers: `PostsCubit.quietAfter`, `postsTabQuiet`, `postInfoQuiet` and any unused
  `postInfoActive*` ARB keys (EN + RU), `kConstellationPostActiveWindow`.
- docs: `post-ttl-design.md` status → shipped; `post-and-constellation-composer-plan.md` Q5 gets
  "superseded by post-ttl-design.md"; `post-ux-mockups.md` line about pinned "never fades out" →
  D4.
- full wrapped suites (server non-pg, pg, client) serially; custom lints for both packages.
- local-stack check (`local-debug` skill): publish a Post with 6 h, shorten it to the past via the
  ⋮ menu → archive; set another Post's `expires_at` to `now() + 2h59m` in SQL → after one sweep the
  author's For You shows the warning and the push opens the Post; then set it to the past → the room
  goes read-only without reload, the row moves to «Архив», bud from archive works.

---

## 5. Invariant → test map

| Invariant | Unit / test |
|---|---|
| I1 open Post always has `expires_at`; Requests never | S1 |
| I2 `expires_at ≤ published_at + 72h` for every Post published after S3 | S3, S10 |
| I3 lifetime never grows | S10 |
| I4 no ordinary write lands in a closed or expired Post, even racing a close | S5a (incl. race), S5b, S6, S7 |
| I5 personal actions work in the archive | S8 |
| I6 every expired Post becomes status 6 within one sweep | S9 |
| I7 bud from archive works and never reopens the Post | S11 |
| I8 one warning per Post, author only | S12 |
| I9 expired Posts leave the field and For You (rows, previews, counts, dot) | S13, C6 |
| I10 the client flips to archive at `expiresAt` with no network event | C1, C3, C4, C6 |
| I11 every unit compiles and is green on its own | §1 note, S1 defaulting trigger, E1 |
| I12 account erasure and image deletion work with archived Posts | S5a |

---

## 6. Astra review (rev 1 → rev 2) — disposition

Reviewer: codex `gpt-6-astra`, effort high, read-only, 2026-10-23. Verdict on rev 1: needs rework.

| # | Sev. | Finding | Disposition |
|---|---|---|---|
| 1 | blocker | domain checks race with close; reactions / attachments / votes unguarded at DB level | Accepted. §0 two-layer model: DB trigger with a row lock that conflicts with the closer's `FOR UPDATE` (no new lock class), domain layer for typed errors, upload compensation; race test in S5a. Writers do not take the global hierarchy lock. |
| 2 | blocker | Hasura `vote_beacon` insert / update bypasses guards | Accepted. `vote_beacon` trigger in S5a + role-`user` Hasura test. |
| 3 | major | `openForwarding`, `beaconStageImage`, `beaconSetMedia` unguarded | Accepted. §0 write-path matrix; S7. |
| 4 | major | `ON DELETE SET NULL` turns delete into an UPDATE caught by the trigger | Accepted. Referential-cleanup exemption (S5a), tested in S5a and S8. |
| 5 | major | S1 CHECK breaks publish before S3 | Accepted. S1 sets `+72h` in `publishDraft`. |
| 6 | major | semantic-done is Request-only | Accepted. Matrix row + negative test with a Request positive control (S5b). |
| 7 | major | `expiresAt` not propagated through the room host / cubit | Accepted. C4 expiry propagation + one writability rule. |
| 8 | major | time passing alone not handled | Accepted. `PostExpiryClock` (C0) used by C1 (incl. pinned), C3, C4, C6; constellation uses current time. |
| 9 | major | removing `quietAfter` in C1 breaks C3's consumer | Accepted. All deletions moved to E1. |
| 10 | major | message-based bud and baton delete paths need `canWrite` | Accepted. C4 message menus. |
| 11 | major | For You predicates are shared across projections; warning exemption keeps archived rows | Accepted. `postLifecycleExcluded` inside the shared eligibility predicate; no exemption. |
| 12 | major | intent defaults to Request; string-keyed client maps | Accepted. Explicit Post facts in S12; literal values shared with C7; E1 local-stack check. |
| 13 | major | warning eligibility read from mutable `expires_at` | Accepted. `expiry_warning_eligible` fixed at publish (S1/S3); shortening tests in S12. |

---

## 7. Round-2 review (rev 2 → rev 3) — disposition

Reviewer: independent Opus subagent (codex quota exhausted), read-only, 2026-10-23. Verdict on
rev 2: ready after fixes. Round-1 items 2, 6–10, 12, 13 resolved; 1, 3, 4, 5 partial (below).

| # | Sev. | Finding | Disposition |
|---|---|---|---|
| 1 | blocker | `ON DELETE SET NULL` cascades on attachment `image_id` / baton `taker_id` hit the guard → account erasure and image deletion fail | Accepted. Triggers are `UPDATE OF` user-editable columns only; erasure / image-delete tests in S5a; also fixes the latent closed-Request reply bug. |
| 2 | blocker | S1 CHECK breaks ~40 pg fixtures that insert open Posts directly | Accepted. Defaulting trigger in S1; S1 done-when = whole pg suite. |
| 3 | major | new-account invite signup admits into expired Posts | Accepted. S7 + matrix row. |
| 4 | minor | S8 needs to skip `_guardMessageMutation`; `check_violation` mapping too broad; exception naming | Accepted. Distinct `post_archived` message; exceptions named per path (§0). |
| 5 | minor | KEY SHARE is a new lock for non-FK tables; reaction should use NO KEY UPDATE; `beacon_participant` rule; "writers never take" wording | Accepted. §0 reworded. |
| 6 | minor | race-test blocking detection; C6 vs E1 deletion | Accepted. `pg_stat_activity` wait detection; deletion in E1 only. |

