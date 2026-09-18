# Availability architecture rev 2 — architecture review

Reviewer posture: independent architecture and correctness review. I read rev 2, both rev-1
reviews, the applicable architecture rules, and the live client/server paths cited below. This
is review only; no implementation is proposed here beyond the smallest correction needed for
each defect.

## 1. Verdict

**Rev 2 is not safe to derive an implementation plan from yet.** It correctly repairs several
rev-1 factual errors, especially the live picker path, presence-table DDL, V2 routing, and most
of the server payload inventory. But rev 2 introduces five blocking architecture defects: the
day/instant privacy split cannot support the promised shared client/server expiry rule; the
GraphQL stack does not preserve the mutation's omitted-vs-null contract; the delete-on-empty
patch has no atomic concurrency design; the proposed server gate is not atomic with edge
insertion; and client-side delivery reconciliation cannot prove which recipients were actually
delivered. Resolve those contracts, close S7b/S10/S11, and correct the remaining blast radius
before planning implementation.

## 2. New defects introduced by rev 2

### 1. BLOCKER — D21 makes exact client-side expiry impossible, and the write API cannot derive the display day

Rev 2 exposes only `paused_until_day` to the client but still requires the client and server to
run the same `effectiveAt(now)` comparison against an exact instant. Those requirements cannot
both hold. A bare subject-calendar date does not identify the subject's local-midnight instant.
For a subject in UTC+14 and a viewer in UTC-10, `2026-08-18` can denote expiry instants almost a
day apart depending on whose zone reconstructs it. Conversely, the proposed mutation sends one
instant through `InputFieldDatetime`; the current parser normalizes it to UTC
(`packages/server/lib/api/controllers/graphql/input/_input_types.dart:110-142`), so the server
cannot recover the submitted local calendar day or original offset from that value. The client
formatter it proposes to extract immediately calls `toLocal()`
(`packages/client/lib/ui/utils/beacon_card_deadline.dart:19-35`), which is viewer-local behavior,
not subject-local behavior. The proposed database pair CHECK enforces only joint nullability; it
cannot prove that the exposed day denotes the stored instant in the subject's calendar.

Concrete failure: Carol chooses “through Sunday night” in UTC+14. The server stores the correct
UTC instant for Carol's Monday midnight and exposes `paused_until_day = 2026-08-17`. Bob in
UTC-10 reconstructs or compares that date in his own zone, keeps Carol blocked after the server
has resumed delivery, and cannot satisfy invariant 1 or the `until == now` boundary. If the
server instead derives the day from the normalized UTC instant, it stores August 16, so the
display is wrong before expiry.

Smallest correct fix: choose one canonical public temporal contract. Either (a) make expiry a
UTC date boundary that every client can reconstruct from the exposed date; or (b) keep subject-
local-midnight enforcement server-only, accept that clients receive a server-derived effective
view plus display day and cannot independently run exact expiry. If (b), submit the calendar day
and enough private offset/zone information for the server to construct and validate the instant,
and delete the “one shared client/server `effectiveAt`” claim. Merely storing two columns does not
bridge the missing information.

### 2. BLOCKER — “omitted = preserve, null = clear” is not carried through this GraphQL stack

The `setHandle` analogy proves the intended server API shape, not that Ferry plus
`graphql_schema2` preserves it. Ferry omits a null variable from JSON
(`packages/client/lib/features/profile/data/gql/_g/profile_update.var.gql.g.dart:43-50`), but the
generated document still always contains the argument `handle: $handle`
(`packages/client/lib/features/profile/data/gql/_g/profile_update.ast.gql.dart:64-76`). The
server's coercer computes a missing variable as null and inserts that nullable argument into the
resolver map (`packages/server/lib/api/controllers/graphql/schema.dart:120-129`). Therefore
`args.containsKey('handle')` in the existing resolver
(`packages/server/lib/api/controllers/graphql/mutation/mutation_user.dart:38-48`) does not
establish a transport-level distinction between an omitted variable and an explicit null for a
fixed document of this form.

