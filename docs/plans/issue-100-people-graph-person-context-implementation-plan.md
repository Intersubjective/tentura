# Issue #100 — People, graph navigation, person context, and canonical visibility

## Execution status

**Status:** implementation-ready plan; no implementation from this plan has started.

**Scope:** issue #100 plus the “Visibility and Request Reachability” patch supplied with it.

**Implementation rule:** execute the work units below in order. Do not skip a stop condition, silently weaken a test, edit a generated file, or infer a missing product decision. If the live repository contradicts a verified baseline recorded here, stop and update this plan before changing production code.

This document is deliberately prescriptive. Names marked “exact” are decisions, not examples. Where a migration number or generated output can drift, the executor must perform the stated rebase-time check instead of assuming this snapshot is still current.

---

## 1. Outcome

Establish three separate graph concerns:

```text
GraphMode
    selects the valid interaction grammar
        ↓
Graph navigation
    previous focus / fit / reset or center / legend
        ↓
Selected person
    visibility / trust / request options / profile / show more
```

Establish one request-reachability contract across database, server, Hasura, client domain, Profile, Graph Person Context, recipient discovery, and the final send mutation:

```text
viewer → subject visibility
    = outgoing explicit trust OR positive forward MeritRank

subject → viewer visibility
    = incoming explicit trust OR positive reverse MeritRank

mutual visibility
    = both directional visibilities

direct request sending
    = mutual visibility
```

Move Blocked People to one semantic owner:

```text
People / Network
    ├── People list
    ├── Invitations
    ├── Graph
    └── Blocked people
```

The five global tabs and internal `friend`/`beacon`/`network` identifiers remain unchanged.

---

## 2. Non-negotiable executor rules

1. Preserve all unrelated changes. Never reset, stash, clean, overwrite, stage, or commit files outside the active work unit.
2. Read `AGENTS.md` and the triggered `.cursor/rules` again before implementation. For client UI, follow `material-3-flutter`: feature UI must use `context.tt`, `TenturaText`, `ColorScheme`, and existing components. Do not add raw feature-level colors, font sizes, padding, radii, or panel dimensions.
3. Never edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, generated l10n, generated Ferry output, or generated Drift output). Edit sources, then run the specified generators.
4. Do not rename `HomeTab.network`, `kPathNetwork`, `FriendsScreen`, friend-domain types, beacon-domain types, or the five global destinations.
5. Do not add generic messaging, a new graph library/fork, a second forwarding engine, a graph-wide refetch after Trust, a Settings compatibility route, or another Blocked Users screen.
6. Do not change `GraphCubit.handleNodeTap()` semantics. Tests may be strengthened around it, but panel selection must be integrated beside it.
7. Do not enable direct sending based on a client-only check. The server mutation is the final authorization boundary.
8. Do not remove trust-graph AppBar Profile/Expand actions until the unbriefed-person usability gate in WU14 has passed and evidence is recorded.
9. Run each work unit’s targeted checks before starting the next work unit.
10. When a required human gate cannot be performed, stop with the implementation incomplete. Do not claim that automated widget tests substitute for an unbriefed participant.

---

## 3. Verified baseline (2026-08-08)

### 3.1 Ownership preflight for issue #86

The overlap is serialized:

- issue #86 is closed;
- no active #86 pull request was found;
- commit `22f9d35dde623e84bdbca8926c4fe20faef087fb` (`Implement graph navigation`) is an ancestor of current `main`;
- the checkout has one worktree only;
- historical plan text that still calls Phase 4B pending is stale bookkeeping.

Therefore #100 must consume the landed #86 APIs. It must not create a competing focus-trail implementation.

At implementation start, rerun:

```bash
git worktree list --porcelain
git merge-base --is-ancestor 22f9d35d HEAD
gh issue view 86 --json state
gh pr list --state open --search '86 in:title,body'
```

**Stop condition:** if a new active branch/PR again owns `GraphCubit`, `GraphState`, `GraphAppBarActions`, `GraphBody`, or graph-navigation tests, serialize that work before WU2.

### 3.2 Dirty-worktree warning

This snapshot already contains unrelated modified and untracked files, including files under `docs/`, `packages/server/lib/`, keys, local defines, and pre-existing graph plans. They belong to other work. The implementation must begin with `git status --short`, record the live list in its journal, and use path-scoped diffs/staging only.

This plan itself owns only:

```text
docs/plans/issue-100-people-graph-person-context-implementation-plan.md
```

until implementation is explicitly authorized.

### 3.3 Existing graph contract

`GraphCubit` already contains `handleNodeTap`, `selectNode`, `expandNode`, `popFocus`, `resetToEgo`, `fitCurrentPath`, and `_everFocusedIds`.

Verified defects/gaps:

- `selectNode()` emits the new `focus` before `_updateFocusPath()` mutates the trail;
- `GraphState` has no immutable focus-trail depth;
- modes are re-inferred in multiple widgets from `forwardsGraphBeaconId` and `genealogyMode`;
- `GraphAppBarActions` calls `jumpToEgo(resetScale: true)` for “Reset to me”; this is camera-only and does not reset traversal;
- contextual Profile/Expand actions are still in the shared AppBar;
- graph nodes have a selected focus ring but no meaningful `Semantics` or pointer hover affordance;
- `NodeDetails` equality includes `score`, but not `rScore`, outgoing trust, incoming trust, or strict mutual-trust state;
- `GraphController.replaceNode()` already preserves position and replaces touching edges; reuse it.

`resetToEgo()` already preserves `_everFocusedIds`. Preserve that behavior and keep the existing regression in `graph_focus_path_visibility_test.dart`; do not “simplify” reset by clearing session exploration memory.

### 3.4 Existing visibility and forwarding contract

Current `Profile` has `score`, `rScore`, `myVote`, and `isMutualFriend`. It lacks an independent incoming-explicit-trust signal. Its current `isMutuallyVisible => score > 0 && rScore > 0` is incomplete.

Current discovery and enforcement gaps:

- `forward_candidates_fetch.graphql` reads `rating` and filters both MR directions positive, so explicit-trust and mixed trust/MR mutual visibility are undiscoverable;
- `ForwardCandidate.isReachable`, `PersonForwardCubit`, and `PersonForwardScreen` use `Profile.isMutuallyVisible` and will benefit from the corrected getter;
- server `ForwardCase.forward()` checks content access, forwarding permission, self, and blocks, but does not authorize recipient mutual visibility before inserting edges;
- `ProfileViewCase.addFriend()` copies only the mutation’s returned `myVote` into the old profile instead of refetching an authoritative viewer-relative projection.

### 3.5 Existing People and routing contract

- `FriendsScreen` currently exposes Create invitation and QR scan only.
- Settings currently owns the Blocked Users action.
- root routing registers `/settings/blocked`.
- `BlockUserSheet` pushes `BlockedUsersRoute` directly via `RootRouter`.
- `kPathBlockedUsers` is `/settings/blocked`.
- `BlockedUsersScreen` is the one implementation and must remain the one implementation.

### 3.6 Version snapshot

At plan creation:

```text
client pubspec:             5.8.0
web bootstrap cache key:   5.8.0
server minimum client:     5.6.38
```

This is a backward-compatible user-visible feature. If those values remain current at release time, bump client to **5.9.0**, sync the web cache key to **5.9.0**, and do not raise the server minimum. Recalculate semver from the live version if another release lands first.

---

## 4. Fixed product and technical decisions

These decisions remove ambiguities left open by the issue text.

### 4.1 Incoming explicit trust field

Add the exact API field:

```text
trusts_viewer
```

Client/domain name:

```dart
subjectExplicitlyTrustsViewer
```

It means: the profile subject has a positive `vote_user` edge toward the authenticated viewer. It is not inferred from `isMutualFriend`, `score`, or `rScore`.

### 4.2 Canonical `Profile` getters

Add/use these exact semantics in `Profile`:

```dart
bool get viewerExplicitlyTrustsSubject => myVote > 0;
bool get forwardMeritRankPositive => score > 0;
bool get reverseMeritRankPositive => rScore > 0;

bool get viewerCanSeeSubject =>
    viewerExplicitlyTrustsSubject || forwardMeritRankPositive;

bool get subjectCanSeeViewer =>
    subjectExplicitlyTrustsViewer || reverseMeritRankPositive;

bool get isMutuallyVisible =>
    viewerCanSeeSubject && subjectCanSeeViewer;
```

Compatibility rules:

- retain `isFriend` as an outgoing-explicit-trust alias;
- retain `isNotFriend` as its inverse;
- retain `isSeeingMe` only if existing callers require it, and document it as **reverse-MeritRank-only**;
- retain `isMutualFriend` as strict reciprocal explicit trust;
- new #100 code must use the explicit directional getters.

### 4.3 Pure action policy

Create:

```text
packages/client/lib/ui/model/person_action_policy.dart
```

with exact public enums:

```dart
enum PersonPrimaryAction { none, trust, sendRequest }
enum PersonVisibilityState { neither, viewerOnly, subjectOnly, mutual }
```

`PersonActionPolicy.from(Profile profile, {required bool isSelf, required bool isBlocked})` must expose:

```text
viewerExplicitlyTrustsSubject
subjectExplicitlyTrustsViewer
viewerCanSeeSubject
subjectCanSeeViewer
visibilityState
isMutuallyVisible
canDirectSendRequest
primaryAction
showSecondaryTrust
showRequestOptions
```

Exact hierarchy:

| State | Filled primary | Secondary trust | Secondary routing entry |
|---|---|---|---|
| self | none | no | no |
| blocked | none | no | no |
| mutual visibility | Send request | yes only when outgoing explicit trust is absent | no |
| not mutual, outgoing explicit trust absent | Trust this user | no | Request options |
| not mutual, outgoing explicit trust already present | none | no | Request options |

`Request options` opens `PersonForwardScreen` but is not labelled or styled as an enabled direct-send action. `PersonForwardScreen` continues to disable actual sending while mutual visibility is false and retains whatever fallback/relay explanation already exists; #100 does not add another explanation engine.

This decision preserves a useful route into the canonical routing surface without claiming one-way visibility can send directly.

### 4.4 Graph mode

Add one exact enum in a non-generated graph domain file:

```dart
enum GraphMode { trust, forwards, genealogy }
```

`GraphCubit` derives a final `mode` once from its existing constructor arguments:

```text
forwardsGraphBeaconId != null → forwards
genealogyMode == true         → genealogy
otherwise                     → trust
```

Keep the existing constructor arguments for compatibility. All new widget/cubit gating uses `mode`; do not independently inspect both old fields.

### 4.5 Graph AppBar by mode

Final controls after the WU14 usability gate:

| Mode | Navigation controls | Contextual controls |
|---|---|---|
| trust | Previous focus, Fit current path, Reset to me, Legend | none; person actions live in panel |
| genealogy | Previous focus, Fit current path, Reset to genealogy origin, Legend | preserve live-user Profile/details behavior |
| forwards | Center view, Legend | preserve Beacon Open Request and existing forwards-valid Profile/details behavior; no Trust, Send, expand paging, `popFocus`, or `resetToEgo` |

`Center view` is camera-only and calls `jumpToEgo(resetScale: true)`. It must never call `resetToEgo()`.

### 4.6 Blocked navigation effect

A path-only `NavigatePush('/home/network/blocked')` is not sufficient for an already-mounted `AutoTabsRouter`. Add a semantic UI effect:

```dart
const NavigateBlockedUsers()
```

and:

```dart
ScreenCubit.showBlockedUsers()
```

The root adapter must activate Network, normalize that branch to `FriendsRoute`, then push `BlockedUsersRoute`. On cold navigation it must construct `HomeRoute → NetworkTabShell → FriendsRoute → BlockedUsersRoute`.

### 4.7 SQL/server source of truth

Use one PostgreSQL visibility projection rather than reproducing the four-signal formula in multiple server repositories.

The migration must add these exact functions:

```text
public.person_visibility_peers(viewer_id text, ctx text)
public.person_is_mutually_visible(viewer_id text, peer_id text, ctx text)
public.user_get_trusts_viewer(user_row public."user", hasura_session json)
public.mutually_visible_users(context text, hasura_session json)
```

`person_visibility_peers` returns one row per non-self peer appearing in either trust direction or the viewer’s `mr_mutual_scores` result, with these columns:

```text
peer_id text
viewer_explicitly_trusts_subject boolean
subject_explicitly_trusts_viewer boolean
forward_mr double precision
reverse_mr double precision
viewer_can_see_subject boolean
subject_can_see_viewer boolean
is_mutually_visible boolean
```

Incoming-only MeritRank is not a visibility signal here. `mr_mutual_scores(viewer)` is ego-outbound, so a peer with only peer→viewer MR (including mixed explicit trustOut + mrIn) is omitted. We dropped `mr_edgelist` / per-peer `mr_node_score` discovery: first for speed, second for simplicity. Mutual visibility remains explicit `vote_user` and/or a `mr_mutual_scores` row (both directions in that row). Mixed `trustIn + mrOut` is unchanged. See migration `m0151`.

Direction mapping for `mr_mutual_scores(viewer_id, coalesce(ctx, ''))` must match the repository’s documented convention in `m0031.dart` and `merit_score_lookup.dart`:

```text
ms.src == viewer → score_value_of_dst is viewer→peer
ms.src == viewer → score_value_of_src is peer→viewer

ms.dst == viewer → score_value_of_src is viewer→peer
ms.dst == viewer → score_value_of_dst is peer→viewer
```

Aggregate duplicate MR rows deterministically with `max`; missing values become `0`. Positive `vote_user.amount` establishes its direction. Non-positive trust/MR does not.

`person_is_mutually_visible` returns false when no peer row exists.

`mutually_visible_users` returns public `user` rows for `is_mutually_visible = true`, excludes self, applies `block_hides(viewer, peer)`, and is exposed to Hasura’s `user` role with `hasura_session` as its session argument.

---

## 5. Change inventory

The executor must confirm paths still exist before editing. Generated outputs are listed only so they can be regenerated, never hand-edited.

### Database, Hasura, and server

```text
packages/server/lib/data/database/migration/_migrations.dart
packages/server/lib/data/database/migration/m0140.dart              [number conditional]
hasura/metadata.json

packages/server/lib/domain/port/vote_user_friendship_lookup_port.dart
packages/server/lib/data/repository/vote_user_friendship_lookup.dart
packages/server/lib/domain/port/person_visibility_repository_port.dart       [new]
packages/server/lib/data/repository/person_visibility_repository.dart         [new]
packages/server/lib/domain/entity/gql_public/user_public_record.dart
packages/server/lib/domain/port/user_profile_batch_lookup_port.dart
packages/server/lib/data/repository/user_profile_batch_lookup.dart
packages/server/lib/data/repository/coordination_repository.dart
packages/server/lib/data/repository/mutual_friends_repository.dart
packages/server/lib/api/controllers/graphql/custom_types.dart
packages/server/lib/api/controllers/graphql/mappers/gql_public_user_maps.dart
packages/server/lib/api/controllers/graphql/mappers/invite_genealogy_gql_maps.dart
packages/server/lib/api/controllers/graphql/query/query_invite_genealogy.dart
packages/server/lib/api/controllers/graphql/query/query_invitation.dart
packages/server/lib/domain/use_case/forward_case.dart
packages/server/lib/api/controllers/graphql/mutation/mutation_forward.dart   [only if error mapping needs it]
```

### Client domain, data, and routing

```text
packages/client/lib/domain/entity/profile.dart
packages/client/lib/data/gql/user_model.graphql
packages/client/lib/data/gql/user_public_model.graphql
packages/client/lib/data/model/user_model.dart
packages/client/lib/data/model/user_public_model.dart
packages/client/lib/features/beacon_view/data/gql/help_offers_with_coordination.graphql
packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart
packages/client/lib/features/profile_view/data/gql/mutual_friends_fetch.graphql
packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart
packages/client/lib/features/forward/data/gql/forward_candidates_fetch.graphql
packages/client/lib/features/forward/data/repository/forward_repository.dart
packages/client/lib/features/profile_view/domain/use_case/profile_view_case.dart
packages/client/lib/ui/model/person_action_policy.dart                         [new]

packages/client/lib/consts.dart
packages/client/lib/app/router/home_tab_branches.dart
packages/client/lib/app/router/root_router.dart
packages/client/lib/ui/effect/ui_effect.dart
packages/client/lib/ui/effect/ui_effect_dispatcher.dart
packages/client/lib/ui/bloc/screen_cubit.dart
packages/client/lib/features/block/ui/screen/blocked_users_screen.dart
packages/client/lib/features/block/ui/sheet/block_user_sheet.dart
packages/client/lib/features/settings/ui/screen/settings_screen.dart
```

### Client People, Profile, and Graph UI

