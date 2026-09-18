---
status: review
kind: architecture-review
source: docs/plans/availability-request-receptiveness-architecture.md
reviewer: grok-4.6
rev: 1
---
# Availability architecture — adversarial review (rev 1)

Source: `docs/plans/availability-request-receptiveness-architecture.md` (draft, rev 1).
This file does not modify the architecture document.

---

## 1. Verdict

**Do not derive an implementation plan from this document as-is.** The storage sketch (side table, Hasura object relationship, `UserModel` fragment, V2 `userPublicToGqlMap` mirror, separate `userAvailabilitySet` mutation) is pointed at the right layers, but the load-bearing picker semantics, the `user_presence` “clone”, expiry-as-privacy, and the “one-branch `PersonActionPolicy`” story are factually wrong against the current code. A plan written from §0 / §8 / §11 would implement a four-bucket layout that is dead, hide paused people from the live `all` filter, miss the invitation issuer V2 path, and ship a send path that reports success for recipients the server dropped. Fix the blocking findings and the D11/D18 product holes before planning.

---

## 2. Blocking findings

Ranked by how badly they would mis-shape a plan. Every claim below was checked in the tree.

### B1. §11 is written against dead code. The live picker is `visibleRecipients`, default filter `unseen`.

**Doc claims:** `ForwardState.computeBeaconListSections()` is “the four-bucket layout”; paused candidates “already fall out of `recommended` once `canForwardTo` is false”; §11 then pins them in `unavailable`. Filters `unseen` and `bestNext` “inherit the `canForwardTo` change automatically.” Scope counts shrink accordingly.

**Reality:** `computeBeaconListSections` is never called. The only production consumers of candidate lists are `state.visibleRecipients` and `state.scopeCounts`. ADR 0004 already recorded this:

> `ForwardState.computeBeaconListSections` is currently unused and is not the render path.

(`docs/adr/0004-beacon-lineage-fork.md` Amendment E, line 54.)

Repo-wide, the symbol exists only at its definition (`packages/client/lib/features/forward/ui/bloc/forward_state.dart:226`) and in this architecture doc. The picker builds from `visibleRecipients` (`forward_recipient_picker.dart:352`).

Default filter is `ForwardFilter.unseen` (`forward_state.dart:105`). For that filter:

```194:198:packages/client/lib/features/forward/ui/bloc/forward_state.dart
      case ForwardFilter.unseen:
        picked = _candidatesBase()
            .where((c) => !lineageIds.contains(c.id))
            .where((c) => !bandIds.contains(c.id))
            .where((c) => c.isUnseen);
```

`isUnseen` is `involvement == unseen` (`forward_candidate.dart:43`). It does **not** consult `canForwardTo`. `scopeCounts.unseen` is the same (`forward_state.dart:173`). `bestNext` / `all` **do** use `canForwardTo` (`forward_state.dart:188–193`, `_filteredFlatFromBase` at 214–215).

Worse: `ForwardFilter.all` is not “everyone, bucketed”. It is “everyone `canForwardTo`”, as a flat list. Author / declined / unreachable / already-forwarded are already omitted from `all`. Adding `!blocksNewRequestsAt(now)` to `canForwardTo` therefore **hides** paused people from `all` and `bestNext`, and **leaves them visible** (disabled) on the default `unseen` tab. That is the opposite of “put them in `unavailable`, still visible, checkbox disabled.”

Even if someone wired `computeBeaconListSections` tomorrow, the current branch order still would not match §11:

```243:253:packages/client/lib/features/forward/ui/bloc/forward_state.dart
    for (final c in base) {
      if (!c.isReachable) {
        notReachable.add(c);
      } else if (c.involvement == CandidateInvolvement.author ||
          c.involvement == CandidateInvolvement.declined) {
        unavailable.add(c);
      } else if (c.canForwardTo) {
        recommended.add(c);
      } else {
        other.add(c);
      }
    }
```

A reachable, unseen, paused candidate fails `canForwardTo` and lands in **`other`**, not `unavailable`. The doc’s “already fall out of recommended; §11 pins unavailable” is two steps, and the second step is not in the code.

**Why it breaks:** A plan that “extends `canForwardTo` and relies on existing buckets” produces hidden paused people on `all`/`bestNext`, disabled paused people mixed into default `unseen` with no section header, and tests written against `computeBeaconListSections` that never run in the UI.

**Smallest fix:** Rewrite §11 against `visibleRecipients` + `ForwardFilter` (the live path). Decide explicitly, per filter:

- `unseen` (default): show paused as disabled rows, or exclude them and shrink the count.
- `all` / `bestNext`: today these already hide non-forwardable people — either keep that (paused vanish) or stop using `canForwardTo` as the `all` predicate and actually render an unavailable section.

Then change the code that the UI calls, not the dead method. If the four-bucket layout is the product intent, the plan must **wire** `computeBeaconListSections` (or delete it and stop citing it).

Call sites of `canForwardTo` that a plan must retouch (doc missed several):

| Site | What it does today |
|---|---|
| `forward_candidate.dart:35` | getter definition |
| `forward_state.dart:193, 214, 248` | `all`/`bestNext` filter; dead bucket method |
| `forward_cubit.dart:407` | send-time ineligible check — fails the **entire** batch |
| `forward_recipient_row.dart:119, 101` | checkbox enablement; unseen tone |

