---
status: implementation-ready
kind: plan
---

# Reply-to-message in request Rooms (issue #115)

**Status:** implementation-ready (rev 3). Two adversarial review rounds by
Codex CLI: round 1 against rev 1 (12 defects, 3 BLOCKER), round 2 against
rev 2's new material (11 defects, 1 BLOCKER). All are folded in — §9 records
both dispositions so the corrections are not silently re-lost. The two open
scope questions were **confirmed with the user on 2026-08-10** (§0.5); nothing
is left to decide before P1 starts.
**Date:** 2026-08-10.
**Scope:** client UI + server read path + realtime paint extension for
[Intersubjective/tentura#115](https://github.com/Intersubjective/tentura/issues/115),
split out of the now-closed #101 (image paste/upload shipped separately).

---

## 0. Why this plan exists

### 0.1 What the issue asks for

- `Reply` action on a message.
- Composer shows referenced author + short source excerpt.
- Sent reply links/scrolls to the original message where available.
- Deleted/unavailable source messages degrade gracefully.
- ACs: works with **mouse and touch** (#115 dropped #101's keyboard clause);
  notification semantics don't spam the Room; references survive reload and
  multi-client sync; widget/integration tests.

### 0.2 What already exists (verified against live code)

The **write path** is wired end-to-end; the **read path and UI are absent**.

| Layer | Fact | Evidence |
|---|---|---|
| DB | `beacon_room_message.reply_to_message_id text NULL` + self-FK `ON DELETE SET NULL` | `packages/server/lib/data/database/migration/m0036.dart:62,70` |
| Drift | `replyToMessageId` column | `packages/server/lib/data/database/table/beacon_room_messages.dart:19` |
| Server domain | `createMessage(replyToMessageId:)` + same-scope validation | `packages/server/lib/domain/use_case/beacon_room_case.dart:179,224-234` |
| Server GraphQL | `RoomMessageCreate(replyToMessageId: String)` arg | `.../mutation/mutation_beacon_room.dart:18,64,77` |
| Notifications | parent author joins the *directed* recipient set | `beacon_room_case.dart:263-322` |
| Client data | `BeaconRoomRepository.createMessage(replyToMessageId:)` | `packages/client/lib/features/beacon_room/data/repository/beacon_room_repository.dart:496,513` |
| Client domain | `BeaconRoomCase.createMessage(replyToMessageId:)` passthrough | `.../beacon_room/domain/use_case/beacon_room_case.dart:136,150` |

**Missing:**

1. **Read path.** `v2_RoomMessageRow` exposes no reply field
   (`packages/server/lib/api/controllers/graphql/custom_types.dart:161-202`;
   `packages/server/lib/data/repository/beacon_room_repository.dart:364-413`),
   so no client can tell that a message is a reply.
2. **Realtime paint** carries no reply data
   (`.../websocket/path_handler/websocket_path_entity_changes.dart:95-105`).
3. **The whole UI** — no entry point, no composer target, no quote, no jump.

`RoomCubit.sendMessage` (`room_cubit.dart:708-784`) never passes
`replyToMessageId`, so the server plumbing is dead code today.

### 0.3 Existing test coverage is thinner than it looks

`packages/server/test/domain/use_case/beacon_room_case_message_mutations_test.dart`
has three reply tests (lines 240, 262, 430), but they are **use-case tests over
`_StubRoom`**. The stub's `insertRoomMessage` records `insertedBody` and
`insertedMentions` and **discards `replyToMessageId`** (lines 96-119), so
nothing today proves the id is persisted, that the FK behaves, that the
GraphQL argument is wired, or that anything reads back. P1.6 and P7 close
that.

Likewise `packages/client/test/features/beacon_room/room_cubit_send_message_test.dart`
drives a **real** `BeaconRoomCase` over `_FakeBeaconRoomRepository`, whose
`createMessage` accepts and then discards `replyToMessageId` (lines 96-107).
That fake must start recording the argument before any cubit test can assert
it (P4.1).

### 0.4 Notification semantics — the accurate statement

`createMessage` builds:

```dart
otherDirectedIds = {repliedMessage?.authorId, threadItem?.targetPersonId}
                     - {self} - mentionRecipientIds          // :263-268
```

and dispatches `roomMessagePosted` **only** to that set (`:310-322`).

So the correct guarantee is: **a reply notifies the parent author, plus — in
an item thread only — the thread item's target person (which any thread
message already notifies, reply or not), minus yourself, minus anyone already
covered by an `@`-mention.** Never the whole Room.

Rev 1 claimed "only the replied-to author", which is false in thread mode.
No server behaviour change is proposed: the thread-target notification is
pre-existing and correct. P1.6 tests the exact set in both modes.

### 0.5 Settled scope decisions (user, 2026-08-10)

| Question | Decision | Consequence |
|---|---|---|
| Thread-mode notification set — a reply inside an item thread reaches the parent author **and** the item's `targetPersonId` (§0.4). Preserve or narrow? | **Leave it alone.** | No server behaviour change. The thread-target notification is pre-existing and fires for *any* thread message, reply or not; a reply adds exactly one recipient (the parent author). P1.6 tests the exact set in both modes rather than changing it. Narrowing it would be a separate issue — it would stop the person accountable for the item hearing about their own thread. |
| Postgres contract tests (P7.2) — in scope for #115 or split out? | **In scope.** | P7.2 ships with this issue. It is the only coverage that proves persistence, the `ON DELETE SET NULL` behaviour, off-window parent resolution, cross-scope isolation, and parent-edit freshness — none of which the stub-based use-case tests can reach (§0.3). Requires a live Postgres; the existing `@Tags(['pg'])` harness skips gracefully when unreachable, so CI without Postgres stays green. |

### 0.6 Design decisions

| Decision | Choice | Why |
|---|---|---|
| How the client learns the parent | **Read-time denormalized snapshot fields on `v2_RoomMessageRow`** | Mirrors the existing `linkedItem*` snapshot fields on the same row; a read-time join stays fresh when the parent is edited (an insert-time snapshot would go stale); no extra client round trip. |
| Parent lookup scope | Filtered by `beacon_id` **and** thread scope, not trusted from the FK | The self-FK constrains existence only, not scope (`m0036.dart:62-71`). A malformed/legacy/direct-DB row must not leak another Chat's body and author. Non-matching parent ⇒ treated as unavailable. |
| Deleted parent | Existing FK `ON DELETE SET NULL` — the pointer clears, quote disappears | Zero migration; no dangling ids possible. |
| Unresolvable snapshot | Muted, non-tappable "Original message is unavailable" quote | Covers the delete-vs-read race and the scope-mismatch rejection above. |
| Realtime | **Extend the paint snapshot with the five reply fields** | Rev 1 proposed *excluding* replies from the fast-paint. That silently breaks the own-message reconciliation protocol (`_deferredOwnPaintByServerId`), producing a transient duplicate and then overwriting the authoritative server row with the local synthetic one (`room_cubit.dart:517-541, 742-765`). Extending the paint keeps the protocol intact, keeps latency, and costs two small queries per *reply* insert (computed once per insert, before the session fan-out loop). |
| Own optimistic send | Client builds the quote from the target's **own identity** | Instant quote without waiting for the echo, and correct when actor echo is disabled (`env.realtimeActorEchoEnabled`, `websocket_path_entity_changes.dart:35-43`). |
| Swipe-to-reply | **Out of scope** (§8) | Horizontal drag on chat content collides with platform back-swipe and the "avoid horizontal swipe on main content" rule; sheet + hover toolbar + secondary-tap already satisfy the mouse/touch AC. |

### 0.7 Non-negotiable compatibility constraint

**Every new `RoomMessage` field, every new widget parameter, and every new
GraphQL field is nullable or has a default.** No existing constructor call,
test fixture, fake, or golden may need editing to keep compiling. This is
what keeps the blast radius at "new tests only" (§7.5).

---

## 1. Rules (repo-wide invariants — read before editing)

From `AGENTS.md` and `.cursor/rules/`:

- **Never edit generated files** (`_g/*.gql.dart`, `*.freezed.dart`,
  `*.g.dart`, `*.config.dart`). Run codegen.
- **Dependency direction inward:** ui → data → domain. Repositories return
  domain entities, never Ferry types. `basic_chat_body.dart` is shared chrome
  and must **not** import `RoomCubit` — reply state arrives as parameters.
- **Design system only in `features/**` / `ui/**`:** no raw `Color`,
  `TextStyle(…)`, inline `fontSize:`, `EdgeInsets.all(<n>)`,
  `BorderRadius.circular(<n>)`. Use `context.tt`, `TenturaText.*`,
  `Theme.of(context).colorScheme.*`. If no radius token ≤ 4dp exists, **add
  one to `tentura_radii.dart` first** — do not inline.
- **Terminology:** user-facing **Chat** / **Request**; code paths stay
  `beacon_room`. `bash scripts/check-user-facing-terminology.sh` gates it.
- **Client version bump mandatory** for user-visible change, and
  `packages/client/web/index.html`'s `flutter_bootstrap.js?v=` synced in the
  same commit.
- **Custom lints do not fire under `flutter analyze`.** Use
  `./scripts/check-custom-lints.sh packages/client` (baseline 115).
- `packages/client/lib/data/gql/schema.graphql` is **hand-maintained**; new
  server fields must be added there manually before `build_runner` accepts
  them in a query document. Hand-editing is not a drift test — P7.2 covers
  drift with a real contract test.

## 2. Verification commands

```bash
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
cd packages/client && flutter gen-l10n && dart run build_runner build -d
cd packages/client && flutter test
cd packages/server && dart run build_runner build -d && dart test          # excludes pg by default
cd packages/server && dart test --tags pg                                  # requires local Postgres
```

---

## Phase P1 — Server: expose the reply snapshot

### P1.1 Public, testable excerpt helper

New `packages/server/lib/domain/util/room_reply_excerpt.dart` (the
`domain/util/` directory already exists):

```dart
const kRoomReplyExcerptMaxChars = 160;

/// One-line excerpt of a quoted message body.
/// Collapses all whitespace runs to single spaces and truncates on a **rune**
/// boundary (so surrogate pairs never split). Full grapheme-cluster safety
/// (ZWJ sequences, skin-tone modifiers) is deliberately *not* promised — the
/// server has no `characters` dependency and a clipped ZWJ sequence degrades
/// to two visible glyphs, which is acceptable in a 160-char preview.
String? roomReplyExcerpt(String? body) { … }
```

Returns `null` for null/blank input. It is a pure function in `domain/` with
no I/O — allowed by the layer rules, and directly unit-testable (rev 1 put it
in a library-private `_replyExcerpt`, which no separate test file can reach).

### P1.2 Extend the GraphQL row type

`packages/server/lib/api/controllers/graphql/custom_types.dart`, in
`gqlTypeRoomMessageRow` after `threadItemId` (line 201):

```dart
field('replyToMessageId', graphQLString),
field('replyToAuthorId', graphQLString),
field('replyToAuthorTitle', graphQLString),
field('replyToBodyExcerpt', graphQLString),
field('replyToHasAttachments', graphQLBoolean),
```

All nullable — a non-reply row emits `null` for all five.

### P1.3 Cheap attachment-presence primitive

`packages/server/lib/data/repository/beacon_room_repository.dart` — new
private method next to `attachmentsJsonByMessageIds` (line 82):

```dart
Future<Set<String>> _messageIdsWithAttachments(List<String> ids) async { … }
```

One `selectOnly(beaconRoomMessageAttachments)` over `messageId` with
`isIn(ids)`, distinct, returning the id set.

Rev 1 proposed reusing `attachmentsJsonByMessageIds`. That is one query, so
not N+1, but it materialises **every attachment row and then every referenced
`Image`** (lines 91-120) just to answer a boolean — and `roomMessageTarget`'s
`limit: 1` bounds messages, not that one parent's attachment count
(lines 427-433). Use the presence query.

### P1.4 Populate the fields in `listMessagesEnriched`

Same file, `listMessagesEnriched` (lines 169-415):

1. `parentIds = {m.replyToMessageId}` (non-empty, deduped).
2. If non-empty, select parents **scope-filtered**:
   ```sql
   WHERE id IN parentIds
     AND beacon_id = :beaconId
     AND thread_item_id IS NOT DISTINCT FROM :threadItemId
   ```
   In Drift: `id.isIn(parentIds) & beaconId.equals(beaconId) &
   (threadItemId == null ? t.threadItemId.isNull() : t.threadItemId.equals(threadItemId))`.
   A parent that fails the filter is simply absent from `parentById` and
   therefore renders as unavailable — no leak.
3. Merge parent author rows into the existing `userById` map with the same
   pattern already used for `missingReactorUserIds` (lines 199-210) — parents
   can be older than the 50-row window, so their authors are frequently
   absent. Their `imageId` does **not** need hydrating: the quote shows a name,
   not an avatar.
4. `attachmentParentIds = await _messageIdsWithAttachments(parentIds)`.
5. In the row map (line 364), emit:

   | Field | Value |
   |---|---|
   | `replyToMessageId` | `m.replyToMessageId` |
   | `replyToAuthorId` | `parent?.authorId` |
   | `replyToAuthorTitle` | `userById[parent.authorId]?.displayName ?? ''` |
   | `replyToBodyExcerpt` | `roomReplyExcerpt(parent?.body)` |
   | `replyToHasAttachments` | `parent != null && attachmentParentIds.contains(parent.id)` |

   When `m.replyToMessageId` is non-null but `parent == null`, emit the id and
   leave the other four `null` — this is the client's "unavailable" signal.

`roomMessageTarget` (line 418) needs no change: it delegates to
`listMessagesEnriched`.

### P1.5 Extend the realtime paint

Three edits, all additive:

1. `packages/server/lib/domain/entity/room_message_snapshot.dart` — add the
   five nullable fields (`replyToHasAttachments` as `@Default(false) bool`).
2. `packages/server/lib/data/repository/room_message_snapshot_lookup.dart`,
   `findEligibleInsert` — when `row.replyToMessageId != null`, resolve the
   parent with the **same scope filter as P1.4** and populate the snapshot.
   The lookup already has the child's `beaconId` and `threadItemId` from the
   row it just read (`:20-22`), so it can enforce the filter without new
   parameters. Keep every existing `return null` guard (empty body, linked
   ids, semantic marker, system payload, attachments) untouched: an
   attachment-bearing or system reply still skips the paint and arrives via
   the normal refresh, exactly as today.
3. `.../websocket/path_handler/websocket_path_entity_changes.dart`,
   `_serializePaint` (line 95) — emit the five fields.

**Cost, stated accurately: two extra queries per reply insert** — and that is
only true if the parent lookup is written as a **parent ⋈ user join** so the
author's `display_name` comes back with the parent row. The second query is
the attachment-presence check (P1.3). A naive parent-select-then-author-select
would be three. Rev 2 claimed "two" while specifying three separate lookups;
the join is what makes the claim true, so write the join.

These run **once per insert**, not per recipient: `findEligibleInsert` is
invoked at `websocket_path_entity_changes.dart:51`, and the session send loop
does not start until line 83. They run only when `reply_to_message_id` is
non-null, so ordinary messages are unaffected.

**Why not exclude replies from the paint instead** (rev 1's proposal): a
paint-less own-message insert makes `_fetchMessagesSnapshot` merge the server
row while retaining the pending local row (`room_cubit.dart:517-541`) → a
transient duplicate; then on mutation success `deferred` is `null`, so
`localMessage.copyWith(id: serverId)` **replaces the authoritative server row
with the local synthetic** (`:742-765`), permanently losing any server-computed
field. This is a real pre-existing wart (attachments hit it and work around it
with an explicit `_requestRefresh` at `:763-765`), but it is not something to
newly opt replies into.

### P1.6 Server unit tests

`packages/server/test/domain/util/room_reply_excerpt_test.dart` (new): null,
empty, whitespace-only, newline/tab collapsing, exactly 160, 161 (ellipsis),
a body ending in a surrogate pair at the boundary.

Extend `beacon_room_case_message_mutations_test.dart`:

- add `String? insertedReplyToMessageId;` to `_StubRoom` and record it in
  `insertRoomMessage` (line 96); assert it in the existing "reply targets the
  original author" test — today that test never proves the id reaches the repo.
- **main-room negative test:** reply in a room with three admitted
  participants ⇒ attention intents to **exactly one** recipient (parent
  author). Asserts the "does not notify the entire Room" AC.
- **thread-mode test:** reply inside an item thread whose `targetPersonId`
  differs from the parent author ⇒ **exactly two** recipients, deduped, no
  third. Documents §0.4's real semantics.
- **self-reply test:** replying to your own message ⇒ **zero** intents.

Extend `packages/server/test/data/repository/room_message_snapshot_lookup_test.dart`
(already `@Tags(['pg'])`): a reply insert yields a snapshot carrying the five
fields; a reply whose parent is in another beacon yields a snapshot with the
id but null author/excerpt.

### P1.7 Docs

`docs/features/beacon_room.md` — a **Reply** paragraph next to the existing
`@mentions` paragraph (line 70), stating: reply points at one message in the
same Chat scope; notifies the parent author (plus, in an item thread, the
item's target person — as any thread message does) and never the whole Room;
never double-notifies someone who is also `@`-mentioned; deleting the original
clears the pointer and the quote disappears.

**Exit:** `dart test` and `dart test --tags pg` green;
`./scripts/check-custom-lints.sh packages/server` clean.

---

## Phase P2 — Client wire: schema, documents, entity, mapper

### P2.1 Hand-edit the client schema

`packages/client/lib/data/gql/schema.graphql`, `type v2_RoomMessageRow`
(line 7151) — add, keeping the file's alphabetical order:

```graphql
  replyToAuthorId: String
  replyToAuthorTitle: String
  replyToBodyExcerpt: String
  replyToHasAttachments: Boolean
  replyToMessageId: String
```

### P2.2 Add them to both query documents

- `.../beacon_room/data/gql/room_message_list.graphql`
- `.../beacon_room/data/gql/room_message_target.graphql`

Identical field sets — both feed the same `_toRoomMessageFields` mapper.
No `build_client.dart` routing change: both operations are already registered
as V2-direct (lines 262, 267).

### P2.3 Domain entity

`packages/client/lib/domain/entity/room_message.dart` — append to the factory:

```dart
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
    @Default(false) bool replyToHasAttachments,
```

and on the existing `const RoomMessage._()` extension:

```dart
  bool get isReply => (replyToMessageId ?? '').trim().isNotEmpty;

  /// Known to be a reply, but the parent snapshot did not resolve — deleted
  /// between list and read, or rejected by the P1.4 scope filter.
  bool get replyTargetUnavailable =>
      isReply && (replyToAuthorId ?? '').trim().isEmpty;
```

### P2.4 Mapper

`.../beacon_room/data/repository/beacon_room_repository.dart` — thread the
five fields through the projection (line ~255) and `_toRoomMessageFields`
(lines 276-381). `replyToHasAttachments` maps `bool? → bool` with `?? false`.

### P2.5 Realtime paint entity + parser

- `packages/client/lib/domain/entity/realtime/realtime_room_message_paint.dart`
  — same five fields, same nullability.
- `packages/client/lib/data/service/invalidation_service.dart`,
  `_parseRoomMessagePaint` (line 268) — parse them.

  **Strictness is a deliberate new contract, not an existing convention.**
  Rev 2 claimed the file already rejects any wrong-typed field; it does not —
  only `editedAt` rejects the whole paint (`:310-318`), while a malformed
  `mentions` degrades to `[]` and a malformed `threadItemId` to `null`
  (`:319-324`). For reply fields, choose **lenient-on-missing,
  strict-on-wrong-type**: absent keys are normal and must parse fine; a
  present-but-wrong-typed key rejects the paint so a corrupt quote never
  renders. Both directions of version skew stay safe: an **old server** omits
  the keys entirely (accepted), and an **old client** ignores unknown JSON
  keys from a new server. P4.3 tests both skew directions explicitly.
- `.../beacon_room/domain/use_case/beacon_room_case.dart`,
  `roomMessageFromPaint` (line 164) — copy the five fields onto the built
  `RoomMessage`.

### P2.6 Codegen

```bash
cd packages/client && dart run build_runner build -d
```

**Exit:** build_runner green; `flutter analyze` clean on touched files.

---

## Phase P3 — Client state: reply target, optimistic quote, jump

### P3.1 `RoomState`

`.../beacon_room/ui/bloc/room_state.dart`:

```dart
    /// Message the composer is replying to; null when reply mode is off.
    RoomMessage? replyTarget,
```

**`emit(state.copyWith(replyTarget: null))` is correct and sufficient.**
Freezed is `3.2.6-dev.1` (`pubspec.lock:844-859`); generated `copyWith` uses
the `freezed` sentinel for nullable fields (`room_state.freezed.dart:76`), and
the cubit already clears nullables exactly this way — `scrollToMessageId: null`
(`room_cubit.dart:263`) and `loadError: null` (`:472`). Rev 1 left this open
and floated an id-plus-lookup fallback; that fallback is **deleted**, not
deferred.

### P3.2 `RoomCubit` — reply target

`.../beacon_room/ui/bloc/room_cubit.dart`:

```dart
/// Ineligible when the message has no server id yet.
static bool canReplyTo(RoomMessage m) => !m.id.startsWith('local:');

void startReplyTo(RoomMessage message) {
  if (!canReplyTo(message)) return;
  emit(state.copyWith(replyTarget: message));
}

void cancelReply() {
  if (state.replyTarget != null) {
    emit(state.copyWith(replyTarget: null));
  }
}
```

`canReplyTo` is `static` so the UI can gate entry points with the *same*
predicate (P5.1, P5.2) instead of duplicating the string check.

### P3.3 `RoomCubit.sendMessage` — explicit quote construction

`sendMessage` (line 708) keeps its current signature; it reads
`state.replyTarget` itself, so `BasicChatBody.onSend` stays generic.

```dart
final target = state.replyTarget;          // capture ONCE, before any await
```

The optimistic `localMessage` (line 718) gains, **built from the target's own
identity — never from the target's own reply fields**:

| Local field | Source |
|---|---|
| `replyToMessageId` | `target.id` |
| `replyToAuthorId` | `target.authorId` |
| `replyToAuthorTitle` | `target.author.shownName` |
| `replyToBodyExcerpt` | `roomReplyExcerpt(target.body)` (client copy, P5.4) |
| `replyToHasAttachments` | `target.attachments.isNotEmpty` |

Rev 1 said "copy the four quote fields from `state.replyTarget`", which read
literally means copying `target.replyTo*` — i.e. quoting the **grandparent**
when you reply to a reply. P6.1 has a regression test for exactly that.

Then:

- `_case.createMessage(..., replyToMessageId: target?.id)`.
- On **success**: clear the reply target **only if it is still the same one**:

  ```dart
  if (state.replyTarget?.id == target?.id) {
    // …copyWith(replyTarget: null) folded into the reconcile emit
  }
  ```

  `sendMessage` awaits the mutation (`room_cubit.dart:735`), and the user can
  pick a *different* message to reply to while that request is in flight. An
  unconditional clear on completion would silently wipe the banner they just
  opened. P4.2 has a completer-gated race test.
- On **failure**: keep the target so the user can retry.
- Reconcile at lines 743-747 is unchanged: `deferred` (the painted server row,
  now carrying server-computed quote fields thanks to P1.5) wins when present;
  otherwise `localMessage.copyWith(id: serverId)` carries the client-built
  quote. Both paths render a correct quote, including when
  `env.realtimeActorEchoEnabled` is false.

### P3.4 Jump to source — a dedicated operation

Rev 1 delegated to `prepareThreadScroll`. That is **not** a safe reuse:

- it unconditionally sets `_pendingThreadItemId = null` (`:283-284`), dropping
  an in-flight item navigation;
- it does nothing at all when `state.messages.isEmpty` (`:285`);
- `_applyPendingThreadScroll` returns `void` and silently no-ops on failure
  (`:304-330`), so a "couldn't load" snackbar cannot tell failure from the
  item-fallback path;
- an off-window target merged by `_fetchFullSnapshot` (`:395-428`) is
  **discarded by the very next `_fetchMessagesSnapshot`**, which rebuilds from
  `rawMessages + pendingLocals` only (`:517-541`) — so the jump target
  vanishes on the next inbound message.

Implement instead:

```dart
/// Off-window messages fetched for a jump; re-merged on every messages
/// refresh so an inbound message does not yank the viewport target away.
/// Bounded LRU, cleared on beacon/thread change.
static const _kMaxPinnedOffWindow = 20;
final _pinnedOffWindowMessages = <String, RoomMessage>{};

Future<bool> jumpToRepliedMessage(String messageId) async {
  final id = messageId.trim();
  if (id.isEmpty) return false;
  if (state.messages.any((m) => m.id == id)) {
    requestScrollToMessage(id);
    return true;
  }
  RoomMessage? target;
  try {
    target = await _case.fetchMessageTarget(
      beaconId: state.beaconId,
      messageId: id,
    );
  } on Object {
    target = null;                     // see note below — this path THROWS
  }
  if (isClosed) return false;
  if (target == null) {
    _showMessage(const RoomReplyTargetUnavailableMessage());
    return false;
  }
  _pinOffWindow(target);               // LRU insert, evicts oldest past 20
  emit(state.copyWith(
    messages: _mergeMessages(serverRows: state.messages),
    pinnedJumpMessageIds: _pinnedOffWindowMessages.keys.toList(),
    scrollToMessageId: id,             // SAME emit — see "auto-follow" below
  ));
  return true;
}
```

**One shared merge routine, pins first.** Add:

```dart
List<RoomMessage> _mergeMessages({required List<RoomMessage> serverRows}) =>
    _sortMessages(_dedupeMessages([
      ..._pinnedOffWindowMessages.values,   // FIRST — see precedence note
      ...serverRows,
      ...state.messages.where((m) => _pendingLocalMessageIds.contains(m.id)),
    ]));
```

and call it from **both** `_fetchMessagesSnapshot` (line 530) **and**
`_fetchFullSnapshot` (line 422). Rev 2 patched only the messages-only path;
`_fetchFullSnapshot` rebuilds from `rawMessages` plus at most
`_pendingThreadMessageId` (`:395-428`), and realtime **catch-up uses a full
refresh**, so a reconnect would drop the just-jumped target.

**Precedence — rev 2 had this exactly backwards.** `_dedupeMessages` is
**last-wins** by id (`byId[message.id] = message`, `:550-556`). Rev 2 ordered
`[...refreshed, ...pinned]` while claiming the refreshed row would win; in
fact the *pin* would have won and served stale content forever — a parent
edit, a new reaction, or a corrected author projection on a pinned row would
never surface. Pins must therefore come **first** so any fresh server row with
the same id overwrites them. P4.2 tests exactly that.

**The `try`/`catch` is required, not defensive noise.** `fetchMessageTarget`
resolves through `dataOrThrow` (`beacon_room_repository.dart:218-233`), and the
server's `roomMessageTarget` **throws** `IdNotFoundException` /
`UnauthorizedException` for a missing or out-of-scope message
(`packages/server/lib/domain/use_case/beacon_room_case.dart:379-406`) rather
than returning null. A bare `await` here would surface a raw GraphQL error
snackbar instead of the intended "original message could not be loaded" copy.
The `null` branch is kept as well, since the field is nullable in the schema.

**Pinned rows must not pollute unread state.** Every entry in `state.messages`
feeds `unreadCount`, `firstUnreadMessageId`, and `firstUnreadIndex`
(`room_state.dart:46-82`), which in turn drive the unread divider and the jump
FAB badge (`basic_chat_body.dart:401-404, 467-469`). `_isUnreadForViewer`
treats **everything** as unread when `unreadAnchorAt` is null (`:50`) — and
because the list sorts ascending by `createdAt`, an injected historical row
would become `firstUnreadMessageId` and inflate the badge. So:

- `RoomState` gains `@Default(<String>[]) List<String> pinnedJumpMessageIds`;
- `_isUnreadForViewer` returns `false` for any id in that list — navigation-only
  rows are never unread and never move the divider;
- the read watermark (`markReadToBottom`, `_advanceReadAnchorToLatestLoaded`)
  is unaffected because it keys off the newest loaded row, and a pinned row is
  always older.

**Lifecycle.** `_pinnedOffWindowMessages` is an LRU capped at
`_kMaxPinnedOffWindow = 20` (evict oldest on insert). Clear it when
`beaconId`/`threadItemId` changes. Do **not** clear it in `load()`: `load()`
is also the pull-to-refresh path for the same scope, and dropping pins there
would re-introduce the disappearing-target bug. Item-thread cubits are
created per item and disposed with the pane
(`item_discussion_pane.dart:18-25`), so cross-thread leakage is not possible.

**The jump must survive auto-follow.** `BasicChatBody.didUpdateWidget`
(`:330-349`) calls `_followLatestAfterLayout()` — a hard `jumpTo(maxScrollExtent)`
— whenever the message count grows and the user is near the bottom. Adding a
pinned row grows the count, and tapping a quote while reading recent messages
is the *normal* case, so the jump would be undone within a frame. Fix:

- `BasicChatBody` gains `final String? pendingJumpMessageId;`, passed from
  `state.scrollToMessageId` by `BeaconRoomBody`;
- `didUpdateWidget` returns early while it is non-null, before the auto-follow
  branch;
- the existing listener already calls `clearScrollToMessageTarget()` once
  `scrollToMessage` succeeds (`beacon_room_body.dart:104-116`), which
  re-enables auto-follow. Add a matching clear on the *failure* path so a
  missed target cannot wedge auto-follow off permanently.

Emitting `scrollToMessageId` in the **same** emit that adds the pinned row
(above) is what makes this airtight: the very first `didUpdateWidget` after
the insert already sees a non-null `pendingJumpMessageId`.

This also fixes the same pre-existing loss for the fact-pin and promote-pin
jumps, which share `scrollToMessage`.

Add `RoomReplyTargetUnavailableMessage` next to
`BeaconFactVisibilitySuccessMessage` in the room message-bus enum, mapped to
`l10n.beaconRoomReplyTargetNotLoaded`.

**Exit:** `flutter test test/features/beacon_room/` green.

---

## Phase P4 — Client test scaffolding (do this before P5/P6 UI work)

### P4.1 Record the argument in the existing fake

`packages/client/test/features/beacon_room/room_cubit_send_message_test.dart`,
`_FakeBeaconRoomRepository.createMessage` (lines 96-107): add
`String? lastReplyToMessageId;` and assign it. Without this, no cubit test can
assert the wire argument at all.

### P4.2 Cubit tests

New `packages/client/test/features/beacon_room/room_cubit_reply_test.dart`,
reusing the fakes from `room_cubit_send_message_test.dart` (extract them into
a shared `room_cubit_fakes.dart` rather than duplicating):

- `startReplyTo` sets the target; `cancelReply` clears it (proves
  `copyWith(replyTarget: null)`).
- `startReplyTo` on a `local:` id is a no-op.
- `sendMessage` with a target passes `replyToMessageId` to the repository and
  the optimistic message carries all five quote fields.
- **reply-to-a-reply:** target is itself a reply ⇒ the new message quotes the
  *target*, not the grandparent.
- successful send clears the target; failed send keeps it.
- **stale-clear race:** gate the fake repository's `createMessage` on a
  `Completer`; while send A is in flight, call `startReplyTo(B)`; complete A;
  assert `state.replyTarget` is still **B** (P3.3).
- `jumpToRepliedMessage` on a loaded id emits `scrollToMessageId` and returns
  `true`; on an off-window id it fetches, merges, scrolls, returns `true`; on
  a **throwing** fetch (the real server behaviour — see P3.4) and on a `null`
  fetch it emits the unavailable message and returns `false`.
- **off-window retention, both paths:** after a successful off-window jump,
  the pinned target survives a `_fetchMessagesSnapshot` cycle **and** a
  `_fetchFullSnapshot` (catch-up) cycle.
- **pin precedence:** when a refresh returns a *changed* row with the pinned
  id (e.g. edited body), the merged list holds the **server** version, not the
  pin (P3.4).
- **LRU eviction:** 21 successive off-window jumps leave exactly 20 pins.
- **unread isolation:** with `unreadAnchorAt == null`, pinning a historical
  row does not change `unreadCount`, does not become `firstUnreadMessageId`,
  and does not move `firstUnreadIndex`.

### P4.3 Realtime paint tests

Extend `packages/client/test/.../invalidation_service` coverage (or add
`realtime_room_message_paint_reply_test.dart`):

- a payload carrying the five reply fields parses into
  `RealtimeRoomMessagePaint`;
- a **wrong-typed** reply field rejects the whole paint;
- **old server → new client:** a payload with the reply keys entirely absent
  parses fine, yielding a non-reply paint (this is the upgrade-order case that
  actually ships first);
- **new server → old client** is covered by construction — unknown JSON keys
  are ignored — but assert it once against the current parser so a future
  strictness change cannot silently break it.

Extend `room_cubit_unread_test.dart`'s paint-driven cases with: an **own**
reply paint arriving before the mutation response is deferred and reconciled
without a duplicate (guards the §0.6 protocol).

**Exit:** new tests fail meaningfully (red) against unimplemented UI, green
against P2/P3.

---

## Phase P5 — Client UI: entry points

### P5.1 Bottom-sheet action

`.../beacon_room/ui/widget/beacon_room_body.dart`, `_onMessageActionsPressed`
(line 316). Insert **directly after** the emoji quick-picker `Wrap` (line 427)
and before the "Turn into…" group — reply is the highest-frequency action:

```dart
if (RoomCubit.canReplyTo(message))
  ListTile(
    leading: const Icon(Icons.reply_outlined),
    title: Text(l10n.beaconRoomActionReply),
    onTap: () {
      Navigator.pop(ctx);
      cubit.startReplyTo(message);
    },
  ),
```

Deliberately **not** gated on `_suppressesRichMessageActions` or thread mode:
replying to a blocker/need-info/done-marked message, and replying inside an
item thread, are both valid and server-supported. System rows
(participant-joined, fact-pin, coordination-timeline notify, promote-pin)
never reach this sheet — `RoomMessageTile.build` returns those as centered
timeline bars before the bubble path (lines 398-500).

### P5.2 Desktop hover toolbar

`room_message_tile.dart`, `_MessageBubbleInteraction` (line 1934) and
`_HoverActionToolbar` (line 2104):

- thread an `onReply` callback from `RoomMessageTile.onReplyPressed`;
- render it as the **first** `IconButton` (`Icons.reply_outlined`,
  `tooltip: l10n.beaconRoomActionReply`, `visualDensity:
  VisualDensity.compact`, `iconSize: 18` to match its siblings);
- **gate with the same predicate as the sheet**: `RoomMessageTile` passes
  `onReply: RoomCubit.canReplyTo(message) ? … : null`, and the toolbar's
  existing `if (onX != null)` pattern hides it. Never render a button that
  deliberately no-ops.

This is what satisfies "works with mouse" without forcing the sheet open.
Secondary-tap → sheet → Reply is the pointer fallback; long-press → sheet →
Reply is the touch path.

### P5.3 Wire the callbacks

- `RoomMessageTile`: `final void Function(RoomMessage message)? onReplyPressed;`
  and `final void Function(String messageId)? onJumpToReply;`.
- `BasicChatBody`: matching `onReply` / `onJumpToReply`, forwarded in the
  `itemBuilder` (line 411).
- `BeaconRoomBody`: `onReply: cubit.startReplyTo`,
  `onJumpToReply: (id) => unawaited(cubit.jumpToRepliedMessage(id))`.

All optional ⇒ no existing call site changes (§0.7).

### P5.4 Shared excerpt helper (client)

New `packages/client/lib/features/beacon_room/ui/util/room_reply_excerpt.dart`:

```dart
String roomReplyExcerpt(RoomMessage parent);            // live message → text
String roomReplyExcerptFor({                            // snapshot fields → text
  required String? excerpt,
  required bool hasAttachments,
  required L10n l10n,
});
```

Precedence: non-blank body/excerpt → it; else `hasAttachments` →
`l10n.beaconRoomReplyAttachmentExcerpt`; else
`l10n.beaconRoomReplyOriginalUnavailable`. Used by **both** the banner and the
bubble so they can never disagree.

**Exit:** `flutter analyze` clean; P5 sheet/toolbar widget tests green.

---

## Phase P6 — Client UI: composer banner, quoted block, highlight

### P6.1 Composer reply banner

`packages/client/lib/ui/widget/basic_chat_body.dart`.

`BasicChatBody` gains `final RoomMessage? replyTarget;` and
`final VoidCallback? onCancelReply;`, forwarded into `BeaconRoomComposer`
(line 506). `BeaconRoomBody` passes `state.replyTarget` / `cubit.cancelReply`.
No `RoomCubit` import in the shared widget (§1).

New private `_ComposerReplyBanner` in the composer `Column` (line 1130),
**above** the pending-attachment strip:

```
┌─────────────────────────────────────────────────┐
│ ▍ Reply to Anna                            [✕]  │  ← 3dp accent, scheme.primary
│ ▍ can you bring the ladder tomorrow…            │  ← 1 line, ellipsis
└─────────────────────────────────────────────────┘
```

- `Row(crossAxisAlignment: CrossAxisAlignment.center)`;
- leading 3dp `DecoratedBox` in `scheme.primary` with a design-system radius
  token (add one to `tentura_radii.dart` if none is ≤ 4dp — §1);
- `SizedBox(width: tt.iconTextGap)`;
- `Expanded(child: Column(crossAxisAlignment: start, mainAxisSize: min))` with
  `l10n.beaconRoomReplyingTo(name)` in
  `textTheme.labelMedium?.copyWith(color: scheme.primary)` and the excerpt in
  `textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)`, both
  `maxLines: 1, overflow: TextOverflow.ellipsis`;
- trailing `IconButton(Icons.close, tooltip:
  MaterialLocalizations.of(context).cancelButtonLabel, onPressed:
  onCancelReply)` — the default `IconButton` already meets the 48dp target;
- outer `Padding(EdgeInsets.only(bottom: kSpacingSmall))`, matching the
  attachment strip (line 1136).

**Responsive:** `Expanded` is the whole mechanism. The banner inherits
`TenturaChatColumn`'s width cap and truncates rather than overflowing at
320dp. There is no layout *switch* here, so no `LayoutBuilder` — adding one
would be cargo cult.

**Esc cancels — but only when there is something to cancel.**
`_handleComposerKeyEvent` (line 579) currently early-returns `ignored` when
`_overlaySuggestions.isEmpty`. Restructure so `escape` is evaluated before
that guard, with this exact precedence:

1. mention overlay open → dismiss it, return `handled`;
2. else `replyTarget != null && onCancelReply != null` → cancel, return
   `handled`;
3. else → return **`ignored`**.

Step 3 matters: `BasicChatBody` is generic chrome and callers may pass a null
`onCancelReply`, and `BeaconRoomBody` passes `cubit.cancelReply` in *both*
main-room and item-thread mode, so an unconditional `handled` would swallow
Escape from every other handler up the tree even with no reply in progress.
(#115 dropped the keyboard AC; this is a cheap courtesy, not a required
deliverable — but it must not regress anything.)

### P6.2 Quoted block in the bubble

`room_message_tile.dart`, inside `coreColumn` — after the author-name header
(line 720) and pinned-fact mark (line 730), **before** the semantic label
(line 731) and body (line 745).

New private `_RoomMessageReplyQuote`:

```
▍ Anna
▍ can you bring the ladder tomorrow morning if you
▍ get a chance…
```

- Same accent-bar structure as the banner; author name in `labelSmall` +
  `FontWeight.w600`; excerpt `maxLines: 2`, ellipsis.
- Inset background `scheme.surfaceContainerHighest.withValues(alpha: 0.5)`
  clipped to `tt.cardRadius`, so it separates from **both** bubble grounds —
  mine (`tt.info @ 0.18`) and theirs (`tt.surface`). Contrast verified in
  light and dark by the P7.3 goldens.
- Tappable `InkWell` → `onJumpToReply(replyToMessageId)`.
- `Semantics(button: true, label: l10n.beaconRoomReplyQuoteA11yLabel(name))`.
- `replyTargetUnavailable` variant: **no `InkWell`**, no author line, excerpt
  replaced by `l10n.beaconRoomReplyOriginalUnavailable` in
  `scheme.onSurfaceVariant`.

**Hazard 1 — hugging width.** The bubble computes a tight width from body and
author text only (lines 907-947) and then adds just the card padding in
`measureBubble` (lines 1102-1127). Measuring the quote's *strings* alone is
not enough: the accent bar (3dp), its gap (`tt.iconTextGap`), and the quote's
own inner horizontal padding are fixed chrome that also consume width.
Define the quote's fixed chrome **once**, as named constants next to the
widget (not inlined at the call site):

```dart
const kRoomReplyQuoteAccentWidth = 3.0;
// tt-derived; see P6.1 for the matching banner values
EdgeInsets roomReplyQuoteInnerPadding(TenturaTokens tt) => …;
```

and expose:

```dart
static double minContentWidth({
  required String authorName,
  required String excerpt,          // FULL excerpt, not just line 1
  required double availableWidth,   // the cap the widget will actually get
  required TextStyle? nameStyle,
  required TextStyle? excerptStyle,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required TenturaTokens tt,
});
```

It must lay the excerpt out with the **same** `TextPainter` configuration the
widget uses — `maxLines: 2`, same styles, same `textScaler`, same
`textDirection`, same `availableWidth` — and take
`max(nameWidth, longestLaidOutLineWidth)`, then add
`kRoomReplyQuoteAccentWidth + tt.iconTextGap +
roomReplyQuoteInnerPadding(tt).horizontal`.

Rev 2 passed only `excerptFirstLine`. With `maxLines: 2` the **second** line
is frequently the wider one, which would size the hugging bubble too narrow
and re-introduce the very clipping this is meant to prevent. Rev 2 also
referenced `quoteInnerPadding` without ever defining it.

Fold the result into `tightTextWidth` next to the existing name-painter block
(lines 935-947). Cover in `room_message_bubble_measure_test.dart`: short body
with a long quote; a quote whose **second** line is wider than its first; RTL
text direction; and `TextScaler.linear(1.6)`.

**Hazard 2 — gesture arena.** The bubble sits inside
`_MessageBubbleInteraction`'s `RawGestureDetector` with a touch-only
`TapGestureRecognizer` for `onOpenItem` (lines 2017-2045). `HitTestBehavior.opaque`
does not prevent descendant hit-testing, but the parent recognizer and the
nested `InkWell` **do** compete in the arena. Prove the resolution with a
widget test on a message that has **both** a linked coordination item and a
reply: tapping the quote must call jump-to-reply and must **not** call
open-item (P7.1).

### P6.3 Highlight on arrival

`BasicChatBodyState.scrollToMessage` (line 160) only scrolls today.

- add a `ValueNotifier<String?> _highlightedMessageId` and a **single**
  `Timer? _highlightTimer`;
- on a successful scroll: `_highlightTimer?.cancel()`, set the notifier, start
  a 1200ms timer whose callback clears **only if** the notifier still holds
  that id (an older timer must never clear a newer highlight);
- dispose both the timer and the notifier in `dispose()` (line 352 currently
  disposes only the scroll controller);
- `RoomMessageTile` gains `final ValueListenable<String?>? highlightedMessageId;`
  (nullable, default null) and wraps **only its own bubble** in a
  `ValueListenableBuilder` + `AnimatedContainer` (180ms) painting
  `tt.attentionHighlight` (token already exists, `tentura_tokens.dart:75`).
  A `setState` on `BasicChatBodyState` would rebuild the whole
  `ListView.builder` and hand every visible tile a changed flag on every
  highlight transition; the notifier confines the rebuild to the target tile;
- **prune `_messageKeys`.** It is `putIfAbsent`-only and never cleaned
  (`basic_chat_body.dart:132,138-139`), so pinned-then-evicted jump targets
  would accumulate `GlobalKey`s for the session. In `didUpdateWidget`, drop
  keys whose id is no longer in `widget.messages`, except the id currently in
  `pendingJumpMessageId` (which is mid-flight and needs its key). This is
  pre-existing debt that pinning would otherwise make worse;
- honour `MediaQuery.disableAnimationsOf(context)` — the tile already reads it
  at line 2015 — by holding a static highlight for the same 1200ms.

This also improves the pre-existing fact-pin / promote-pin jumps.

### P6.4 l10n

New keys in **both** `packages/client/l10n/app_en.arb` and `app_ru.arb`,
placed next to the existing `beaconRoomAction*` block (`app_en.arb:4185`):

| Key | EN | RU |
|---|---|---|
| `beaconRoomActionReply` | `Reply` | `Ответить` |
| `beaconRoomReplyingTo` `{name}` | `Reply to {name}` | `Ответ: {name}` |
| `beaconRoomReplyAttachmentExcerpt` | `Attachment` | `Вложение` |
| `beaconRoomReplyOriginalUnavailable` | `Original message is unavailable` | `Исходное сообщение недоступно` |
| `beaconRoomReplyQuoteA11yLabel` `{name}` | `Reply to {name}, opens the original message` | `Ответ на сообщение {name}, открывает оригинал` |
| `beaconRoomReplyTargetNotLoaded` | `Original message could not be loaded` | `Не удалось загрузить исходное сообщение` |

Then `flutter gen-l10n`.

**Exit:** `./scripts/check-custom-lints.sh packages/client` at or below the
115 baseline; `bash scripts/check-user-facing-terminology.sh` clean.

---

## Phase P7 — Tests, goldens, docs, version

### P7.1 Widget tests

New files under `packages/client/test/features/beacon_room/`:

| File | Asserts |
|---|---|
| `room_message_reply_quote_test.dart` | author + excerpt render; 2-line ellipsis; attachment-only parent shows "Attachment"; `replyTargetUnavailable` renders muted, non-tappable |
| `room_message_reply_tap_test.dart` | tapping the quote invokes jump-to-reply; on a message that **also** has a linked coordination item, open-item is not invoked (P6.2 hazard 2) |
| `room_reply_composer_banner_test.dart` | banner shows name + excerpt; close clears; Esc clears; absent with no target; truncates at 320dp without overflow |
| `room_reply_excerpt_test.dart` | client `roomReplyExcerpt*` precedence table |

Extend `beacon_room_message_actions_sheet_test.dart`: Reply present for a
normal message, absent for a `local:` id.

Extend `room_message_bubble_measure_test.dart`: quote wider than body
(P6.2 hazard 1).

Extend `room_message_reply_tap_test.dart` (or add a
`room_reply_jump_scroll_test.dart`) with the **auto-follow regression**: pump
a chat scrolled to the bottom, inject a pinned historical target plus
`pendingJumpMessageId` in one frame, settle, and assert the final scroll
offset is at the target — not back at `maxScrollExtent` (P3.4).

Add Escape cases to `room_reply_composer_banner_test.dart`: overlay open,
reply target open, neither open (must return `ignored` — assert the key is
**not** consumed), and `onCancelReply == null`.

**Both modes need a harness, not a parameter.** `BeaconRoomBody` has **no**
`threadItemId` constructor argument (`beacon_room_body.dart:35-42`); thread
mode is read from the injected cubit's state (`:200`), and production
establishes it via `itemDiscussionProviders` building a thread-scoped
`RoomCubit` (`item_discussion_pane.dart:18-25`). Rev 2's "parameterize over
`threadItemId: null` and a thread id" is therefore not executable as written.
Instead add a shared
`packages/client/test/features/beacon_room/support/room_body_harness.dart`
that pumps `BeaconRoomBody` under a `BlocProvider<RoomCubit>` holding a test
cubit seeded with `RoomState(threadItemId: …)` plus the `GetIt` registrations
`BeaconRoomBody` needs (`ProfileCubit`, `ImageRepository`,
`ClipboardImageRepository`). Run the banner / quote / jump tests through it
in **both** seedings.

### P7.2 Postgres contract tests (`@Tags(['pg'])`)

New `packages/server/test/data/repository/room_message_reply_readback_pg_test.dart`,
following the existing skip-if-unreachable harness in
`room_message_snapshot_lookup_test.dart`:

- create a reply → stored `reply_to_message_id` matches; `RoomMessageList`
  returns all five fields;
- **parent outside the 50-row window** → snapshot still resolves (this is the
  case a naive in-page join would silently drop);
- **parent author absent from the page's authors** → `replyToAuthorTitle`
  still populated (P1.4 step 3);
- **attachment-only parent** → `replyToBodyExcerpt == null`,
  `replyToHasAttachments == true`;
- `roomMessageTarget` returns the same five fields as `RoomMessageList`;
- **cross-scope isolation** → a hand-inserted row pointing at another beacon's
  message yields id-only, no author/body leak (P1.4 step 2);
- **parent edit** → every visible child quote reflects the new body on the
  next read (proves the read-time join beats an insert-time snapshot), and
  `editMessage` re-notifies **only newly added mentions**, not the reply
  recipient (`beacon_room_case.dart:941-978`);
- **parent delete** → `ON DELETE SET NULL` clears the pointer; the child reads
  back with all five fields null.

### P7.3 Layout assertions (image goldens are disabled repo-wide)

`room_message_tile_layout_golden_test.dart` has **two** groups: the image
goldens (`room message layout goldens`, line 115) are `skip: 'Goldens
disabled'` (line 214), while `room message layout` (line 216) is live and
asserts geometry, not pixels. So:

- **Primary:** add reply cases to the **live** `room message layout` group —
  mine and theirs, each with a quote — asserting the bubble hugs correctly and
  the quote is not clipped at compact width (this is the real regression risk
  from P6.2 hazard 1).
- **Secondary:** add the four light/dark image-golden cases to the skipped
  group so they exist for whenever goldens are re-enabled, but do **not**
  claim quote-contrast is verified by CI — it is not. Verify contrast by hand
  in both themes and record the check in the journal.

Rev 2 said "regenerate with `--update-goldens` and eyeball the PNGs"; against
a skipped group that would have produced nothing.

### P7.4 Realtime / race coverage

Client-side (P4.3) covers paint parsing and own-message deferral. Add a manual
scripted check to the exit checklist using the existing
`scripts/run_realtime_multiclient_web_local.sh` harness:

1. A replies to B's message → B sees the quoted bubble without reloading.
2. B replies to a message far above the window → tapping B's quote scrolls to
   it, and an inbound message from A does **not** yank the target away
   (P3.4 pinning).
3. Reload both clients → quotes survive (P2 round-trip).
4. A deletes the parent → both clients' quotes disappear after refresh, no
   crash, no dangling tap.

### P7.5 Regression posture

By §0.7 every addition is optional/nullable, so **no existing test or golden
should need editing**. If one does, that is a signal the constraint was
violated — fix the signature, not the test. Run the full suites in §2 (not
just the new files) before declaring the phase done.

### P7.6 Docs + version

- `docs/features/beacon_room.md` — the P1.7 paragraph.
- `packages/client/pubspec.yaml`: `5.9.0` → **`5.10.0`** (minor — new
  backward-compatible user-visible capability).
- Run the app once (`flutter run -d chrome` or `flutter build web`) so
  `hook/build.dart` rewrites `packages/client/web/index.html`'s
  `flutter_bootstrap.js?v=5.10.0`, and **commit that diff** (§1).
- `kDefaultMinClientVersion` in `packages/server/lib/env.dart`: **no change**.
  Old clients never send `replyToMessageId` and ignore the new nullable row
  fields. Confirm against the decision table in `DEV_GUIDELINES.md` § Client
  version gate at implementation time.

---

## 8. Out of scope / follow-ups

| Item | Why deferred |
|---|---|
| **Swipe-to-reply gesture** | Collides with platform back-swipe and the "avoid horizontal swipe on main content" rule; sheet + hover toolbar + secondary-tap already satisfy the mouse/touch AC. Revisit with a `PointerDeviceKind.touch`-only `HorizontalDragGestureRecognizer` plus an edge-exclusion zone if users ask. |
| **Reply chains / "N replies" affordance** | The issue asks for a pointer, not threading. Item threads already cover real branching. |
| **Parent excerpt inside the push/Updates body** | `roomMessagePosted` already carries the *reply's* excerpt to the right recipient; showing the *parent's* excerpt is a separate copy change. |
| **Cross-scope quoting** | Server rejects it (`beacon_room_case.dart:227-233`) and that is correct product behaviour. |
| **Transient own-message duplicate on paint-less inserts** | Pre-existing for attachment/poll/linked messages (`room_cubit.dart:517-541`); replies do not make it worse because P1.5 keeps them on the paint path. Worth a separate fix. |
| **Avatar in the quote block** | Name-only keeps the quote to two lines and avoids hydrating parent author images in `listMessagesEnriched` (P1.4 step 3). |

---

## 9. Adversarial review disposition

Reviewer: Codex CLI, read-only, adversarial-reviewer prompt, two rounds.
Every defect was verified against the code before acceptance.

### 9.1 Round 1 (rev 1 → rev 2) — 12 defects, 3 BLOCKER, 6 missing items

| # | Sev | Defect | Disposition |
|---|---|---|---|
| 1 | BLOCKER | "notifies only the replied-to author" is false — `threadItem.targetPersonId` is also in the directed set | **Accepted.** §0.4 rewritten; P1.6 tests both modes with exact recipient counts. |
| 2 | MAJOR | Parent lookup trusted a scope invariant the self-FK does not provide | **Accepted.** P1.4 step 2 filters by `beacon_id` + `thread_item_id IS NOT DISTINCT FROM`; P7.2 has a leak test. |
| 3 | MAJOR | `attachmentsJsonByMessageIds` hydrates every attachment + image to answer a boolean | **Accepted.** P1.3 adds a distinct-id presence query. |
| 4 | MAJOR | "write path already tested" overstated — the stub discards `replyToMessageId` | **Accepted.** §0.3 states the real coverage; P1.6 adds `insertedReplyToMessageId`; P7.2 adds pg readback. |
| 5 | MAJOR | A library-private `_replyExcerpt` cannot be unit-tested from another file; grapheme safety over-promised | **Accepted.** P1.1 makes it a public `domain/util/` function and scopes the promise to **rune** boundaries. |
| 6 | BLOCKER | Excluding replies from the fast paint breaks own-message reconciliation (duplicate, then synthetic-overwrites-authoritative) | **Accepted, with the opposite fix.** Rather than patching around the exclusion, P1.5 **extends** the paint with reply fields, so the deferred-own protocol is untouched. §0.6 records why. |
| 7 | MAJOR | "copy the quote fields from `replyTarget`" would quote the grandparent | **Accepted.** P3.3 gives the explicit field-by-field mapping from the target's own identity; P4.2 adds a reply-to-a-reply test. |
| 8 | MAJOR | Freezed nullable-clear left open; it is settled | **Accepted.** P3.1 states `copyWith(replyTarget: null)` is correct (freezed 3.2.6-dev.1, sentinel `copyWith`, precedent at `room_cubit.dart:263,472`) and deletes the fallback designs. |
| 9 | BLOCKER | `prepareThreadScroll` reuse clobbers pending item nav, no-ops on an empty list, returns no outcome, and its off-window target is discarded by the next messages refresh | **Accepted.** P3.4 is now a dedicated `Future<bool> jumpToRepliedMessage` with a bounded pinned-off-window map re-merged in `_fetchMessagesSnapshot`. |
| 10 | MAJOR | Width fix measured only text, omitting accent bar / gap / inner padding | **Accepted.** P6.2 hazard 1 specifies a `minContentWidth` helper covering all fixed chrome with real styles/scaler/direction. Reviewer's note that `HitTestBehavior.opaque` does not by itself block descendant hit-testing is reflected in the hazard-2 wording. |
| 11 | MINOR | Hover toolbar not gated for `local:` ids | **Accepted.** P3.2 exposes `RoomCubit.canReplyTo`; P5.1/P5.2 both use it; the toolbar receives `null` and hides. |
| 12 | MINOR | Highlight timer had no lifecycle/replacement rule | **Accepted.** P6.3 specifies one timer, cancel-before-replace, cancel in `dispose`, id-guarded clear. |

Missing work items, all folded in: parent edit/delete pg tests (P7.2);
repository + `roomMessageTarget` contract tests including off-window parent,
off-page author, attachment-only parent, cross-scope isolation (P7.2);
realtime race tests (P4.3, P7.4); the `_FakeBeaconRoomRepository` scaffolding
fix (P4.1); thread-mode parameterization of the UI tests (P7.1); and the
"keep everything optional so nothing existing breaks" constraint made explicit
(§0.7, P7.5).

One reviewer aside is recorded but **not** actioned: it noted there is no chat
forwarding surface to reuse and that `ForwardRepository` is unrelated. Correct
— the plan never proposed touching it.

**Found while verifying rev 2 (not by the reviewer):** rev 2's own P3.4
pseudo-code assumed `fetchMessageTarget` returns `null` for a missing or
unauthorized message. It does not — it resolves through `dataOrThrow` and the
server case throws. P3.4 now wraps the call in `try`/`catch` and P4.2 tests the
throwing path.

### 9.2 Round 2 (rev 2 → rev 3) — 11 defects, 1 BLOCKER, 6 missing items

Round 2 was scoped to rev 2's *new* material, with §9.1's accepted corrections
declared off-limits unless the correction itself was wrong.

| # | Sev | Defect | Disposition |
|---|---|---|---|
| 1 | BLOCKER | The P3.4 jump is undone within a frame by existing auto-follow: adding a pinned row grows `messages.length`, and `didUpdateWidget` hard-jumps to the bottom when the user is near it (`basic_chat_body.dart:330-349`) — which is the normal case for tapping a quote | **Accepted.** P3.4 adds `pendingJumpMessageId` to `BasicChatBody`, emitted in the *same* emit as the pinned row, suppressing auto-follow until the jump resolves; failure now also clears it so auto-follow cannot wedge off. P7.1 adds a scroll-offset regression test. |
| 2 | MAJOR | Rev 2's merge order was backwards — `_dedupeMessages` is last-wins, so `[...refreshed, ...pinned]` lets the **stale pin** win, exactly the opposite of the stated rationale | **Accepted; this was my error, not the reviewer's.** P3.4 merges pins **first**; P4.2 asserts a refreshed row replaces a pin. |
| 3 | MAJOR | Pins were merged only in `_fetchMessagesSnapshot`; `_fetchFullSnapshot` (used by realtime catch-up) would drop the jump target on reconnect | **Accepted.** P3.4 introduces one `_mergeMessages` routine used by both paths. |
| 4 | MAJOR | A pinned historical row silently pollutes `unreadCount` / `firstUnreadMessageId` / the divider / the FAB badge — and with `unreadAnchorAt == null` everything is unread, so the old row becomes *first* unread (`room_state.dart:46-82`) | **Accepted.** `RoomState.pinnedJumpMessageIds` excludes navigation-only rows from unread derivation; P4.2 asserts it. |
| 5 | MAJOR | `sendMessage` captures `target`, awaits, then clears `state.replyTarget` unconditionally — wiping a *newer* target the user selected mid-flight | **Accepted.** P3.3 clears only when `state.replyTarget?.id == target?.id`; P4.2 adds a completer-gated race test. |
| 6 | MAJOR | "two extra queries" was false — P1.5 specified three (parent, author, attachments) | **Accepted.** P1.5 now specifies a parent ⋈ user **join**, which makes "two" true, and says so explicitly. The reviewer's confirmation that the lookup runs once before the fan-out loop is recorded. |
| 7 | MAJOR | `minContentWidth` took only `excerptFirstLine` though the quote allows 2 lines (the second is often wider), and `quoteInnerPadding` was never defined | **Accepted.** P6.2 names the chrome constants and measures the full excerpt with the widget's own `TextPainter` config; tests add wider-second-line, RTL, and 1.6× text-scale cases. |
| 8 | MINOR | Escape returned `handled` even with no overlay and no reply target, swallowing the key from other handlers; `onCancelReply` may be null | **Accepted.** P6.1 specifies a three-step precedence ending in `ignored`; P7.1 tests all four states. |
| 9 | MINOR | `_messageKeys` never prunes (pinning makes it worse), and a `setState`-driven highlight rebuilds the whole list | **Accepted.** P6.3 switches to a `ValueNotifier` consumed per-tile and prunes keys in `didUpdateWidget`, preserving the in-flight target. |
| 10 | MINOR | "wrong-typed field rejects the whole paint" was described as the existing convention; only `editedAt` behaves that way | **Accepted.** P2.5 reframes it as a deliberate new contract and adds both version-skew tests. |
| 11 | MAJOR | "parameterize tests over `threadItemId`" is not executable — `BeaconRoomBody` has no such argument; mode comes from the injected cubit | **Accepted.** P7.1 specifies a shared `room_body_harness.dart` seeding a test cubit in both modes. |

Round-2 missing items, all folded in: race tests (newer target during send,
catch-up after jump, refreshed row replacing a pin, scroll surviving
auto-follow) → P4.2/P7.1; unread/FAB/divider/watermark assertions → P4.2; LRU
eviction and key pruning tests → P4.2/P6.3; quote measurement for wider second
line, RTL, and text scaling → P6.2/P7.1; the four Escape states → P7.1; and
old-server/new-client plus new-server/old-client payload tests → P4.3.

**Round-2 findings the reviewer explicitly cleared as sound** (recorded so
they are not re-litigated): `findEligibleInsert` is called once per fan-out
event and has the scope data it needs; reply paint ids remain valid dedup
keys with no inherent flicker; item-thread cubits are created per item and not
reused; and §0.7's "no existing golden shifts" holds — the quote is
conditional, a non-highlighted wrapper is layout-neutral, and the image-golden
group is skipped anyway (which itself corrected P7.3, see §9.2 note below).

**Also surfaced in round 2:** `room_message_tile_layout_golden_test.dart`'s
image-golden group is `skip: 'Goldens disabled'` (line 214). Rev 2's P7.3
instructed regenerating PNGs that would never be produced; P7.3 now puts the
real assertions in the live `room message layout` group and is explicit that
quote contrast is a manual check, not CI-verified.

Every line-number citation in this plan was re-checked against the working
tree on 2026-08-10.