Concrete failure: device A calls `userAvailabilitySet(isLimited: true)` using the proposed
generated operation. The document also syntactically supplies `pausedUntil: $pausedUntil`; its
unset variable is coerced to null, and the resolver interprets it as “clear pause.” Turning on
the standing disposition unexpectedly resumes an active pause. The inverse operation can clear
`is_limited` while replacing a pause.

Smallest correct fix: make field presence explicit in the schema, for example required
`setIsLimited` / `setPausedUntil` booleans paired with nullable values, or separate focused
mutations. Do not base the contract on nullable variable omission. Add resolver-level tests using
the actual GraphQL document and serialized variables, not direct `Map` calls.

### 3. BLOCKER — the orthogonal patch plus CHECK/delete branch has no safe concurrent write contract

The four user actions are partial updates to one row, but §7 specifies only “upsert” followed by
a delete when the combined state is empty. A read-modify-write implementation loses independent
updates. The repository has transaction primitives that can provide a real boundary
(`packages/server/lib/data/database/tentura_db.dart:182-209`), and existing multi-step invitation
writes explicitly use a database transaction
(`packages/server/lib/data/repository/user_repository.dart:823-873`); rev 2 does not allocate an
equivalent boundary or lock for availability.

Concrete failure: the row is `{is_limited: true, paused_until: Monday}`. Device A clears limited
while device B resumes now. Both read the original row. A writes `{false, Monday}`; B writes
`{true, null}`. Last writer wins, so one clear is lost and the final row is either paused-only or
limited-only instead of open. A naive `INSERT ... ON CONFLICT DO UPDATE` is also not enough: a
clear-only call against an existing row has an insert candidate `{false, null}`, which violates
`CHECK (is_limited OR paused_until IS NOT NULL)` before it can serve as a general patch/delete
mechanism.

Smallest correct fix: define one atomic repository-port operation taking explicit presence bits,
and linearize it per `user_id` inside one PostgreSQL transaction or database function. It must
lock/read the current row, apply both patches, update both pause columns as a pair, and delete or
write before releasing the lock. Because absence cannot be row-locked, use an advisory key lock,
serializable retry, or a single proven SQL construction that also handles concurrent first
inserts. Require two-connection PostgreSQL tests for clear-limited vs resume, pause vs clear,
replace vs resume, and first-write races.

### 4. BLOCKER — D10's hard server gate is a TOCTOU check unless eligibility and edge insertion are one operation

The natural-looking implementation—read availability in `ForwardCase.forward`, filter, then call
`createBatch`—does not enforce a hard boundary. Today the analogous block and visibility checks
occur before the transactional action (`packages/server/lib/domain/use_case/forward_case.dart:191-244`),
while edge creation begins later inside `_attention.runAction`
(`packages/server/lib/domain/use_case/forward_case.dart:248-271`). `createBatch` owns the actual
insert transaction (`packages/server/lib/data/repository/forward_edge_repository.dart:94-147`).

Concrete failure: forwarding reads Carol as open; Carol's pause commits; then the forward
transaction inserts Carol's edge. Invariant 7 says a request naming a paused recipient creates no
edge “regardless of client state,” but the proposed use-case read has already gone stale.

Smallest correct fix: make the insertion repository contract atomically predicate each edge on
current effective availability in the same SQL/transaction that inserts it, and return typed
delivered and availability-skipped ids. A use-case pre-read is fine for UX but cannot be the
authoritative gate. Keep the policy owned by the use case/port contract; do not let a controller
or ad-hoc data-layer call become the business rule.

### 5. BLOCKER — D23's post-send diff is not a delivery contract, and client-side stripping recreates a silent drop

The client does not currently await a post-send candidate reload. The repository emits a change
after the mutation (`packages/client/lib/features/forward/data/repository/forward_repository.dart:167-176`),
the cubit listener starts `_loadCandidates` without awaiting it
(`packages/client/lib/features/forward/ui/bloc/forward_cubit.dart:63-74`), and `forward()` records
the selected ids immediately (`packages/client/lib/features/forward/ui/bloc/forward_cubit.dart:434-460`).
Even an explicitly awaited reload can only infer “now looks `forwardedByMe`,” not whether this
batch inserted the edge or why an id disappeared. The server already has the exact inserted set
from `createBatch` (`packages/server/lib/data/repository/forward_edge_repository.dart:99-146`),
but `ForwardCase` discards it and returns only `batchId`
(`packages/server/lib/domain/use_case/forward_case.dart:273-319`).