`isUnseen` call sites (`forward_state.dart:172, 197, 216`) do **not** follow `canForwardTo`. Lineage / band / beacon-create are additional (B2, B3).

---

### B2. Lineage autoselect + preserved selection + disabled checkbox can deadlock send.

**Doc claims:** Availability extends `canForwardTo`; lineage is otherwise untouched. Auto-select “inherits” the change.

**Reality:** `ForwardCase.loadForwardCandidates` copies `s.autoSelect` onto candidates with **no** `canForwardTo` check (`forward_case.dart:174–184`). `ForwardCubit` then preselects `load.autoSelectIds.intersection(availableIds)` where `availableIds` is “present in the list”, not “forwardable” (`forward_cubit.dart:170–181`). Reloads **preserve** `state.selectedIds` against that same set (`forward_cubit.dart:174`).

The row cannot deselect a non-forwardable person:

```156:157:packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart
        onTap: canSelect ? onToggle : null,
```

```496:496:packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart
          onTap: enabled ? onTap : null,
```

Send then refuses the whole batch:

```406:411:packages/client/lib/features/forward/ui/bloc/forward_cubit.dart
    final ineligible = selectedCandidates
        .where((c) => !c.canForwardTo)
        .toList();
    if (ineligible.isNotEmpty) {
      _emitSnackError(const IneligibleRecipientsException());
      return false;
    }
```

The same `ForwardCubit` is embedded in beacon-create Recipients (`beacon_create_screen.dart:77, 147`; `sendRequest` at `beacon_create_cubit.dart:579–601`).

**Why it breaks:** A paused lineage auto-select, or a person who pauses after being checked, becomes selected + untoggleable + blocking send. That is not “they fall into unavailable.”

**Smallest fix:** Filter `autoSelectIds` and preserved `selectedIds` with the same predicate used to enable the checkbox; allow deselect when `isSelected && !canSelect`; strip ineligible ids before send instead of failing the batch. State this in §11. Beacon-create Recipients is in scope.

---

### B3. Recipient row: availability cannot “replace the presence slot” without fighting existing precedence. Row height is not a stable invariant.

**Doc claims (D12, §9.4):** Line 2 is `<presence> · <relation> · <receipt>`. Availability replaces presence when non-`open`, and replaces presence **and** the relation label when `paused`. “Row height is unchanged”; “nothing is appended to an already four-element row.” Label precedence: `notReachable` → `paused` → involvement.

**Reality:** Line 2 is not a three-part string. It is a `Wrap` of optional widgets, and two flags already steal the slot:

```190:232:packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart
                    if (tierEvidenceLabel != null)
                      TenturaStatusText(
                        tierEvidenceLabel!,
                        tone: tierEvidenceTone ?? TenturaTone.info,
                      )
                    else if (showPresenceLine)
                      Wrap(
                        ...
                          if (presence.isNotEmpty) Text(presence, ...),
                          if (forwardedByMeWithNote) ShowMoreText(...)
                          else TenturaStatusText(relationLabel, ...),
                          if (candidate.involvement == forwardedByMe)
                            _ForwardReadReceipt(...),
                      ),
```

`tierEvidenceLabel` **replaces the entire line** (comment at line 57: “replaces the involvement / presence status line”). Band evidence rows set it (`forward_band_strip.dart:130`). Exploration rows set `showPresenceLine: false` (`forward_band_strip.dart:134`), so there is **no** second line at all.

`_relationLabel` already has its own precedence: unreachable (unless author/declined) wins, then involvement (`forward_recipient_row.dart:70–88`). There is no `paused` rung. `notReachable` is a relation-label string, not a bucket.

The `Wrap` wraps. “Not taking new requests until Monday” is longer than “Last seen 3d ago”; `runSpacing: tt.tightGap` will grow the row. Capability chips are already a third line (`forward_recipient_row.dart:233–250`). The “four-element row, height unchanged” claim is not true of the widget as written.

D12 vs D18 on an already-forwarded person who then pauses: `alreadyInvolved` is intentionally not filtered (§11), but D12 says `paused` replaces the relation label. That would replace “Forwarded by me” (and hide the read receipt’s sibling context) with the pause line — the worse label for that row.

**Why it breaks:** A plan that “swaps the presence `Text`” never runs on band evidence/exploration rows, so paused people in the capability band show a disabled checkbox with no reason. A plan that also overrides `tierEvidenceLabel` throws away the band’s whole point.

**Smallest fix:** Write an explicit line-2 function with ordered slots, e.g. `tierEvidence` > `notReachable` > (`paused` only when involvement is `unseen`) > `presence` + involvement + receipt. Require `showPresenceLine` exploration rows to still show a pause reason if the checkbox is disabled. Do not promise constant height. Treat band rows as a fourth render site, or exclude paused users from the band.

---

### B4. `user_presence` is not an “exact structural clone” for a user-created/deleted row.

**Doc claims (D5, §2, §5):** `public.user_availability` is “an exact structural clone” of `public.user_presence`, which “buys the Hasura object relationship, the `block_hides` visibility gate, and the `UserModel` fragment read path for free.”

