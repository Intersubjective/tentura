# Adversarial review — availability-request-receptiveness-architecture (rev 1)

Reviewer posture: every load-bearing factual claim was checked against the code. Findings are
ranked by severity. Line numbers are as of the working tree on 2026-08-13.

## 1. Verdict

**Not safe to derive an implementation plan from as-is.** The storage/privacy/read-path skeleton
(§3–§6, §12) is unusually well-grounded — I verified the `user_presence` precedent, the
`user.updated_at` oracle claim, the realtime-trigger argument, and the V2 mirror mechanics, and
they are essentially all correct. But the document's core behavioral section, §11 (recipient
picker semantics), is written against **dead code**: `computeBeaconListSections()` and its four
buckets have zero call sites, the live picker renders `visibleRecipients`, and the default scope
(`unseen`) does not consult `canForwardTo` at all. A plan derived from §11 would implement the
feature where nobody will see it and leave the actual picker behavior wrong. On top of that, the
doc misses the lineage auto-select path, the band-row label override, two of the four server-side
`UserPublicRecord` construction sites, and the fact that "silent drop" composes with the client's
"forwarded to N people" confirmation into a systematic lie to the sender. None of these are fatal
to the design; all of them must be fixed in the document before a plan can be derived, because
each changes what the plan's tasks are.

## 2. Blocking findings

### B1. §11 describes dead code; the live picker path ignores `canForwardTo` in the default scope

**Doc claims** (§2 row 5, §11): `ForwardState.computeBeaconListSections()` is "the four-bucket
layout (`recommended` / `other` / `unavailable` / `notReachable`)"; "`paused` candidates already
fall out of `recommended` once `canForwardTo` is false"; "`unseen` and `bestNext` inherit the
`canForwardTo` change automatically"; "Scope counts (`ForwardScopeCounts.unseen`) shrink
accordingly".

**Reality:**
- `computeBeaconListSections` has **no callers** anywhere in `packages/client` (grep for
  `computeBeaconListSections` / `ForwardBeaconListSections` returns only
  `packages/client/lib/features/forward/ui/bloc/forward_state.dart` itself). The
  `recommended`/`other`/`unavailable`/`notReachable` buckets are never rendered.
- The picker renders `state.visibleRecipients`
  (`packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart:352`).
- The default filter is `ForwardFilter.unseen`
  (`forward_state.dart:105`), and the `unseen` branch filters on `c.isUnseen` — **not**
  `canForwardTo` (`forward_state.dart:194-198`; same in `_filteredFlatFromBase`,
  `forward_state.dart:216-217`). Only `all` and `bestNext` use `canForwardTo`
  (`forward_state.dart:190-193, 215`).
- `ForwardScopeCounts.unseen` counts `isUnseen` only (`forward_state.dart:170-176`). Involvement
  is computed purely from beacon involvement (`forward_case.dart:236-265`) and knows nothing
  about availability, so a paused candidate stays `unseen` forever.

**Why it breaks:** the described end state — paused people visibly grouped in an `unavailable`
section, counts shrinking, filters inheriting the gate — would not occur even after a perfect
implementation of §11, because the sectioned layout doesn't exist in the running app. What would
actually happen: paused people **vanish** from the `all` and `bestNext` scopes (no "unavailable"
grouping, no explanation), and **remain** in the default `unseen` scope with a disabled checkbox
and the `l10n.forwardFilterUnseen` label ("Unseen", `app_en.arb:2134`), while the "N unseen"
scope count still includes them.

**Smallest correct fix:** rewrite §11 against the real code: (a) gate the `unseen` branches of
`visibleRecipients` and `_filteredFlatFromBase` on `canForwardToAt(now)`, or redefine
`isUnseen`/`scopeCounts` to exclude blocked-by-availability candidates; (b) delete or explicitly
revive `computeBeaconListSections` — if the "unavailable section" UX is wanted, it is **new UI**,
not a consequence of an existing one; (c) state explicitly what the default `unseen` list does
with a paused row (drop it vs. show disabled with the availability label).

### B2. Lineage suggestions and their auto-select are not gated

**Doc:** §11 never mentions `lineageSuggestions`, `autoSelectIds`, or `initialSelectedIds`.