```text
packages/client/lib/features/friends/ui/screen/friends_screen.dart
packages/client/lib/features/friends/ui/widget/friends_app_bar_actions.dart   [new]
packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart
packages/client/lib/features/capability/ui/widget/network_person_card.dart

packages/client/lib/features/graph/domain/entity/graph_mode.dart              [new]
packages/client/lib/features/graph/domain/entity/node_details.dart
packages/client/lib/features/graph/ui/bloc/graph_cubit.dart
packages/client/lib/features/graph/ui/bloc/graph_state.dart
packages/client/lib/features/graph/ui/bloc/graph_person_context_cubit.dart     [new]
packages/client/lib/features/graph/ui/bloc/graph_person_context_state.dart     [new]
packages/client/lib/features/graph/ui/widget/graph_app_bar_actions.dart
packages/client/lib/features/graph/ui/widget/graph_body.dart
packages/client/lib/features/graph/ui/widget/graph_node_widget.dart
packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart  [new]
packages/client/lib/features/graph/ui/screen/graph_screen.dart
packages/client/lib/design_system/tentura_tokens.dart
packages/client/lib/ui/test_ids.dart
```

### Localization and release

```text
packages/client/l10n/app_en.arb
packages/client/l10n/app_ru.arb
packages/client/pubspec.yaml
packages/client/web/index.html
```

---

## 6. WU0 — Rebase-time preflight and characterization

### Production changes

None.

### Actions

1. Re-run the #86 ownership commands in §3.1.
2. Capture `git status --short`, current version/cache key, next migration part, and current Hasura metadata state in an implementation journal.
3. Confirm the next migration number. Use `m0140` only if `_migrations.dart` still ends at `m0139`; otherwise allocate the next unused sequential number and replace `m0140` references in this plan’s execution notes.
4. Run the existing characterization tests before changing behavior:

```bash
cd packages/client
flutter test test/features/graph/graph_focus_path_visibility_test.dart
flutter test test/features/graph/graph_body_navigation_controls_test.dart
flutter test test/features/graph/graph_cubit_genealogy_test.dart
flutter test test/features/graph/graph_body_genealogy_test.dart
flutter test test/features/graph/graph_body_select_expand_test.dart
flutter test test/features/graph/forward_graph_focus_rules_test.dart
flutter test test/app/router/home_tab_branch_routing_test.dart
flutter test test/features/block/ui/sheet/block_user_sheet_test.dart
flutter test test/ui/widget/contact_badge_legend_test.dart

cd ../server
dart test --exclude-tags pg test/domain/use_case/forward_case_test.dart
dart test --exclude-tags pg test/domain/use_case/forward_case_auth_test.dart
```

5. Record which existing tests already cover:
   - reset preserving `_everFocusedIds`;
   - new-node explore versus visited-node rollback;
   - cached path reconstruction;
   - genealogy focus behavior.

Do not duplicate those tests merely to inflate counts. Extend them when their asserted state must change.

### Stop condition

All baseline tests pass, or every pre-existing failure is recorded and explicitly separated from #100. No production file has changed.

---

## 7. WU1 — Canonical visibility at the database and API boundary

This work comes before the client policy so the client never invents an incoming-trust approximation.

### 7.1 Add migration

Create the allocated migration part and register it in both the `part` list and ordered `InMemory` list in `_migrations.dart`.

Implement the four functions specified in §4.7. Requirements:

- every function is `STABLE`, not `IMMUTABLE`, because it reads tables and/or MeritRank state;
- normalize only the visibility-query context with `coalesce(ctx, '')`;
- treat a missing/blank authenticated viewer as no visibility;
- exclude self;
- do not infer incoming trust from reciprocal trust or MeritRank;
- mixed `trustIn + mrOut` remains valid; mixed `trustOut + mrIn` is not mutual (m0151: speed, then simplicity);
- use existing `block_hides` only in the public candidate function, not in the raw directional projection;
- function bodies must be valid PostgreSQL, not SQLite-compatible approximations.

### 7.2 Hasura metadata

In `hasura/metadata.json`:

1. Add computed field `trusts_viewer` to table `public.user`, backed by `user_get_trusts_viewer`, with `user_row` and `hasura_session` arguments.
2. Add `trusts_viewer` to the `user` role’s allowed computed fields.
3. Track `mutually_visible_users` as a query function, with `hasura_session` configured and `user` permission.
4. Do not remove `my_vote`, `is_mutual_friend`, `scores`, `rating`, or graph functions.

### 7.3 V2 public-user projection

Add non-null GraphQL field `trusts_viewer` to `gqlTypeUserPublic`. Add `subjectExplicitlyTrustsViewer` with default `false` to `UserPublicRecord`, and map it to JSON key `trusts_viewer` in `userPublicToGqlMap`.

Extend `VoteUserFriendshipLookupPort` with one batch result that independently returns:

```dart
({Set<String> viewerTrusts, Set<String> trustsViewer})
```

for a viewer and candidate IDs. Implement it with two indexed `vote_user.amount > 0` queries. Keep existing reciprocal and single-peer methods, but implement/verify them from the directional result so their semantics cannot drift.

Populate incoming trust in every viewer-aware V2 user projection:

- `DriftUserProfileBatchLookup.userPublicRecordsByIds` receives incoming-trust IDs;
- `CoordinationRepository.helpOffersWithCoordination` obtains one directional batch and supplies both reciprocal and incoming sets;
- `MutualFriendsRepository.fetchMutualFriends` supplies incoming trust;
- invite-genealogy overlay returns scores, strict mutual-trust IDs, and incoming-trust IDs, then passes the incoming set through all mapper functions;
- `QueryInvitation` sets `trusts_viewer` for the issuer using the signed-in viewer;
- blocked-user responses explicitly map `trusts_viewer: false`, because normal person actions are unavailable and hidden relationships must not be exposed.

Search after changes:

```bash
rg -n "UserPublicRecord\(" packages/server/lib packages/server/test
rg -n "userPublicToGqlMap|gqlTypeUserPublic" packages/server/lib
```

Every resolver returning `gqlTypeUserPublic` must supply a non-null value; defaults must not conceal a viewer-aware projection that forgot to query it.

### 7.4 Tests

Add:

```text
packages/server/test/data/database/person_visibility_migration_pg_test.dart
packages/server/test/data/repository/vote_user_friendship_lookup_test.dart
packages/server/test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart
```

The PostgreSQL test is tagged `pg` and uses the live Postgres/MeritRank services. It must seed or construct all four signals independently and prove at least these rows:

| T→ | MR→ | T← | MR← | visible → | visible ← | mutual |
|---|---:|---|---:|---|---|---|
| no | ≤0 | no | ≤0 | no | no | no |
| yes | ≤0 | no | ≤0 | yes | no | no |
| no | >0 | no | ≤0 | yes | no | no |
| no | ≤0 | yes | ≤0 | no | yes | no |
| no | ≤0 | no | >0 | no | no | no |
| yes | ≤0 | yes | ≤0 | yes | yes | yes |
| no | >0 | no | >0 | yes | yes | yes |
| yes | ≤0 | no | >0 | yes | no | no |
| no | >0 | yes | ≤0 | yes | yes | yes |
| yes | >0 | no | ≤0 | yes | no | no |

Incoming-only MeritRank is not a visibility signal here. `mr_mutual_scores(viewer)` is ego-outbound, so a peer with only peer→viewer MR (including mixed explicit trustOut + mrIn) is omitted. We dropped `mr_edgelist` / per-peer `mr_node_score` discovery: first for speed, second for simplicity. Mutual visibility remains explicit `vote_user` and/or a `mr_mutual_scores` row (both directions in that row). Mixed `trustIn + mrOut` is unchanged (`m0151`). The `MR← only` and `T→ + MR←` rows therefore have no reverse visibility.

Also prove:

- `user_get_trusts_viewer` reads only peer→viewer positive trust;
- `mutually_visible_users` includes explicit-mutual, MR-mutual, and mixed `trustIn + mrOut`;
- mixed `trustOut + mrIn` is not in `mutually_visible_users`;
- one-way cases are absent;
- self and blocked peers are absent;
- `person_is_mutually_visible` returns false for a missing peer row;
- `context == null`/empty normalization matches the empty-context candidate query.

If the disposable migration harness lacks the external MeritRank functions, use `docker compose up -d meritrank postgres`, run migrations into that integration database, and keep this as a `pg` test. Do not replace behavioral proof with string matching alone.

### Generate and verify

```bash
cd packages/server
dart run build_runner build -d
dart format lib test
dart test --exclude-tags pg
dart test --tags pg test/data/database/person_visibility_migration_pg_test.dart
```

### Stop condition