Concrete failure: Alice requests Bob and Carol. Carol pauses, while Bob becomes hidden because of
a concurrent block. Both are absent or unchanged after reload. A client diff cannot truthfully
say which was skipped for availability; rev 2's localized partial-delivery message can
misattribute the block case to a pause. Separately, §11 tells the client to strip a locally
ineligible selected id before sending. Unless that id remains in the requested denominator and
is explicitly reported, the client itself has silently changed what Alice asked for—the behavior
D11 rejects.

Smallest correct fix: make S7b mandatory for correctness. Return a typed result such as
`{batchId, deliveredIds, availabilitySkippedIds}` from the transactional server operation, and
build both snackbar and beacon-create confirmation from it. If the client removes a stale
selection before the call, surface that adjustment and keep it in the requested count; otherwise
fail visibly rather than silently rewriting the action.

### 6. HIGH — the write-side business rules are allocated to the resolver instead of a use case

Rev 2 repeatedly says “the resolver clamps” and lists a mutation controller plus repository, but
its server blast radius contains no availability use case. The existing user resolver is thin:
it extracts credentials/input and delegates to `UserCase`
(`packages/server/lib/api/controllers/graphql/mutation/mutation_user.dart:28-49`), while validation
and orchestration live in `UserCase`
(`packages/server/lib/domain/use_case/user_case.dart:52-103`). Horizon enforcement, patch
semantics, pair construction, and delete-on-empty are domain/application rules, not GraphQL
adapter behavior.

Concrete failure: a later REST/internal caller reaches the repository without the resolver clamp,
or resolver tests pass while a retry splits the pause pair update from deletion. The invariant is
owned by one transport rather than the application boundary.

Smallest correct fix: add a `UserAvailabilityCase` (or equivalently focused application use case)
that owns validation and the atomic patch port. The GraphQL resolver should only preserve explicit
field-presence flags, authenticate the subject, and delegate. Bind repository implementations to
domain-owned ports through DI.

### 7. MEDIUM — D27 is stale enum machinery from rev 1

The new storage/wire model is a Boolean plus a nullable date, and the view enum is derived from
both. There is no availability smallint to map. The three duplicated functions rev 2 cites are
specifically presence-status decoders
(`packages/client/lib/data/model/user_model.dart:35-42`,
`packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart:68-75`,
`packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart:262-269`).

Concrete failure: an implementation plan invents an ordinal mapping for `AvailabilityView`, then
some V2 mapper treats `is_limited` as that ordinal or freezes `paused` at map time, contradicting
D1 and D3.

Smallest correct fix: delete D27 and the “smallint/bool mapper” language for availability.
Centralizing the existing presence decoder is a valid cleanup, but it is unrelated scope. Share
the availability derivation function/value object instead—after D21 is resolved.

### 8. MEDIUM — the revised unseen count deliberately disagrees with the rows it counts

The live unseen tab renders `visibleRecipients`, whose unseen branch uses `isUnseen`
(`packages/client/lib/features/forward/ui/bloc/forward_state.dart:183-207`). The count is painted
directly beside that tab label (`packages/client/lib/features/forward/ui/widget/forward_scope_links.dart:49-65,108-118`).
Rev 2 keeps paused unseen rows visible but tells `scopeCounts.unseen` to exclude them. That yields
“Unseen (0)” above a list containing paused unseen rows. No change to `isUnseen` is required for
the desired visible-disabled behavior; checkbox disablement already follows `canForwardTo`
(`packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart:115-145,352-356`).

Concrete failure: three paused, never-involved people remain visible on the default tab while its
counter says zero. The correction creates the contradiction it says it removes.

Smallest correct fix: decide what the count means. If it is row count, keep paused `isUnseen`
rows in it. If it is actionable count, rename the tab/count and expose unavailable count
separately. Do not silently redefine an “Unseen” count as “forwardable unseen.” Also note that
`all` and `bestNext` are not selectable in the production `ForwardScopeLinks`; only unseen and
already-involved are exposed at `forward_scope_links.dart:108-119`.