**What is actually true (keep this):**

- Drift: PK `user_id` → `user.id`, `withoutRowId`, `intEnum` status (`packages/server/lib/data/database/table/user_presence.dart:8–28`).
- Hidden-for-viewer: `block_hides(session user, row.user_id)` (`m0136.dart:184–195`).
- Hasura on `user`: object relationship `user_presence` via `user_presence.user_id` (`hasura/metadata.json:815–824`).
- Hasura on `user_presence`: select-only for role `user`; columns `last_seen_at`, `status`, `user_id`; filter `hidden_for_viewer._eq false`; **no** `last_notified_at`; **no** insert/update/delete (`metadata.json:989–1033`).
- `user.updated_at` **is** in the `user` select column list (`metadata.json:969`). D5’s reason not to put columns on `user` is correct.
- `mutually_visible_users` returns `SETOF public."user"` (`m0140.dart:204–207`, `m0142.dart:75–78`), so a nested object relationship on `user` is queryable from `ForwardCandidatesFetch`.

**What cloning would get wrong:**

1. **Row lifecycle is the opposite.** `user_presence` is created for **every** user: backfill + `on_user_created` trigger (`m0007.dart:57–68`). Writes are in-place `update` (`user_presence_repository.dart:38–56`; `UserPresenceCase.touch` / `setStatus`). Rows are not deleted when someone goes “offline”. Absence is exceptional. Availability’s `open` **deletes** the row (D4). Copying the trigger, or treating “no row” like presence does, permanently marks everyone `limited`/`paused` or else materializes a row for `open` and voids D4.

2. **UNLOGGED.** `m0007.dart:16` is `CREATE UNLOGGED TABLE`. There is no later `SET LOGGED` in this repo. A crash/replica rebuild wipes presence; that is acceptable for session telemetry. It is not acceptable for a user-declared 90-day pause. §5’s SQL correctly uses a logged `CREATE TABLE` — so it is **not** a clone. A mechanical copy of `m0007` would be an expensive-to-undo production incident.

3. **Hasura writes.** Presence has no user-role insert/update/delete, which is correct because the websocket path writes via the server. Availability rows **are** user-created. An implementer who “clones the table including write permissions” bypasses the V2 clamp (90-day, past-until, subject=`sub`). §5 only specifies select — that must be stated as a hard prohibition on Hasura writes, not left as “mirror presence.”

4. **`updated_at` is new.** Presence has no such column. Adding it is fine (D6) but it is extra, not cloned.

**Smallest fix:** Stop saying “exact clone.” Specify: logged table; **no** `on_user_created` insert; **no** Hasura insert/update/delete; object relationship + `hidden_for_viewer` + select `{state, until, user_id}` only; Drift table registered in `tentura_db.dart` (presence is at line 144 of that list) plus a hand-written `migrant` migration (this repo does not use `drift_dev make-migrations` for app schema; `schemaVersion` stays 1).

---

### B5. Lazy expiry is not “indistinguishable from `open`” on the wire. D3 + D4 + D6 overclaim privacy.

**Doc claims:** An expired row is indistinguishable from `open` to every reader (D3). `open` deletes the row so change history is “structurally impossible to read” (D4, §12). `updated_at` unexposed (D6). No realtime (D17).

**Reality:** Hasura select on the cloned table would return `{ state, until }` for any non-hidden row with `until` in the past. The client is explicitly told **not** to expire at map time (`UserModel.toEntity()` today maps presence raw; §6 says the same for availability). So:

- GraphQL, V2, and the Ferry cache still contain `paused` + a past `until` until an optional janitor runs.
- Anyone who can read `UserModel` (not just the three render sites) can see “they were paused until last Tuesday.” That **is** history. D4 only deletes on explicit `open`, not on lapse.
- `until` itself is a change oracle: two fetches with different `until` values prove a reset. That is inherent in exposing the date, but then §12 must not say history is structurally impossible.
- Early resume (`DELETE` while `until` is still in the future): other clients keep the cached nested object until refetch. They will treat the person as paused (fail closed in the picker, fail open on the server). D17 calls this “one screen-load”; combined with B2 it is a stuck checkbox.

`RealtimeEntityKind.profile` **does** exist and `ProfileCubit` subscribes (`profile_cubit.dart:45–47`). Side-table writes will **not** bump `user.updated_at` (that is D5’s point), so other profiles will not live-refresh. That matches D17, but it also means the “screen-load of staleness” is the only invalidation story — there is no catch-up.

**Clock / send-after-expiry (checkable, not hypothetical):**

- Client `now` ahead of server: picker shows open, server still `paused` → D11 silent drop (B6).
- Client `now` behind server: picker shows paused, server would accept → user cannot send (B2 deadlock if still selected).
- `effectiveAt` uses `until!.isAfter(now)` so `until == now` is expired. Server and client must share a clock source or this boundary flaps.

**Smallest fix:** Make expiry true at the API, not only in `effectiveAt`: Hasura select filter `until > now()` (or a `is_expired` computed field, same pattern as `hidden_for_viewer`). Then a lapsed row is actually `null` ≡ `open` to every GraphQL reader; the janitor stays hygiene. State in §12 that observable deltas of `until` across fetches are accepted, and that early-resume is stale until refetch. Do not claim “structurally impossible.”