**Reality:**
- Lineage rows render in their own block in every scope except `alreadyInvolved`
  (`forward_recipient_picker.dart:353-357, 583-612`), independent of `canForwardTo`.
- `_loadCandidates` pre-checks `load.autoSelectIds`
  (`forward_cubit.dart:179-181`) when `preselectLineageSuggestions` is true — which it is in the
  beacon-create fork flow (`beacon_create_screen.dart:150-152`). Auto-select is computed
  server-side with no availability input.
- `initialSelectedIds` (profile → new request, `beacon_create_screen.dart:153-155`) is
  intersected with `availableIds`, which includes paused candidates
  (`forward_cubit.dart:170-192`).
- `forward()` then rejects the whole send with the generic
  `IneligibleRecipientsException` ("Some recipients cannot receive forwards",
  `forward_cubit.dart:407-413`, `features/forward/domain/exception.dart:11`) — after the user
  has composed an entire request in the create flow.

**Why it breaks:** the feature's hardest surface is precisely the pre-selected checkbox: the
product auto-checks a paused person, the row can't explain itself (B3), and the send fails with
a message that names no one. "The client already excludes them" (§7) is false for every
pre-selection path.

**Smallest correct fix:** filter `autoSelectIds` and `initialSelectedIds` through
`canForwardToAt(now)` at load time in `_loadCandidates`; render paused lineage rows with the
availability label and disabled checkbox; decide whether the lineage engine itself should stop
suggesting paused users (it won't, without server changes — say so).

### B3. The recipient-row claims are wrong about its actual structure

**Doc claims** (§9.4, D12): line 2 "currently reads `<presence> · <relation label> · <receipt>`";
availability can "replace the presence slot" (`limited`) or "replace both presence and the
relation label" (`paused`) with row height unchanged; label precedence "`notReachable` → `paused`
→ involvement label" (§11).

**Reality** (`forward_recipient_row.dart`):
- Line 2 is a `Wrap` of: presence `Text` (only if non-empty), then **either** a `ShowMoreText`
  of my forward note **or** `TenturaStatusText(relationLabel)`, then a read-receipt icon — the
  receipt and note exist only for `forwardedByMe` (`:196-233`).
- `tierEvidenceLabel` **replaces the entire Wrap** (`:191-196`), and `showPresenceLine: false`
  (band exploration rows, `forward_band_strip.dart:134`) suppresses it. Both override the very
  slot the doc plans to occupy. The precedence list omits `tierEvidenceLabel` entirely: a paused
  person shown as a band evidence row would display capability evidence + a disabled checkbox
  with **no reason anywhere**.
- The `notReachable → paused → involvement` precedence, applied naively, replaces the
  "Forwarded by you" label and read receipt for a recipient who paused *after* you forwarded —
  destroying the edit/cancel affordance context (`:276-311`) and contradicting the doc's own D18
  ("already involved is already involved", §11 line 520-521).
- "Row height unchanged" is only approximately true: the Wrap is variadic; replacing
  `bodySmall` presence with `TenturaStatusText` changes line metrics, and the `paused` case
  removes a Wrap child (the relation label), which changes wrap behavior for long notes.

**Smallest correct fix:** define precedence over all four real slots:
`tierEvidenceLabel → notReachable → involvement(never overridden for forwardedByMe)`, with
availability replacing **only the presence `Text`** for `limited`, and for `paused` replacing
presence **and** the involvement label only when involvement is `unseen`/`forwarded`/`watching`.
State what band evidence rows and `showPresenceLine: false` rows do with a paused candidate
(disabled checkbox + no line is the current outcome of the doc as written — presumably not
intended).

### B4. The V2-mirror inventory misses two of four `UserPublicRecord` construction sites

**Doc claims** (§2 last row, §6 "V2 (mirror)"): the mirror work is `userPublicToGqlMap` +
`UserPublicRecord` + `gqlTypeUserPublic` + `user_profile_batch_lookup.dart`; forgetting the batch
join is "the easiest thing in the feature to miss".

**Verified true for those four** (`gql_public_user_maps.dart:16-24, 35-46`;
`user_public_record.dart:21, 42`; `user_profile_batch_lookup.dart:54, 83-99`;
`custom_types.dart:456-460, 463-478`). **But incomplete:** `UserPublicRecord` is also constructed
by:
- `MutualFriendsRepository.fetchMutualFriends`
  (`packages/server/lib/data/repository/mutual_friends_repository.dart:100-124`) — builds the
  record by hand, including a **per-user** presence fetch (not the batch lookup).
- `_userToPublic` in
  `packages/server/lib/api/controllers/graphql/mappers/invite_genealogy_gql_maps.dart:95-103` —
  already omits `userPresence` entirely.

If `availability` is an optional/nullable field on the record (as `userPresence` is), both sites
compile unchanged and silently report `open` — the exact failure mode §12 calls "invisible in
testing unless asserted", on paths invariant 4 ("read parity") does not name. The doc's own
warning applies to the doc.

**Smallest correct fix:** enumerate every `UserPublicRecord(` construction site in §6 (there are
four today) and make the invariant "every construction site" rather than "the batch lookup".
Consider making the record field required so omission is a compile error.

### B5. "Silently drop on partial" (D11) composes with the client into a false delivery confirmation

**Doc claims** (§7, D11): silent partial drops "only fire on a real race (they paused between
the picker's fetch and the send)".

**Reality:**
- On success the cubit reports the **requested** set, not the delivered one:
  `ForwardSentMessage(recipientIds.length)` ("Request forwarded to N people",
  `forward_cubit.dart:417, 460`; `forward_messages.dart:9-11`) and
  `ForwardDeliveryOutcome(deliveredRecipientIds: recipientIds)` (`forward_cubit.dart:448-450`).
- The staleness window is not a race: availability emits **no** realtime event (D17) and the
  picker's only reload triggers are forward/contact/block changes
  (`forward_cubit.dart:63-93`). A picker kept open across someone's pause will never learn about
  it; every send from a long-lived picker session is a "race". The window is the session
  lifetime, not milliseconds.
- After the silent drop the sender can detect the contradiction anyway: post-send reload flips
  delivered recipients to `forwardedByMe` while the dropped one stays `unseen`. So D11 is not
  even silent — it is silently wrong in the snackbar and visibly inconsistent in the list.

**Separately verified in the doc's favor:** the mechanism is implementable. `ForwardCase.forward`
already silently drops self (`packages/server/lib/domain/use_case/forward_case.dart:191-196`) and
blocked recipients (`:197-203`) and returns `batchId` even when the delivery set is empty
(`:232` skips the visibility check; `createBatch` with an empty list succeeds) — so "throw on
total" is **new** behavior, not the existing convention, but it needs no change to the `String!`
return (`mutation_forward.dart:64-66`), and a thrown domain exception surfaces through
`_emitSnackError` (`forward_cubit.dart:95-100, 476`).

**Smallest correct fix:** either (a) drop the "silence" requirement — reconcile after send by
reloading and showing "N of M couldn't receive this" (the data is already client-side); or (b)
keep silence but stop lying: compute the confirmation from the post-send candidate state, not
the request. Also delete the "real race" sentence; write the failure-mode table entry as
"staleness window = picker session".

### B6. `PersonActionPolicy` "one branch" — the mechanism is right, the cited pattern doesn't do what the doc says

**Doc claims** (§9.3): one new branch suppresses `PersonPrimaryAction.sendRequest`, "replaced by
the existing disabled-explanation pattern already used for `profileRequestUnavailable`".

**Reality:** the `profileRequestUnavailable` text renders only when
`primaryAction == none && showRequestOptions && viewerExplicitlyTrustsSubject`
(`profile_view_body.dart:342-353`) — and the same `showRequestOptions` flag renders a working
"Request options" button that opens the person-forward screen (`profile_view_body.dart:365-373`;
mirrored in `graph_person_context_panel.dart:188-201`). The current `isMutuallyVisible` branch
sets `showRequestOptions: false` (`person_action_policy.dart:65`), so the new paused branch must
*choose*: copy the none-branch flags (explanation text **plus** a live door into person-forward,
where §9.5's banner must then block everything — including the "New request" button,
`person_forward_screen.dart:328`) or suppress both (in which case it is not "the existing
pattern"). The doc picks neither.

Verified in the doc's favor: both profile surfaces and the graph panel construct the policy via
`PersonActionPolicy.from` (`profile_view_body.dart:42`, `graph_person_context_panel.dart:38`),
and the graph panel's profile comes from a `UserModel`-fragment query
(`features/graph/data/gql/graph_fetch.graphql:28`,
`graph_repository.dart:145`), so one branch does cover all three — provided `Profile.availability`
has a safe `@Default` (consistent with `presenceStatus` at `profile.dart:34-35`).

**Smallest correct fix:** specify the exact flag tuple for the paused branch
(`primaryAction: none`, and an explicit yes/no on `showRequestOptions`), and state that the
explanation copy replaces — not accompanies — the "Request options" affordance if S2's "hard, no
override" is to mean anything on this surface.

### B7. Minor verified doc errors (would mislead a plan, cheap to fix)

1. **D20 misstates the convention it reuses.** `profilePresenceDisplayLine` does *not* render a
   weekday inside 7 days — it renders relative durations ("Last seen 3d ago",
   `ui/utils/profile_presence_line.dart:28-42`), and it calls `DateTime.now()` internally
   (`:24`), unlike the injected-`now` convention §8 cites (that convention is real for
   `formatScheduleDate(..., now: ...)`). The 7-day boundary matches; "reuses verbatim" does not.
2. **§15 delivery constraints omit the V2 routing registration.** A new `userAvailabilitySet`
   mutation must be added to `_tenturaDirectOperationNames`
   (`packages/client/lib/data/service/remote_api_client/build_client.dart:159-170`) or the client
   routes it through Hasura's remote-schema proxy. Works, but violates the documented V2 routing
   procedure (codegen.mdc § Ferry).
3. **`tentura_root` path.** The shared enum file is `lib/domain/enums.dart` at the **repo root**
   (the `tentura_root` package lives at root), not under `packages/`. §5's table is ambiguous
   about this; §8's `tentura_root/lib/domain/enums.dart` is fine only if read as a package
   reference. `UserPresenceStatus` is confirmed there (`lib/domain/enums.dart:6-11`).
4. **The smallint↔enum mapping is not centralized.** It is a hand-duplicated switch in at least
   three client places (`data/model/user_model.dart:35-41`,
   `features/profile_view/data/repository/mutual_friends_repository.dart:68-74`,
   `features/beacon_view/data/repository/coordination_repository.dart:262-266`). "Same int-enum ↔
   smallint mapping" (§2) means "write a fourth copy" unless the doc prescribes a shared mapper.

## 3. Design objections

### O1. D11's silence is the wrong default even where it works

The permission-wall precedent the doc cites is a *read* convention (rows you may not see simply
don't appear). Forwarding is a *write with a confirmation*: the sender is told "Request forwarded
to N people" (`forward_messages.dart:9-11`). Silence converts a boundary the *recipient* set into
a false belief in the *sender*, with the contradiction one pull-to-refresh away (B5). The
90-second alternative: after send, diff requested vs. now-`forwardedByMe` recipients and show
"Delivered to N of M — Carol isn't taking new requests right now." This needs no API change
(the client refetches anyway) and preserves every privacy property except "the sender can never
learn the pause happened", which D11 does not achieve anyway (the total-failure throw announces
exactly that). If product insists on silence, the confirmation must at least stop quoting the
requested count.

### O2. Mandatory `until` on `limited` (D2) will be the feature's biggest source of annoyance-driven abandonment

The doc's own S3 states the cost: "a genuinely long-term low-bandwidth disposition must be re-set
every ≤ 90 days." That is not a corner case — "I'm a slow responder, be selective" is a standing
trait for exactly the people this feature serves, and D2 forces them into a quarterly ritual
whose penalty for forgetting is silent reversion to `open` (D3) — the one outcome they explicitly
didn't want. The doc argues "a disposition without an end date is a profile trait"; true, and the
conclusion should follow: `limited` is trait-like, `paused` is episode-like. Alternative:
`CHECK ((state = 2 AND until IS NOT NULL) OR (state = 1))` — mandatory horizon on the hard state
(where rot is dangerous), optional on the informational one (where rot is harmless because it
blocks nothing, D13). Keep the 90-day clamp for `paused`. This weakens no invariant except the
aesthetic "one rule".

### O3. The `until` value is a timezone oracle; the privacy table (§12) misses it

D21 resolves presets to *local midnight* and stores UTC. `until` is exposed verbatim via Hasura
(`state`, `until` columns). A value like `2026-08-17T22:00:00Z` is midnight in UTC+2 — any
technically able viewer reads the subject's approximate timezone (and, combined with day
boundaries, their rough geography and DST regime) off a field the doc treats as inert. This is
exactly the class of side channel §12 prides itself on excluding, and it's structural, not
implementation sloppiness. Alternative: expose day granularity on the wire (`until_day date`) and
keep the instant server-side for enforcement; or accept and document the leak in §12 with a
rationale. Either way it belongs in the table — currently the doc's "bounded by day-granularity
display" claim confuses *display* granularity with *wire* granularity.

### O4. "Structurally impossible to read" (§12, row 2) overclaims

What is true: no history table, `open` deletes the row (D4), `updated_at` unexposed (D6), and the
`profile` realtime trigger fires only on `display_name`/`description`/`handle`/`image_id` changes
(`m0114.dart:723-737`), so side-table writes genuinely emit nothing. All verified. What is not
true: "who paused right after I asked" being unreadable. The *current* state is rendered on the
profile and in the picker; any viewer who remembers yesterday's read can diff. D11's
total-failure throw is a real-time oracle by design. The claim should be scoped to "no stored
history and no mutation timestamp", which is strong enough; as written it invites a security
reviewer to "find" the obvious counterexamples and discredit the sound parts.

### O5. D18's boundary is clean for verbs but not for recommendations

Enumerating the product's "involve in a new request" verbs: `beaconForward` (picker, person
forward, embedded create — all funnel through `ForwardCase.forward`, verified) is the only
write verb, and the doc gates it. Invitations create accounts (no availability to violate), room
admission and help offers concern existing requests (D18's exclusion is defensible), mentions
live inside rooms. The boundary problem is not verbs but **the product's own recommendations**:
the lineage engine emits auto-select suggestions (`forward_case.dart:184-187`) and the capability
band promotes people with evidence tiers — both will keep recommending paused users as *the best
recipients*, with the picker pre-checking them (B2). "Existing interactions untouched" is the
right rule for state; "the recommendation engine keeps vouching for paused people" undermines
the feature's point. At minimum the doc should state that suggestion/band generation is
availability-blind by decision, and that auto-select filtering happens client-side.

### O6. D3's lazy expiry is right, but the doc should own its one bad case

The doc claims expired rows are "indistinguishable from `open` to every reader". With read-time
evaluation plus a selection preserved across reloads (`forward_cubit.dart:174`), a recipient
whose `until` lapses mid-session stays checked and becomes sendable with no visual change — the
inverse race to B5, and server-side it *delivers*, because enforcement evaluates at write time
and the row is now expired. So the picker can show "Not taking new requests until Monday" (stale
label) while the send succeeds. Harmless to the recipient (they're open again), confusing to the
sender. One sentence in §4 and a re-evaluation of labels at send time closes it; the doc's
"every consumer calls `effectiveAt(now)` and nothing else" needs the rider "and labels are
recomputed on every build, which nothing currently guarantees for time-triggered changes" —
Flutter does not rebuild rows when midnight passes.

## 4. Unverifiable / risky claims

- **`limit: 10` on the `user` select permission** (verified present in `hasura/metadata.json`,
  alongside `updated_at` in the exposed columns). Hasura documents that SETOF-table permissions
  apply to tracked functions like `mutually_visible_users`, but I could not confirm from the repo
  whether the *row-fetch limit* is enforced on function results at runtime, and the stack wasn't
  exercised. If it is, the forward candidate pool is hard-capped at 10 and paused users consume
  capped slots; `users_fetch_by_ids` (`users_fetch_by_ids.graphql` queries the root `user` field)
  would likewise truncate beyond 10 ids — which matters because lineage extras ride that path
  (`forward_case.dart:151`). Either way the doc should state the cap it is designing against;
  "every consumer inherits the data" is true per-row but says nothing about row count.
- **Old clients.** The doc notes the semver bump and cache-buster (§15) but never addresses
  mixed-version operation: old clients get no paused UI yet are subject to server enforcement
  (D10), i.e. silent drops + a wrong confirmation count. Whether `kDefaultMinClientVersion`
  should rise is a real product decision (versioning.mdc / DEV_GUIDELINES § Client version gate)
  and belongs in §15.
- **Remote-schema type merge.** Cloning `gqlTypeUserPresence` as a nested type on V2's `user`
  object (`custom_types.dart:456-460`) has precedent, but whether Hasura's remote-schema merge
  accepts the new nested type name without collision is asserted, not shown. Low risk, worth a
  smoke test during the first migration.
- **`ProfileCubit` as "the global own-profile singleton with a `changes` stream"** — verified
  (`profile_cubit.dart:41-47`, `profile_repository.dart:30, 95`). What I did not verify: that the
  own-profile fetch (`fetchById` → `user_by_pk`) returns the availability row for the *self* role
  under the `hidden_for_viewer` filter. `block_hides` is symmetric and self-blocking is absent
  (`m0135.dart:36-40`), so it should hold, but it is the kind of thing that fails silently at 2am.
- **Invariant 10 ("no gendered predicative adjective in Russian")** is a human review item
  dressed as an executable invariant; the l10n contract test
  (`test/l10n/request_terminology_contract_test.dart`) checks terminology, not grammar.

## 5. What the document gets right (verified, don't churn)

- **The `user_presence` precedent is real and accurately described.** The hidden-for-viewer
  computed field (`m0136.dart:184-196`), the select permission exposing exactly
  `last_seen_at`/`status`/`user_id` with the `hidden_for_viewer = false` filter and no
  `updated_at` (hasura/metadata.json, `user_presence` entry), the object relationship on `user`,
  and the `UserModel` fragment slot (`user_model.graphql:18-21`) all match §2/§5. The
  user-created vs session-created row distinction does not matter: `user_presence` has no Hasura
  insert permission either; all writes are already server-side (Drift), exactly as the V2
  mutation would be. Cloning works.
- **The `user.updated_at` oracle argument (D5) is verified, not plausible.** `updated_at` is in
  the `user` select permission columns, and the profile realtime trigger
  (`m0114.dart:723-737`) fires only on content columns — so a side table genuinely avoids both
  the timestamp oracle and any realtime emission (supporting D17).
- **The V2 mirror mechanics (§6) are exactly right about the four named files** — the claim that
  forgetting the join "fails open, invisible in testing" is precisely accurate (see B4 for the
  two sites it under-counts).
- **Server enforcement placement (§7) is correct and cheap.** `ForwardCase.forward` already
  filters recipients (`forward_case.dart:191-203`), so the paused filter has a natural home;
  "throw on total" needs no `String!` change (`mutation_forward.dart:64-66`).
- **§9.5's decision to leave `PersonForwardBlock` alone** is right: `blockFor` is a pure
  `(involvement, beacon.status)` function (`person_forward_row.dart:32-49`) and the screen
  already has a single `canSend` gate to extend (`person_forward_state.dart:28-29`).
- **`notReachable`-wins precedence** matches the row's existing structure
  (`forward_recipient_row.dart:70-75`), and `block_hides` being symmetric
  (`m0135.dart:36-40`) makes the clone's visibility gate correct for both directions.
- **The enum placement and naming note (§5)** check out: `UserPresenceStatus` lives in
  `tentura_root`'s `lib/domain/enums.dart`, and the `no_request_domain_entity` lint exists
  (`packages/tentura_lints/lib/src/rules/no_request_domain_entity.dart`), so `Availability` (not
  `RequestAvailability`) is the right call.
- **D9 (separate mutation, not `userUpdate`)** is consistent with the existing split —
  `userUpdate` exists as its own mutation (`mutation/mutation_user.dart:29`) with form-patch
  semantics — and `InputFieldDatetime` with force-UTC parsing exists as claimed
  (`input/_input_types.dart:97-112`).
- **D17's "no realtime entity" is consistent with the client's actual invalidation sources**:
  `ProfileCubit` subscribes to `RealtimeEntityKind.profile` (`profile_cubit.dart:45-47`), which
  is driven by the `user`-table trigger above — side-table writes wouldn't fire it even by
  accident.
