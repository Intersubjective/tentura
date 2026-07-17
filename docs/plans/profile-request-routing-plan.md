---
status: active
kind: plan
---
# Profile → request-routing surface — implementation plan

Issue: [Intersubjective/tentura#83](https://github.com/Intersubjective/tentura/issues/83)
(parent #72). Status: **planned, not started** (2026-07-08).

Users navigate to a *person* first and then look for a way to ask that person for
help. Today the only path is request-first: open the request → Forward → pick the
person. This plan adds the inverse entry point: from a person's profile, forward one
of my existing requests to them, or start a new request with them preselected.

**Out of scope (explicitly deferred):**
- The graph-node side panel variant from the issue. We only keep the door open: all
  new behavior is reachable through one routed screen keyed by `userId`, so a future
  graph panel just pushes the same route. Do not touch `features/graph`.
- Multi-beacon batch send (one request per send action is enough).
- Forward-reason chips on this new screen (the request-first picker keeps them).
- Relaying requests that were forwarded *to* me (only my authored requests in v1 —
  see §8.14).

---

## 1. Read these first (hard project rules)

Before writing any code, the implementer must read:

| What | Why |
|---|---|
| `.cursor/rules/terminology.mdc` | Users see **Request**, code stays **beacon/forward**. Never create a `Request` domain type (lint `no_request_domain_entity` blocks it). Routes must NOT contain `request`. |
| `.cursor/rules/architecture.mdc` | Layering. A cubit touching ≥2 repositories must go through a `*Case` (lint `cubit_requires_use_case_for_multi_repos`). |
| `.cursor/rules/tentura-design-system.mdc` + `material-3-flutter` skill | No raw `EdgeInsets`/`BorderRadius`/`Color`/`TextStyle`/`fontSize` in `features/**` (lints). Use `context.tt` tokens, `TenturaText.*`, `TenturaTopBar`, `TenturaContentColumn`. |
| `.cursor/rules/codegen.mdc` | GraphQL lives in `.graphql` files (lint `no_raw_graphql_in_dart`), then codegen. Never edit `*.g.dart`, `*.gr.dart`, `*.freezed.dart`, `*.config.dart`. |

Codegen commands used throughout (run from `packages/client/`):

```bash
dart run build_runner build --delete-conflicting-outputs   # gql/freezed/DI/auto_route
flutter gen-l10n                                           # after editing l10n/*.arb
```

Note: `di.config.dart` is gitignored — regenerating it locally is expected.

---

## 2. Map of the existing machinery (all reused, none rewritten)

| File | What it gives us |
|---|---|
| `packages/client/lib/features/forward/domain/use_case/forward_case.dart` | Request-first forward orchestration. **`computeInvolvement(userId, involvementData)`** is a static pure function mapping a user to `CandidateInvolvement` — reuse it, do not reimplement. |
| `packages/client/lib/features/forward/domain/entity/forward_candidate.dart` | The eligibility rule of record: `canForwardTo` = `profile.isSeeingMe` **and** involvement ∉ {author, forwardedByMe, declined, helpOffered, withdrawn}. Our per-beacon rule mirrors this with person fixed and beacon varying. |
| `packages/client/lib/features/forward/data/repository/forward_repository.dart` | `forwardBeacon(...)` mutation (fires the `forwardCompleted` stream on success), `fetchBeaconInvolvement(beaconId)` (V2 `beaconInvolvement` + beacon fetch), `mapBeaconInvolvement(...)` static mapper, `BeaconInvolvementData` typedef. |
| `packages/client/lib/features/beacon/data/repository/beacon_repository.dart` | `fetchBeacons({profileId, offset, lifecycleStates, limit})` — my authored beacons filtered by status smallints server-side. |
| `lib/domain/entity/beacon_status.dart` (package `tentura_root`) | `BeaconStatus.openFamilyValues = {0,7,8}`, `status.allowsForward`. |
| `packages/client/lib/domain/entity/profile.dart` | `isSeeingMe => rScore > 0` (reachability), `isFriend`. `rScore` is populated by the shared `UserModel` fragment (`scores { src_score }`), so any profile fetched via `ProfileRepositoryPort` already carries it. |
| `packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart` | The profile screen body — the new entry button goes here. |
| `packages/client/lib/features/beacon_create/ui/screen/beacon_create_screen.dart` | Hosts an **embedded** `ForwardCubit` on its Recipients tab (created in `_forwardCubitFor`), draft is auto-created via `ensureDraft()` when the tab opens. Phase 2 hooks in here. |
| `packages/client/lib/ui/bloc/screen_cubit.dart` | Path-string navigation helpers (`showProfile`, `showBeaconCreate`, …). Add ours here so graph code can reuse it later. |
| `packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart` | `fetchMutualFriends(userId)` — powers the "relay" suggestion when the person is unreachable (Phase 3). |

Server facts that shape the client design (verified in
`packages/server/lib/domain/use_case/forward_case.dart` and
`packages/server/lib/data/repository/forward_edge_repository.dart`):

- `beaconForward` validates only: sender `canReadContent` on the beacon, and
  `beacon.allowsForward` (open family). It does **not** check reachability
  (`rScore`) — reachability is a client-side product rule. Enforce it in UI; do not
  expect a server error for it.
- `createBatch` silently **skips recipients that already have an active edge**
  (idempotent). A stale "already sent" state on our screen therefore cannot corrupt
  data — worst case the server no-ops.
- Forwarding creates a `beacon_forward_edge` (+ a "watching" inbox row for the
  sender) and **nothing else** — no trust edge, no vote. This is exactly the
  issue's "does not create a general social tie" criterion; there is nothing to do,
  just don't add any `like`/vote call to the new flow.
- **No server changes are needed for any phase of this plan.**

---

## 3. Target UX

### 3.1 Profile screen (entry point)

In `ProfileViewBody`, insert one primary action directly after the presence line and
before the capability strip:

- `FilledButton.icon`, icon `Icons.send_outlined`, label l10n
  `profileSendRequestTo` (EN: `Send a request`).
- Visible only when: profile is loaded (`profile.id` non-empty) **and** it is not my
  own profile (compare with `context.read<ProfileCubit>().state.profile.id`, same
  pattern the capability block already uses).
- Do **not** gate the button on `isSeeingMe` — unreachable people still get the
  screen, which explains why and shows the relay path (issue requirement 4).
- On tap: `context.read<ScreenCubit>().showForwardToPerson(profile.id)`.

Leave the existing "Add to my field" `FilledButton` as-is (it only shows for
non-friends; two filled buttons never render adjacently since ours is at the top).

### 3.2 Person-forward screen (the routing surface)

New routed screen `PersonForwardScreen` at path `/forward-person/:id` (see §8.2 for
why not `/forward/person/:id`). Layout top to bottom:

1. `TenturaTopBar` with title l10n `beaconForwardToPersonTitle`
   (EN: `Send a request to {name}`), `AutoLeadingButton` leading.
2. **Reachability banner** (only when `!person.isSeeingMe`): explains the person
   cannot receive my requests yet (`beaconForwardPersonUnreachable`, EN:
   `{name} can't receive your requests yet — they don't see you in their trust
   network.`) plus a `TextButton` `beaconForwardPersonShowMutuals`
   (EN: `Show mutual connections`) — Phase 3.
3. **My open requests list**: one row per authored open-family beacon —
   leading beacon emoji/icon, title, and a status subtitle. Eligible rows carry a
   radio-style single selection. Ineligible rows are rendered disabled
   (`tt.textMuted`) with a reason subtitle (§5 mapping). Tap on an
   "already sent" row navigates to `ForwardBeaconRoute(beaconId)` so the user can
   manage/cancel that forward there (we do not duplicate edge management here).
4. **Note field + send**: single optional `TextField` (l10n
   `beaconForwardPersonNoteHint`, EN: `Add a note (optional)`) and a full-width
   `FilledButton` `beaconForwardPersonSend` (EN: `Send request`), enabled only when
   an eligible row is selected **and** `person.isSeeingMe`.
5. **New request entry**: a `TextButton.icon` (icon `Icons.add`) with l10n
   `beaconForwardPersonNewRequest` (EN: `New request for {name}`) — always visible
   at the bottom of the list; it is the whole body of the empty state when I have
   zero open requests (empty-state copy `beaconForwardPersonEmpty`, EN:
   `You have no open requests {name} can receive.`). Disabled when
   `!person.isSeeingMe` (a preselected-but-unreachable recipient would be dropped
   in beacon-create anyway — dead end).

After a successful send: `ShowMessage`/snackbar confirmation
(`beaconForwardPersonSent`, EN: `Request sent to {name}`) and `NavigateBack` (same
`UiEffectPort` pattern as `ForwardCubit._emitNavigateBack`).

RU copy for every key above goes into `l10n/app_ru.arb` in the same change (values
use **запрос**; see §8.6).

### 3.3 Create-new-with-preselect (Phase 2)

"New request for {name}" pushes the existing beacon-create screen with a new query
param, e.g. `/beacon/new?forward_to=U…`. The user fills Info as usual; when the
Recipients tab is prepared, the embedded `ForwardCubit` starts with that person
already checked (still fully editable — adding/removing others is untouched
picker behavior).

---

## 4. Architecture decisions

- **Everything new lives in `features/forward/`.** Person-anchored forwarding is
  still forwarding: same entities, same repository, same invalidation streams. Do
  not create a new feature directory, and do not put logic in `profile_view`
  (profile only gets a button + navigation).
- **New `PersonForwardCase`** (`features/forward/domain/use_case/person_forward_case.dart`)
  rather than growing `ForwardCase` — `ForwardCase` is already ~300 lines and the
  lint only requires *a* case. It injects: `ForwardRepository`, `BeaconRepository`,
  `ProfileRepositoryPort`, `AuthLocalRepositoryPort`, `ContactsCase` (and
  `MutualFriendsRepository` in Phase 3). Follow `ForwardCase`'s constructor shape
  (`extends UseCaseBase`, `required super.env, required super.logger`,
  `@singleton`). Cross-feature imports into a Case are established practice here
  (`ForwardCase` already imports from `beacon_room`, `profile`, `contacts`).
- **New `PersonForwardCubit`** talks **only** to `PersonForwardCase` (+
  `UiEffectPort`). Copy the constructor/DI/`debugSkipInitialLoad` pattern from
  `ForwardCubit` so the existing test style applies.
- **No new GraphQL documents.** Every query/mutation needed already exists
  (`GBeaconsFetchByUserIdReq`, `GBeaconInvolvementDataReq`, `GForwardBeaconReq`,
  `GMutualFriendsFetchReq`). This also means no schema/codegen risk.
- **Send path calls `ForwardRepository.forwardBeacon` via the new case**, not
  `ForwardCubit.forward()` — the cubit's send path is tangled with multi-recipient
  state we don't have. The repository method already fires `forwardCompleted`, so
  every other screen (beacon view, inbox, request-first picker) live-updates for
  free.

---

## 5. Domain model for eligibility

New file `features/forward/domain/entity/person_forward_row.dart`:

```dart
/// Why a given authored beacon cannot be forwarded to the person (or none).
enum PersonForwardBlock {
  none,          // eligible
  notOpen,       // beacon.status.allowsForward == false (defensive; see §8.3)
  alreadySent,   // CandidateInvolvement.forwardedByMe
  alreadyHelping,// CandidateInvolvement.helpOffered
  declined,      // CandidateInvolvement.declined
  withdrawn,     // CandidateInvolvement.withdrawn
  theirOwn,      // CandidateInvolvement.author (possible once relaying lands)
}

@freezed
abstract class PersonForwardRow with _$PersonForwardRow {
  const factory PersonForwardRow({
    required Beacon beacon,
    required CandidateInvolvement involvement,
    @Default(PersonForwardBlock.none) PersonForwardBlock block,
  }) = _PersonForwardRow;

  const PersonForwardRow._();
  bool get isEligible => block == PersonForwardBlock.none;
}
```

Plus a **pure static** mapper (unit-test target):

```dart
static PersonForwardBlock blockFor(
  CandidateInvolvement involvement,
  BeaconStatus status,
) { ... }   // order: notOpen first, then involvement cases, else none
```

Note the person-level `isSeeingMe` is deliberately **not** a `PersonForwardBlock`:
it blankets the whole screen (banner + disabled send), not individual rows.

`CandidateInvolvement.forwarded` / `.watching` / `.unseen` map to `none` — someone
else having forwarded the same beacon to this person does not block me from
forwarding it too (mirrors `ForwardCandidate.canForwardTo`, which only excludes
*my* prior forward).

---

## 6. Implementation steps — Phase 1 (profile → forward existing request)

Work top-down in this order; each step compiles on its own.

1. **l10n**: add the keys from §3 to `packages/client/l10n/app_en.arb` and
   `app_ru.arb` (both, same commit), then `flutter gen-l10n`. Keys are prefixed
   `beaconForwardPerson*` / `profileSendRequestTo` — key names may say `beacon`,
   values must say request/запрос (§8.6).
2. **Entity** `person_forward_row.dart` (§5) + build_runner (freezed).
3. **Repository addition** in `forward_repository.dart`: the existing
   `fetchBeaconInvolvement` refetches the beacon each call — wasteful for N rows
   whose `Beacon` we already hold. Add:

   ```dart
   /// Involvement sets for a beacon we already have (skips the beacon refetch).
   Future<BeaconInvolvementData> fetchInvolvementForBeacon(Beacon beacon) =>
       _remoteApiService
           .request(GBeaconInvolvementDataReq((r) => r..vars.id = beacon.id))
           .firstWhere((e) => e.dataSource == DataSource.Link)
           .then((r) => mapBeaconInvolvement(
                 beacon: beacon,
                 inv: r.dataOrThrow(label: _label).beaconInvolvement,
               ));
   ```

   Do **not** try to fold involvement into the Hasura beacon query instead — §8.4.
4. **Use case** `person_forward_case.dart`:

   ```dart
   Future<PersonForwardLoad> load(String personId) async {
     await _contactsCase.refresh();
     final myId = await _authLocalRepository.getCurrentAccountId();
     final person = (await _profileRepository.fetchProfilesByIds({personId}))
         .firstOrNull;             // null → throw a typed NotFound exception
     final beacons = await _beaconRepository.fetchBeacons(
       profileId: myId,
       offset: 0,
       lifecycleStates: BeaconStatus.openFamilyValues.toList(),
       limit: 50,                  // pagination deferred, see §8.11
     );
     // N+1 by design (§8.4/§8.5): per-beacon involvement, failure-tolerant.
     final rows = await Future.wait(beacons.map((b) async {
       try {
         final inv = await _forwardRepository.fetchInvolvementForBeacon(b);
         final involvement = ForwardCase.computeInvolvement(personId, inv);
         return PersonForwardRow(
           beacon: b,
           involvement: involvement,
           block: blockFor(involvement, b.status),
         );
       } catch (e) {
         logger.warning('PersonForward: involvement failed for ${b.id}: $e');
         return PersonForwardRow(beacon: b,
             involvement: CandidateInvolvement.unseen);   // §8.5
       }
     }));
     return (person: applyOverlay(person), rows: sort(rows)); // eligible first
   }

   Future<void> send({required String beaconId, required String personId,
       String? note}) =>
     _forwardRepository.forwardBeacon(
         beaconId: beaconId, recipientIds: [personId], note: note);
   ```

   Also re-expose `forwardCompleted` and `contactChanges` streams (copy
   `ForwardCase`). Person display name must go through the contact overlay
   (`profileWithContactOverlay`), same as `ForwardCase.applyContactOverlay`.
5. **DI**: build_runner regenerates `di.config.dart` (gitignored).
6. **Cubit + state** (`person_forward_cubit.dart`, `person_forward_state.dart`):
   state = `personId`, `person: Profile?`, `rows`, `selectedBeaconId: String?`,
   `note`, `status`. Behaviors:
   - constructor validates `personId.startsWith('U')` like `ProfileViewCubit`
     (bad deep link → error state + `ShowError`), then loads;
   - subscribe `forwardCompleted` → if the beaconId is one of `rows`, reload
     (covers "I forwarded the same beacon from another screen meanwhile");
   - subscribe `contactChanges` → re-apply name overlay;
   - `send()` guards: a row is selected, `row.isEligible`, `person!.isSeeingMe`,
     then calls the case; success → `ShowMessage` + `NavigateBack`; failure →
     `ShowError` and stay (state back to success so the UI un-spins).
7. **Screen** `person_forward_screen.dart` (§3.2). `@RoutePage()` +
   `AutoRouteWrapper` providing the cubit — copy `ForwardBeaconScreen`'s shape.
   Invoke the `material-3-flutter` skill before writing widget code.
8. **Routing**: `consts.dart`: `const kPathForwardPerson = '/forward-person';`
   register in `root_router.dart` next to `ForwardBeaconRoute` with
   `path: '$kPathForwardPerson/:id'`; run build_runner (`root_router.gr.dart` is
   generated). Add to `screen_cubit.dart`:

   ```dart
   void showForwardToPerson(String id) =>
       _navigateTo('$kPathForwardPerson/$id');
   ```
9. **Profile button** in `profile_view_body.dart` (§3.1).
10. **Tests** (§9) and full verify pass.

---

## 7. Implementation steps — Phase 2 (new request with person preselected)

1. `consts.dart`: `const kQueryBeaconForwardTo = 'forward_to';`
2. `BeaconCreateScreen`: new
   `@QueryParam(kQueryBeaconForwardTo) this.forwardToUserId = ''` field; pass it to
   both places touching `ForwardCubit` — that is, only inside `_forwardCubitFor`,
   which is the single construction point:

   ```dart
   _forwardCubit = ForwardCubit(
     beaconId: id,
     context: contextName,
     preselectLineageSuggestions: ...,
     initialSelectedIds: widget.forwardToUserId.isEmpty
         ? const {} : {widget.forwardToUserId},
     embedded: true,
   );
   ```

   Run build_runner (route args regen). Do **not** auto-open the Recipients tab —
   the user must fill Info first; the preselect applies whenever the tab is first
   prepared.
3. `ForwardCubit`: new `final Set<String> initialSelectedIds` constructor param
   (default `const {}`), applied **once** in `_loadCandidates` alongside the
   existing preselect block, guarded by its own `_appliedInitialUserPreselect`
   flag and by `preservedSelection.isEmpty` (never fight a user's manual edits):

   ```dart
   final userPreselect = !_appliedInitialUserPreselect
       && preservedSelection.isEmpty
       ? initialSelectedIds.intersection(availableIds)
       : const <String>{};
   if (initialSelectedIds.isNotEmpty && !_appliedInitialUserPreselect) {
     _appliedInitialUserPreselect = true;
     // dropped = initialSelectedIds.difference(availableIds) → state flag
   }
   ```

   Read §8.7 before touching this method — there is a deliberate QA rule against
   preselection in this file; the comment at the preselect block
   (`forward_cubit.dart:129`) must be extended, not deleted, to say user-explicit
   preselects (person came from a profile action) are exempt.
4. Dropped-preselect UX: if the person is not in `availableIds` (they became
   unreachable between screens), expose `droppedPreselectedIds` in `ForwardState`
   and show a one-line banner on the Recipients tab
   (`beaconRecipientsPreselectDropped`, EN:
   `{name} can't receive requests from you yet and was not added.`). Do not block
   the rest of the flow.
5. `PersonForwardScreen` "New request" button → new `ScreenCubit` helper:

   ```dart
   void showBeaconCreateFor(String userId) => _navigateTo(
       '$kPathBeaconNew?$kQueryBeaconForwardTo=${Uri.encodeQueryComponent(userId)}');
   ```

---

## 8. Quirks, gotchas, corner cases (read all before coding)

1. **Terminology lints will fail the build, not just review.**
   `no_request_domain_entity` blocks any class named `Request`/`RequestEntity`;
   `scripts/check-user-facing-terminology.sh` (CI) scans user-facing strings.
   Internal names in this plan are deliberately `PersonForward*`, route
   `/forward-person`, keys `beaconForwardPerson*`.
2. **Route collision**: `root_router.dart` already has `'$kPathForwardBeacon/:id'`
   (`/forward/:id`). A nested `'/forward/person/:id'` would depend on route
   registration order to not be swallowed by the `:id` param. Use the distinct
   prefix `/forward-person/:id` and the problem cannot exist.
3. **Status-gate inconsistency (do not copy it).**
   `ForwardCubit.forward()` currently refuses unless `status == BeaconStatus.open`,
   while every entry point (my-work cards, share sheet, overflow menus) gates on
   `status.allowsForward` (open family: `open`, `needsMoreHelp`, `enoughHelp`).
   The new flow must use `beacon.status.allowsForward` everywhere (list filter is
   already server-side via `lifecycleStates: openFamilyValues`; keep the defensive
   `PersonForwardBlock.notOpen` mapping for rows that change status between load
   and render). Optionally, as a separate one-line fix with its own test, relax
   `forward_cubit.dart:314` to `!beacon.status.allowsForward` — but do not silently
   fold that into this feature.
4. **Hasura workaround — involvement must stay a V2 call.** Do not "optimize" the
   N+1 by adding `rejected_user_ids`-style fields into the Hasura beacon list
   query: when `beacon_get_rejected_user_ids` returns zero rows Hasura drops the
   whole beacon row (documented in `packages/server/WORKAROUNDS.md` and in the
   comment at `forward_repository.dart:159`). The N+1 over `beaconInvolvement` is
   the intended design; N = my open requests, typically < 10. If it ever measures
   slow, the fix is a batch V2 endpoint (server work, out of scope).
5. **Involvement fetch failure ≠ screen failure.** One failed `beaconInvolvement`
   call must degrade to `CandidateInvolvement.unseen` (row stays eligible), not
   sink the screen. This is safe because the server idempotently skips duplicate
   active edges (`createBatch` checks `findActiveEdge` first) — worst case a
   redundant send is a no-op.
6. **l10n mechanics**: keys go into BOTH `packages/client/l10n/app_en.arb` and
   `app_ru.arb` (missing RU breaks `flutter gen-l10n` untranslated checks / CI
   terminology test). Placeholders use ICU syntax (`{name}`) — copy an existing
   parameterized key such as the evaluation strings for the metadata block shape.
   Russian noun: **запрос/запросы**, workspace is **чат** — never «маяк», never
   "beacon" in values.
7. **The preselect QA rule.** `forward_cubit.dart:129` has a hard-won rule:
   *never pre-select server-suggested recipients* (mis-forwarding incident,
   QA Jun-26). Phase 2 is allowed because the preselect encodes the **user's own
   explicit intent** (they tapped an action on that person's profile). Keep the
   two mechanisms separate (`preselectLineageSuggestions` vs `initialSelectedIds`,
   separate applied-flags), apply once, never re-apply after the user edits the
   selection, and extend the comment.
8. **Reachability is client-side only.** `isSeeingMe == rScore > 0` (their
   MeritRank score of me). The server will happily create an edge to an
   unreachable person. Keep the UI gate (disabled send + banner) to preserve the
   product rule; do not rely on a server rejection, and do not add a server check
   in this change.
9. **Self-profile**: hide the profile button when `profile.id == myId`
   (`ProfileCubit`). Also guard in `PersonForwardCubit.load` (`personId == myId`
   → error state) — the route is deep-linkable, the button isn't the only way in.
10. **Fresh/zero-score users**: a brand-new contact may have `rScore == 0` until
    MeritRank recomputes. They will show as unreachable — this matches the
    existing request-first picker (such a person doesn't appear in its candidates
    at all). Consistency beats cleverness; do not special-case.
11. **Pagination**: `fetchBeacons` takes `offset`/`limit`. v1 uses
    `offset: 0, limit: 50` with no pager — more than 50 *open* authored requests
    is outside the current product reality. Leave a `// TODO(pagination)` at the
    call site.
12. **Contact names**: any place a person's name is rendered or interpolated into
    copy must use the overlay-adjusted profile (`profileWithContactOverlay` /
    `ContactsCase.refresh()` first) — otherwise renamed contacts show their raw
    display name. Subscribe to `contactChanges` like `ForwardCubit` does.
13. **Desktop + touch parity** (project rule): no long-press-only or hover-only
    affordances on the new screen. Everything here is plain taps/buttons — keep it
    that way.
14. **Why only authored requests in v1**: requests forwarded *to* me are also
    relayable in the product model, but listing them needs an inbox-wide fetch +
    per-beacon involvement, and `computeInvolvement` then can legitimately return
    `author` (the person authored the thing that was forwarded to me) — that is
    what `PersonForwardBlock.theirOwn` is reserved for. Ship authored-only first;
    add relayables as a follow-up list section, same row model.
15. **Draft/finished requests never appear**: the server-side
    `lifecycleStates` filter ({0,7,8}) excludes drafts (3), wrapping-up (5),
    closed/cancelled/deleted — no client-side status filtering needed beyond the
    defensive `notOpen` block.
16. **Watching side effect**: after my first forward of a beacon I authored…
    nothing changes (author). But when relayables land (see 14), a successful
    forward may add me to "watching" — the inbox updates itself via invalidation
    streams; do not manually poke inbox state from this feature.
17. **UiEffect pattern**: `ProfileViewScreen` wraps with `localScreenCubitScope`;
    `ForwardBeaconScreen` does not (global bus). Follow the `ForwardBeaconScreen`
    pattern for the new screen — `NavigateBack`/`ShowError` through
    `GetIt.I<UiEffectPort>()` — so snackbars/back work identically to the
    request-first forward screen.

---

## 9. Testing & verification

Unit tests (mirror existing patterns under `packages/client/test/features/forward/`):

- `person_forward_block_test.dart` — pure `blockFor` matrix: every
  `CandidateInvolvement` × {open, needsMoreHelp, enoughHelp, reviewOpen, closed}.
  Model on `forward_compute_involvement_test.dart`.
- `person_forward_cubit_test.dart` — mocked case: load happy path; involvement
  failure degrades to eligible row; send guards (nothing selected / ineligible row
  / unreachable person → no repository call); successful send emits
  `NavigateBack`; `forwardCompleted` for a listed beacon triggers reload. Use the
  `debugSkipInitialLoad`-style constructor seam.
- Extend `forward_cubit_preselect_test.dart` (Phase 2): `initialSelectedIds`
  applied once; not re-applied after manual deselect + live reload; dropped id
  surfaces in `droppedPreselectedIds`; lineage preselect and user preselect don't
  interfere.

Full gate (CI parity):

```bash
cd packages/tentura_lints && dart test        # custom lint rules still pass
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
bash scripts/check-user-facing-terminology.sh
cd packages/client && flutter test
```

Reminder: custom lints do not fire under CLI `flutter analyze` in this repo — the
`dart test` in `packages/tentura_lints` is the real gate for them.

Manual e2e (use the `local-debug` skill: QA login bypass, Playwright, seeded users
via `scripts/seed_society`):

1. As user A with ≥1 open request, open user B's profile → "Send a request" →
   pick request → note → send → snackbar + back on profile.
2. As B (QA login), verify the request appears in Inbox with A's note; verify **no**
   friendship/trust change appeared on either side (B's profile of A unchanged).
3. Repeat 1 → the request row now shows "already sent" disabled; tap navigates to
   the request-first forward screen showing the existing edge.
4. Empty state: user with no open requests → only the "New request for …" CTA.
5. Phase 2: "New request" → fill Info → Recipients tab shows B pre-checked →
   uncheck/re-check works → Send request → confirmation dialog lists B.
6. Unreachable person (fresh seeded account that never rated A): banner shown,
   send disabled, mutuals entry visible (Phase 3).

## 10. Acceptance-criteria mapping (issue #83)

| Criterion | Where satisfied |
|---|---|
| Profile primary actions include contextual request actions, not generic messaging | §3.1 button → §3.2 screen; no DM affordance added |
| Existing-request picker filters to requests the person can validly receive | §5 `blockFor` + server-side open-family filter; ineligible rows shown disabled **with the reason** (issue req. 3) |
| Creating from profile preselects recipient but doesn't prevent adding others | §7: `initialSelectedIds` on the unchanged multi-select picker |
| Same action model available from a graph node | Deferred by request; the routed `/forward-person/:id` screen + `ScreenCubit.showForwardToPerson` is the reuse hook |
| Preserve scoped visibility, no general social tie | §2 server facts: forward edge only; no new read paths added, reachability gate kept |
| No dead end when direct forwarding impossible | §3.2 banner + Phase 3 mutual-connections relay entry |