---

### B6. D11 silent partial drop is not implementable as specified without lying to the sender. Total throw *can* keep `String!`.

**Doc claims:** Filter paused ids out of the delivery set; if the set empties, throw a user-facing description. `beaconForward` stays `String!`. Precedent: “Hasura permission-wall.” Client already excludes paused people, so silence only fires on a race.

**Reality — server:** `MutationForward.forward` returns `graphQLString.nonNullable()` and passes `recipientIds` straight into `ForwardCase.forward` (`mutation_forward.dart:63–122`). `ForwardCase.forward` already silently drops **blocked** peers (`forward_case.dart:191–196`) and **throws** if any remaining id is not mutually visible (`forward_case.dart:207–241`). `createBatch` with an empty list inserts nothing and returns `[]` (`forward_edge_repository.dart:112–147`); the use case still returns `batchId` (`forward_case.dart:247–317`). So “all recipients dropped” is currently **success**. D11’s total-throw is new, and the Hasura permission-wall is the wrong precedent: that pattern hides people the sender must not know exist. Paused people are **visible** in the picker.

Implementing “filter then throw if empty” does **not** require changing `String!`. Throw `UnauthorizedException(description: '...')` (`exception.dart:125–132`); `toMap` puts `description` in GraphQL `message`.

**Reality — client:** `forwardBeacon` reads `r.dataOrThrow(...).beaconForward` and returns that string (`forward_repository.dart:167–176`). On success, `ForwardCubit.forward` sets

```449:460:packages/client/lib/features/forward/ui/bloc/forward_cubit.dart
      final outcome = ForwardDeliveryOutcome(
        deliveredRecipientIds: recipientIds,
      );
      ...
        _effects.emit(ShowMessage(ForwardSentMessage(recipientIds.length)));
```

`recipientIds` is the **client selection**, not the server delivery set. Beacon-create confirmation uses that outcome (`beacon_create_cubit.dart:601`; `beacon_send_confirmation_dialog.dart:38`). Partial D11 drop ⇒ snackbar “sent to N”, confirmation names people who did not get an edge, `lastDeliveryOutcome.deliveredRecipientIds` is a lie.

Total throw: `dataOrThrow` → `mapRemoteFailure` → `RemoteApiException(message)` (`auth_loss_classifier.dart:52–56, 173–178`) → `ShowError` shows `e.toL10n` which for `RemoteApiException` is the raw English server `description` (`generic_exception.dart:41–50`; `ui_effect_dispatcher.dart:85–102`). So a total failure **does** surface, in English, on both forward and person-forward (`person_forward_cubit.dart:132–133`). It does not surface as the l10n key `availabilityPersonPaused`. Person-forward `canSend` does not look at availability (`person_forward_state.dart:28–29`; `send` at `person_forward_cubit.dart:118` only checks mutual + `row.isEligible`).

**Why it breaks:** D11 + `String!` + current client accounting = sender believes a paused race still received the request, with no skip list and no way to see it in-product except “they never showed up as involved.” That is not a rare-path footnote; it is the only feedback channel.

**Smallest fix (product, then API):** Either (a) reject D11 silence — return a payload `{ batchId, deliveredIds, skippedIds }` and drop the `String!` freeze, or (b) keep `String!` but **throw on any skip**, not only total skip, and make the client strip ineligible ids *and* treat `IneligibleRecipientsException` as the race UI. Do not cite Hasura row filters as precedent for dropping a named recipient.

---

### B7. The V2 mirror is real and required. The doc missed a second builder. The new mutation is missing from V2 routing.

**Doc claims (correct):** `userPublicToGqlMap` / `UserPublicRecord` / `gqlTypeUserPublic` / `user_profile_batch_lookup.dart` already join `user_presence` and must join `user_availability` or V2-sourced users fail open.

**Verified:**

```35:46:packages/server/lib/api/controllers/graphql/mappers/gql_public_user_maps.dart
Map<String, dynamic> userPublicToGqlMap(UserPublicRecord u) => {
  ...
  'user_presence': userPresenceToGqlMap(u.userPresence),
};
```

`UserPublicRecord` has `userPresence` only (`user_public_record.dart:21–42`). Batch lookup loads presence in `_presenceByUserId` and never availability (`user_profile_batch_lookup.dart:54–64, 83–99`). `gqlTypeUserPublic` declares `user_presence` only (`custom_types.dart:463–478`). Consumers of that map include mutual friends, help-offer coordination rows, user-block payloads, invite genealogy.

**Missed builder:** `query_invitation.dart:52–58` does **not** use `userPublicToGqlMap` for presence. It patches `issuer['user_presence']` from `UserPresenceCase.get` after `e.asMapWithIssuer`. Updating only the batch-lookup map leaves `invitationById.issuer` without availability (invariant 4 fails for that operation).

**Missed routing (codegen.mdc, `DEV_GUIDELINES.md` § V2 direct routing):** new V2 operations must be listed in `_tenturaDirectOperationNames` (`build_client.dart:154–182`). `ProfileUpdate` / `userUpdate` is already there (`build_client.dart:252`). A new `userAvailabilitySet` that is **not** listed is sent to Hasura, which does not have it. §8 lists `availability_set.graphql` and never mentions the allow-list. That is a silent production miss, the same class of bug the doc warns about for the V2 join.