The database can answer each direction independently, mixed `trustIn + mrOut` works, mixed `trustOut + mrIn` is not mutual (m0151), Hasura metadata applies, and all V2 public-user resolvers return the incoming signal. No client formula has yet changed.

---

## 8. WU2 — Client profile projection and canonical getters

### Schema/codegen sequence

Because `trusts_viewer` is additive server/Hasura schema, perform this in order:

1. start migrated local Postgres/MeritRank/Hasura and the updated server;
2. apply metadata with `./scripts/hasura_apply_metadata.sh`;
3. reload the Tentura remote schema after the updated server starts;
4. from repository root run `docker compose run --rm schema_fetcher`;
5. verify `packages/client/lib/data/gql/schema.graphql` contains both `trusts_viewer` and `mutually_visible_users`;
6. edit source `.graphql` fragments;
7. run client build runner.

Do not hand-edit `schema.graphql` or generated Ferry Dart.

### Source changes

1. Add `@Default(false) bool subjectExplicitlyTrustsViewer` to `Profile`.
2. Add the canonical getters from §4.2 and correct `isMutuallyVisible`.
3. Add `trusts_viewer` to `user_model.graphql`, `user_public_model.graphql`, `help_offers_with_coordination.graphql`, and `mutual_friends_fetch.graphql`.
4. Map the field in `UserModel.toEntity`, `UserPublicModel.toEntity`, coordination mapping, and mutual-friends mapping.
5. Search all direct `Profile(...)` construction. Test fixtures may rely on the default false; production mappers must set the field when their API includes it.
6. Update trust reciprocity copy on `ProfileViewBody` and `NetworkPersonCard`: incoming **explicit trust** uses `subjectExplicitlyTrustsViewer`; do not use `isSeeingMe` for a trust label.
7. The avatar eye continues to consume `profile.isMutuallyVisible`; correcting the getter updates it globally.
8. Correct graph/contact legend text that currently says an open eye requires positive MR both ways. It must say two-way visibility can come from Trust or MeritRank in each direction.

### Tests

Replace the old MR-only assertion in `contact_badge_legend_test.dart` with exhaustive domain tests in a new file:

```text
packages/client/test/domain/entity/profile_visibility_test.dart
```

Test all 16 boolean combinations of:

```text
T→ = myVote > 0
MR→ = score > 0
T← = subjectExplicitlyTrustsViewer
MR← = rScore > 0
```

For every row assert `viewerCanSeeSubject`, `subjectCanSeeViewer`, and `isMutuallyVisible` from the Boolean formula. Include negative and zero score boundary values. Separately assert:

- explicit mutual trust sends even with non-positive MR;
- positive MR both ways sends without trust;
- both mixed cases send (`trustIn + mrOut`; `trustOut + mrIn` is not mutual after m0151);
- either one-way state keeps the eye closed;
- `isMutualFriend` remains strict reciprocal explicit trust and is not used as incoming trust;
- `isSeeingMe`, if retained, remains reverse-MR-only and is not used by new policy code.

### Generate and verify

```bash
cd packages/client
dart run build_runner build -d
dart format lib test
flutter test test/domain/entity/profile_visibility_test.dart
flutter test test/ui/widget/contact_badge_legend_test.dart
flutter test test/features/beacon/data/additive_graphql_contract_test.dart
```

### Stop condition

Every client projection carries incoming explicit trust, the eye uses mutual visibility, and no production mapper approximates incoming trust.

---

## 9. WU3 — Server enforcement and candidate discovery

### Server authorization port

Create `PersonVisibilityRepositoryPort` with:

```dart
Future<Set<String>> mutuallyVisiblePeerIds({
  required String viewerId,
  required Iterable<String> peerIds,
  required String context,
});
```

Its Drift/Postgres implementation queries `person_visibility_peers(viewerId, context)` once, filters to requested peer IDs and `is_mutually_visible`, and returns IDs. It must not restate the trust/MR formula in Dart.

Inject the port into server `ForwardCase`.

### Exact validation order in `ForwardCase.forward()`

1. Keep empty-list, attribution, self, content-access, `allowsForward`, parent-edge, and block rules.
2. Create exactly once:

```dart
final visibilityContext = context ?? '';
```

3. Preserve the original nullable `context` when storing the forward edge and inbox row; existing SQL distinguishes null invite-forward context. Use `visibilityContext` only for candidate/authorization lookup.
4. After self removal and current block hiding, before `createBatch`, query mutually visible IDs for every remaining recipient.
5. Compare sets. If any remaining recipient is not mutually visible, throw `UnauthorizedException` with exact description `Direct request routing requires mutual visibility`.
6. Reject the entire remaining batch; never partially insert visible recipients from a mixed authorized/unauthorized input.
7. Verify `createBatch`, inbox watching, attribution, capability events, and attention intents were not called on rejection.

The server rule protects Graph, Profile, PersonForwardScreen, generic forward selection, create-request preselection, stale clients, and direct GraphQL callers.

### Candidate discovery

Change `forward_candidates_fetch.graphql` from `rating(where: both positive)` to:

```graphql
mutually_visible_users(args: {context: $context}) {
  ...UserModel
}
```

Update `ForwardRepository.fetchForwardCandidates` mapping and comment. Do not client-filter the returned rows with a second formula. Keep `ForwardCandidate.isReachable` and PersonForward guards on the canonical `Profile.isMutuallyVisible` as defense-in-depth.

### Tests

Update `forward_case_mocks.dart` to generate `PersonVisibilityRepositoryPort`, regenerate mocks, and extend:

```text
packages/server/test/domain/use_case/forward_case_auth_test.dart
packages/server/test/domain/use_case/forward_case_test.dart
packages/client/test/features/forward/person_forward_case_test.dart
packages/client/test/features/forward/person_forward_cubit_test.dart
```

Mandatory server cases:

- exact authorized set inserts;
- one-way outgoing trust rejects;
- one-way outgoing MR rejects;
- one-way incoming trust/MR rejects;
- explicit mutual trust authorizes;
- mutual positive MR authorizes;
- both mixed mechanisms authorize (`trustIn + mrOut`; `trustOut + mrIn` is not mutual after m0151);
- batch `[authorized, unauthorized]` inserts neither;
- authorization uses `context ?? ''`;
- blocked recipients retain existing hidden-recipient behavior without leaking relationship state;
- rejected validation causes no edge, inbox, attribution, capability, or attention effect.

Mandatory client cases:

- corrected `isMutuallyVisible` enables PersonForward rows for explicit-mutual and mixed `trustIn + mrOut` projections;
- one-way projections keep row selection/send disabled;
- manually invoking `send()` in a one-way state does not call the case;
- generic forward candidate discovery accepts all rows returned by the canonical function.

### Verify

```bash
cd packages/server
dart run build_runner build -d
dart test --exclude-tags pg test/domain/use_case/forward_case_auth_test.dart
dart test --exclude-tags pg test/domain/use_case/forward_case_test.dart

cd ../client
dart run build_runner build -d
flutter test test/features/forward/person_forward_case_test.dart
flutter test test/features/forward/person_forward_cubit_test.dart
```

### Stop condition

Valid explicit/mixed `trustIn + mrOut` recipients are discoverable and every direct-send caller is protected by server-side mutual visibility. Mixed `trustOut + mrIn` is not mutual after m0151.

---

## 10. WU4 — Explicit graph modes and reactive navigation

### Graph mode

Add `graph_mode.dart`, derive `GraphCubit.mode` once, and replace mode inference in:

- `GraphCubit` private gates;
- `GraphBody` legend/layout selection;
- `GraphAppBarActions`;
- any graph test stub that currently exposes `genealogyMode` and `forwardsGraphBeaconId` only.

Keep old public fields only where constructor/API compatibility requires them. Add constructor assertion tests for mutually exclusive flags.

### Reactive focus depth

Add `@Default(1) int focusPathDepth` to `GraphState`.

For every focus-path mutation:

```text
mutate _focusPathIds
then emit exactly one state containing focus + focusPathDepth
```

Apply this ordering to:

- `selectNode`;
- `popFocus`;
- `resetToEgo`;
- `setContext`;
- block-triggered full context reset;
- genealogy bootstrap/root establishment.

The AppBar computes availability as `graphState.focusPathDepth > 1`; do not add another cached Boolean and do not read private `_focusPathIds` from UI.

Preserve `_everFocusedIds` on `resetToEgo`. Only full context resets such as `setContext` may clear it.

### Mode-specific commands

Implement AppBar controls from §4.5 while **temporarily retaining** existing trust Profile/Expand actions.