## 3. Rev 1 fixes that are still wrong or incomplete

### 1. Lazy lapse still leaves public episode history, so D4/invariant 3 remain overstated

Rev 2 improved the privacy wording, but a pause-only row that lapses remains
`{false, expired paused_until, expired paused_until_day}` until the optional janitor runs. The
proposed Hasura shape exposes the day, just as the current presence relationship exposes raw
allowed columns under its select permission (`hasura/metadata.json:989-1033`), and current entity
mapping carries raw nested values rather than expiring them in the adapter
(`packages/client/lib/data/model/user_model.dart:8-31`). Therefore derived `open` can have a row
and can reveal “paused until last Tuesday.” The CHECK only rejects `{false, null}`; it does not
delete expired rows.

Concrete failure: a viewer queries the nested relationship on Tuesday after a Monday lapse and
reads the prior pause day even though rev 2 says open stores nothing and no public history is
structural.

Smallest correct fix: narrow the claim to “explicit reset stores no row; lazy expiry may leave a
public past end-day until cleanup,” or make the read API suppress expired pause-only rows. If
suppression is load-bearing, implement it in the API/relationship rather than the optional
janitor.

### 2. D25 fixes server construction sites, but §8 still misses the client-side V2 mapping sites

Making `UserPublicRecord.availability` a required named parameter will correctly fail every
server constructor. It does not force the clients of those V2 payloads to put availability on
`Profile`, because `Profile.availability` is planned with a safe default. The V2 shared mapper is
`packages/client/lib/data/model/user_public_model.dart:8-33`; mutual friends maps its generated
shape separately (`packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart:36-62`),
and coordination maps another V2 user shape separately
(`packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart:241-259`).
None appears in §8.

Concrete failure: server read parity is perfect, but profiles arriving through invite genealogy,
blocks, invitations, mutual friends, or coordination map to default-open on the client. The
server compiles and the UI fails open.

Smallest correct fix: expand read parity to both sides of the boundary: server producer sites
plus every client adapter that constructs `Profile` from `GUserPublicModel` or a V2 user-shaped
type. Add `user_public_model.dart`, `mutual_friends_repository.dart`, and
`coordination_repository.dart` to §8 and to parity tests.

### 3. §9.4 fixes `forwardedByMe` but leaves four involvement states without precedence

The live relation function has distinct labels for `author`, `declined`, `helpOffered`, and
`withdrawn` as well as `forwardedByMe`
(`packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart:69-88`). All four are
already ineligible under `canForwardTo`
(`packages/client/lib/features/forward/domain/entity/forward_candidate.dart:35-41`), and the
already-involved scope includes all non-unseen, non-author states
(`packages/client/lib/features/forward/ui/bloc/forward_state.dart:152-156`). Rev 2's table specifies
paused behavior only for unseen/forwarded/watching and forwardedByMe.

Concrete failure: a paused person who declined is shown in already-involved. The generic fifth
precedence rule says pause replaces the decline relation even though pause is not why the row is
ineligible. The same ambiguity applies to help-offered and withdrawn rows.

Smallest correct fix: preserve every already-ineligible involvement label, not only
`forwardedByMe`; availability may replace the relation only for otherwise-forwardable
unseen/forwarded/watching rows. Resolve S10 before planning because a paused band row currently
gets tier evidence or no second line at all
(`packages/client/lib/features/forward/ui/widget/forward_band_strip.dart:109-135`).

### 4. “Recompute at send” does not repair a lapsed disabled row

Row eligibility is computed only when Flutter rebuilds the widget
(`packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart:115-145`). If the row
was paused when built, its row and checkbox taps are disabled
(`packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart:140-145,474-517`). With
no selected recipients the cubit exits before any send-time logic
(`packages/client/lib/features/forward/ui/bloc/forward_cubit.dart:385-390`).

Concrete failure: Carol's pause lapses while she is the only person Bob wants. Bob still cannot
select her, so there is no send on which to “recompute.” The server would accept the forward, but
the client remains fail-closed until some unrelated rebuild/refetch.