**Room members do not use `UserModel`.** `BeaconParticipantList` is a V2 list of denormalized `userTitle` / `userHandle` / image fields (`beacon_participant_list.graphql:1–26`). §6’s “room member payloads inherit UserModel” is false. D19 says not to render there, so this is a factual error in the read-path story, not a missing render site — but a plan that “adds one fragment field and rooms light up” would waste time on the wrong type.

**`UsersFetchByIds` is a root `user` query** (`users_fetch_by_ids.graphql:3–6`). The `user` select permission has `"limit": 10` (`metadata.json:982`) — the only such limit in the metadata file. Nested `user_availability` is 1:1 and is **not** affected by that cap. The parent query **is**: Hasura applies permission `limit` as max/default on table root fields. `PersonForwardCase.load` uses this for a single id (`person_forward_case.dart:54`); lineage extras use it for a set (`forward_case.dart:126–128`). Limit 10 is a pre-existing truncation, not introduced by availability, but §6’s “every consumer, zero new queries, no N+1” oversells this path. `mutually_visible_users` is a **function** with its own `limit` argument (`schema.graphql:4733–4753`); `ForwardCandidatesFetch` does not pass `limit`. Whether the table permission limit also caps the function is **not** proven in-repo (SQL tests call the function directly). Nested availability does not change parent cardinality either way.

**Smallest fix:** Treat invariant 4 as covering `userPublicToGqlMap` **and** `query_invitation` issuer patching. Add `UserAvailabilitySet` (exact client operation name) to `_tenturaDirectOperationNames`. Strike “room member payloads” from the UserModel inheritance list. Note `UsersFetchByIds` / `user` `limit: 10` as pre-existing.

---

### B8. `PersonActionPolicy` “one branch” is not enough. Graph panel and person-forward are not covered. The “existing disabled-explanation pattern” cannot be reused as written.

**Doc claims (§2, §9.3):** Policy gains one branch; reads `profile.availability`; injectable `now`; when paused, `sendRequest` is replaced by the `profileRequestUnavailable` explanation. Person-forward keeps `PersonForwardBlock` untouched and adds a screen-level boolean (§9.5).

**Reality:**

`PersonActionPolicy.from` has no `now` and no availability (`person_action_policy.dart:23–96`). Mutual visibility unconditionally sets `primaryAction: sendRequest` and `showRequestOptions: false` (lines 54–66).

`profileRequestUnavailable` is **not** a disabled Send button. It is a `Text` shown only when `primaryAction == none && showRequestOptions && viewerExplicitlyTrustsSubject` (`profile_view_body.dart:342–352`; same in `graph_person_context_panel.dart:175–185`). `showRequestOptions` also uncorks an outlined button that still calls `showForwardToPerson` (`profile_view_body.dart:365–372`; graph panel `188–200`). You cannot show that explanation without also showing “Request options” unless you change those widgets. `PersonPrimaryAction` is only `{ none, trust, sendRequest }` — there is no disabled-send variant.

Both the other-profile screen **and** the graph side panel use this policy. D19 forbids rendering availability on “graph nodes and the graph side panel.” A paused mutual user today has a Send button on that panel (`graph_person_context_panel.dart:148–160`). One policy branch that hides `sendRequest` either (a) removes Send with no copy (violates the brief’s “control” + discoverability), or (b) puts pause copy on an excluded surface (violates D19).

Person-forward: `canSend` is `person.isMutuallyVisible && selectedRow.isEligible` (`person_forward_state.dart:28–29`). `PersonForwardCase.send` has no availability check (`person_forward_case.dart:100–107`). The screen already has an unreachable banner (`person_forward_screen.dart:106–108`) — that is the pattern §9.5 should copy, and it is **not** implied by a policy branch. The route is `@PathParam('id')` (`person_forward_screen.dart:18–21`); hiding the profile button does not close the screen.

`PersonActionPolicy.from` is also constructed in tests and the graph cubit. Adding `now` is an API break at every call site, not “one branch.”

**Smallest fix:** Split “gate the verb” from “render the line.” (1) New policy field `blocksNewRequests` / new enum value, not a reuse of `showRequestOptions`. (2) Profile view: disabled explanation. (3) Graph panel: either an explicit D19 exception for this one sentence, or leave Send and let person-forward’s banner be the gate (and then **must** implement §9.5 `canSend`). (4) Person-forward `canSend` and `send()` must check effective availability regardless of how the user arrived. §8 file list must include `person_forward_state.dart`, `person_forward_screen.dart`, `graph_person_context_panel.dart`.

---

### B9. D18’s single gate is not the only “involve this person in a new request” write.

**Doc claims:** Availability gates exactly `being newly forwarded to`. Cancel, update, help-offer, admission, room mutations are not gated.

**Reality — `beaconForward` is not the only materializer of a forward edge.** Consuming a beacon-tied invite inserts `beacon_forward_edge` in `UserRepository._materializeBeaconInviteForward` (`user_repository.dart:112–145`), called from `bindMutual` when `invitation.beaconId != null` (`user_repository.dart:847–853`) and from invited-user create paths (same file, lines 222 and 385). That path never touches `ForwardCase.forward`. The forward picker even has `_inviteNewPerson` (`forward_recipient_picker.dart:536–538`).