- Trust “Reset to me” calls `resetToEgo()`.
- Genealogy reset calls `resetToEgo()` and uses genealogy-origin copy.
- Forwards “Center view” calls only `jumpToEgo(resetScale: true)`.
- Previous calls `popFocus()` and is disabled at depth 1.
- Fit calls `fitCurrentPath()` and is disabled until controller layout exists.
- Legend stays available in all modes.

Use `TestIds` for Previous, Fit, Reset/Center, Profile/details, and Expand.

### Tests

Extend existing focused test files rather than one generic mode test.

#### Trust

In `graph_focus_path_visibility_test.dart` and `graph_body_navigation_controls_test.dart` assert:

- two-hop and three-hop depth is emitted with the same state as focus;
- Previous decrements depth and restores focus without refetch;
- Fit calls the controller path fit after pan/zoom;
- Reset clears current trail, focus, pan, and zoom;
- Reset after rollback and repeated Reset are idempotent;
- `_everFocusedIds` survives Reset;
- a previously visited node still selects/rolls back without fetch after Reset;
- the AppBar Reset test replaces the current “home recenters without clearing focus trail” expectation.

#### Genealogy

In genealogy cubit/body tests assert:

- Previous uses node keys and never account IDs;
- Fit uses the genealogy path;
- Reset returns to `egoNodeId`, preserves genealogy parent-chain pins, and does not apply trust-graph visibility rules;
- Profile/details remains for a live genealogy user;
- deleted nodes have no invalid details action.

#### Forwards

Add a spy/stub assertion that:

- no visible action invokes `resetToEgo`, `popFocus`, or trust paging;
- Center invokes only camera recenter;
- repeated Center changes no nodes, edges, pins, focus, or forwards contents;
- Beacon Open Request and valid Profile/details remain.

### Generate and verify

```bash
cd packages/client
dart run build_runner build -d
flutter test test/features/graph/graph_focus_path_visibility_test.dart
flutter test test/features/graph/graph_body_navigation_controls_test.dart
flutter test test/features/graph/graph_cubit_genealogy_test.dart
flutter test test/features/graph/graph_body_genealogy_test.dart
flutter test test/features/graph/graph_body_select_expand_test.dart
```

### Stop condition

Mode is explicit, UI trail depth is immutable/reactive, trust reset is canonical, forwards state is never destructively reset, and #95 tap tests remain unchanged and green.

---

## 11. WU5 — People entry points

### UI structure

Create `FriendsAppBarActions` as a small testable widget with injected callbacks. `FriendsScreen` supplies callbacks and retains invitation creation logic.

Compact action order:

```text
Graph
Create invitation
More
```

`More` contains, in order:

```text
Scan invitation QR
Blocked people
```

Behavior:

- Graph reads the current account ID from `ProfileCubit` and calls existing `ScreenCubit.showGraphFor(id)`;
- Create invitation calls the existing `_onCreateInvitation` flow;
- Scan calls existing `ConnectBottomSheet.show`;
- Blocked calls `ScreenCubit.showBlockedUsers()` after WU6 adds it;
- do not create a new responsive action framework;
- if an existing top-bar responsive facility already exposes more actions on expanded width, reuse it; otherwise keep the same compact grammar on all widths.

Do not rename the two tabs or internal Friends types in this issue.

### Tests

Add:

```text
packages/client/test/features/friends/friends_app_bar_actions_test.dart
```

Pump the extracted widget with callbacks/fakes and assert:

- Graph is directly visible;
- Create invitation is directly visible;
- More is directly visible without overflow at 320 px;
- QR and Blocked appear only after opening More;
- each item calls exactly its callback;
- invitation creation and scanning remain reachable.

Add one FriendsScreen integration assertion that Graph uses the current `ProfileCubit` account ID and emits the existing graph navigation effect.

### Stop condition

An unbriefed user can find Graph and Blocked People from People without Settings.

---

## 12. WU6 — Blocked People route ownership

### Route table

1. Change `kPathBlockedUsers` to exact canonical path `/home/network/blocked`.
2. Remove the root `/settings/blocked` `AutoRoute` entirely.
3. Under `networkTabShell.children`, add:

```dart
AutoRoute(page: BlockedUsersRoute.page, path: 'blocked')
```

beside the initial `FriendsRoute`.
4. Do not add this route to `browseDetailChildren()`.
5. Do not add a redirect, alias, legacy Settings child, or compatibility route.
6. Regenerate AutoRoute output; never hand-edit `root_router.gr.dart`.

### Semantic navigation

Add `NavigateBlockedUsers` to `ui_effect.dart` and handle it in `dispatchUiEffect` by calling the exact public root-router adapter method `RootRouter.openBlockedUsers()`.

Exact adapter behavior:

```text
warm Home tabs available:
    set active tab = Network
    replace Network branch stack with FriendsRoute
    push BlockedUsersRoute

cold Home tabs unavailable:
    navigate HomeRoute(
      NetworkTabShell(
        FriendsRoute,
        BlockedUsersRoute,
      ),
    )
```

Await branch normalization before pushing Blocked. This explicit domain transition is allowed to discard the prior Network detail stack.

Add `ScreenCubit.showBlockedUsers()` which emits only `NavigateBlockedUsers`. No caller knows the nested route shape.

Change `BlockedUsersScreen` leading to:

```dart
AutoLeadingWithFallback(fallbackPath: kPathNetwork)
```

so a browser refresh with no prior in-memory stack still returns to People.

### Callers and Settings

- Friends More calls `ScreenCubit.showBlockedUsers()`.
- Inject/read `ScreenCubit` in `BlockUserSheetBody` and use the helper from the snackbar action; remove direct `RootRouter`/`BlockedUsersRoute` knowledge.
- Remove the Settings tile/action/import.
- Search all direct callers:

```bash
rg -n "BlockedUsersRoute|kPathBlockedUsers|settings/blocked|blockedUsersTitle" packages/client/lib packages/client/test
```

After migration, route construction may appear in the root router/adapter and router tests only. Application feature callers use `showBlockedUsers()`.

### Tests

Extend `home_tab_branch_routing_test.dart` to save/restore a fake `BlockedUsersRoute.page` and cover:

1. People helper → canonical Blocked URL;
2. caller from another tab → Network activated, branch stack `[FriendsRoute, BlockedUsersRoute]`;
3. direct `/home/network/blocked` browser/platform initial route renders Blocked;
4. refresh on canonical route renders Blocked;
5. normal Back after helper navigation returns to Friends root;
6. fallback Back after cold refresh navigates to `/home/network`;
7. `/settings/blocked` is not registered and follows normal unknown-route behavior;
8. route-table inspection finds `BlockedUsersRoute` once and only under Network.

Update `block_user_sheet_test.dart` to use `FakeUiEffectPort`/`ScreenCubit` and assert `NavigateBlockedUsers`, not a pushed route.

Add/extend a Settings widget test to assert no Blocked People title/action is present.

### Generate and verify

```bash
cd packages/client
dart run build_runner build -d
flutter test test/app/router/home_tab_branch_routing_test.dart
flutter test test/features/block/ui/sheet/block_user_sheet_test.dart
flutter test test/features/block/ui/screen/blocked_users_screen_test.dart
```

### Stop condition

There is one Blocked Users screen, one Network-owned route, no Settings route/action, and every application caller enters the People branch semantically.

---

## 13. WU7 — Pure person policy and Profile hierarchy

### Policy tests first

Add:

```text
packages/client/test/ui/model/person_action_policy_test.dart
```

Test all 16 trust/MR mechanism combinations plus self and blocked. For every mechanism row assert:

- both explicit-trust flags;
- both directional visibility flags;
- enum visibility state;
- mutual visibility/direct send;
- primary action;
- secondary Trust visibility;
- Request options visibility.

Permanent transition regressions:

```text
subject-only visibility + Trust → mutual → Send primary
neither visibility + Trust → viewer-only → no Send primary
viewer-only with outgoing trust already set → no misleading Trust CTA
mutual MR without outgoing trust → Send primary + secondary Trust
```

Reachability must never mutate or imply explicit trust.

### Profile refactor

Refactor `ProfileViewBody` in this order:

```text
avatar
description / presence
explicit relationship state
directional visibility state + open/closed-eye semantics
zero or one Filled primary CTA from PersonActionPolicy
secondary person actions
capabilities / graph / genealogy / request history / mutual connections
```

Rules:

- normal `ProfileViewBody` is unblocked because `ProfileViewScreen` already selects `BlockedProfileViewBody` for blocked fallback; pass real `isSelf` and `isBlocked: false` to policy;
- blocked body remains unblock-only and has no normal policy actions;
- mutual: Filled Send request; if outgoing explicit trust absent, secondary Trust;
- non-mutual and outgoing trust absent: Filled Trust; secondary Request options;
- non-mutual and outgoing trust present: no Filled CTA; show request-unavailable status plus secondary Request options;
- Request options calls `showForwardToPerson`; direct Send uses the same route but is displayed only for mutual visibility;
- Connections remains secondary and means “open this person’s graph”;
- use the new `trustThisUser` l10n key on #100 surfaces; do not perform a repository-wide identifier rename;
- `ProfileViewCubit.addFriend()` remains the UI event, but WU10 will make its use case authoritative.

Keep rendering helpers private to `profile_view_body.dart`; do not create a new domain layer or another public component API for this refactor.

### Profile widget tests

Add:

```text
packages/client/test/features/profile_view/profile_view_body_action_policy_test.dart
```

Use the existing `ProfileViewCubit`, `ProfileCubit`, `ScreenCubit`, `TenturaResponsiveScope`, and l10n harness patterns. Assert every hierarchy case, exactly one or zero `FilledButton` as specified, correct navigation effect, and no send-to-self action.

Keep `profile_view_blocked_profile_test.dart` green and assert blocked body never renders Trust, Send, or Request options.

### Stop condition

Profile communicates relationship and visibility independently and never offers an enabled direct-send CTA for one-way visibility.

---

## 14. WU8 — First manual usability check (before graph panel)

Use a build containing WU1–WU7. Give an unbriefed participant only these tasks:

1. open Graph from People;
2. find Blocked people from People;
3. return to People;
4. open a person Profile;
5. explain whether each side can see the other;
6. identify the primary action and why it is Trust, Send, or unavailable.

Record:

```text
date/build/commit
viewport/device
participant had no issue briefing: yes/no
task outcome and time
verbatim misunderstandings
screenshots or screen recording reference
changes required before WU9
```

**Stop condition:** People/Blocked/Profile terminology is understandable. Fix failures in the owning work unit before adding panel complexity.

---

## 15. WU9 — Graph projection patch and equality

Implement this before Trust UI so a successful mutation cannot be panel-local.

### `patchLoadedProfile(Profile updated)`

Add the API to `GraphCubit`. It is a projection patch, not a repository mutation.

For every `_nodes` entry:

- `UserNode.user.id == updated.id`: construct a new `UserNode` with `updated`, existing `size`, existing `pinned`, and existing `isHelpOfferer`;
- `GenealogyUserNode.user.id == updated.id`: construct a new `GenealogyUserNode` with `updated`, existing `nodeKey`, `size`, and `pinned`;
- Beacon/deleted/unrelated nodes: leave identical.

Update `_nodes`. If the old node is currently present in `graphController.nodes`, call `graphController.replaceNode(old, replacement)`. Do not clear, refetch, relayout from scratch, modify edge semantics, or replace unrelated nodes.

Trust-to-self is forbidden by policy, so this API is called for non-ego profiles. Implement `if (updated.id == state.me.id) return;` plus a debug assertion explaining that self profile updates belong to `ProfileCubit`; never corrupt `_egoNode`’s “Me” projection.

### Equality

Update `NodeDetails` equality/hash minimally:

- base includes `rScore` in addition to existing fields;
- live user equality additionally includes `myVote`, `subjectExplicitlyTrustsViewer`, and `isMutualFriend`;
- retain `isHelpOfferer` for `UserNode`;
- do not include the whole `Profile` or unrelated presence/description fields.

Apply the live-user relationship comparison to both `UserNode` and `GenealogyUserNode`.

### Tests

Add:

```text
packages/client/test/features/graph/graph_profile_projection_patch_test.dart
packages/client/test/features/graph/node_details_equality_test.dart
```

Assert:

- `myVote 0 → 1` keeps ID, size, pin, position, and edges while replacing controller node;
- incoming-trust-only change is distinguishable;
- `rScore` change is distinguishable;
- `isMutualFriend` change is distinguishable;
- `isHelpOfferer` survives;
- genealogy `nodeKey` survives;
- multiple genealogy occurrences of one account all update;
- Alice update leaves Bob identical and unreplaced;
- no fetch occurs;
- position remains unchanged through `GraphController.replaceNode`.

### Stop condition

A relationship projection can be patched by account ID without graph data loss, and equality guarantees the renderer observes the relationship change.

---

## 16. WU10 — Authoritative Trust mutation and race-safe context cubit

### Existing use case

Change `ProfileViewCase._setRelationship` to:

```text
perform LikeRemoteRepository mutation
    ↓
refetch profile through ProfileRepositoryPort.fetchById(profile.id)
    ↓
apply ContactsCase overlay
    ↓
return authoritative Profile
```

Do not synthesize reverse trust or MR after the mutation. The refetch supplies `myVote`, `subjectExplicitlyTrustsViewer`, `score`, `rScore`, and `isMutualFriend` together.

Update ProfileViewCase/Cubit tests so Trust from Profile also observes correct transitions:

- subject-only → mutual → Send;
- neither → viewer-only → Request remains unavailable.

### Context state-holder

Create Freezed state and cubit. Its constructor requires `ProfileViewCase` and the route-local `GraphCubit`; it must not inject Like, graph, forward, or block repositories directly.

State fields:

```text
Profile? selectedProfile
String? dismissedFocusId
bool trustLoading
Object? trustError
int selectionSequence
```

Required methods/semantics:

```text
selectProfile(profile, intentional)
dismiss()
trustSelected()
clearSelection()
```

- a new person ID increments sequence, replaces profile, clears dismissal/error/loading;
- intentional reselect of the same focused node clears its dismissal so the panel can reopen;
- graph-driven re-emission of the same focus does not reopen a dismissed panel;
- dismiss records current ID and leaves graph focus unchanged;
- non-person, self, empty focus, or reset clears selected panel state.

Race-safe Trust algorithm:

```text
capture Alice id + selection sequence
set loading only for Alice
await ProfileViewCase.addFriend(Alice)
always patch Alice in GraphCubit by Alice id if route is still alive
if selected id + sequence still identify Alice:
    update visible panel with authoritative Alice
    clear Alice loading/error
else:
    do not mutate Bob's visible state
```

On error, update/show the panel error only if the captured selection still matches. A late Alice error must not appear as Bob’s error.

After success, derive policy again from the authoritative profile. Never hard-code `Trust success → Send`.

### Cubit tests

Add `graph_person_context_cubit_test.dart` with controllable completers:

- successful trust patches graph and panel;
- neither→viewer-only does not enable Send;
- subject-only→mutual enables Send;
- dismiss/reselect keeps patched trust;
- switch Alice→Bob while Alice pending: Alice graph patches, Bob panel unchanged;
- late Alice error does not become Bob error;
- close during request causes no emit-after-close;
- repeated tap of current person reopens dismissed panel.

### Stop condition

Trust returns an authoritative projection, updates loaded graph nodes, recomputes visibility, and cannot race onto another selected person.

---

## 17. WU11 — Trust-graph Person Context presentation

### Provider/integration

Provide `GraphPersonContextCubit` only in `GraphScreen` (trust graph). Do not add it to forwards or genealogy routes.

`GraphBody` keeps its existing outer `Stack`; the GraphView remains the full stack size. The panel is a sibling overlay, never inside the scaled canvas and never in a modal sheet.

### Selection synchronization

Do not change `handleNodeTap()`.

On a node tap:

1. call `GraphCubit.handleNodeTap(node)` exactly as now;
2. separately notify context cubit that this was an intentional selection if `node` is a non-self `UserNode` in trust mode.

Also listen to `GraphState.focus` so:

- Previous follows restored focused person;
- Reset/empty focus closes panel;
- Beacon/non-person focus closes panel;
- self/ego closes panel;
- a different person reopens panel;
- an ordinary rebuild of a dismissed current focus stays dismissed.

Lookup the focus profile from the current loaded `UserNode`; do not refetch just to show the panel.

### Responsive layout

Add design-system tokens:

```text
graphPersonContextWidth = 320
graphPersonContextCompactMaxHeightFraction = 0.42
```

Update token constructor, light/dark values, `copyWith`, `lerp`, and window-class application. Feature UI consumes the tokens; it does not repeat numbers.

- `WindowClass.compact`: bottom non-modal card, safe-area aware, horizontally inset by `screenHPadding`, height capped by the fraction token; graph remains interactive above it.
- regular/expanded: fixed right overlay with token width and safe-area/card gaps; graph does not resize.
- wide legend: lower-left; panel: right.
- compact while panel visible: place legend upper-left so rectangles cannot overlap; restore lower-left when panel hides.