Smallest correct fix: schedule a bounded local rebuild at the next known expiry when the client
has a usable boundary, or refresh/re-evaluate on app resume and picker interaction. If D21 keeps
the exact boundary server-only, own this as an unavoidable fail-closed session stale case rather
than claiming send-time recomputation closes it.

### 5. D19 is a useful principle but not yet a closed, enforceable surface inventory

The person-targeted forward affordances are the other-profile primary/secondary buttons
(`packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart:290-319,342-373`),
the graph-panel equivalents
(`packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart:147-200`), and the
deep-linkable person-forward screen, including its “New request” path
(`packages/client/lib/features/forward/ui/screen/person_forward_screen.dart:98-123,308-330`). The
shared recipient picker is hosted by the ordinary forward page and the beacon-create recipients
tab (`packages/client/lib/features/forward/ui/screen/forward_beacon_screen.dart:35-48`,
`packages/client/lib/features/beacon_create/ui/widget/recipients_tab.dart:127-141`) and itself has
standard, lineage, band, and full-screen search presentations; search reuses
`visibleRecipients` but is a separate row host
(`packages/client/lib/features/forward/ui/widget/forward_search_overlay.dart:271-335`). In the
opposite direction, `lineage_suggestions_sheet.dart` reuses `ForwardRecipientRow` with no send
action (`packages/client/lib/features/forward/ui/widget/lineage_suggestions_sheet.dart:133-149`),
so an unconditional row-level availability line would violate D19's “none that don't” half.

Concrete failure: an implementer changes the shared row and covers all picker hosts, but also
renders availability in the read-only lineage preview. Or they gate the existing-send button on
person-forward but leave “New request” enabled for the same paused person.

Smallest correct fix: define D19 as applying to a displayed subject adjacent to an affordance
that can newly involve that subject, enumerate the hosts above, and make the row's availability
slot an explicit host policy. Generic buttons that merely open a recipient picker do not need to
show every possible recipient's constraint; the picker does. Add the missing hosts to §8.

## 4. Attack on the orthogonal model

The orthogonal model is **semantically more faithful than the rev-1 enum, but it is not simpler**.
It replaces a hidden fallback rule with an explicit overlay, which is a legitimate trade, not a
reduction in state space. Storage has four meaningful states: absence/open, limited, pause-only,
and limited+pause. Lazy expiry adds two ghost variants: expired pause-only derives open while a
row remains, and expired limited+pause derives limited while stale pause columns remain. The
fallback edge is now easy to explain, but it still exists and must be tested.

The sequential transitions are coherent only if one atomic patch owns them:

| Action | Open/absence | Limited | Pause-only | Limited + pause |
|---|---|---|---|---|
| Set limited | insert limited | no-op | limited + same pause | no-op |
| Clear limited | no-op | delete | no-op | pause-only |
| Pause/replace | insert pause | limited + pause | replace pair | replace pair, keep limited |
| Resume | no-op | no-op | delete | limited |
| Lapse | stays absent | stays limited | derived open, stale row | derived limited, stale pair |

No sequential transition inherently creates an orphan or wrong fallback. The failure surface is
the patch implementation: the row must preserve an omitted field, clear an explicit-null field,
update the instant/day pair together, and delete only from the combined post-patch state. The
two-device clear-limited/resume example in finding 2.3 demonstrates why ordinary last-write-wins
upserts are not sufficient. Current code's transaction wrapper is capable of hosting the
boundary (`packages/server/lib/data/database/tentura_db.dart:182-209`), but the architecture must
name it.

The two-line own-profile rendering is coherent UX, not itself a defect. It truthfully tells the
user what will reappear after a pause. I found no blocking issue with that presentation. The
cost is that orthogonality is visibly part of the product: two controls, two network mutations,
and a two-line combined state. That cost is justified only if combined limited+paused is an
actual supported state, as rev 2 now decides.

D2 overstates the rot distinction. A permanent `is_limited` cannot create a stale hard block,
but it can still rot as a public social statement and mislead senders indefinitely. The correct
claim is “rot of limited is lower impact because it does not block,” not “dispositions do not
rot.” This is a product risk, not a blocking storage defect.