For a **new** account this is mostly orthogonal (no availability row). For `acceptAsExisting` + beacon invite (`invitation_case.dart:262–310`), an existing user who is `paused` can still be attached as a recipient by accepting a link — that is the recipient opting in, which may be fine, but it is not “the one verb.” The **issuer** can also still mint a beacon invite to someone they could not pick in the recipient list.

Other verbs checked:

| Verb | Gated by D10 as written? |
|---|---|
| `beaconForward` / person-forward / beacon-create Recipients | yes, if `ForwardCase.forward` is updated |
| Onward forward by a third party | same mutation — yes |
| Beacon-tied invitation accept | **no** — `_materializeBeaconInviteForward` |
| `BeaconOfferHelp` / admission / room add / remove | no (D18 says so; recipient is already in the request or is the actor) |
| Mentions, graph Send, lineage suggestion display | not writes, except graph Send → person-forward (B8) |
| Authoring own requests, offering help as the paused user | no (D18) |

**Smallest fix:** Add S5: does a beacon-tied invite bypass pause? If no, run the same `effectiveAt` check inside `_materializeBeaconInviteForward` (recipient is the accepter — product call: self-opt-in vs incoming). If yes, write that down so D18 stops saying “exactly one verb.”

---

### B10. D20 cites the wrong formatter. `canForwardToAt(now)` is not a local conjunct.

**Doc claims:** Date display reuses the shipped 7-day rule from `profilePresenceDisplayLine`: inside 7 local calendar days → weekday (“until Monday”); beyond → localized date.

**Reality:** `profilePresenceDisplayLine` (`ui/utils/profile_presence_line.dart:10–42`) uses online / just now / minutes / hours / “Last seen Nd ago” / `yMMMd` after 7 days. It never emits a weekday name. Weekday copy lives in `beaconCardCalendarDeadlineStatus` (`ui/utils/beacon_card_deadline.dart:8–36`, `DateFormat('EEE')` + `myWorkStatusDueWeekday`). `formatScheduleDate` is absolute `MMMd`/`yMMMd` with no 7-day weekday rule (`ui/utils/schedule_date_format.dart:5–16`).

**Doc claims:** `canForwardTo` “gains one conjunct” becoming `canForwardToAt(now)`.

**Reality:** `canForwardTo` is a **getter** (`forward_candidate.dart:35`). `visibleRecipients` is a **getter** with no clock (`forward_state.dart:183`). Injecting `now` requires threading a clock through every getter listed in B1, or calling `DateTime.now()` inside the getter (which §3 forbids). This is not a one-line conjunct.

**Smallest fix:** Cite `beaconCardCalendarDeadlineStatus` (or extract a shared weekday-or-date helper) and drop the presence-line claim. Decide: UI getters may use `DateTime.now()`; tests and the server take `now`. Do not pretend `visibleRecipients` stays a pure getter of `canForwardToAt(now)` without an API change.

---

### B11. §8 / §0 understate blast radius. Settings door is claimed and does not exist.

**Doc claims:** “the whole feature reduces to: one shared enum, one Freezed value object, one new field in one GraphQL fragment, one mutation, one bottom sheet, and three render sites.” §9.1: sheet reached from own profile **and** a Settings tile.

**Reality:** `settings_screen.dart` is a fixed list of `TenturaCommandButton`s (language, theme, seed, credentials, notifications, routing mute, debug, reset, delete) — no availability hook (`settings_screen.dart:116–172`). §8 does not list a settings file. Own `ProfileBody` has no presence/availability row today (`profile_body.dart:19–95`); inserting one is real work, not “the fragment already did it.”

Missing from §8 (client, and this is not “shape so we skip files” — these are the places the decisions attach):

- `forward_candidate.dart`, `forward_state.dart`, `forward_cubit.dart`, `forward_recipient_row.dart`, `forward_band_strip.dart`, `forward_recipient_picker.dart`
- `person_forward_state.dart`, `person_forward_screen.dart`, `person_forward_cubit.dart`
- `profile_view_body.dart`, `graph_person_context_panel.dart`, `person_action_policy.dart` (listed)
- `user_model.dart` `toEntity()` (presence mapping is here: `data/model/user_model.dart:9–31`)
- `build_client.dart` allow-list
- settings screen, if S-door stays
- server: Drift table, port, `ForwardCase.forward`, `custom_types.dart`, batch lookup, `query_invitation.dart`, Hasura metadata, migrant SQL

Layer check that **is** fine: `AvailabilityState` in `tentura_root` `lib/domain/enums.dart` matches `UserPresenceStatus` (`lib/domain/enums.dart:6–11`). Client entity + server entity split matches presence. `no_request_domain_entity` only flags types named `Request` / `RequestEntity` (`no_request_domain_entity.dart:51–58`); `Availability` is the right name. `ProfileCubit` already injects one `ProfileRepositoryPort`; adding `setAvailability` does not trip `cubit_requires_use_case_for_multi_repos`. `availability_line.dart` in `ui/utils` (l10n-aware) is the right layer. No cubit→`data/service` import proposed. D9 not extending `userUpdate` matches `profile_update.graphql` (form fields only). Design-system: `TenturaStatusText`, no chips on operational surfaces (`docs/tentura-design-system.md:198`) — RadioListTile is already used in-app (`notification_settings_screen.dart`). `InputFieldDatetime` does force-UTC (`_input_types.dart:97–133`).

