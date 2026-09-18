# Mention without handle plan rev 1 — architecture and correctness review

Reviewer posture: independent adversarial architecture and correctness review. I read the
draft in full and checked its cited GraphQL, Drift, repository, compositor, composer, edit, and
realtime paths against the live checkout. This review reports only defects found in this pass.

## 1. Verdict

**Rev 1 is not safe to implement.** The proposed feature is internally contradictory at its
authoritative validation boundary, loses mention identity under ordinary edits, and reaches only
one of the live message-rendering branches. The edit and realtime sections are also based on
code paths that do not exist in the shape the plan assumes. In addition, the server contract is
unbounded at an attacker-controlled quadratic algorithm and the read/render boundary trusts
unvalidated offsets. Resolve the seven blockers below before deriving implementation units.

## 2. Defects

### 1. BLOCKER — D2 rejects every handle-less token produced by D4

D4 and section 9.3 send `text = '@' + displayName.trim()`. The validation pseudocode in section
5.2 compares that value, lowercased, with `p.displayName.trim().toLowerCase()` and
`p.handle.trim().toLowerCase()`—neither expected value contains `@`. This is not a cosmetic
example mismatch: the live composer currently inserts the prefix as part of the token
(`packages/client/lib/features/beacon_threads/ui/widget/mention_text_controller.dart:73-82`), and
the server resolves and persists the already-trimmed body
(`packages/server/lib/domain/use_case/beacon_room_case.dart:237-259,277-284`). Following the plan
literally therefore produces no validated explicit candidate, no `mentionSpans`, no unioned
`mentions` id, and no mention notification.

Concrete failure: Alice selects handle-less Bob Smith. The client sends
`explicitMentionTexts: ['@Bob Smith']`; the server's expected set contains only `bob smith`, drops
the entry under D6, and stores an ordinary unhighlighted string.

Smallest correct fix: define one canonical claimed-token representation and use it on both sides.
If the wire text includes `@`, validate it against `'@${displayName.trim()}'` (and, only if this
channel intentionally accepts handles, `'@${handle.trim()}'`) without stripping or independently
trimming characters that participate in offsets. Add an end-to-end use-case test using the exact
token emitted by the composer; testing the validator with a bare display name would miss this
failure.

### 2. BLOCKER — the pending list cannot preserve which duplicate occurrence names which user

Section 9.3 stores only `(userId, text)` in insertion order and section 9.4 considers every entry
alive whenever `body.contains(text)`. D3 then assigns surviving candidates to the first unclaimed
equal substring in the current body. That is not enough state to survive deletion, reordering, or
replacement when two admitted people have the same display name. The live controller does have
the insertion range at selection time (`mention_text_controller.dart:17-20,64-65`), but the plan
throws that positional identity away and explicitly declines to track edits.

Concrete failure: two participants are both named Sam Lee. Alice inserts Sam-1 and then Sam-2,
giving `@Sam Lee ... @Sam Lee`, then deletes the first token. Both pending records pass
`body.contains('@Sam Lee')`; the claimant gives the sole remaining occurrence to Sam-1 and drops
Sam-2. The displayed text is unchanged, but the wrong account is highlighted and receives the
attention intent. Moving the second token before the first produces the same identity swap with
both tokens still present.

Smallest correct fix: track occurrence identity through text edits, not mere string survival.
Maintain marked ranges in the controller and update/invalidate them for every editing delta, then
send the surviving claimed offsets (or another unambiguous occurrence identifier) with the ids
and text. The server must validate each supplied range against the normalized stored body, the
admitted user, and the canonical token, reject overlaps, and derive persisted spans from those
validated ranges. Add duplicate-display-name deletion and reorder tests involving two different
user ids.

### 3. BLOCKER — D7 styles only the inline-meta branch and leaves the live `ShowMoreText` branch unchanged

The two-stage compositor itself is viable for a `TextSpan` consumer, but the plan does not connect
it to all live consumers. `room_message_tile.dart` has two mutually exclusive body renderers:
`RoomMessageTextBody` for inline metadata and `ShowMoreText(display, annotations: ...)` otherwise
(`packages/client/lib/features/beacon_threads/ui/widget/room_message_tile.dart:797-817`). Messages
with reactions use the latter because inline metadata is allowed only when reaction counts are
empty (`room_message_trailing_meta_layout.dart:30-33`). Section 10 changes
`buildMessageTextSpanWithTrailingMeta`, which is used only inside `RoomMessageTextBody`
(`packages/client/lib/features/beacon_threads/ui/widget/room_message_text_body.dart:30-41`);
`ShowMoreText` still receives regex-only annotations and cannot render the explicit spans.