## 5. Verified correct

1. **D5's corrected storage precedent holds; no blocking issue found.** Presence really is
   `UNLOGGED`, backfilled, and inserted by `on_user_created`
   (`packages/server/lib/data/database/migration/m0007.dart:15-24,55-71`). Its Hasura shape is an
   object relationship plus select-only permission filtered by `hidden_for_viewer`
   (`hasura/metadata.json:807-825,989-1033`). Availability should copy that permission shape but
   use a logged, sparse table with no creation trigger/backfill/write permission.

2. **The Drift/migrant statements are correct; no blocking issue found.** Tables are registered
   in `@DriftDatabase` (`packages/server/lib/data/database/tentura_db.dart:88-149`), Drift runtime
   migrations are disabled and `schemaVersion` remains 1
   (`packages/server/lib/data/database/tentura_db.dart:153-169`), while app DDL is registered in
   the migrant list (`packages/server/lib/data/database/migration/_migrations.dart:154-304`).

3. **D25's server-side compile-time claim holds.** `UserPublicRecord` uses required named
   parameters for required fields (`packages/server/lib/domain/entity/gql_public/user_public_record.dart:10-22`).
   Adding `required this.availability` will fail all three production constructor sites:
   `user_profile_batch_lookup.dart:120`, `mutual_friends_repository.dart:112`, and
   `invite_genealogy_gql_maps.dart:102`, plus tests. `query_invitation.dart` is correctly called
   out separately because it patches a map rather than constructing the record
   (`packages/server/lib/api/controllers/graphql/query/query_invitation.dart:36-60`). The client
   adapter gap in finding 3.2 remains.

4. **D26 is correct.** Direct V2 routing is operation-name allow-listed and unlisted operations
   use Hasura (`packages/client/lib/data/service/remote_api_client/build_client.dart:152-182`);
   `ProfileUpdate` is explicitly present at line 252. `UserAvailabilitySet` must be added.

5. **The main §11 correction is directionally correct.** Adding availability to
   `canForwardToAt(now)` makes paused candidates disappear from `all`/`bestNext`, while the
   default unseen branch continues to list them because it uses `isUnseen`
   (`packages/client/lib/features/forward/ui/bloc/forward_state.dart:183-219`). The row then
   disables selection via the same eligibility predicate. The desired unseen behavior does not
   require changing `isUnseen`; rev 2 is clear on that. The count error and the fact that
   all/bestNext have no production tab remain finding 2.8.

6. **The pre-selection and deselection diagnosis is correct; no blocking issue found in those
   two changes.** Both lineage `autoSelectIds` and profile `initialSelectedIds` are intersected
   only with ids present in the loaded lists
   (`packages/client/lib/features/forward/ui/bloc/forward_cubit.dart:170-207`). The row disables
   both its outer tap and checkbox tap whenever `canForwardTo` is false
   (`packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart:120-145,474-517`),
   so an already-selected candidate that becomes paused needs the proposed selected-row
   deselection exception. The third proposed change, stripping at send, remains blocked by
   finding 2.5 unless the adjustment is reported in the typed result.

7. **The profile/graph flag-tuple correction is right; no blocking issue found in that branch.**
   Both surfaces use `PersonActionPolicy`, and `showRequestOptions` independently opens a live
   person-forward door (`profile_view_body.dart:342-373`,
   `graph_person_context_panel.dart:174-200`). A paused branch must set `primaryAction: none` and
   `showRequestOptions: false`, then render dedicated explanation copy. Keeping
   `PersonForwardBlock` unchanged is also correct; person availability belongs in
   `PersonForwardState.canSend` and `PersonForwardCubit.send`
   (`person_forward_state.dart:24-29`, `person_forward_cubit.dart:113-127`).

8. **D20 now points at the right source of weekday formatting.** The current helper uses
   `DateFormat('EEE')` (`packages/client/lib/ui/utils/beacon_card_deadline.dart:27-35`), whereas
   presence does not. It still needs a new/extracted beyond-seven-days date branch; the current
   function emits a weekday for every future date.