### Panel content and hierarchy

Always repeat avatar and `Profile.displayLabel(l10n.unknownPerson)`. Show directional visibility text and eye state before actions.

Exact policy rendering:

- mutual: Filled Send request; View profile; Show N more; secondary Trust only if outgoing trust absent;
- viewer-only/outgoing trust already present: Request unavailable status; Request options; View profile; Show N more; no Trust;
- subject-only: Filled Trust; Request options; View profile; Show N more;
- neither: Filled Trust; Request options; View profile; Show N more.

Actions:

- Send request / Request options → `ScreenCubit.showForwardToPerson(profile.id)` only;
- View profile → `ScreenCubit.showProfile(profile.id)`;
- Show N more → `GraphCubit.expandNode(current UserNode)`;
- Trust → `GraphPersonContextCubit.trustSelected()`;
- close → context cubit `dismiss()` only.

Show expansion only when `!graphState.isLoading && graphCubit.canPageMore(node.id)`. Use exact count from `hiddenNeighborCounts` when positive; never show an enabled generic expand when the transition is invalid.

Keep AppBar Profile/Expand actions during this work unit.

### Tests

Add panel widget tests and extend graph-body integration tests for:

- new node selection opens panel;
- visited node rollback selection opens panel without fetch;
- current-node expand tap behavior remains unchanged;
- focus change swaps avatar/name/actions immediately;
- dismiss leaves graph focus;
- different selection reopens;
- intentional same-node tap can reopen;
- Previous follows focus;
- Reset hides;
- Beacon/self/non-person hides;
- forwards and genealogy never instantiate panel;
- each visibility state renders the exact hierarchy;
- Send/Request options emit correct person ID;
- Show count calls `expandNode` and disappears when `canPageMore` false;
- 320×800 compact and 900×600 wide layouts do not overflow;
- opening panel does not change GraphView size;
- Legend and panel positions do not overlap.

### Stop condition

The panel is complete and testable, but duplicate trust AppBar Profile/Expand controls still exist pending human validation.

---

## 18. WU12 — Accessibility and pointer affordance

### Graph nodes

Wrap interactive node content with:

```text
MouseRegion(cursor: SystemMouseCursors.click)
Semantics(button: true, selected: isFocused, label: ...)
```

Human label rules:

- live user: `Profile.displayLabel(l10n.unknownPerson)`;
- Beacon: localized Request label plus visible title;
- deleted genealogy node: its anonymized human label;
- never expose opaque account IDs or node keys.

Keep `GestureDetector` tap semantics and focus ring.

### Panel traversal

Use normal Material controls in source/focus order:

```text
primary action
Request options / secondary Trust
View profile
Show N more
Close
```

Do not build spatial keyboard navigation across graph nodes. Once a node is selected through supported interaction, Tab traversal through panel controls must work.

### Tests

Use `tester.getSemantics` and keyboard events to assert:

- selected node announces selected/button/human name;
- non-selected interactive node announces button/human name;
- no opaque ID in labels;
- hover cursor is click;
- Tab order reaches primary, secondaries, close;
- forwards/genealogy/Beacon labels remain meaningful.

### Stop condition

Nodes have meaningful semantics/hover and selected-person controls are normally keyboard navigable, with no out-of-scope spatial-navigation system.

---

## 19. WU13 — Localization

Add source ARB keys in English and Russian, including metadata/placeholders. Use these exact concepts and copy; a fluent reviewer may improve Russian grammar without changing semantics.

| Key concept | English | Russian |
|---|---|---|
| People Graph | Graph | Граф |
| People More | More | Ещё |
| Blocked people | Blocked people | Заблокированные |
| Previous focus | Previous focus | Предыдущий фокус |
| Center view | Center view | Центрировать |
| Reset genealogy origin | Reset to origin | Вернуться к началу |
| Trust CTA | Trust this user | Доверять этому пользователю |
| Mutual visibility | Two-way visibility | Двусторонняя видимость |
| Viewer side | You can see {name} | Вы видите {name} |
| Missing reverse | {name} can't see you yet | {name} пока не видит вас |
| Subject side | {name} can see you | {name} видит вас |
| Missing forward | You don't currently see {name} | Сейчас вы не видите {name} |
| Neither | No two-way visibility | Нет двусторонней видимости |
| Request unavailable | Request unavailable | Запрос недоступен |
| Routing entry | Request options | Варианты отправки запроса |
| Show more | Show {count} more connections | Показать ещё связей: {count} |

Also update legend copy so the eye means mutual visibility established by Trust or MeritRank in either direction. Do not say “positive MeritRank both ways”.

Run:

```bash
cd packages/client
flutter gen-l10n
dart run build_runner build -d
bash ../../scripts/check-user-facing-terminology.sh
```

Do not hand-edit generated localization Dart.

### Stop condition

EN and RU expose the same semantics, generated localization is current, and user-facing surfaces say Request/Chat/Trust correctly.

---

## 20. WU14 — Mandatory visual-association usability gate

Keep the existing trust AppBar Profile/Expand fallbacks while testing.

Use an unbriefed participant on both compact and wide layouts. Ask them to:

1. select a graph person;
2. state which person the visible actions refer to;
3. open that person’s Profile;
4. explain the open/closed eye;
5. Trust the person;
6. state whether Trust did or did not unlock direct sending and why;
7. open request routing/options;
8. reveal more of the selected person’s graph;
9. use Previous focus and Reset to me.

Pass criteria:

- participant identifies panel subject without prompting;
- persistent focus ring and repeated avatar/name are understood as one object relation;
- participant does not describe panel as global graph chrome;
- participant does not infer one-way visibility can send;
- all Profile/Trust/request/show-more tasks are found from the panel.

Record the evidence fields from WU8 plus task-by-task pass/fail and participant wording.

If association fails, improve visual attachment within the allowed overlay design: focus-ring salience, matching avatar/name treatment, panel hierarchy, or transition. Do not add an anchored coordinate popover, modal sheet, GraphView fork, or more explanatory prose as the only fix.

**Stop condition:** human evidence passes. Otherwise issue #100 remains incomplete and WU15 must not remove AppBar fallbacks.

---

## 21. WU15 — Remove duplicate trust-person AppBar actions

Only after WU14 passes:

- remove Profile and Expand from trust-mode AppBar;
- retain Previous, Fit, Reset to me, Legend;
- retain genealogy live-user Profile/details and valid genealogy navigation;
- retain forwards-valid Profile/Beacon Open Request and camera Center;
- retain Beacon Open Request behavior;
- do not add Trust/Send panel to forwards or genealogy.

Update `graph_body_navigation_controls_test.dart` with separate mode groups that assert exact visible controls, not merely absence of overflow.

Re-run all graph tests from WU4, WU9, WU11, and WU12.

### Stop condition

Trust person actions have one home in the panel; other modes retain their distinct contextual grammar.

---

## 22. WU16 — Version, deployment compatibility, and full regression

### Version

Read the live client version first. This feature is a semver minor increment.

If still `5.8.0`:

```text
packages/client/pubspec.yaml       → 5.9.0
packages/client/web/index.html     → flutter_bootstrap.js?v=5.9.0
```

If not, increment the live minor and reset patch to zero. Verify the values are identical.

Do not raise `kDefaultMinClientVersion` solely for this feature: the database/API change is additive and old clients remain structurally compatible. Revisit only if the live implementation introduces an actual mixed-version safety requirement not present in this plan. Record the decision and current value.

### Deployment order

New clients query `trusts_viewer` and `mutually_visible_users`; deploy producers before consumers:

```text
1. PostgreSQL migration/functions
2. Hasura metadata and schema reload
3. updated server/V2 projection and server send enforcement
4. client/web 5.9.0 release
```

Do not release the new client before schema/metadata. Server enforcement may intentionally reject stale clients’ one-way direct sends; that is the corrected authorization rule, not a compatibility redirect.

### Focused regression matrix

Run every new/modified test plus:

```bash
cd packages/client
flutter test test/features/graph
flutter test test/features/profile_view
flutter test test/features/forward
flutter test test/features/friends
flutter test test/features/block
flutter test test/app/router/home_tab_branch_routing_test.dart

cd ../server
dart test --exclude-tags pg
dart test --tags pg
```

### Repository gates

From repository root:

```bash
cd packages/tentura_lints && dart test
cd ../..
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh

cd packages/force_directed_graphview && flutter test
cd ../client && flutter test
cd ../server && dart test --exclude-tags pg
```