The plan also claims width measurement needs no change, but the live tight-width path constructs
another body span directly with `buildRoomMessageAnnotatedBodySpan`
(`room_message_tile.dart:1024-1047`). Even the inline branch would therefore render one styled
tree while measuring a different unstyled tree.

Concrete failure: a new `@Bob Smith` mention highlights until somebody reacts to the message.
The rebuild switches to `ShowMoreText`, and the highlight disappears. Before a reaction, the
bubble can also be sized from the regex-only tree rather than the tree actually painted.

Smallest correct fix: specify one validated body-span builder used by rendering and measurement,
then design an explicit-span-capable collapsed/expanded renderer for the non-inline path (or make
the existing read-more implementation accept the precomposed span without losing URL behavior).
Test both no-reaction inline rendering and reaction-bearing/read-more rendering, including the
transition between them and tight-width measurement.

### 4. BLOCKER — section 9.4's edit pre-seed targets a composer that is never used for editing

The live edit action does not open `BeaconRoomComposer`. It opens a separate
`_BeaconRoomTextBottomSheet` with only `initialText: message.body`, receives a `String`, and calls
`RoomCubit.editMessage(messageId, newBody)`
(`packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart:738-760`). The cubit
and use case likewise carry only the body
(`packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart:902-913` and
`packages/client/lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart:241-249`).
There is no moment when “the composer becomes interactive” in which the proposed
`_BeaconRoomComposerState._pendingMentions` can be pre-seeded.

Concrete failure: Alice edits an existing explicit mention without changing its text. The edit
sheet has no pending claims to submit, so the server fully recomputes `mentionSpans` from an empty
explicit list and removes Bob's structured mention and `mentions` membership. The plan's proposed
edit-preseed test cannot be written against the actual UI path.

Smallest correct fix: allocate edit ownership explicitly. Either reuse a mention-aware editor for
both create and edit, or add a `MentionTextController`, participant suggestions, pending-range
state, and a structured edit result to `_BeaconRoomTextBottomSheet`; thread that result through
the cubit/use case/repository. Cover unchanged resubmit, deletion, retry, and duplicate-name
editing through the real edit sheet.

### 5. BLOCKER — section 6 assumes insert-time data can be handed to a post-trigger snapshot lookup

The realtime snapshot is not populated inside `createMessage` or `insertRoomMessage`. After the
database trigger event reaches the websocket handler, it independently calls
`RoomMessageSnapshotLookup.findEligibleInsert(messageId, beaconId)`
(`packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart:46-73`).
That repository re-reads the committed Drift row and builds the snapshot
(`packages/server/lib/data/repository/room_message_snapshot_lookup.dart:17-23,65-79`). Section 6.2
instead says to populate the snapshot “from the same `claimedSpans` computed in section 5.2, no
extra query needed”; those values are not in scope and cannot cross this asynchronous boundary.

The actual domain row also has no `mentionSpans` field
(`packages/server/lib/domain/entity/beacon_room_record.dart:2-29`), and the Drift-to-domain mapper
copies only `mentions` (`packages/server/lib/data/repository/mappers/coordination_row_mappers.dart:34-50`).
Consequently the section 7 row projection cannot read `m.mentionSpans` either.

Concrete failure: an implementer follows section 6 and discovers there is nowhere to pass
`claimedSpans`; if they merely add it to `RoomMessageSnapshot`, realtime inserts paint `[]` while
the later GraphQL refresh paints the stored span, causing the exact reconcile flicker D3 claims
to prevent.

Smallest correct fix: make the committed jsonb column the sole realtime source. Add the field to
`BeaconRoomMessageRecord`, its Drift mapper, `RoomMessageSnapshot`, and the snapshot lookup; parse
the row's jsonb value there before serialization. Add an insert-through-database websocket test
that proves the emitted paint contains the committed spans, rather than a direct snapshot fixture
test.

### 6. BLOCKER — the server port and GraphQL blast radius do not match the live shapes