9. **D28's product reasoning is defensible; I found no authorization bypass by the issuer.** The
   issuer can mint a beacon invite, but the edge is created only when the recipient consumes it
   (`packages/server/lib/data/repository/user_repository.dart:112-145,847-853`). Existing-user
   acceptance is authenticated, rejects blocked pairs, and is initiated by the accepting user
   (`packages/server/lib/domain/use_case/invitation_case.dart:262-315`). The client confirmation
   explicitly shows the request title/snippet before Yes
   (`packages/client/lib/features/invitation/ui/dialog/invitation_accept_dialog.dart:40-92`). That
   is informed recipient opt-in, not issuer-side push. D28 should therefore be marked resolved,
   not simultaneously left open as S5.

10. **The exposed-day half of D21 closes the specific offset leak.** A bare date does not reveal
   the subject's UTC offset. The blocker is loss of exact shared expiry semantics, not failure of
   the narrow privacy mitigation.

11. **Core dependency direction is sound.** Client entities/presets remain inward and pure;
    `ProfileCubit` can remain a one-port cubit. Server `ForwardCase` already depends on
    domain-owned ports rather than data repositories
    (`packages/server/lib/domain/use_case/forward_case.dart:1-53`). Add availability through a
    port and typed result; do not move the rule into UI/data/controller code.

## 6. Residual risks and evidence gaps

1. **§8 is still incomplete.** At minimum add:
   `packages/client/build.yaml` and the tracked `data/gql/schema.graphql` for the new Hasura
   `date` scalar (current overrides cover `Date`, `v2_Date`, and `timestamptz`, not lowercase
   `date`, at `packages/client/build.yaml:29-51`); `data/model/user_public_model.dart`;
   `mutual_friends_repository.dart`; `coordination_repository.dart`;
   `forward_search_overlay.dart`; `forward_scope_links.dart`;
   `person_forward_cubit.dart`; `forward_messages.dart`; `beacon_create_cubit.dart` and
   `beacon_send_confirmation_dialog.dart`; and `lineage_suggestions_sheet.dart` for the explicit
   no-render host policy. The server list also needs an availability use case and a typed forward
   result/API type.

2. **Several “executable invariants” are not executable as written.** Invariant 1 is impossible
   under D21 and also says “one function” while §5 allocates separate client and server entities.
   Invariant 3 conflicts with lazy lapsed rows. Invariant 5 covers server payload sites but not
   client adapters. Invariants 7-8 require transactional/result contracts the design omits.
   Invariant 12 quantifies over all present and future Send surfaces and needs an enumerated host
   registry or architecture test. Invariant 13 explicitly requires human review. Invariant 14
   spans local calendar selection, server clock, offset/DST, and the 90-day instant boundary; a
   shared numeric constant alone does not prove it.

3. **§15 mixes decided and open state.** D28 and S5 contradict each other. S10 is load-bearing
   row behavior, not optional polish, and must close before a plan. S7b is required once D23 is
   made honest. S11 should default to raising `kDefaultMinClientVersion`: otherwise old clients
   are server-filtered while reporting requested counts. S12 can remain an explicit scope choice
   because it does not affect enforcement.

4. **No PostgreSQL concurrency evidence exists yet.** Required future tests must use two real
   connections and prove both availability patch linearization and pause-vs-forward insertion.
   Sequential Drift/SQLite-style tests cannot establish either property.

5. **No Hasura/runtime evidence closes the `limit: 10` question.** The permission limit is real
   (`hasura/metadata.json:957-983`), but whether it caps the tracked SETOF function remains an
   explicit integration-test gap. There is no blocking availability-specific finding beyond the
   documented risk.

6. **The date scalar/codegen path is unproven.** Current schema has no Hasura lowercase `date`
   scalar and the build config has no matching override. Before accepting D21, generate the real
   Hasura schema and prove round-trip behavior on web/native clients without timezone shifting.

7. **Mixed-version behavior remains a release gate.** Rev 2 correctly identifies the risk but
   leaves it to S11. Server-side partial delivery plus old-client requested-count confirmation is
   observably false; do not call the architecture safe while that rollout decision is open.