Run the repository’s migration/Hasura validation available in the live branch. Apply metadata to a migrated local stack and execute one real GraphQL query containing:

```graphql
trusts_viewer
my_vote
is_mutual_friend
scores { src_score dst_score }
```

Then exercise `mutually_visible_users` for explicit-mutual, MR-mutual, mixed `trustIn + mrOut`, dropped mixed `trustOut + mrIn`, and one-way fixtures.

### Manual responsive QA

With real endpoint-driven data, verify:

- 320 px/narrow mobile;
- regular tablet/desktop-narrow resize;
- expanded desktop;
- panel open/closed while panning and zooming;
- Legend + panel coexistence;
- Previous/Fit/Reset after two- and three-hop exploration;
- repeated Reset;
- forwards Center preserves graph contents;
- genealogy reset/profile behavior;
- Trust transition subject-only→mutual;
- Trust transition neither→viewer-only (Send remains unavailable);
- dismiss/reselect does not revert Trust;
- browser refresh `/home/network/blocked` and fallback Back;
- `/settings/blocked` unsupported;
- ordinary keyboard Tab traversal and desktop hover.

### Acceptance rechecks

Explicitly map evidence to issues #83, #86, #95, #100, #113:

- #83: graph/profile/request routing still reaches correct nested branch;
- #86: focus navigation and graph controls work by mode;
- #95: new-node explore and visited-node rollback behavior is unchanged;
- #100: People discovery, Blocked ownership, profile hierarchy, panel, Trust, routing, show-more, accessibility;
- #113: Reset calls canonical state reset and preserves exploration memory.

### Final diff audit

```bash
git diff --check
git status --short
git diff -- packages/client/pubspec.yaml packages/client/web/index.html
rg -n "settings/blocked|BlockedUsersRoute" packages/client/lib packages/client/test
rg -n "score > 0 && rScore > 0|isMutuallyVisible" packages/client/lib packages/server/lib
rg -n "trusts_viewer|subjectExplicitlyTrustsViewer" packages/client/lib packages/server/lib hasura/metadata.json
```

Inspect every hit; do not accept a second reachability formula or direct feature caller to Blocked route.

---

## 23. Required test traceability

| Contract | Enforcement test location |
|---|---|
| Four-signal Boolean visibility | `profile_visibility_test.dart`, policy test, PostgreSQL visibility test |
| Incoming explicit trust independent | Profile mapper tests, friendship lookup test, GraphQL mapper/query tests |
| Mixed trust/MR discovery | PostgreSQL candidate-function test, forward repository test |
| One-way cannot send | policy, PersonForward cubit, server ForwardCase auth tests |
| Server rejects entire mixed batch | `forward_case_auth_test.dart` |
| Reset preserves `_everFocusedIds` | `graph_focus_path_visibility_test.dart` |
| Focus depth emitted reactively | graph cubit and AppBar navigation tests |
| Forwards never receives trust reset | mode-specific Graph AppBar test |
| Profile one-primary hierarchy | `profile_view_body_action_policy_test.dart` |
| People Graph/More/Blocked discovery | `friends_app_bar_actions_test.dart` |
| Blocked route single Network owner | `home_tab_branch_routing_test.dart` plus route search |
| BlockUserSheet semantic navigation | `block_user_sheet_test.dart` |
| Projection patch preserves metadata | `graph_profile_projection_patch_test.dart` |
| Trust race cannot update Bob | `graph_person_context_cubit_test.dart` |
| Panel state/dismiss/reselect | context cubit + panel/body widget tests |
| Show N more uses `expandNode` | panel integration test |
| Node semantics/hover/keyboard | graph-node and panel accessibility tests |
| Human panel association | WU14 evidence, required before WU15 |
| Version/cache equality | final diff plus version consistency tooling/build |

---

## 24. Definition of Done

### Ownership and graph modes

- [ ] #86 ownership rechecked and serialized before edits.
- [ ] `GraphMode` is explicit and derived once.
- [ ] Trust, forwards, and genealogy controls are tested separately.
- [ ] Focus depth is immutable/reactive.
- [ ] Previous and Fit work where specified.
- [ ] Trust Reset calls `resetToEgo()`.
- [ ] Genealogy reset uses genealogy origin semantics.
- [ ] Forwards never invokes `resetToEgo()`.
- [ ] Reset preserves `_everFocusedIds`.
- [ ] #95 explore/rollback semantics remain green.

### Canonical visibility and forwarding

- [ ] Incoming explicit trust is independently represented in database/API/server/client projections.
- [ ] Each direction is explicit Trust OR positive MeritRank.
- [ ] Live mixed is `trustIn + mrOut` only; `trustOut + mrIn` is not mutual (m0151: speed, then simplicity).
- [ ] Explicit mutual trust sends with non-positive MR.
- [ ] Mutual positive MR sends without explicit trust.
- [ ] One-way visibility never sends.
- [ ] Eye state follows mutual visibility, not MR or trust alone.
- [ ] Candidate discovery includes explicit and mixed `trustIn + mrOut` (not `trustOut + mrIn`).
- [ ] PersonForwardScreen uses corrected canonical getter.
- [ ] Server mutation authorizes all recipients before any insertion.
- [ ] A mixed valid/invalid batch inserts none.
- [ ] Trust refetches authoritative Profile and recomputes both directions.
- [ ] Trust does not automatically enable Send when reverse visibility is absent.

### People and Blocked ownership

- [ ] Graph, Create invitation, and More are directly available from People.
- [ ] QR scan and Blocked people are in More.
- [ ] `BlockedUsersRoute` exists only under Network.
- [ ] canonical `/home/network/blocked` works on navigation and refresh.
- [ ] Back returns to People, including cold-refresh fallback.
- [ ] `/settings/blocked` is unregistered with no redirect/alias.
- [ ] Settings contains no Blocked People action.
- [ ] BlockUserSheet and all feature callers use `showBlockedUsers()`.
- [ ] one Blocked Users screen implementation remains.

### Profile and Person Context

- [ ] Pure policy models explicit trust and directional visibility separately.
- [ ] Profile renders zero or one Filled primary CTA per policy.
- [ ] non-mutual routing is labelled Request options, not enabled direct Send.
- [ ] trust graph alone provides Person Context.
- [ ] compact bottom card and wide right overlay do not resize graph.
- [ ] focus ring plus avatar/name clearly attach panel to person.
- [ ] dismiss/reselect/Previous/Reset behavior matches contract.
- [ ] Send/Request options reuse `PersonForwardScreen` only.
- [ ] Show N more uses `expandNode` and hides when invalid.
- [ ] Trust uses existing `ProfileViewCase` mutation path.
- [ ] successful Trust patches all loaded matching live-user nodes.
- [ ] node equality observes relationship-relevant changes.
- [ ] dismiss/reselect cannot revert Trust UI.
- [ ] stale Trust cannot update the wrong panel.
- [ ] no full graph refetch occurs after Trust.
- [ ] AppBar person actions are removed only after WU14 human evidence passes.
- [ ] forwards/genealogy/Beacon contextual behavior is preserved.

### Accessibility, localization, release

- [ ] graph nodes expose human Semantics, selected state, and pointer hover.
- [ ] panel controls follow normal keyboard order.
- [ ] no whole-graph spatial keyboard system was added.
- [ ] EN and RU source ARBs are updated and generated l10n is current.
- [ ] graph legend explains Trust-or-MR mutual visibility.
- [ ] targeted, full client/server, custom lint, terminology, and graph-package tests pass.
- [ ] narrow, regular, expanded, Legend+panel, forwards, and genealogy manual QA passes.
- [ ] issues #83/#86/#95/#100/#113 acceptance is rechecked.
- [ ] client semver receives a minor bump.
- [ ] `flutter_bootstrap.js?v=` exactly matches client version.
- [ ] deployment follows migration → metadata → server → client order.

---

## 25. Out of scope

Do not add any of the following while executing this plan:

- sixth global destination;
- generic direct messaging;
- GraphView fork or private transform access;
- node-coordinate popover;
- modal Person Context sheet;
- draggable layout;
- new forwarding/reachability algorithm outside the canonical visibility functions;
- MeritRank controls;
- genealogy Trust/Send surface;
- forwards Person Context;
- complete graph spatial keyboard navigation;
- graph-wide refetch after Trust;
- new Blocked Users screen;
- `/settings/blocked` compatibility;
- router-wide Network/Friends rename;
- repository-wide friend→trust identifier migration;
- broad new realtime architecture solely for relationship projection.

If a later requirement needs one of these, create a separate issue/plan rather than expanding #100 silently.