**Smallest fix:** Replace the “reduces to” sentence with the actual surface list. Either add a settings tile to the architecture (file + copy) or drop the second door. Keep the layering paragraph; it is mostly right.

---

## 3. Design objections

Judgement, not “the code already contradicts you.” Alternatives are the ones I would take.

### D-obj 1. D11 silence is indefensible even after B6 is “fixed” with a skip list.

A race is still a user-visible event: the sender named a person and the product accepted the tap. Dropping them because they paused between fetch and send is exactly the case where you **owe** a sentence. Hasura hiding blocked rows is “this person does not exist for you.” Pause is “this person exists and refused.” Collapsing those trains people that Tentura’s send confirmation is advisory. I would throw (or return skipped ids) on **any** paused drop, and keep the picker as the happy path.

### D-obj 2. Mandatory `until` on `limited` (D2 / S3) makes `limited` a nag, not a disposition.

`limited` is defined as informational, never blocking (D13, D22). Forcing a ≤90-day end date means the only honest long-term “please be selective” users must reset a radio every quarter or lapse to looking `open`. That is the same rot D2 claims to prevent, just with extra ceremony. I would keep `until` **required for `paused` only**; let `limited` be `until` nullable. That is still one table, one read path; the CHECK becomes `(state = 2 AND until IS NOT NULL) OR (state = 1)`. D22’s “sever `limited`” remains true. If product will not accept standing `limited`, cut it in v1 (S1) rather than shipping a fake expiry.

### D-obj 3. Three states are not the minimum that covers the brief.

The brief as quoted in the doc is “is it appropriate to involve this person in a new request right now?” A hard pause plus default open answers that. `limited` is a social hint with no mechanism; it will generate “why did they still show up in recommended?” bugs and pressure to demote it in MR (already rejected, D13 — good rejection, bad prediction). Ship `open`/`paused` until someone uses pause enough to prove a middle state is needed. D22 already admits this is severable; S1 should default the other way.

### D-obj 4. `open` deletes the row (D4) is the right *privacy* idea and the wrong *concurrency* idea.

DELETE-as-default plus UPSERT-on-pause across two devices is last-write-wins with a delete/insert race (pause then resume on A, pause on B: either stuck paused or stuck open with no row). Presence avoids this by never deleting. I would upsert a row for every non-default state and, if history must be unreadable, **null out `until`/`state` in the API** rather than delete. If DELETE stays, the write path needs a single-row compare-and-swap on `updated_at` (ops-only column used as version), which the doc never mentions.

### D-obj 5. §9.6 exclusions vs the Send verb.

Excluding avatars, inbox, My Work, member lists is coherent: those are presence-shaped. Excluding the **graph side panel** is not, once that panel has the same `PersonPrimaryAction.sendRequest` as the profile (B8). Either the panel is a forward surface (show the pause line) or Send must leave that panel. The current exclusion list treats “where we paint a badge” and “where we offer the verb” as the same set. They are not.

Mutual-friends sheet and search: if I am picking someone to involve, I need the signal. Those are closer to the recipient row than to a chat member list. I would not paint it on search hits, but I would on any row that has a Send/forward affordance.

### D-obj 6. §9.1 sheet copy vs behavior.

“Each choice applies immediately and the sheet closes” and an **Apply** button after picking `until` cannot both be true. Immediate-apply on `open` / Resume now, Apply on `limited`/`paused` after a preset, is the workable split — write that, not both.

Sheet RU `availabilityOpenTitle` = «Принимает запросы» is third-person on a first-person control. The gender-free constraint in §10 is right; this key violates it for the self sheet. Use the `availabilitySelfOpen` wording on the radios.

### D-obj 7. Rejected-designs table.

| Rejection | Call |
|---|---|
| Presence-derived availability | Correct. Do not touch. |
| Demoting `limited` in MR | Correct if `limited` ships. |
| Columns on `user` | Correct (B4: `updated_at` is Hasura-visible). |
| Extending `userUpdate` | Correct (B11). |
| `RealtimeEntityKind.availability` | Correct given D17, **if** B5’s API-level expiry lands. |
| “Send anyway” | Coupled to D11. If pause is hard, an override is a lie. If D11 is silent, users will demand an override because they cannot tell a drop from a send. Pick one: hard + loud failure, or advisory + send anyway. Not hard + silent. |
| Indefinite pause | Reasonable. 90 days as a constant is fine (S4). |
| “Paused except close contacts” | Reasonable for v1. Viewer-dependent labels on a batch join are real cost. |
| Working hours | Correct to reject for v1. |

Bad omission: rejecting a **structured skip report** on `beaconForward` because the field is `String!`. That is a frozen accident (`batchId`), not a product invariant. Changing it is cheaper than building D11’s silence mythology.

### D-obj 8. Missing from §15.

Add at least:

- **S5.** Beacon-tied invitations vs pause (B9).
- **S6.** Graph side panel: hide Send, show pause copy, or leave Send and gate on person-forward (B8 vs D19).
- **S7.** Partial skip UX: throw / skip-list / silence (B6, D-obj 1). `String!` is not a given.
- **S8.** Default forward filter (`unseen`) vs `all`: are paused people listed-disabled or omitted? (B1)
- **S9.** Clock: client `DateTime.now()` vs server `DateTime.timestamp()` at the `until == now` boundary.

S1–S4 as written are real product calls; I would flip S1 and S3 as above.

---

## 4. Unverifiable / risky claims

These a reader would take on faith; I could not close them from the repo.

1. **Hasura permission `limit: 10` on `mutually_visible_users`.** The function is tracked with `{ role: user }` only (`metadata.json:1857–1869`) and the GraphQL field exposes `limit`/`offset`/`where` like a table. Whether Hasura also applies the `user` table permission limit to SETOF-function results is not tested via Hasura in this repo (PG tests call SQL directly). Nested `user_availability` does not change the answer. A plan should either pass an explicit high `limit` on `ForwardCandidatesFetch` or add a Hasura-level test with 11 peers.

2. **Ferry identity cache across UserModel consumers.** Adding the nested field will store `state`/`until` on the `user` cache entity for graph, My Work, rating, friends, beacon authors — not just the three render sites. I did not run Ferry to prove update coalescing. D19 is render-only; the payload leak to those queries is the same class as today’s `user_presence` on those fragments (so it is consistent, not new in kind).

3. **Postgres WAL / logical replication / ops SQL** as a history side channel. D4 is “no product API history,” not “no WAL.” Fine if that is the bar; §12’s “structurally impossible” language is still too strong (B5).

4. **90-day local-midnight vs resolver `now + 90d` UTC.** D21 + client `lastDate` can disagree around TZ offsets; I did not enumerate every TZ. Treat as a test matrix, not a proven invariant 11.

5. **Whether `on_user_created` still includes the `user_presence` insert after later migrations.** `m0007` defines it; I did not replay every later `CREATE OR REPLACE` of `on_user_created`. Presence rows existing for all users is still evidenced by the backfill + trigger in `m0007` and the update-only repository.

6. **Product intent of the original brief** (is `limited` required? is pause allowed to be self-override by accepting an invite?). Not in this repo as a signed brief; only this draft.

---

## 5. What the document gets right

Only non-obvious items that survived the check. Do not churn these.

1. **Do not put this on `user`.** `updated_at` is in the Hasura `user` select columns (`metadata.json:969`). Availability writes would become a “this person changed” oracle. Side table is the right move.

2. **The V2 `UserModel` shape is a real second path**, not a nice-to-have. `userPublicToGqlMap` + batch-join of `user_presence` is the pattern; forgetting it fails **open**. Invariant 4 belongs in the plan. Extend it to `query_invitation` (B7).

3. **Do not reuse presence.** Websocket `path: user_presence`, `UserPresenceCase.touch/setStatus`, `last_seen_at` are observed session state. Availability must not derive from them. The “must not be reused” paragraph is correct.

4. **`block_hides` via a `hidden_for_viewer` computed field is the right visibility gate** to copy (select-only). Presence proves the Hasura shape. Do not copy UNLOGGED, the insert trigger, or write permissions (B4).

5. **`mutually_visible_users` returning `SETOF user` means a nested object relationship on the fragment is sufficient for Forward candidates.** No new candidate query is required for the happy path. (`forward_candidates_fetch.graphql` already spreads `UserModel`.)

6. **D9: new mutation, not `userUpdate`.** `ProfileUpdate` is a dirty-tracking form (`profile_update.graphql`). Availability needs immediate apply + clamp. Correct split.

7. **`PersonForwardBlock` must not grow a pause case.** It is `(involvement, beacon.status)` (`person_forward_row.dart`). Person-level pause is screen-level. That distinction is right; the miss is not implementing the screen-level boolean (B8).

8. **D13: do not demote `limited` in MR.** If the state exists, a silent rank penalty is the wrong incentive. (Whether the state should exist is D-obj 3.)

9. **D16 / no avatar chrome.** Presence already taught this codebase that a glyph on an avatar becomes global. `TenturaStatusText` only is the right constraint. Chip ban on operational surfaces is already in the design system.

10. **Enum placement.** `AvailabilityState` next to `UserPresenceStatus` in `tentura_root` `lib/domain/enums.dart`, ordinals as wire smallints, `CHECK (state IN (1,2))` so `open` is unrepresentable in SQL — internally consistent with how presence is mapped in `user_model.dart:35–42`.

11. **`beaconForward` can throw without changing `String!`.** The total-failure path will show up as `RemoteApiException` / snackbar. The bug is treating that as sufficient for **partial** failure (B6), not that throw-on-empty is unimplementable.

12. **Delivery footnotes** (client semver + `web/index.html` cache-buster, Hasura metadata apply, migrant rollback simulation, terminology script) match `AGENTS.md` / `versioning.mdc`. Keep them.

13. **Russian gender-free constraint** is a real l10n landmine and should stay binding. Do not ship predicative «открыт/а».
