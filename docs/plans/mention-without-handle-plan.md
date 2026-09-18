---
status: draft
kind: plan
---

# Mentioning a participant with no `@handle` (id-anchored text mentions)

**Status:** draft, rev 2. One adversarial review round by Codex CLI (`gpt-5.6-sol`)
against rev 1: 7 blockers, 1 high. All eight are folded in below — §0.7 records
what changed and why, so the corrections are not silently re-lost the way an
unlogged fix would be.
**Scope:** client composer + client rendering + server write path + server
GraphQL wire + realtime paint, for: a participant who has never set a public
`@handle` currently cannot be `@`-addressed in a Chat at all. This plan adds a
second, id-anchored mention channel ("text mention", after Telegram's own name
for the same mechanism) that coexists with the existing `@handle` channel
without changing it.
**Explicitly not in scope:** auto-generating a handle for handle-less users
(rejected — §0.3), tap-to-profile navigation on a mention (neither channel has
this today — §3 D8), fixing the two duplicate handle-format-constant
definitions (§0.6), retiring the apparently-dead
`RoomState.participantsMatchingQuery` twin (§0.6), **adding or removing an
explicit mention while editing an existing message** (rev 2 narrowing — §3 D13:
the live edit UI is a plain text sheet with no mention machinery at all;
teaching it one is a separate, larger piece of work than this plan's core
problem).

---

## 0. Why this plan exists

### 0.1 The problem

`Profile.handle` / `BeaconParticipant.handle` is deliberately optional — a
5–30-char (doc comment says 5–30; the actually-enforced range is 3–30, see
§0.6) `[a-z0-9_]` slug a user may or may not set
(`packages/client/lib/domain/entity/profile.dart:26-27`). Today the entire
`@`-mention mechanism is keyed off that field. A participant who never set one
is invisible to `@`-completion and cannot be mentioned by anyone, ever, in any
Chat.

### 0.2 How mentioning works today (verified against live code)

**The wire contract is "type the literal token, let the server re-parse it."**
Nothing about a mention is sent explicitly by the client — not today.

| Layer | Fact | Where |
|---|---|---|
| Schema | `beacon_room_message.mentions text[]` — user ids, doc: *"server-resolved from @handle in body"* | `packages/server/lib/data/database/table/beacon_room_messages.dart:47-50` |
| Server resolution | `resolveMentionUserIdsForBeacon(beaconId, body)` re-parses the **raw body string** on every create *and every edit* with `RegExp('@([a-zA-Z0-9_]{3,30})')`, matches case-insensitively against **admitted participants'** current handles, returns the id set | `packages/server/lib/utils/room_mention_utils.dart` (regex); `packages/server/lib/data/repository/beacon_room_repository.dart:762-793` (resolution); called from `beacon_room_case.dart:254` (create) and `:970` (edit) |
| GraphQL write | `RoomMessageCreate(beaconId, body, replyToMessageId, threadItemId, file)` / `RoomMessageEdit(beaconId, messageId, body)` — **no mentions argument exists**, client never sends one | `packages/server/lib/api/controllers/graphql/mutation/mutation_beacon_room.dart:58-149`; confirmed by both client `.graphql` documents under `packages/client/lib/features/beacon_threads/data/gql/` |
| Client autocomplete | `participantsMatchingMentionQuery` requires `roomAccess == admitted && p.handle.isNotEmpty` — a handle-less participant **never appears** in the `@`-suggestion list | `packages/client/lib/features/beacon_threads/ui/widget/participants_matching_mention_query.dart` |
| Client insertion | `MentionTextController.insertMention(handleLowercase)` always inserts literal `'@$handleLowercase '` | `packages/client/lib/features/beacon_threads/ui/widget/mention_text_controller.dart:73-90` |
| Client rendering | Per message render, `room_message_tile.dart:641-658` rebuilds `handleToUserId` from the **current** room participant list, intersects with that message's `mentions` id list, and `buildRoomMessageMentionAnnotations` recolors any `@[a-zA-Z0-9_]{3,30}` regex match whose lowercased handle is a key in that map | `packages/client/lib/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart:118-149` |
| Notification copy | Push/notification body is the **raw message excerpt**, unmodified — whatever literal text is in the body is what a reader sees, verbatim | `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart:153-155` |
| Edit UI | Editing opens `_BeaconRoomTextBottomSheet`, a **plain text sheet** — `initialText: message.body`, returns a bare `String`, no `MentionTextController`, no suggestion overlay | `packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart:738-760`; `RoomCubit.editMessage`/`BeaconThreadsCase.editMessage` carry only `newBody`, nothing structured |
| Message body renderer | Two **mutually exclusive** branches: `RoomMessageTextBody` (inline trailing-meta, only when `reactionCounts.isEmpty`) vs `ShowMoreText` (Tentura's own subclass of the `readmore` package's `ReadMoreText`, used whenever there is at least one reaction) | `packages/client/lib/features/beacon_threads/ui/widget/room_message_tile.dart:797-817`; gate at `room_message_trailing_meta_layout.dart:30-33`; `packages/client/lib/ui/widget/show_more_text.dart:6` |
| Tight-width measurement | Builds its **own** body span directly via `buildRoomMessageAnnotatedBodySpan`, independent of which renderer branch is chosen | `room_message_tile.dart:1024-1047` |

Two consequences worth naming up front because this plan's design leans on
both:

1. **Rendering is a live re-match, not a stored fact.** A message's
   highlighted-mention appearance is recomputed from the room's *current*
   participant handles every time it renders. If a participant changes or
   clears their handle, every past message that mentioned them silently stops
   highlighting — the literal text is still there, the link is gone. This
   plan's new channel does not have this bug (§3 D7), which is a real
   improvement, not just parity.
2. **Nothing about a mention is structured on the wire.** `mentions` is a
   flat, order-less `text[]` of ids with no positions. There is no existing
   "send an explicit mention" precedent to imitate for the *argument shape* —
   the closest live precedent for "a small structured list attached to a
   message, computed server-side, JSON-encoded, parsed client-side" is
   `attachmentsJson` (§0.5), not `mentions` itself.

### 0.3 Why not just auto-generate a handle for everyone (rejected)

The obvious cheap fix — mint a private, never-shown, always-present slug for
handle-less users and let the existing `@handle` machinery pick it up
unchanged — was considered and rejected. It reduces to a real defect: the
notification/push copy path renders the **raw body text verbatim**
(`beacon_notification_copy_builder.dart:153-155`). A handle chosen by a human
(`@alice_baker`) reads fine in a push notification. An opaque generated key
(`@x7f3q9k2p`) does not, and would leak into every push notification, digest,
and future export that touches raw body text. A meaningful display name typed
into ordinary body text has no such problem — this is the actual reason the
plan below keeps the message `body` as plain, fully human-readable text and
carries the mention *linkage* on a side channel instead of encoding identity
into an opaque wire token.

### 0.4 Design in one paragraph (rev 2)