Section 4.3 changes concrete repository signatures but omits the domain-owned
`BeaconRoomRepositoryPort`. The live use case depends on that port, whose `insertRoomMessage` and
`updateMessage` contracts currently expose only `mentions`
(`packages/server/lib/domain/port/beacon_room_repository_port.dart:79-90,203-207`). The use case
cannot pass `mentionSpans` until the port changes. The required `BeaconRoomMessageRecord` and row
mapper changes are likewise absent, as noted above.

Section 7.2 also instructs the implementer to add `mentionSpansJson` beside *every* occurrence of
`attachmentsJson` in `custom_types.dart`. The second occurrence is not a duplicate room-message
type; it belongs to `gqlTypeBeaconFactCardRow`
(`packages/server/lib/api/controllers/graphql/custom_types.dart:255-269`). Adding a required
message-span field there creates an unrelated fact-card schema contract with no producer.
Finally, section 8.1 declares the client field nullable (`mentionSpansJson: String`) while section
7.2 declares the server field non-null (`graphQLString.nonNullable()`), unlike the actual
`attachmentsJson: String!` precedent (`packages/client/lib/data/gql/schema.graphql:6889`).

Concrete failure: following the listed files either fails compilation at the use-case port call,
or encourages an ad-hoc cast/query that bypasses the domain boundary. Following “every
occurrence” also advertises an unsupported non-null field on fact cards, while Ferry generates a
nullable room-message model from a schema that disagrees with the server.

Smallest correct fix: enumerate the real end-to-end server chain: domain port, domain record,
Drift mapper, concrete repository, use case, snapshot lookup, and GraphQL room-message row only.
Add `mentionSpansJson: String!` to the hand-maintained client schema to match the server. Do not
touch `gqlTypeBeaconFactCardRow`.

### 7. BLOCKER — attacker-controlled claim lists are unbounded and feed a quadratic algorithm

`InputFieldStringList` performs only a `List<String>.from` cast and has no length or element-size
limit (`packages/server/lib/api/controllers/graphql/input/_input_types.dart:71-92`). The plan adds
two such public arguments, takes their full common prefix, and runs every candidate through
`body.indexOf` plus `consumed.any`. Although message bodies are capped at 4,000 characters
(`packages/server/lib/consts/beacon_room_consts.dart:71` and
`packages/server/lib/domain/use_case/beacon_room_case.dart:153-158`), the claim lists are not tied
to that bound. Rate limiting occurs before mention resolution, but it does not make one admitted
user's single oversized request cheap (`beacon_room_case.dart:236-259`).

Concrete failure: an admitted attacker sends tens of thousands of repeated valid-looking ids and
texts in one mutation. Candidate validation, repeated substring scans, and the growing
`consumed.any` loop consume disproportionate CPU and memory before most entries are dropped. A
few requests can monopolize the Dart isolate even though each message body is small.

Smallest correct fix: define and enforce a small server-side maximum number of explicit claims
before participant lookup/claiming, reject mismatched or oversized lists at the application
boundary, cap each claimed token to the message-body limit, and implement claiming with bounded
or linear range accounting rather than scanning every consumed range. Add resolver-level abuse
tests against the actual GraphQL arguments, not only pure-function happy paths.

### 8. HIGH — persisted offsets are not validated before substring slicing

The proposed JSON parser accepts any numeric `offset` and `length`, truncates fractional numbers
with `toInt()`, does not reject negatives, sorts despite D7 sorting again elsewhere, and
does not reject overlaps or ranges beyond the body. D7 then treats non-overlap as guaranteed by
construction and slices the body. That guarantee holds only for fresh output of
`claimMentionSpans`; it does not hold at the database/GraphQL compatibility boundary the parser
exists to defend. The live attachment precedent is lenient about malformed attachment facts
(`packages/client/lib/domain/entity/room_message_attachment.dart:32-78`), but attachment values
are not used as string indices.

Concrete failure: one malformed/backfilled row contains `{offset: -1, length: 8}` or an offset
beyond a subsequently corrected body. Opening the room reaches `substring` in the new compositor
and throws, taking down rendering of the message list. A fractional offset is silently moved to a
different character before that.

Smallest correct fix: validate integer-ness, non-negative offset, positive length, in-body end,
ascending order, and non-overlap against the actual body before any substring call. Put the
defensive normalization at the rendering/domain boundary so GraphQL and realtime inputs share it;
drop invalid spans and render plain text. Test negative, fractional, overflow, overlap, unsorted,
and surrogate-pair-adjacent ranges.