The composer gains a second way to insert a mention: picking a **handle-less**
suggestion inserts their **display name**, prefixed with `@` for visual parity
with the handle case (`'@Bob Smith '`), as ordinary text. The controller that
owns the text field **tracks the exact character range of every mention it
inserted, live, through every subsequent keystroke** (§3 D3/D-rev2), so the
client always knows precisely which offsets are mentions — it never has to
re-search for them. At submit time it sends three parallel arrays —
`explicitMentionUserIds`, `explicitMentionOffsets`, `explicitMentionLengths` —
alongside `body`. The server validates each triple (admitted participant,
in-bounds, non-overlapping, and the substring it names must equal that
participant's real display name or handle — never arbitrary text) and stores
the accepted, offset-resolved list in a new `mentionSpans` column — purely for
rendering. The existing `mentions` id column keeps meaning exactly what it
means today (union of the old regex-derived ids and the new explicitly-claimed
ids) so every downstream consumer — the Postgres realtime-fan-out trigger,
attention intents, notification copy — needs **zero changes**.

### 0.5 The shape precedent to copy: `attachmentsJson`, not `mentions`

`RoomMessageAttachment` is the live precedent for "a small ordered list of
structured facts about one message, computed server-side, shipped as a single
JSON-string GraphQL field, defensively parsed client-side, degrading unknown/
malformed entries rather than throwing":

- Server: `attachmentsJsonByMessageIds` builds it once per read
  (`beacon_room_repository.dart:81-84`), the row map emits
  `'attachmentsJson': attachmentsJsonByMid[id] ?? '[]'`
  (`beacon_room_repository.dart:467`), typed `graphQLString.nonNullable()` in
  the schema.
- Client: `parseRoomMessageAttachmentsJson(String raw)`
  (`packages/client/lib/domain/entity/room_message_attachment.dart:33-79`) —
  type-checks every field, `continue`s (drops) a malformed entry instead of
  throwing.

`mentionSpans` copies this shape exactly, **including the non-null typing on
both sides** (rev 1 mismatched this — client nullable, server non-null;
corrected in §7–§8). `mentions` (the flat id array) is left completely alone —
it is the input to the realtime Postgres trigger (`notify_entity_change()`,
re-declared across migrations m0055 through m0133 each time other schema
evolves) and to `attention_intent_case.roomMentioned` (§0.2), and touching
either is out of scope and unnecessary.

### 0.6 Two things noticed in passing, deliberately not fixed here

- `packages/server/lib/consts/user_handle_consts.dart` and the canonical
  `kUserHandleRegExp` in the root `tentura_root` package (`lib/consts.dart:15-26`)
  are two independent definitions of the same 3–30 `[a-z0-9_]` bound,
  currently in sync. A latent drift risk, not this plan's problem to fix.
- `RoomState.participantsMatchingQuery` (`room_state.dart:106-124`) is a
  structurally identical twin of `participantsMatchingMentionQuery` with, as
  far as a full-repo grep can tell, zero callers outside its own definition —
  looks dead. §9.1 touches the live one only; do not "helpfully" update the
  dead twin to match — verify it is still dead first if you touch it at all,
  and prefer leaving it alone.

### 0.7 What changed in rev 2, and why

Codex CLI (`gpt-5.6-sol`) reviewed rev 1 against live code and found 7
blockers + 1 high defect, recorded in full at
`docs/plans/mention-without-handle-review-sol.md`. Summary of what each
forced:

1. **D2/D4 self-contradiction** — rev 1's validation compared the claimed text
   *without* `@` against a token the composer inserted *with* `@`, so every
   handle-less mention would have been rejected. Fixed by making both sides
   agree on the `@`-prefixed canonical token (§3 D2/D4, §5.2).
2. **Duplicate-display-name identity loss** — rev 1 tracked pending mentions
   by `(userId, text)` and re-searched `body` for a surviving occurrence at
   submit time, which cannot tell two same-named participants' mentions apart
   under deletion/reordering. Fixed by switching to **live, position-tracked**
   mentions in `MentionTextController` (§3 D-rev2, §9.2) — the client always
   knows the exact offset, never searches. This also let the server-side
   algorithm drop its own text-search entirely (see point 7).
3. **Only one of two live render branches was wired up**, and reactions force
   the *other* one (`ShowMoreText`, which the `readmore` package renders
   internally from regex `Annotation`s only — it accepts no precomposed span).
   Tight-width measurement was also left calling the untouched function
   directly. Fixed in §10 with an explicit branch for the has-explicit-mention
   + has-reactions combination, and a matching fix to the width-measurement
   call site.
4. **The edit UI is not the composer** — rev 1's edit-preseed logic targeted
   `BeaconRoomComposer`/`MentionTextController`, but editing opens a plain
   text sheet with none of that machinery, so every edit of a message with
   explicit mentions would have silently dropped them. Fixed by **narrowing
   scope** (§3 D13): editing cannot add/remove explicit mentions in this plan;
   the server preserves existing ones across an edit unless the edited text no
   longer contains them, using the same validator that governs create (§5.3).
5. **Realtime snapshot timing** — rev 1 said to hand `claimedSpans` computed
   inside `createMessage` across to the snapshot lookup, but that lookup runs
   later, independently, over a fresh DB re-read
   (`websocket_path_entity_changes.dart:46-73` →
   `room_message_snapshot_lookup.dart:17-23,65-79`) with no access to that
   in-memory value. Fixed in §6: the persisted `mention_spans` column is the
   sole source for the snapshot, read back like every other field it already
   reads.
6. **Missing domain layers + wrong GraphQL type edited** — rev 1 skipped
   `BeaconRoomRepositoryPort`, `BeaconRoomMessageRecord`, and the Drift↔domain
   mapper, and told the implementer to edit "every occurrence" of
   `attachmentsJson` in `custom_types.dart`, one of which belongs to fact
   cards, not room messages. Fixed with an explicit port/record/mapper phase
   (§4.4) and a corrected, single-target GraphQL edit (§7.2).
7. **Unbounded, quadratic claim processing** — rev 1's `explicitMentionTexts`
   channel had no length cap and searched `body` per candidate. Superseded
   entirely by the position-tracking redesign (point 2): the server no longer
   searches at all (candidates arrive with their own offsets), and a hard cap
   (`kMaxExplicitMentionsPerRoomMessage`, §5.1) bounds the validator's
   O(n²) overlap check to a small constant.
8. **Unvalidated offsets before `substring`** — rev 1's parser didn't reject
   negative/fractional/out-of-bounds spans before the compositor sliced by
   them. Fixed by making the compositor itself the single defensive
   validation point (§10.1), regardless of what produced the span list.

---

## 1. Rules (repo-wide invariants — read before editing)

From `AGENTS.md` and `.cursor/rules/`, restated because they bind every phase
below:

- **Never edit generated files** (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, anything under `_g/`). Run codegen instead.
- **Dependency direction inward:** ui → data → domain. Repositories return
  domain entities, never raw Ferry/GraphQL types. Server use cases import
  `domain/port/` only — this is exactly the layer rev 1 skipped (§0.7 point 6)
  and §4.4 restores.
- **Design system only in `features/**`/`ui/**`:** no raw `Color`,
  `TextStyle(...)`, inline `fontSize:`. Use `context.tt`, `Theme.of(context)`.
  The new mention-span styling (§10) must reuse the *existing*
  `mentionColor`/`selfMentionBackground` tokens already threaded into
  `buildRoomMessageMentionAnnotations` — do not invent new ones.
- **Terminology:** user-facing **Chat**/**Request**; code paths stay
  `beacon_room`/`beacon`. `bash scripts/check-user-facing-terminology.sh`
  gates it.
- **`packages/client/lib/data/gql/schema.graphql` is hand-maintained.** New
  server fields/arguments must be added there manually before `build_runner`
  accepts them in a query document.
- **Custom lints do not fire under `flutter analyze`.** Use
  `./scripts/check-custom-lints.sh packages/client` /
  `packages/server` and compare against the current baseline, not zero.
- **Client version bump mandatory** for any user-visible change, with
  `packages/client/web/index.html`'s `flutter_bootstrap.js?v=` synced in the
  same commit.
- **Server ships before client** for any wire-contract-widening change. The
  new mutation arguments and `mentionSpansJson` field are additive/optional
  (all default to absent/empty on the old code path), so an **old client
  talking to the new server behaves exactly as it does today** — this is what
  makes that sequencing safe here.

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
dart test                                                                  # root tentura_root package
```

---

## 3. Decisions this plan makes

Read this section before any phase — the phases assume these are settled.

**D1 — Wire shape: three parallel arrays, not a nested input object.** Every
existing mutation argument in this codebase is a flat scalar or a flat list
(`InputFieldString`, `InputFieldStringList` — see
`packages/server/lib/api/controllers/graphql/input/_input_types.dart:72-87`,
already used for `RoomPollCreate`'s `variants`). There is **no existing
`GraphQLInputObjectType` anywhere in this codebase** (repo-wide grep for
`InputObjectType` returns nothing). `explicitMentionUserIds: [String]`,
`explicitMentionOffsets: [Int]`, `explicitMentionLengths: [Int]` — three
same-length, positionally-paired lists — reuse `InputFieldStringList`
verbatim and require one new, equally small `InputFieldIntList` mirroring it
1:1 (no `InputFieldIntList` exists yet; `InputFieldInt`, singular, does —
`_input_types.dart:146-147` — mirror `InputFieldStringList`'s shape with
`graphQLInt` in place of `graphQLString`).

**D2 — Anti-spoof rule: claimed text must equal the mentioned participant's
real name, `@`-prefixed.** A client that names an arbitrary substring of
`body` as "Carol's mention" must not be able to make that substring render as
a tappable-looking, highlighted, notifying link to Carol's account — that
would be a strictly worse griefing primitive than today's (typing `@carol
you're an idiot` at least shows the real handle in the link). The server
rejects (drops, does not error the whole send — D6) any explicit-mention
proposal whose `body.substring(offset, offset+length)`, trimmed and
lowercased, is not equal to `'@' + displayName.trim()'` or `'@' +
handle.trim()'` (also trimmed/lowercased) for the named participant. **This
must match D4's insertion convention exactly** — rev 1 broke this by
validating the bare name against a token that included `@` (§0.7 point 1);
there must be exactly one canonical token shape, used identically by
insertion (§9.2), validation (§5.2), and the shared validator (below).

**D3 — Client-side, mentions are tracked live by position, not re-searched at
submit time.** This supersedes rev 1's "shared claiming function that
searches `body` for surviving text" design, which could not tell two
same-named participants' mentions apart (§0.7 point 2). Instead,
`MentionTextController` maintains a list of **committed mention ranges** —
`{userId, start, end}` — updated on every text change via a prefix/suffix diff
(§9.2, exact algorithm given there) that shifts unaffected ranges and drops
any range the edit touched. The client therefore always knows the *exact*
current offset of every mention it inserted; it never searches `body` for
text at submit time.

**D4 — Inserted/claimed text always includes the leading `@`.** The composer
inserts `'@' + displayName.trim()'` (not the bare name). Visual parity with
the existing handle-mention convention (both read as `@Something` in the chat
bubble), and it keeps the render-boundary clean — an un-prefixed name would
leave a stray unstyled `@` character sitting next to the styled span.

**D5 — `mentions` (existing column) = regex-derived ids ∪ validated explicit
ids.** Nothing downstream of that union — the Postgres trigger, attention
intents, notification copy, unread/mention badges — needs to know or care
which half of the union a given id came from. Zero changes to any of those
consumers.

**D6 — Invalid, out-of-bounds, overlapping, or content-mismatched explicit
proposals are dropped silently, never fail the send.** Consistent with how a
stray `@nobody` in body text today just fails to resolve and the message
still sends.

**D7 — Rendering is a two-stage compose: index-slice first, reuse the
existing regex compositor only on the plain-text remainder — applied to
*both* live body-renderer branches, not just the inline-meta one.** The
rejected simpler alternative ("just add one more regex `Annotation` per
explicit span") is recorded in full detail at the end of this section because
a reviewer independently re-derived and confirmed the same failure mode rev 1
already knew about, and it is worth keeping visible rather than re-litigated.

*Rejected: "just add one more regex `Annotation` per explicit span."*
`Annotation` and the merge engine
(`buildRoomMessageAnnotatedBodySpan`/`_mergeMentionRegexPatterns`,
`room_message_trailing_meta_layout.dart:151-248`) come from the third-party
`readmore` package (confirmed by reading
`~/.pub-cache/hosted/pub.dev/readmore-3.0.0/lib/readmore.dart` directly) —
`Annotation.spanBuilder` receives only the matched **text** and a `TextStyle`,
never a `Match`/capture-group, and the merge function ORs every annotation's
pattern into **one** alternation regex scanned in a **single**
`data.splitMapJoin` pass. Anchoring an explicit span's pattern to its exact
offset with `^.{N}(literal)` finds the right substring for the first matched
`^`-anchored annotation in the alternation — but `^` without the multiline
flag matches **only true string position 0**, so a message with two or more
explicit mentions breaks: only the first one's pattern can ever match; the
rest silently never fire. Lookbehind (`(?<=...)`) was also considered and
rejected on cross-target (dart2js/dart2wasm/VM) portability grounds.

*What this plan does instead — and where it actually plugs in (rev 2
correction).* `room_message_tile.dart` has **two mutually exclusive body
renderers** (§0.2), and `readmore`'s `ReadMoreText`/`ShowMoreText` — confirmed
by reading its source directly — takes only `data: String` and
`annotations: List<Annotation>?`; it does its own internal trimming and
regex-annotation pass and **exposes no hook to accept a precomposed span**.
So the two-stage compositor cannot be plugged into the `ShowMoreText` branch
at all. §10 handles this with an explicit branch rather than pretending one
function change covers both renderers:

- **`mentionSpans.isEmpty`** (the overwhelming majority of messages): both
  branches render **exactly as they do today** — `RoomMessageTextBody` via
  the unmodified `buildRoomMessageAnnotatedBodySpan`, `ShowMoreText` via its
  own unmodified regex annotations. Zero behavior change, zero added cost.
- **`mentionSpans.isNotEmpty` and the inline-meta branch applies** (no
  reactions): use the new two-stage compositor (§10.2) inside
  `RoomMessageTextBody`, exactly as originally designed.
- **`mentionSpans.isNotEmpty` and reactions are present** (so `ShowMoreText`
  would otherwise be chosen): render the composed span in a plain
  `Text.rich` (mirroring `RoomMessageTextBody`'s own use of `Text.rich`,
  `room_message_text_body.dart:54-63`), **skipping `ShowMoreText`'s
  trim/expand-collapse behavior entirely** for that message. This is a
  deliberate, named scope limitation, not a silent gap: a message that both
  has a handle-less mention *and* at least one reaction *and* is long enough
  to normally trigger "read more" will show in full rather than truncated.
  Building span-aware truncation into `ShowMoreText` is a reasonable follow-up,
  out of scope here — the alternative (reimplementing `ReadMoreText`'s
  trim/expand state machine from scratch to make it span-aware) is
  disproportionate to this plan's actual goal.

Tight-width measurement (`room_message_tile.dart:1024-1047`) currently builds
its own body span via `buildRoomMessageAnnotatedBodySpan` unconditionally.
§10.3 makes it branch identically to the render call site — same
`mentionSpans.isEmpty` check, same compositor call when non-empty — so the
tree that gets measured is always the tree that gets painted.

**D8 — No tap-to-navigate on a mention, either channel.** Grepped
`room_message_tile.dart` for `TapGestureRecognizer`/`onTap` near the mention
rendering call sites: there is none. Today's `@handle` mentions are
**style-only** — colored/bold text, not a link. The new explicit-mention
spans match that.

**D9 — Autocomplete admits a participant with a handle *or* a display name;
excludes only participants with neither.** `Profile.needEdit`/
`needsDisplayNamePrompt` (`profile.dart:112-116`) confirms `displayName` can
legitimately be empty (a very freshly joined participant). Such a participant
truly cannot be named by text yet — correctly still excluded.

**D10 — A hard cap bounds the explicit-mention channel.**
`kMaxExplicitMentionsPerRoomMessage` (§5.1) — enforced by truncating the three
incoming arrays to this length **before** any validation work, at the same
place `kMaxRoomMessageAttachments = 10`
(`packages/server/lib/consts/beacon_room_consts.dart`) already bounds
attachments. This exists specifically because the wire arguments are public
and attacker-reachable by any admitted participant, independent of the
message-body length cap (`kMaxRoomMessageBodyLength = 4000`,
`beacon_room_consts.dart`) which does not bound *list* length.

**D11 — Explicit-mention proposals never trigger a text search.** The
server-side validator (§5.1) takes offsets and lengths **as given** by the
client, checks bounds/overlap/content-match by direct `substring`, and never
calls `indexOf`. This is what keeps validation O(cap) instead of O(cap ×
body length) (§0.7 point 7), and is a direct consequence of D3.

**D12 — Persisted spans are re-validated at the point of use, not trusted by
provenance.** The compositor (§10.1) defensively checks every span's bounds
against the *actual* `body` it is about to slice, drops anything invalid, and
never calls `substring` on an unchecked range — regardless of whether the
span came from a fresh GraphQL read, a realtime paint, or (hypothetically) a
future backfill/migration that forgot to run the validator (§0.7 point 8).

**D13 — Editing a message cannot add or remove explicit mentions in this
plan; existing ones survive an edit unless the edited text no longer contains
them.** The live edit UI (`_BeaconRoomTextBottomSheet`) is a bare text sheet
with no `MentionTextController`, no suggestion overlay, and no structured
return value (§0.2, §0.7 point 4) — giving it mention-authoring capability is
a second UI surface's worth of work, disproportionate to this plan's actual
goal. Instead: the edit mutation gains one more argument,
`explicitMentionsProvided: bool` (default `false` — see the note in §5.3 on
why collapsing "omitted" and "explicit `null`" to the same meaning is safe
*here*, unlike the input-omission hazard flagged in
`docs/plans/availability-review-codex.md` for a *different* field). When
`false` (what the current, unaware edit sheet always sends), the server
**preserves** the message's existing `mentionSpans`, but re-validates each one
against the *new* body through the exact same validator used for create — an
untouched mention's substring still matches, so it survives automatically; an
edited-over one no longer matches and is silently dropped. When `true` (not
reachable by any UI in this plan; reserved for whenever a future plan gives
the edit sheet real mention-authoring), the three arrays are authoritative and
fully replace, exactly like create. **Out of scope:** a user cannot add a new
explicit mention while editing, nor can they see or edit which explicit
mentions survive — only "type over the mention text to remove it" is
available, matching how removing a `@handle` mention today already works (delete
the token, it stops resolving).

---

## 4. Server: schema

### 4.1 Migration

Latest migration on disk as of this writing is `m0151.dart`
(`packages/server/lib/data/database/migration/`). **Verify this is still
current before picking a number** — `ls
packages/server/lib/data/database/migration/ | sort -V | tail -3` and check
`_migrations.dart`'s registration list, which needs **both** a `part
'mNNNN.dart';` line and an entry in the ordered list.

New migration `m0152.dart`:

```sql
ALTER TABLE beacon_room_message
  ADD COLUMN mention_spans jsonb;
```

Nullable, no default at the SQL level (mirror `system_payload`'s own nullable
jsonb column exactly — same table, same shape, §4.2). **Do not touch**
`mentions text[]` or the `notify_entity_change()` trigger function — this
column is invisible to both; the realtime fan-out and every notification
consumer keep working unmodified (§0.5, §3 D5).

### 4.2 Drift table

`packages/server/lib/data/database/table/beacon_room_messages.dart` — add,
next to `systemPayload` (line 35-37), mirroring its exact declaration:

```dart
  late final mentionSpans = customType(
    PgTypes.jsonb,
  ).nullable()();
```

### 4.3 Constant

`packages/server/lib/consts/beacon_room_consts.dart` — add next to
`kMaxRoomMessageAttachments`, matching its doc-comment style:

```dart
/// Max explicit (id-anchored, handle-less) mentions accepted per message.
/// Bounds `explicitMentionUserIds`/`Offsets`/`Lengths` list length — these
/// are public, attacker-reachable arguments independent of body length.
const kMaxExplicitMentionsPerRoomMessage = 20;
```

### 4.4 Domain layers — port, record, mapper (rev 2: this whole subsection is
new; rev 1 omitted it entirely and would not have compiled)

Four files, in dependency order, all mirroring how `mentions` (the sibling
field already on every one of them) is already threaded through:

1. **`packages/server/lib/domain/entity/beacon_room_record.dart`** —
   `BeaconRoomMessageRecord` gains
   `this.mentionSpans = const []` in the constructor and
   `final List<Map<String, Object?>> mentionSpans;` as a field, positioned
   next to `final List<String> mentions;`.
2. **`packages/server/lib/data/repository/mappers/coordination_row_mappers.dart`**
   — `BeaconRoomMessageRowMapper.toRecord()` (currently lines ~34-50) gains
   `mentionSpans: (mentionSpans as List?)?.cast<Map<String, Object?>>() ??
   const []` (mirror however `mentions: List<String>.from(mentions)` on the
   line right above it actually casts the Drift jsonb column's runtime
   type — verify against the live `mentions`/`systemPayload` casts in this
   exact function rather than assume the cast shown here is precisely right;
   the jsonb column decodes to a dynamically-typed `List`/`Map` and needs the
   same defensive cast style already used for `systemPayload` two lines
   above).
3. **`packages/server/lib/domain/port/beacon_room_repository_port.dart`** —
   `insertRoomMessage` (currently lines 79-90) gains
   `List<Map<String, Object?>> mentionSpans = const []`, positioned after
   `List<String> mentions = const []`. `updateMessage` (currently lines
   203-207) gains `List<Map<String, Object?>> mentionSpans = const []` (its
   `mentions` parameter is `required`, not defaulted — match that: **required**
   here too, since §5.3 always computes a spans list to pass, even when it is
   the preserved/re-validated one).
4. **`packages/server/lib/data/repository/beacon_room_repository.dart`** —
   the concrete `insertRoomMessage` (currently lines 629-659) threads
   `mentionSpans: Value(mentionSpans)` into `createReturning`, mirroring
   `mentions: Value(mentions)` on the line right above it. Find and update
   `updateMessage`'s concrete implementation the same way (grep
   `Future<void> updateMessage(` in this file — not cited with a line number
   here because it was not read in this research pass; verify its current
   shape mirrors `insertRoomMessage`'s `mentions` handling before editing).

**Do this subsection before §5** — the use case cannot pass `mentionSpans`
anywhere until this chain exists end to end.

---

## 5. Server: write-path resolution (create + edit)

### 5.1 Shared validator

Add `lib/domain/mention_span_validation.dart` to the root `tentura_root`
package (flat, alongside `enums.dart`/`availability.dart` — that package's
existing layout has no `domain/util/` subfolder to match, don't invent one).
Contents, verbatim:

```dart
/// One caller-validated-elsewhere-for-admission candidate: the server (or,
/// for the create-time optimistic echo, the client) already knows [userId]
/// and proposes that [body] contains their mention at [offset]..[offset +
/// length]. This function does no participant lookup and no text search —
/// see `acceptableTokensForUserId`.
typedef ExplicitMentionProposal = ({String userId, int offset, int length});

typedef ValidatedMentionSpan = ({String userId, int offset, int length});

/// Validates and de-overlaps client-proposed explicit-mention ranges against
/// [body]. No I/O: participant lookup is the caller's job via
/// [acceptableTokensForUserId], which must return the set of exact,
/// already-`@`-prefixed tokens acceptable for that user (empty set ⇒ not
/// admitted / unknown — see D2's exact token shape, `'@' + displayName` /
/// `'@' + handle`). Proposals are validated in the order given; on overlap,
/// the earlier one wins (D6). Malformed (negative/zero-length/out-of-bounds),
/// overlapping, or content-mismatched proposals are dropped, never thrown.
/// **No substring search is performed** — offsets are trusted as positions
/// to check, not as text to locate (D11).
List<ValidatedMentionSpan> validateExplicitMentionSpans({
  required String body,
  required List<ExplicitMentionProposal> proposals,
  required Set<String> Function(String userId) acceptableTokensForUserId,
}) {
  final consumed = <({int start, int end})>[];
  final out = <ValidatedMentionSpan>[];
  for (final p in proposals) {
    if (p.offset < 0 || p.length <= 0 || p.offset + p.length > body.length) {
      continue;
    }
    final overlaps = consumed.any(
      (r) => p.offset < r.end && (p.offset + p.length) > r.start,
    );
    if (overlaps) continue;
    final acceptable = acceptableTokensForUserId(p.userId);
    if (acceptable.isEmpty) continue;
    final candidate =
        body.substring(p.offset, p.offset + p.length).trim().toLowerCase();
    if (!acceptable.any((t) => t.trim().toLowerCase() == candidate)) continue;
    consumed.add((start: p.offset, end: p.offset + p.length));
    out.add((userId: p.userId, offset: p.offset, length: p.length));
  }
  return out;
}
```

Add `test/mention_span_validation_test.dart` in that package covering: empty
proposals; a single valid proposal; two proposals with genuinely overlapping
ranges (second dropped, first kept — this is the direct replacement for rev
1's duplicate-text test, now expressed as overlapping *positions* instead of
matching *text*, which is the actually-correct level for this to operate at
per D3); an out-of-bounds proposal (offset+length > body.length); a negative
offset; a zero-length proposal; a proposal whose substring does not match any
acceptable token (dropped); a proposal naming an unknown/non-admitted user
(empty acceptable set, dropped).

### 5.2 `createMessage` (`beacon_room_case.dart:254-330`)

New parameters, all defaulted so no existing call site needs updating:
`List<String> explicitMentionUserIds = const []`,
`List<int> explicitMentionOffsets = const []`,
`List<int> explicitMentionLengths = const []`.

Insert, right after the existing `resolveMentionUserIdsForBeacon` call and
before `insertRoomMessage`:

```dart
final cap = kMaxExplicitMentionsPerRoomMessage;
final n = [
  explicitMentionUserIds.length,
  explicitMentionOffsets.length,
  explicitMentionLengths.length,
  cap,
].reduce(min); // mismatched-length lists (D6) and D10's cap both apply here

final proposals = <ExplicitMentionProposal>[
  for (var i = 0; i < n; i++)
    (
      userId: explicitMentionUserIds[i].trim(),
      offset: explicitMentionOffsets[i],
      length: explicitMentionLengths[i],
    ),
];

// §5.4: reuse whatever admitted-participant lookup resolveMentionUserIdsForBeacon
// already performs — do not issue a second, differently-shaped query.
final admitted = await _admittedParticipantsWithNamesForBeacon(beaconId);

Set<String> acceptableTokensFor(String userId) {
  final p = admitted[userId];
  if (p == null) return const {};
  return {
    if (p.displayName.trim().isNotEmpty) '@${p.displayName.trim()}',
    if (p.handle.trim().isNotEmpty) '@${p.handle.trim()}',
  };
}

final validatedSpans = validateExplicitMentionSpans(
  body: trimmed,
  proposals: proposals,
  acceptableTokensForUserId: acceptableTokensFor,
);

final explicitIds = validatedSpans.map((s) => s.userId).toSet();
final mentionIds = {...regexMentionIds, ...explicitIds}.toList(); // D5 union
```

(`regexMentionIds` is whatever local name the existing
`resolveMentionUserIdsForBeacon(...)` result is already bound to — rename if
needed for clarity, but do not remove that call; it remains the sole source
of handle-based mentions. `trimmed` is the same already-trimmed body variable
`resolveMentionUserIdsForBeacon` was called with.)

Pass `mentionSpans: validatedSpans.map((s) => {'userId': s.userId, 'offset':
s.offset, 'length': s.length}).toList()` into `insertRoomMessage`, and
`mentions: mentionIds` exactly as today (now the unioned set).

**Do not change** how `mentionRecipientIds`/`otherDirectedIds`/the
`roomMentioned` attention-intent call are computed (`:260-307`) — they already
key off `mentionIds`, which now correctly includes the explicit half for
free.

### 5.3 `editMessage` (`beacon_room_case.dart:937-1008`)

New parameters: the same three arrays as create, plus
`bool explicitMentionsProvided = false` (D13).

```dart
final proposals = explicitMentionsProvided
    ? <ExplicitMentionProposal>[
        for (var i = 0; i < n; i++)  // n computed as in §5.2, against the new arrays
          (userId: explicitMentionUserIds[i].trim(),
           offset: explicitMentionOffsets[i],
           length: explicitMentionLengths[i]),
      ]
    : <ExplicitMentionProposal>[
        // D13 sticky-preserve: reinterpret the message's EXISTING spans as
        // proposals against the NEW body. An untouched region's substring
        // still matches acceptableTokensFor — survives. An edited-over one
        // no longer matches — dropped. No special-case code beyond this.
        for (final s in msg.mentionSpans)
          (userId: s['userId'] as String,
           offset: s['offset'] as int,
           length: s['length'] as int),
      ];

final validatedSpans = validateExplicitMentionSpans(
  body: newBodyTrimmed,
  proposals: proposals,
  acceptableTokensForUserId: acceptableTokensFor, // same helper as §5.2
);
```

**Why collapsing "omitted" and "explicit `false`/`null`" to one meaning is
safe here, unlike the input-presence hazard `availability-review-codex.md`
found for a different field:** that review's blocker was that *omitted* and
*explicit null* needed to mean **different things** (preserve vs. clear) for
a nullable argument, and Ferry/this GraphQL stack does not reliably
distinguish the two at the transport level. `explicitMentionsProvided` avoids
that failure mode by construction: both "the argument was never sent" (every
client before this plan ships) and "the argument was sent as `false`" (a
mention-unaware sender, including any future caller that just forgets to set
it) are supposed to mean the *same* thing — preserve-and-revalidate. There is
no case this field needs to distinguish that the transport can't reliably
signal. Still add one resolver-level test that sends the real generated
mutation document with the field omitted and confirms preserve-behavior,
rather than only unit-testing the Dart-level default — the sibling review's
core lesson was "test the actual document/variables, not a direct `Map`
call."

`newlyMentionedIds` diff logic (`:974-976`) is unchanged — it already diffs
against `msg.mentions`. Pass `validatedSpans` (mapped to the storage shape as
in §5.2) to `updateMessage` as a **full replace** of `mentionSpans` — this is
correct in both branches: the `explicitMentionsProvided: true` branch
replaces with the caller's authoritative list; the `false` branch replaces
with "the subset of the old list that still validates," which is exactly the
preserve-with-drop semantics D13 specifies, not a merge.

### 5.4 Refactor note, not optional

`resolveMentionUserIdsForBeacon`'s own implementation already loads "admitted
participants of this beacon" and their handles
(`beacon_room_repository.dart:762-793`). §5.2/§5.3's
`_admittedParticipantsWithNamesForBeacon` needs the **same** set, plus
`displayName` (which the existing method may not currently select). Do not
issue a second, separately-shaped repository query for this — extend the
existing lookup (or the port method backing it) to return
`{userId, displayName, handle}` for admitted participants once, and have both
the regex path and the new explicit-validation path consume that one result.
Without this, every message send/edit does two structurally-identical "who is
admitted right now" queries instead of one.

---

## 6. Server: realtime paint (rev 2: rewritten — rev 1's design could not work)

The realtime snapshot is **not** built inside `createMessage`/`editMessage`.
After the database trigger fires, the websocket handler independently calls
`RoomMessageSnapshotLookup.findEligibleInsert(messageId, beaconId)`
(`websocket/path_handler/websocket_path_entity_changes.dart:46-73`), which
**re-reads the already-committed Drift row** and builds the snapshot from it
(`data/repository/room_message_snapshot_lookup.dart:17-23,65-79`) — there is
no in-memory value from §5.2/§5.3 available to hand across that boundary.

Because §4.4 already put `mentionSpans` on the committed row (via
`insertRoomMessage`/`updateMessage`), the fix is: **read it back**, exactly
like every other field this lookup already reads back from the row it just
re-fetched.

1. `RoomMessageSnapshot` (wherever it is declared — grep
   `class RoomMessageSnapshot`) gains
   `@Default(<Map<String, Object?>>[]) List<Map<String, Object?>>
   mentionSpans`.
2. `RoomMessageSnapshotLookup.findEligibleInsert` — verify whether `mentions`
   (the existing sibling id list) is *already* threaded through this exact
   lookup and paint today. If it is, mirror that mechanism precisely for
   `mentionSpans` (same cast/decode step, same place in the row-to-snapshot
   mapping). If `mentions` is *not* currently part of the realtime paint
   either, that is a pre-existing gap outside this plan's scope — do not
   silently expand scope to add it; only add `mentionSpans` if there is a
   `mentions`-shaped precedent to mirror, and flag the alternative (skip
   §6 entirely, mention-highlighting for freshly-sent messages arrives on the
   next full fetch instead of instantly) if there is not.
3. `websocket_path_entity_changes.dart`'s paint serialization — emit
   `mentionSpans` as a JSON-encodable list, next to `mentions`.
4. Client-side `invalidation_service.dart`'s paint parser — add
   `mentionSpans` with **lenient-on-missing, strict-on-wrong-type**: an
   absent key parses to `[]` (old-server compatibility); a
   present-but-wrong-typed value rejects the *whole* paint. Mirror whatever
   contract the existing reply-field paint parsing already established for
   this exact file (that mechanism is live, shipped code — grep
   `replyToAuthorId` in this file to find its current shape) rather than
   inventing a new contract.
5. `roomMessageFromPaint` (or its current name/location) copies `mentionSpans`
   onto the built `RoomMessage`, same as every other paint-carried field.

**This phase depends on locating code by grep, not by a citation trusted in
advance.** Budget extra verification time here; do not assume the exact
function/line shapes above without confirming against the live tree first.

---

## 7. Server: GraphQL wire

### 7.1 Mutation arguments

`packages/server/lib/api/controllers/graphql/mutation/mutation_beacon_room.dart`:
new fields on `MutationBeaconRoom`, next to the existing `InputFieldStringList`
precedent (`_variantsInput`, used by `roomPollCreate` — mirror it exactly),
plus one new `InputFieldIntList` (§3 D1):

```dart
final _explicitMentionUserIds =
    InputFieldStringList(fieldName: 'explicitMentionUserIds');

final _explicitMentionOffsets =
    InputFieldIntList(fieldName: 'explicitMentionOffsets');

final _explicitMentionLengths =
    InputFieldIntList(fieldName: 'explicitMentionLengths');

final _explicitMentionsProvided =
    InputFieldBool(fieldName: 'explicitMentionsProvided');
```

Add `InputFieldIntList` to `_input_types.dart` as a new `part`-included file
(`input_field_int_list.dart`), mirroring `InputFieldStringList`
(`_input_types.dart:72-87`) with `graphQLInt` in place of `graphQLString`.

`roomMessageCreate`'s `arguments:` list gains
`_explicitMentionUserIds.fieldNullable`,
`_explicitMentionOffsets.fieldNullable`,
`_explicitMentionLengths.fieldNullable` (all nullable — an old client omits
them entirely); pass `.fromArgs(args) ?? const []` for each into
`_case.createMessage(...)`.

`roomMessageEdit`'s `arguments:` list gains the same three plus
`_explicitMentionsProvided.fieldNullable`; pass
`_explicitMentionsProvided.fromArgs(args) ?? false` into
`_case.editMessage(...)` (§5.3's safety argument covers why `?? false` is
correct for both "omitted" and "sent as null/false").

### 7.2 Row projection (rev 2: corrected target — do not repeat rev 1's
mistake here)

`packages/server/lib/api/controllers/graphql/custom_types.dart` has **two**
occurrences of an `attachmentsJson` field: one on `gqlTypeRoomMessageRow`
(the one this plan cares about), and a **separate, unrelated** one on
`gqlTypeBeaconFactCardRow` (`custom_types.dart:255-269`, fact-card image
attachments — nothing to do with room-message mentions). **Edit only the
`gqlTypeRoomMessageRow` occurrence.** Add, matching `attachmentsJson`'s exact
non-null typing:

```dart
field('mentionSpansJson', graphQLString.nonNullable()),
```

Server-side encoder: a small pure function next to wherever
`encodeSystemPayload` lives (grep it — same file/directory as
`roomReplyExcerpt`, `domain/util/`), e.g. `encodeMentionSpans(List<Map<String,
Object?>> spans) => jsonEncode(spans)`. Row map gains
`'mentionSpansJson': encodeMentionSpans(m.mentionSpans)`, next to
`'attachmentsJson': attachmentsJsonByMid[id] ?? '[]'`
(`beacon_room_repository.dart:467`).

`gqlTypeRoomMessageCreatePayload` (`custom_types.dart:160-164`, `{id}` only)
needs **no change** — the client builds its own optimistic spans (§9.4)
directly from its own live-tracked ranges, no server round-trip needed.

---

## 8. Client: wire (schema, gql documents, entity, mapper, codegen)

### 8.1 Hand-edit the client schema

`packages/client/lib/data/gql/schema.graphql`, `type v2_RoomMessageRow` —
add `mentionSpansJson: String!` (**non-null — rev 1 wrongly declared this
nullable while the server field is non-null; match `attachmentsJson: String!`
exactly**, `schema.graphql:6889`), keeping the file's alphabetical field
order.

### 8.2 Query and mutation documents

- `room_message_list.graphql`, `room_message_target.graphql`: add
  `mentionSpansJson` to the selection set.
- `room_message_create.graphql`: add `$explicitMentionUserIds: [String!]`,
  `$explicitMentionOffsets: [Int!]`, `$explicitMentionLengths: [Int!]` as
  optional variables and pass them as the new mutation arguments.
- `room_message_edit.graphql`: the same three, plus
  `$explicitMentionsProvided: Boolean`.

### 8.3 Client entity

New `packages/client/lib/domain/entity/room_message_mention_span.dart`,
mirroring `room_message_attachment.dart`'s shape:

```dart
@freezed
abstract class RoomMessageMentionSpan with _$RoomMessageMentionSpan {
  const factory RoomMessageMentionSpan({
    required String userId,
    required int offset,
    required int length,
  }) = _RoomMessageMentionSpan;
}

/// Drops malformed entries instead of throwing. Does **not** validate
/// offset/length against any body — that defensive check happens once, at
/// the rendering boundary (§10.1, D12), shared by every producer of this
/// list (fresh read, realtime paint).
List<RoomMessageMentionSpan> parseRoomMessageMentionSpansJson(String raw) {
  if (raw.trim().isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) return const [];
  final out = <RoomMessageMentionSpan>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    final userId = item['userId'];
    final offset = item['offset'];
    final length = item['length'];
    if (userId is! String || offset is! num || length is! num) continue;
    out.add(RoomMessageMentionSpan(
      userId: userId,
      offset: offset.toInt(),
      length: length.toInt(),
    ));
  }
  return out;
}
```

`RoomMessage` (`packages/client/lib/domain/entity/room_message.dart`) gains
`@Default(<RoomMessageMentionSpan>[]) List<RoomMessageMentionSpan>
mentionSpans`.

### 8.4 Mapper + codegen

Thread `mentionSpansJson` → `parseRoomMessageMentionSpansJson(...)` through
`_toRoomMessageFields` (`beacon_threads_repository.dart`, the same mapper the
reply/attachment fields already go through), then:

```bash
cd packages/client && dart run build_runner build -d
```

**Exit (§4–8):** `dart run build_runner build -d` green on both packages;
`./scripts/check-custom-lints.sh` clean on both.

---

## 9. Client: composer state (rev 2: rewritten around live position-tracking)

### 9.1 Autocomplete widening

`participants_matching_mention_query.dart` — change the gate from
`p.handle.isNotEmpty` to `(p.handle.isNotEmpty || p.userTitle.isNotEmpty)`
(D9); re-read the current match predicate before editing — it may already
check `p.userTitle` for the *contains-query* half, in which case only the
gate line needs to change.

### 9.2 `MentionTextController` — live position tracking (rev 2: new; this is
the mechanism D3 depends on and rev 1 did not have)

`mention_text_controller.dart` gains a committed-mention list and a
prefix/suffix diff that keeps it correct through arbitrary edits:

```dart
typedef CommittedMention = ({String userId, int start, int end});

final class MentionTextController extends TextEditingController {
  MentionTextController({super.text});

  final _committed = <CommittedMention>[];

  /// Live, always-current offsets of every explicit mention still intact in
  /// the text — never a re-search, always exactly maintained through edits.
  List<CommittedMention> get committedMentions => List.unmodifiable(_committed);

  @override
  set value(TextEditingValue newValue) {
    final oldText = text; // capture BEFORE mutating — see ordering note below
    if (oldText != newValue.text) {
      _shiftCommittedMentionsForEdit(oldText, newValue.text);
    }
    super.value = newValue;
    _recompute(); // existing active-mention-query logic, unchanged
  }

  /// Prefix/suffix diff: finds the single contiguous changed region between
  /// [oldText] and [newText], then for every committed range: unaffected if
  /// entirely before the region (kept as-is); shifted by the length delta if
  /// entirely after it; **dropped** if it overlaps the region at all. This
  /// is the fix for duplicate-display-name identity loss (§3 D3) — ranges
  /// are never re-matched by text, only shifted or invalidated by position.
  void _shiftCommittedMentionsForEdit(String oldText, String newText) {
    var prefixLen = 0;
    final maxPrefix = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefixLen < maxPrefix &&
        oldText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }
    var suffixLen = 0;
    final maxSuffix = maxPrefix - prefixLen;
    while (suffixLen < maxSuffix &&
        oldText[oldText.length - 1 - suffixLen] ==
            newText[newText.length - 1 - suffixLen]) {
      suffixLen++;
    }
    final oldChangedStart = prefixLen;
    final oldChangedEnd = oldText.length - suffixLen;
    final delta = newText.length - oldText.length;

    final next = <CommittedMention>[];
    for (final m in _committed) {
      if (m.end <= oldChangedStart) {
        next.add(m); // entirely before the edit: unaffected
      } else if (m.start >= oldChangedEnd) {
        next.add((userId: m.userId, start: m.start + delta, end: m.end + delta));
      }
      // else: overlaps the edited region — dropped, not carried forward
    }
    _committed
      ..clear()
      ..addAll(next);
  }

  /// Inserts a literal mention token (already including any leading `@`) at
  /// the active mention range, replacing it, with a trailing space, and
  /// records its exact range. Call order matters: `value = ...` runs the
  /// diff above first (over the *old* committed list — nothing new to
  /// shift/invalidate yet), then the new range is appended using offsets
  /// computed from the *pre-edit* text, which remain valid as the start
  /// offset in the *post-edit* text because nothing before `range.start`
  /// changed.
  bool insertLiteralMentionText(String token, {String? userId}) {
    final range = _activeMentionRange;
    if (range == null) return false;
    final full = '$token ';
    final t = text;
    final before = t.substring(0, range.start);
    final after = t.substring(range.end);
    final next = before + full + after;
    final nextCursor = before.length + full.length;
    value = value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
      composing: TextRange.empty,
    );
    if (userId != null) {
      _committed.add((
        userId: userId,
        start: before.length,
        end: before.length + token.length, // token, not `full` — excludes the trailing space
      ));
    }
    return true;
  }

  bool insertMention(String handleLowercase) =>
      insertLiteralMentionText('@$handleLowercase'); // unchanged path, no userId tracked — handle mentions stay regex-resolved server-side
}
```

Refactor `insertMention` to delegate as shown (behavior-preserving — verify
with the existing `mention_completion_test.dart` before and after). Clear
`_committed` wherever the composer clears its text after a successful send
(§9.4).

### 9.3 Suggestion acceptance

In `_BeaconRoomComposerState`'s `_acceptMentionSuggestion`
(`packages/client/lib/ui/widget/basic_chat_body.dart`, around line ~808-817
per this research pass — verify current line):

```dart
if (participant.handle.isNotEmpty) {
  _text.insertMention(participant.handle.toLowerCase());   // unchanged path
} else {
  _text.insertLiteralMentionText(
    '@${participant.userTitle.trim()}',
    userId: participant.userId,
  );
}
```

`MentionSuggestionsOverlay`/`_MentionSuggestionRow` — for a handle-less
participant, render `participant.userTitle` as the primary line with no `@`
prefix in the **suggestion row** (D4's `@`-prefix rule governs only what gets
typed into the body, not how the picker row reads). A small presentational
branch only; no new widget class needed.

### 9.4 Submit

Wherever `_submit()` currently calls `widget.onSend(body, uploads)` — extend
to also read `_text.committedMentions` directly (no filtering step needed —
the controller already only contains ranges that survived every edit; §9.2's
diff already dropped anything invalidated):

```dart
final explicitMentionUserIds = [for (final m in _text.committedMentions) m.userId];
final explicitMentionOffsets = [for (final m in _text.committedMentions) m.start];
final explicitMentionLengths = [for (final m in _text.committedMentions) m.end - m.start];
```

Pass all three through `onSend` (widen its signature — nullable/defaulted, no
existing caller needs to change), down to
`BeaconThreadsCase.createMessage` (`beacon_threads_case.dart:155`) →
repository → GQL variables. Clear `_text` (and therefore `_committed`) on
successful send as today; **on failure, do not clear** — the controller
already holds the correct live state for a retry with no extra bookkeeping.

**Note the `editMessage` call site (`beacon_threads_case.dart:241`) is
untouched by this section** — per D13, edits never send a populated explicit-
mention channel from any UI in this plan; the client's edit call simply never
sets `explicitMentionsProvided: true`, and the server's sticky-preserve path
(§5.3) does the rest.

### 9.5 Optimistic local echo

The optimistic `localMessage` built at send time gets its `mentionSpans`
**directly from `_text.committedMentions`** — already correct, exact, and
non-overlapping by construction of live editing; no search, no shared
validator call needed client-side (§3 D3's whole point). This is simpler than
rev 1's design, which needed the client to independently re-run a search
algorithm to reconstruct what it already knew.

**Exit (§9):** existing `mention_completion_test.dart`,
`mention_suggestions_overlay_test.dart`, `basic_chat_body_test.dart` still
green; new tests per §11 added, including a `MentionTextController`-level
test suite for the diff algorithm itself (§11).

---

## 10. Client: rendering

### 10.1 Defensive validation at the point of use (D12 — rev 2: new,
addresses the unvalidated-offset finding)

Before any span is used to slice `body`, filter it:

```dart
List<RoomMessageMentionSpan> _usableMentionSpans(
  List<RoomMessageMentionSpan> spans,
  String body,
) {
  final sorted = [...spans]..sort((a, b) => a.offset.compareTo(b.offset));
  final out = <RoomMessageMentionSpan>[];
  var lastEnd = 0;
  for (final s in sorted) {
    if (s.offset < lastEnd) continue; // overlaps a prior kept span — drop
    if (s.length <= 0) continue;
    if (s.offset < 0 || s.offset + s.length > body.length) continue;
    out.add(s);
    lastEnd = s.offset + s.length;
  }
  return out;
}
```

Call this **once**, at the top of §10.2's compositor and again wherever §10.3
measures width — or, simpler and less error-prone, call it once at the
`room_message_tile.dart` call site and pass the already-filtered list into
both the render and the measurement path, so there is exactly one place this
filtering happens rather than two that could drift apart.

### 10.2 Two-stage compositor, wired into both render branches (rev 1's
design was correct in isolation; rev 2 corrects *where it plugs in* — §3 D7)

New function in `room_message_trailing_meta_layout.dart`:

```dart
TextSpan buildRoomMessageBodySpanWithExplicitMentions({
  required String data,
  required TextStyle? textStyle,
  required List<Annotation>? plainTextAnnotations, // the existing handle/URL set
  required List<RoomMessageMentionSpan> explicitSpans, // already filtered, §10.1
  required TextStyle Function(String userId) explicitMentionStyle,
}) {
  // Walk `data`, alternating: a plain segment run through the EXISTING,
  // unmodified buildRoomMessageAnnotatedBodySpan(...) (still where @handle
  // and URL detection happens, scoped to that substring), and one segment
  // per explicitSpans entry, built directly as
  // TextSpan(text: data.substring(s.offset, s.offset+s.length),
  //          style: explicitMentionStyle(s.userId)) — no regex involved,
  // position is already known exactly. Concatenate in original order into
  // one outer TextSpan(style: textStyle, children: [...]).
}
```

`explicitMentionStyle(userId)` reuses the **same** self-vs-other color logic
already inline in `buildRoomMessageMentionAnnotations`'s `spanBuilder`
(`room_message_trailing_meta_layout.dart:130-146` —
`mentionColor`/`selfMentionBackground`/`isSelfMention`). Factor that styling
decision into a small shared helper used by **both** the existing regex
`spanBuilder` and this new function — do not duplicate the color/weight
logic.

**Call sites — both of them (rev 2 correction, §3 D7):**

- `RoomMessageTextBody` path (`room_message_tile.dart:797-808`,
  `buildMessageTextSpanWithTrailingMeta` at
  `room_message_trailing_meta_layout.dart:212-230`): branch on
  `mentionSpans.isEmpty` — empty uses the existing
  `buildRoomMessageAnnotatedBodySpan` call unchanged (cheap path, the
  overwhelming common case); non-empty calls the new function.
- `ShowMoreText` path (`room_message_tile.dart:809-817`, taken whenever
  `reactionCounts` is non-empty, §0.2): `ShowMoreText`/`ReadMoreText` cannot
  accept a precomposed span (confirmed by reading the `readmore` package
  source — it takes `data: String` + `annotations: List<Annotation>?` and
  does its own internal regex pass). When `mentionSpans.isEmpty`, this branch
  is **untouched** — same `ShowMoreText(display, annotations:
  mentionAnnotations, ...)` call as today. When `mentionSpans.isNotEmpty`,
  replace the `ShowMoreText` call with a plain `Text.rich` of the composed
  span (mirroring `RoomMessageTextBody`'s own `Text.rich` usage,
  `room_message_text_body.dart:54-63`, inside the same `TenturaSelectionArea`
  wrapper) — this deliberately **skips read-more truncation** for that
  message (named, scoped limitation — §3 D7).

### 10.3 Tight-width measurement

`room_message_tile.dart:1024-1047` currently calls
`buildRoomMessageAnnotatedBodySpan` unconditionally to build the span it
measures. Change this call site to the **same branch** as §10.2: empty
`mentionSpans` → unchanged; non-empty → `buildRoomMessageBodySpanWithExplicitMentions`,
using the same filtered span list from §10.1. This is what keeps the
measured tree and the painted tree identical — rev 1 left this call site
untouched, which would have measured one tree and painted another whenever an
explicit mention was present.

**Exit (§10):** `flutter analyze` clean; new widget/unit tests (§11) green,
including the reaction-bearing-message-with-explicit-mention case and a
same-message width-vs-paint consistency check.

---

## 11. Tests

Server (new or extended):

- `test/mention_span_validation_test.dart` (root `tentura_root` package) —
  cases listed in §5.1.
- Extend `room_mention_utils_test.dart` or add a sibling — D2 anti-spoof with
  the **correct `@`-prefixed** token shape (the concrete regression case for
  rev 1's blocker 1): a proposal whose substring is `'@Bob Smith'` validates
  against a participant named `Bob Smith`; a proposal naming an admitted
  participant but with mismatched text is dropped; a proposal naming a
  non-admitted participant is dropped; mismatched list lengths and an
  over-cap list both degrade to the bounded/common prefix, never error.
- Extend `beacon_room_case_message_mutations_test.dart` — create with
  explicit mentions: `mentions` id set is the correct union; `mentionSpans`
  persisted with correct offsets; a handle-less participant reachable **only**
  via the explicit channel still triggers `roomMentioned`. Edit:
  `explicitMentionsProvided: false` with an untouched mention preserves it;
  with an edited-over mention drops it; `explicitMentionsProvided: true`
  fully replaces.
- A resolver-level test sending the **actual generated `RoomMessageEdit`
  document** with `explicitMentionsProvided` genuinely omitted from the
  variables payload (not just a Dart-level `null`/absent argument to a direct
  method call) — per §5.3's note, this is the specific thing the sibling
  availability review found broken for a structurally similar field; do not
  skip this test on the assumption a unit test of the resolver function is
  equivalent.
- pg-tagged test extending whatever covers `mentions`/`replyTo*` persistence
  today — `mention_spans` round-trips through the real jsonb column.

Client (new or extended):

- `MentionTextController` diff-algorithm tests (new, standalone from the
  widget layer): insert one mention, edit text before it (range shifts,
  survives); edit text after it (unaffected); edit *inside* it (dropped);
  insert two mentions with **identical display names**, delete the first
  (second's range is unaffected — the direct regression test for rev 1's
  blocker 2); insert two mentions, then an edit that spans across both
  (both dropped); insert, then undo via setting `value` back to the exact
  prior state (range restored — verifies the diff is symmetric, not just
  forward-only).
- `mention_completion_test.dart` — handle-less participant now appears in
  suggestions; picking one inserts `@DisplayName ` verbatim and records its
  range; picking a duplicate-named participant twice records two independent,
  correctly-offset ranges.
- New composer test — submit reads `committedMentions` directly; a message
  sent with zero explicit mentions sends empty lists (not a regression on
  ordinary `@handle` sends).
- New rendering test — two explicit mentions in one message both render
  styled (the regression case D7's rejected regex-only alternative would have
  silently failed); a reaction-bearing message with an explicit mention
  renders via the `Text.rich` fallback, styled, without crashing; a malformed
  persisted span (negative offset, overlapping range, out-of-bounds) is
  dropped by §10.1's filter rather than throwing; self-mention styling
  matches the handle-path's own self-mention styling; width measurement and
  painted content agree for a message with explicit mentions (§10.3).
- Realtime paint test — mirror whatever lenient/strict test pattern already
  covers the reply fields, for `mentionSpans`, contingent on §6 actually
  finding a `mentions`-shaped precedent to mirror (see §6's fallback note).

---

## 12. Docs, l10n, version

- `docs/features/beacon_room.md` — extend the existing **@mentions** sentence
  (line 106) to note that a participant without a public handle can still be
  mentioned by name, and that this only works when *composing or sending* a
  message — not while editing an existing one (D13).
- `packages/server/lib/domain/entity/notification_kind.dart:14-15` — the
  `roomMention` doc comment currently says *"Personal `@handle` mention"*;
  reword to not imply handle-only.
- l10n: no new user-facing strings are strictly required (the suggestion row
  needs no new copy, just a presentational branch — §9.3). If the suggestion
  row's accessibility semantics currently reference `@handle` text directly,
  add a generic "Mention {name}" label instead; otherwise skip.
- Client version bump + `flutter_bootstrap.js?v=` sync, same commit as the
  UI-visible change, per §1.

**Exit (§12):** `bash scripts/check-user-facing-terminology.sh` clean.
