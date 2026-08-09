# Issue #100 implementation journal

## Scope and baseline

- **Objective:** execute `issue-100-people-graph-person-context-implementation-plan.md` end to end.
- **Repository / branch / starting HEAD:** `/home/vader/MY_SRC/tentura`, `main`, `c094c40a9ae317c9c3ea1b45de1c1de38fc933ee`.
- **Plan source:** `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`.
- **Workflow:** sequential fresh `cursor-agent` workers, pinned to non-fast `composer-2.5`; no resume, push, reset, stash, generated-file edits, or unrelated staging.

## Preserved pre-existing worktree changes

Modified:

- `docs/README.md`
- `docs/archive/journals/commitment-truth-rework-journal.md`
- `docs/archive/plans/commitment-truth-rework-plan.md`
- `docs/audits/room-coordination-audit.md`
- `docs/plans/room-composer-clipboard-paste-implementation-journal.md`
- `packages/server/lib/data/database/table/beacon_commitment_events.dart`
- `packages/server/lib/env.dart`

Untracked:

- `dart-defines`
- `docs/plans/graph-navigation-implementation-guide.md`
- `docs/plans/graph-navigation-rework-plan.md`
- `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`
- `docs/plans/received-reviews-trust-changes-plan.md`
- `docs/plans/room-composer-clipboard-paste-plan.md`
- `graph-ego-neighbors-layout-issue.md`
- `key.fb`
- `out.key`
- `product_testing_compact_buglist.md`
- `product_testing_detailed_report.md`

## Ordered manifest

1. **WU0** — preflight and characterization — **complete** (2026-08-08).
2. **WU1** — database, Hasura, and V2 visibility boundary — **complete** (2026-08-08).
3. **WU2** — client profile projection and canonical getters — **complete** (2026-08-08).
4. **WU3** — server enforcement and candidate discovery — **complete** (2026-08-08).
5. **WU4** — graph modes and reactive navigation — **complete** (2026-08-08).
6. **WU5** — People entry points — **complete** (2026-08-08).
7. **WU6** — Blocked People route ownership — **complete** (2026-08-08).
8. **WU7** — policy and Profile hierarchy — **complete** (2026-08-08).
9. **WU8** — mandatory first human usability check — **complete** (2026-08-09, user-confirmed).
10. **WU9** — graph profile projection patch and equality — **complete** (2026-08-09).
11. **WU10** — authoritative Trust and context cubit — **complete** (2026-08-09).
12. **WU11** — Person Context presentation — **complete** (2026-08-09).
13. **WU12** — accessibility and pointer affordance — **complete** (2026-08-09).
14. **WU13** — localization — **complete** (2026-08-09).
15. **WU14** — mandatory visual-association human gate — **complete** (2026-08-09, user-confirmed).
16. **WU15** — conditional AppBar cleanup after WU14 pass — **complete** (2026-08-09).
17. **WU16** — version, compatibility, and full regression — **partial** (2026-08-09).

## Preflight evidence

### #86 ownership (re-run 2026-08-08)

```bash
git worktree list --porcelain
# ~/MY_SRC/tentura c094c40a [main]

git merge-base --is-ancestor 22f9d35d HEAD
# exit 0

gh issue view 86 --json state
# {"state":"CLOSED"}

gh pr list --state open --search '86 in:title,body'
# No Pull Requests
```

- One worktree; `22f9d35d` is an ancestor of `HEAD` (`c094c40a`); issue #86 closed; no open PR owns graph navigation.
- **Stop condition not triggered:** safe to proceed to WU1 when authorized.

### Live worktree snapshot (2026-08-08)

`git status --short` matches the preserved list above; no new modified or untracked paths beyond the journal itself after WU0.

### Version / cache / migration / metadata (2026-08-08)

| Item | Live value |
|---|---|
| Client `pubspec.yaml` version | `5.8.0` |
| `web/index.html` bootstrap cache key | `flutter_bootstrap.js?v=5.8.0` |
| Server `kDefaultMinClientVersion` (`env.dart`) | `5.6.38` (pre-existing local modification; unchanged by WU0) |
| Next migration part | **`m0140`** — `_migrations.dart` ordered list ends at `m0139`; no `m0140` part exists yet |
| Hasura `trusts_viewer` | absent (`rg` on `hasura/metadata.json`: no matches) |
| Hasura `mutually_visible_users` | absent |

## WU0 — characterization test results (2026-08-08)

All baseline tests **passed**. No pre-existing failures observed.

### Client (`packages/client`)

```bash
flutter test test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_body_select_expand_test.dart \
  test/features/graph/forward_graph_focus_rules_test.dart \
  test/app/router/home_tab_branch_routing_test.dart \
  test/features/block/ui/sheet/block_user_sheet_test.dart \
  test/ui/widget/contact_badge_legend_test.dart
```

**Outcome:** `00:03 +110: All tests passed!` (exit 0)

Per-file counts: `graph_focus_path_visibility_test.dart` 37; `graph_body_navigation_controls_test.dart` 6; `graph_cubit_genealogy_test.dart` 16; `graph_body_genealogy_test.dart` 3; `graph_body_select_expand_test.dart` 4; `forward_graph_focus_rules_test.dart` 7; `home_tab_branch_routing_test.dart` 20; `block_user_sheet_test.dart` 13; `contact_badge_legend_test.dart` 4.

### Server (`packages/server`)

```bash
dart test --exclude-tags pg test/domain/use_case/forward_case_test.dart \
  test/domain/use_case/forward_case_auth_test.dart
```

**Outcome:** `00:00 +30: All tests passed!` (exit 0)

## Existing test traceability (WU0 characterization map)

| Contract | Primary test file(s) | Representative test name(s) |
|---|---|---|
| Reset preserves `_everFocusedIds` | `graph_focus_path_visibility_test.dart` | `resetToEgo keeps everFocused so rollback taps do not refetch` |
| New-node explore vs visited-node rollback | `graph_focus_path_visibility_test.dart`, `graph_body_select_expand_test.dart` | `rollback tap on ancestor with hidden badge does not fetch`; `tap sequence A→B→E→back-to-B spotlights the ego→focus path and backtracking refetches nothing`; `tap on unexpanded node expands once`; `tap on already expanded node selects without fetching` |
| Cached path reconstruction | `graph_focus_path_visibility_test.dart` | `teleport select rebuilds focus path through cached edges after resetToEgo`; `adjacent hop appends to focus path even when a shorter chord exists` |
| Genealogy focus behavior | `graph_cubit_genealogy_test.dart`, `graph_body_genealogy_test.dart` | `genealogy parent-chain nodes pin on first exploration tap and remain visible`; `genealogy exploration hides sibling branches while keeping the parent chain`; `genealogy tap on parent chain after sibling spotlight selects only`; `genealogy mode ignores context and positive-only controls`; widget: `GraphBody wires withRating for GenealogyUserNode` |

**Decision:** do not duplicate these tests in WU0; extend them in later work units only when asserted state must change (per plan §6).

## Verification matrix

- Per-unit commands and all plan-final client/server/custom-lint/terminology/graph-package checks from WU16.
- PostgreSQL evidence remains required for WU1 and final verification; SQLite-only results cannot accept the visibility SQL.

## Unresolved gates and decisions

- WU8 and WU14 require an unbriefed human participant. Automated tests cannot substitute; WU15 cannot begin unless WU14 evidence passes.
- Preserve all listed pre-existing changes and never stage or commit them.
- WU0 made **no production or generated file changes**.

---

## WU0 final entry — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor agent (composer-2.5), WU0 only.

**Actions performed:**

1. Re-ran §3.1 #86 ownership commands — all green.
2. Re-captured `git status --short`, version/cache/migration/metadata snapshot.
3. Confirmed next migration is `m0140` (`m0139` is last registered part).
4. Ran all 11 client + 2 server characterization test files from plan §6 — all passed.
5. Mapped existing tests to reset/rollback/cached-path/genealogy contracts (table above).
6. Verified no production or generated files were edited.

**Commits:** see below (journal only).

**Findings:**

- Baseline is clean: 140 characterization tests (110 client + 30 server), zero failures.
- `env.dart` remains locally modified (pre-existing); `kDefaultMinClientVersion` read as `5.6.38` but not touched.
- Hasura metadata has no `trusts_viewer` or `mutually_visible_users` yet — expected pre-WU1 state.
- `graph_body_navigation_controls_test.dart` still expects `home recenters without clearing focus trail` (camera-only reset); plan WU4 will replace this when trust Reset calls `resetToEgo()`.

**Remaining:** WU1 — canonical visibility at database and API boundary.

---

## Manager review — WU0 accepted (2026-08-08)

- Inspected `967152cd` and confirmed it contains only the journal.
- Re-ran the complete characterization matrix independently: 110 client and 30 server tests passed.
- `git show --check 967152cd` and the live worktree diff check passed.
- **Verdict:** accepted. WU1 may begin; all preserved unrelated changes remain unstaged.

---

## WU1 recovery boundary — 2026-08-08

- The first fresh WU1 worker was interrupted before committing after it used an unsafe cleanup command (`git checkout --`) while trying to undo broad formatter output. It also left WU1 source/test changes uncommitted.
- The two paths that had been listed as pre-existing dirty work, `packages/server/lib/env.dart` and `packages/server/lib/data/database/table/beacon_commitment_events.dart`, are now clean. The user has explicitly confirmed that they were not user work and directed execution to continue; no restoration is required.
- Preserve all remaining uncommitted WU1 paths. A fresh recovery worker must audit, complete, test, and split them into focused commits. It must never use reset, checkout, restore, clean, stash, or any mass-reversion command.

## Manager review — WU1 accepted (2026-08-08)

- Reviewed `17635581`, `637d3375`, and `9c8abb87`; diff checks are clean and scope matches WU1.
- Independently ran `dart test --tags pg test/data/database/person_visibility_migration_pg_test.dart`: all 7 live PostgreSQL proofs passed.
- **Verdict:** accepted. WU2 may begin.

---

## WU1 — canonical visibility boundary — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor recovery worker (composer-2.5), WU1 only.

**Commits:**

| Hash | Subject |
|---|---|
| `17635581` | feat(server): add m0140 canonical person visibility SQL and Hasura fields |
| `637d3375` | feat(server): project trusts_viewer through V2 public-user resolvers |

**Actions performed:**

1. Audited and preserved interrupted WU1 partial changes; repaired PG test SQL (`$1` not `\$1` in raw strings), truth-table all-absent row handling, and `mr_edge_in`/`mr_node_score` supplement in m0140 for one-way MeritRank edges missing from `mr_mutual_scores(viewer)`.
2. Registered `m0140` in `_migrations.dart`; applied migrations locally via `dart run bin/utils/run_migrations_once.dart` and manually re-applied updated `person_visibility_peers` on the already-migrated dev DB.
3. Hasura metadata: `trusts_viewer` computed field + `mutually_visible_users` query function; `./scripts/hasura_apply_metadata.sh` → `is_consistent: true`.
4. V2 projection: `gqlTypeUserPublic.trusts_viewer`, `UserPublicRecord.subjectExplicitlyTrustsViewer`, directional `VoteUserFriendshipLookupPort.directionalPositiveTrustPeerIds`, viewer-aware resolvers (coordination, mutual friends, invite genealogy, invitation issuer, blocked users default false).
5. Fixed stub override in `evaluation_graph_test_repos.dart` and removed WU1-unused import in `coordination_repository.dart`.

**Tests (commands and outcomes):**

```bash
cd packages/server
dart test --exclude-tags pg \
  test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart \
  test/api/controllers/graphql/user_block_graphql_test.dart \
  test/api/controllers/graphql/query_invite_genealogy_test.dart \
  test/api/controllers/websocket/presence_watch_gate_test.dart
# 00:00 +21: All tests passed!

dart test test/data/repository/vote_user_friendship_lookup_test.dart
# 00:00 +4: All tests passed!

dart test --tags pg test/data/database/person_visibility_migration_pg_test.dart
# 00:39 +7: All tests passed!
```

PG truth table covers all 10 plan rows (all-absent via missing peer row + `person_is_mutually_visible` false), `user_get_trusts_viewer` trust-only semantics, `mutually_visible_users` explicit/MR/mixed mutual cases, blocked/self exclusion, blank viewer, and null/empty context normalization.

**Findings:**

- `mr_mutual_scores(viewer)` alone does not surface peer→viewer-only MeritRank edges; m0140 unions `mr_edgelist` peer discovery with `greatest(mr_mutual_scores, mr_node_score)` directional scores.
- Re-running `migrateDbSchema` does not replace an already-applied m0140 body on existing dev DBs; fresh installs get the final SQL from git.
- Blocked-user GraphQL responses rely on default `trusts_viewer: false` (no incoming-trust query).

**Remaining:** WU2 — client profile projection and canonical getters.

---

## WU2 — client profile projection and canonical getters — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor recovery worker (composer-2.5), WU2 only. No process/port/Docker management.

**Commits:**

| Hash | Subject |
|---|---|
| `add0bdc2` | feat(client): canonical Profile visibility and trusts_viewer projection |
| `0b8f9abc` | test(client): exhaustive Profile visibility getter coverage |

**Actions performed:**

1. Preserved interrupted WU2 partial edits; verified live `schema.graphql` (schema-fetcher result) already exposes `trusts_viewer` and `mutually_visible_users` — no schema re-fetch or service restart required.
2. Added `subjectExplicitlyTrustsViewer` to `Profile` with canonical getters from plan §4.2; corrected `isMutuallyVisible` and `isSeeingMe` semantics.
3. Added `trusts_viewer` to `user_model`, `user_public_model`, `help_offers_with_coordination`, and `mutual_friends_fetch` fragments; mapped in `UserModel`, `UserPublicModel`, coordination, and mutual-friends repositories.
4. Updated `ProfileViewBody` and `NetworkPersonCard` one-way-in labels to use `subjectExplicitlyTrustsViewer` (not `isSeeingMe`).
5. Updated EN legend copy (`graphLegendEyeOpen`, `graphLegendForwardEligible`) for Trust-or-MeritRank two-way visibility; ran `flutter gen-l10n`.
6. Ran `dart run build_runner build -d` and formatted WU2-owned paths (generated outputs gitignored per client `.gitignore`).
7. Collateral fix: `block_repository.dart` nullable list handling after schema refresh (analyzer errors blocked custom-lint gate).

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter test test/domain/entity/profile_visibility_test.dart \
  test/ui/widget/contact_badge_legend_test.dart \
  test/features/beacon/data/additive_graphql_contract_test.dart
# 00:00 +31: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 tentura_lints vs baseline 111)
```

`profile_visibility_test.dart`: all 16 T→/MR→/T←/MR← combinations; zero/negative score boundaries; explicit-mutual, MR-mutual, mixed cases; one-way eye closed; `isMutualFriend` strict; `isSeeingMe` reverse-MR-only; `isFriend` alias.

**Findings:**

- Prior worker interrupted after schema fetch; uncommitted `schema.graphql` was valid — no `docker compose run schema_fetcher` rerun needed.
- `build_runner` regenerated gitignored Ferry/Freezed/l10n Dart; committed sources only.
- Schema refresh made `myBlocks` / `blockInherited` nullable in generated Ferry types; minimal null-safe mapping fix required outside WU2 path list.
- `app_ru.arb` legend strings not updated (WU13 localization scope).

**Remaining:** WU3 — server enforcement and candidate discovery.

---

## WU2 manager acceptance — 2026-08-08

**Verdict:** accepted.

Manager review confirmed that the tracked schema contains both required fields,
all four required fragments and their mappers propagate `trusts_viewer`, and
the `Profile` directional getters preserve the plan's alias semantics. The
schema-refresh nullability adjustment in `BlockRepository` is scoped and
null-safe. `git diff --check 80b0e1a2..92c91fcb` was clean.

Independent verification:

```bash
cd packages/client
flutter test test/domain/entity/profile_visibility_test.dart \
  test/ui/widget/contact_badge_legend_test.dart \
  test/features/beacon/data/additive_graphql_contract_test.dart
# 00:00 +31: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK
```

**Accepted commits:** `add0bdc2`, `0b8f9abc`, `92c91fcb`.

**Next:** WU3.

---

## WU3 — server enforcement and candidate discovery — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor worker (composer-2.5), WU3 only. No process/port/Docker management.

**Commits:**

| Hash | Subject |
|---|---|
| `f425a53f` | feat(server): enforce mutual visibility in ForwardCase via person_visibility_peers |
| `6f005c0f` | feat(client): discover forward candidates via mutually_visible_users |
| `b63b6af0` | docs: record WU3 mutual visibility enforcement evidence for issue #100 |

**Actions performed:**

1. Added `PersonVisibilityRepositoryPort.mutuallyVisiblePeerIds` and `PersonVisibilityRepository` querying `person_visibility_peers(viewerId, context)` once with `is_mutually_visible` + peer filter (no Dart formula).
2. Injected port into server `ForwardCase`; added `final visibilityContext = context ?? ''` once; mutual-visibility check after block filtering and parent-edge resolution, before `createBatch`; rejects entire batch with exact `Direct request routing requires mutual visibility`.
3. Switched `forward_candidates_fetch.graphql` to `mutually_visible_users(args: {context: $context}) { ...UserModel }`; updated `ForwardRepository.fetchForwardCandidates` mapping (no second client formula).
4. Extended `forward_case_mocks.dart` / regenerated mocks; added mandatory server auth tests and client PersonForward / candidate-discovery tests.

**Tests (commands and outcomes):**

```bash
cd packages/server
dart run build_runner build -d
dart test --exclude-tags pg test/domain/use_case/forward_case_auth_test.dart test/domain/use_case/forward_case_test.dart
# 00:00 +41: All tests passed!

cd ../client
dart run build_runner build -d
flutter test test/features/forward/person_forward_case_test.dart test/features/forward/person_forward_cubit_test.dart
# 00:00 +14: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
# both OK
```

**Findings:**

- `PersonForwardCase.send` remains a thin repository delegate; cubit/UI `Profile.isMutuallyVisible` guards are defense-in-depth (server is final boundary).
- `websocket_realtime_protocol_test.mocks.dart` regenerated collaterally from server `build_runner`; left unstaged (unrelated).

**Remaining:** WU4 — explicit graph modes and reactive navigation.

---

## Manager review — WU3 accepted (2026-08-08)

- Reviewed `f425a53f`, `6f005c0f`, and `b63b6af0`; the server depends on the new narrow domain port and calls the canonical `person_visibility_peers` projection once, while the client maps only `mutually_visible_users` output.
- Confirmed `ForwardCase.forward()` preserves nullable stored context, normalizes only the visibility lookup context, checks after block hiding and before `createBatch`, and atomically rejects a mixed remaining batch before edge, inbox, attribution, capability, or attention effects.
- Independently ran `dart test --exclude-tags pg test/domain/use_case/forward_case_auth_test.dart` (12 passed), `dart test --exclude-tags pg test/domain/use_case/forward_case_test.dart` (29 passed), `flutter test test/features/forward/person_forward_case_test.dart` (7 passed), and `flutter test test/features/forward/person_forward_cubit_test.dart` (7 passed).
- Independently ran `./scripts/check-custom-lints.sh packages/server` (OK) and `./scripts/check-custom-lints.sh packages/client` (OK; 106 versus baseline 111). `git diff --check 7a6c85fa..b63b6af0` passed.
- **Verdict:** accepted. WU4 may begin; all unrelated working-tree entries remain unstaged and untouched.

---

## WU4 — explicit graph modes and reactive navigation — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor worker (composer-2.5), WU4 only. No process/port/Docker management.

**Commits:**

| Hash | Subject |
|---|---|
| `ab6c6ff9` | feat(client): explicit GraphMode and reactive graph navigation |

**Actions performed:**

1. Added `GraphMode` enum (`trust` / `forwards` / `genealogy`); `GraphCubit.mode` derived once in constructor initializer list from existing flags with preserved mutual-exclusion asserts.
2. Added `@Default(1) int focusPathDepth` to `GraphState`; every focus-path mutation (`selectNode`, `popFocus`, `resetToEgo`, `setContext`, block reset, genealogy bootstrap) mutates `_focusPathIds` then emits `focus` + `focusPathDepth` together (fixed `selectNode` ordering).
3. `resetToEgo` preserves `_everFocusedIds`; only `setContext` and genealogy block reset clear session exploration memory.
4. Rebuilt `GraphAppBarActions` by mode: trust/genealogy Previous (depth > 1), Fit (when layout ready), Reset (`resetToEgo` with genealogy-origin copy); forwards Center view (`jumpToEgo` camera-only); legend all modes; retained trust Profile/Expand context actions.
5. `GraphBody` legend/layout gating uses `cubit.mode`; added `graphCenterView` / `graphResetGenealogyOrigin` l10n keys and `TestIds.graphFit` / `TestIds.graphCenterView`.
6. Extended focused graph tests per plan §10 (trust depth/navigation, genealogy cubit/body, forwards center-view stub).

**Tests (commands and outcomes):**

```bash
cd packages/client
dart run build_runner build -d
flutter gen-l10n
flutter test test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_body_select_expand_test.dart
# 00:02 +73: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Findings:**

- AppBar shows Fit once `graphController.canLayout` is true (not hidden at depth 1); compact layout test updated accordingly.
- Genealogy `popFocus` at origin clears `focus` to `''` (same empty-focus convention as trust overview), while `focusPathDepth` returns to 1.
- Accidental `dart format` on unrelated graph layout/repo test files was reverted before commit.

**Remaining:** WU5 — People entry points.

---

## WU4 remediation — AppBar control availability — 2026-08-08

**Status:** remediation complete (pending manager re-review of `ab6c6ff9` / `7dd1ca29` plus this fix)

**Worker:** fresh Cursor remediation worker (composer-2.5), WU4 nonconformance only.

**Manager finding:** `GraphAppBarActions` omitted Previous at `focusPathDepth == 1` and Fit until controller layout was ready. Plan §10 requires both controls remain visible but disabled when unavailable.

**Commits:**

| Hash | Subject |
|---|---|
| `6ba751fc` | fix(client): keep graph Previous and Fit visible when disabled |

**Actions performed:**

1. Trust/genealogy: always render Previous (`TestIds.graphBack`) and Fit (`TestIds.graphFit`); set `onPressed: null` when `focusPathDepth <= 1` or `!canLayout` respectively.
2. Preserved forwards Center-only navigation (disabled until layout); no forwards Previous/Fit/Reset; legend always available; trust Profile/Expand unchanged.
3. Strengthened `graph_body_navigation_controls_test.dart` to assert visible + disabled Previous at depth 1, enabled Previous after exploration, and disabled Previous again after Reset.

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter test test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_body_select_expand_test.dart
# 00:02 +73: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Findings:**

- Forwards mode still omits Previous/Fit/Reset (by design); `graph_body_select_expand_test.dart` unchanged.
- Fit is visible and enabled after `_settleGraph` in widget harness; disabled-until-layout contract is enforced via `onPressed: null` when `!canLayout`.

**Remaining:** manager acceptance of WU4 (`ab6c6ff9`, `7dd1ca29`, `6ba751fc`); then WU5 — People entry points.

---

## Manager review — WU4 accepted (2026-08-08)

- Reviewed `ab6c6ff9` and `6ba751fc`: the `GraphMode` derivation is immutable, focus-path mutations emit the depth with focus, Reset preserves exploration memory, and forwards Center is camera-only.
- Required availability remediation is present: trust/genealogy Previous and Fit always render with `onPressed: null` at depth 1 / before layout, while forwards deliberately has only Center.
- Independently ran each required focused WU4 test: 37, 8, 19, 4, and 5 tests passed respectively. `./scripts/check-custom-lints.sh packages/client`, `git diff --check 95f61064..HEAD`, and `git show --check` for implementation/remediation commits all passed.
- **Verdict:** accepted. WU5 may begin; recorded unrelated worktree paths remain unstaged.

---

## WU5 — People entry points — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor recovery worker (composer-2.5), WU5 only. No process/port/Docker management.

**Commits:**

| Hash | Subject |
|---|---|
| `96a6b448` | feat(client): People top-bar Graph, invitation, and More actions |

**Actions performed:**

1. Added `FriendsAppBarActions` with injected callbacks: Graph, Create invitation, and More (Scan invite code, Blocked people) per plan §11 compact grammar on all widths.
2. Wired `FriendsScreen` Graph via `ProfileCubit` account id → `ScreenCubit.showGraphFor`; preserved existing invitation and `ConnectBottomSheet` scan flows.
3. Added `navigateToBlockedPeopleFromFriends` semantic hook (commented `showBlockedUsers()` call site for WU6); More → Blocked invokes the injected callback through that hook — action is visible, not silently dropped.
4. Added l10n keys (`friendsPeopleGraph`, `friendsPeopleMore`, `friendsBlockedPeople`) and `TestIds` for graph/create/more.
5. Restored accidental `friend_remove_dialog.dart` formatting-only diff from interrupted prior worker (no behavioral change).

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter gen-l10n
flutter test test/features/friends/friends_app_bar_actions_test.dart
# 00:01 +4: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Findings:**

- Widget tests cover 320 px overflow, More menu order (Scan then Blocked), per-action callbacks, and one `FriendsScreen` integration asserting Graph → `NavigatePush('$kPathGraph/$accountId')` via `ProfileCubit` + `ScreenCubit`.
- Version bump deferred to WU16 per plan §22 (live client still `5.8.0`).

**Remaining:** WU6 — Blocked People route ownership.

---

## Manager review — WU5 accepted (2026-08-08)

- Reviewed `96a6b448`: the extracted action group preserves the required compact order (Graph, Create invitation, More), with More ordered Scan invitation QR then Blocked people. Its callback seam keeps Blocked visible for WU6 routing while no WU6 route API exists yet.
- Confirmed `FriendsScreen` obtains the current `ProfileCubit` account id and calls `ScreenCubit.showGraphFor(id)`; invitation creation and `ConnectBottomSheet.show` remain reachable.
- Repaired and committed test-only GetIt isolation in `1748556d`: teardown now unregisters only dependencies registered by this test.
- Independently ran `flutter test test/features/friends/friends_app_bar_actions_test.dart` (4 passed), `./scripts/check-custom-lints.sh packages/client` (OK; 106 vs baseline 111), `git show --check` for `96a6b448`, `e31b11ae`, and `1748556d`, and `git diff --check 9c9fc9dd..HEAD` (clean).
- **Verdict:** accepted. WU6 may begin; unrelated working-tree entries remain unstaged and untouched.

---

## WU6 — Blocked People route ownership — 2026-08-08

**Status:** complete

**Commits:**

| Hash | Subject |
|---|---|
| `76ae90c4` | feat(client): move Blocked people under Network tab routing |

**Root cause (remediation):** `RootRouter.openBlockedUsers` awaited `branch.push(const BlockedUsersRoute())`; AutoRoute push futures resolve on route pop, so router/widget tests hung after normalization.

**Fix:** await Network branch `replaceAll([FriendsRoute()])`, then `unawaited(branch.push(const BlockedUsersRoute()))`; fall through to cold `HomeRoute → NetworkTabShell → FriendsRoute → BlockedUsersRoute` when tabs are mounted but the Network branch router is absent.

**Actions performed:**

1. Canonical path `kPathBlockedUsers = '/home/network/blocked'`; `BlockedUsersRoute` registered once under Network tab shell; removed Settings child route.
2. `NavigateBlockedUsers` → `dispatchUiEffect` → `RootRouter.openBlockedUsers()`; `ScreenCubit.showBlockedUsers()` for feature callers.
3. `BlockedUsersScreen` leading: `AutoLeadingWithFallback(fallbackPath: kPathNetwork)`.
4. Friends More and block-sheet snackbar use `showBlockedUsers()`; Settings tile removed.
5. Router tests: WU6 group (8 cases); block sheet asserts `NavigateBlockedUsers`; Settings absence test via `MaterialApp.router` + `RootRouter`.

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter test test/app/router/home_tab_branch_routing_test.dart --name "WU6"
# 00:00 +8: All tests passed!

flutter test test/features/block/ui/sheet/block_user_sheet_test.dart
# 00:01 +9: All tests passed!

flutter test test/features/block/ui/screen/blocked_users_screen_test.dart
# 00:00 +2: All tests passed!

flutter test test/features/settings/settings_screen_blocked_absence_test.dart
# 00:00 +1: All tests passed!

dart run build_runner build -d
# Built with build_runner/aot; wrote 403 outputs (no tracked drift)

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK

bash scripts/check-user-facing-terminology.sh
# ok
```

**Findings:**

- Test harness fixes only: conditional router tearDown for route-table unit test; AppBar-scoped back tap for cold-refresh fallback; unknown `/settings/blocked` lands on default tab `kPathMyWork` after wildcard redirect.
- Version bump deferred to WU16 per plan §22 (live client still `5.8.0`).

**Remaining:** WU7 — policy and Profile hierarchy.

---

## WU7 — pure person policy and Profile hierarchy — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor worker (composer-2.5), WU7 only. No process/port/Docker management.

**Commits:**

| Hash | Subject |
|---|---|
| `20ff6cdc` | feat(client): add pure PersonActionPolicy for profile actions |
| `3b0aa79a` | feat(client): refactor ProfileViewBody with PersonActionPolicy hierarchy |
| `1433a3ab` | test(client): ProfileViewBody action policy widget coverage |

**Actions performed:**

1. Added `PersonActionPolicy` in `lib/ui/model/person_action_policy.dart` with `PersonPrimaryAction` / `PersonVisibilityState` enums; pure `from(Profile, isSelf, isBlocked)` exposing all plan §4.3 fields.
2. Policy matrix: self/blocked suppress actions; mutual → Send primary + secondary Trust when outgoing explicit trust absent; non-mutual without outgoing explicit trust → Trust primary + Request options; non-mutual with outgoing explicit trust → no Filled CTA + Request unavailable + Request options.
3. Refactored `ProfileViewBody` hierarchy (avatar → description/presence → trust relation → directional visibility + eye → primary CTA → secondary actions → capabilities/graph/genealogy/history/mutual); helpers private to `profile_view_body.dart`.
4. Added EN/RU l10n keys (`trustThisUser`, visibility lines, `profileRequestUnavailable`, `profileRequestOptions`); ran `flutter gen-l10n` (generated output gitignored).
5. Blocked fallback unchanged (unblock-only); extended blocked widget test to assert no Trust/Send/Request options.

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter gen-l10n
flutter test test/ui/model/person_action_policy_test.dart \
  test/features/profile_view/profile_view_body_action_policy_test.dart \
  test/features/profile_view/profile_view_blocked_profile_test.dart
# 00:01 +38: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)

bash scripts/check-user-facing-terminology.sh
# ok
```

Policy tests cover all 16 T/MR combinations plus self/blocked, transition regressions (subject-only→mutual, neither→viewer-only, viewer-only no misleading Trust, mutual MR + secondary Trust), and reachability-not-implying-explicit-trust.

**Findings:**

- `addToMyField` l10n retained for legacy surfaces; #100 profile CTAs use new `trustThisUser` key per plan (full WU13 localization deferred).
- `ProfileViewCubit.addFriend()` unchanged; WU10 will make the use case authoritative.
- Version bump deferred to WU16 per plan §22 (live client still `5.8.0`).

**Remaining:** WU8 — mandatory first human usability check (human gate).

---

## Manager review — WU6 accepted (2026-08-08)

- Reviewed `76ae90c4`: `BlockedUsersRoute` has exactly one Network-child registration at `blocked`; it is absent from Settings and not included through `browseDetailChildren()`.
- Verified `openBlockedUsers()` awaits Network normalization but deliberately does not await the pushed route, avoiding the AutoRoute pop-future deadlock; a missing mounted Network branch uses the specified cold `HomeRoute → NetworkTabShell → FriendsRoute → BlockedUsersRoute` construction.
- Confirmed callers emit only `ScreenCubit.showBlockedUsers()` / `NavigateBlockedUsers`, and the dispatcher invokes the public `RootRouter.openBlockedUsers()` boundary; the cold leading fallback goes to `kPathNetwork`.
- Independently ran all focused suites: router WU6 group (8), block sheet (9), blocked screen (2), and Settings absence (1) — all passed. `./scripts/check-custom-lints.sh packages/client`, terminology, `git show --check`, and `git diff --check 2d8bb3e7..HEAD` passed; no generated files were committed.
- **Verdict:** accepted. WU7 may begin; preserved unrelated worktree paths remain unstaged and untouched.

---

## Manager review — WU7 accepted (2026-08-08)

- Reviewed `20ff6cdc`, `3b0aa79a`, and `1433a3ab`: the pure UI policy preserves independent explicit-trust and directional-visibility facts, covers all 16 mechanism combinations plus self/blocked, and makes direct Send conditional on mutual visibility only.
- Confirmed ProfileView renders the required hierarchy, offers at most one normal Filled CTA, routes both Send and Request options through `showForwardToPerson`, and leaves the blocked fallback unblock-only.
- Independently ran the policy, Profile hierarchy, and blocked-profile suites: 38 tests passed. `git show --check` for all WU7 commits and `git diff --check e2d8ed41..HEAD` passed; no generated files were committed.
- **Verdict:** accepted. WU8 is now the mandatory unbriefed-human usability gate; no automated worker may substitute for it.

---

## Overseer re-entry — 2026-08-09

- **Manager / source:** Codex `cursor-plan-overseer`, re-entered at `569071bab611bd7191b6063945a6c925e22485b5` on `main`.
- **Live reconciliation:** commits from WU0 through WU7 are ancestors of HEAD; the prior journal records manager acceptance for each. The plan's top-level statement that implementation has not started is stale.
- **Current preserved worktree:**
  - Modified: `docs/README.md`, `docs/archive/journals/commitment-truth-rework-journal.md`, `docs/archive/plans/commitment-truth-rework-plan.md`, `docs/audits/room-coordination-audit.md`, `docs/plans/room-composer-clipboard-paste-implementation-journal.md`, `packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart`.
  - Untracked: `dart-defines`, `docs/plans/graph-navigation-implementation-guide.md`, `docs/plans/graph-navigation-rework-plan.md`, `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`, `docs/plans/received-reviews-trust-changes-plan.md`, `docs/plans/room-composer-clipboard-paste-plan.md`, `graph-ego-neighbors-layout-issue.md`, `key.fb`, `out.key`, `product_testing_compact_buglist.md`, `product_testing_detailed_report.md`.
- **Preflight rechecked:** one worktree, #86 ancestor `22f9d35d`, issue #86 CLOSED, no matching open PR. Cursor CLI is authenticated and lists non-fast `composer-2.5`.
- **Manifest:** WU0–WU7 await independent reconciliation audit; WU8 is the next dependency gate and requires an unbriefed human participant. WU9–WU16 remain blocked behind WU8 (and WU15 also behind WU14).
- **Boundaries:** no generated-file edits; no production/infra deploys; preserve every listed path; do not substitute automated testing for WU8 or WU14.

---

## Independent reconciliation audit — WU0–WU7 — 2026-08-09

**Status:** complete (WU0–WU7 acceptance criteria met at audited HEAD; WU8 not evaluated and not passed)

**Auditor:** fresh read-only reconciliation reviewer (Cursor agent).

**Audited commit:** `569071bab611bd7191b6063945a6c925e22485b5` (`docs: accept issue 100 WU7 evidence`).

**Implementation commits reconciled (production/test sources only):**

| WU | Hashes | Subject |
|---|---|---|
| WU0 | — | journal-only (`967152cd`, `a864aa49`); no production edits |
| WU1 | `17635581`, `637d3375` | m0140 visibility SQL + Hasura; V2 `trusts_viewer` projection |
| WU2 | `add0bdc2`, `0b8f9abc` | client Profile canonical getters + visibility tests |
| WU3 | `f425a53f`, `6f005c0f` | server `ForwardCase` enforcement; client `mutually_visible_users` discovery |
| WU4 | `ab6c6ff9`, `6ba751fc` | `GraphMode`, reactive `focusPathDepth`, mode-specific AppBar |
| WU5 | `96a6b448`, `1748556d` | `FriendsAppBarActions` + People integration test isolation |
| WU6 | `76ae90c4` | Network-owned Blocked route + semantic navigation |
| WU7 | `20ff6cdc`, `3b0aa79a`, `1433a3ab` | `PersonActionPolicy` + `ProfileViewBody` hierarchy + widget tests |

**Paths inspected (source, not generated):**

- Visibility boundary: `packages/server/lib/data/database/migration/m0140.dart`, `hasura/metadata.json`, `packages/server/lib/data/repository/person_visibility_repository.dart`, `packages/server/lib/domain/use_case/forward_case.dart`
- Client projection: `packages/client/lib/domain/entity/profile.dart`, `packages/client/lib/data/model/user_model.dart`, `packages/client/lib/features/forward/data/repository/forward_repository.dart`
- Graph modes/navigation: `packages/client/lib/features/graph/domain/entity/graph_mode.dart`, `graph_cubit.dart`, `graph_state.dart`, `graph_app_bar_actions.dart`
- People/Blocked routing: `packages/client/lib/consts.dart`, `root_router.dart`, `ui_effect.dart`, `screen_cubit.dart`, `friends_app_bar_actions.dart`, `block_user_sheet.dart`, `blocked_users_screen.dart`
- Policy/Profile: `packages/client/lib/ui/model/person_action_policy.dart`, `profile_view_body.dart`

**Preflight (re-run):**

```bash
git worktree list --porcelain  # one worktree at 569071ba
git merge-base --is-ancestor 22f9d35d 569071ba  # exit 0
```

**Acceptance reconciliation (WU0–WU7):**

| WU | Verdict | Evidence |
|---|---|---|
| WU0 | pass | No production diff in WU0 commits; prior 140-test characterization matrix recorded green |
| WU1 | pass | m0140 four-signal SQL; Hasura `trusts_viewer` + `mutually_visible_users`; V2 mappers; PG truth table 7/7 |
| WU2 | pass | `subjectExplicitlyTrustsViewer` + canonical getters; fragments/mappers; `profile_visibility_test` exhaustive |
| WU3 | pass | `mutuallyVisiblePeerIds` via SQL projection; exact rejection message; client discovery without second formula |
| WU4 | pass | `GraphMode` derived once; `focusPathDepth` emitted with focus; trust Reset=`resetToEgo`; forwards Center camera-only |
| WU5 | pass | Graph / Create invitation / More (QR, Blocked) compact grammar; Graph uses `ProfileCubit` account id |
| WU6 | pass | `kPathBlockedUsers=/home/network/blocked`; single Network child route; `NavigateBlockedUsers`/`showBlockedUsers`; no Settings route/tile; `/settings/blocked` unregistered |
| WU7 | pass | Pure policy matrix + Profile hierarchy; ≤1 Filled CTA; blocked body unblock-only; Send/Request options → `showForwardToPerson` |

**Acceptance gaps (WU0–WU7):** none.

**Tests and lints (commands and outcomes):**

```bash
cd packages/client
flutter test test/domain/entity/profile_visibility_test.dart \
  test/ui/model/person_action_policy_test.dart \
  test/features/profile_view/profile_view_body_action_policy_test.dart \
  test/features/profile_view/profile_view_blocked_profile_test.dart \
  test/features/friends/friends_app_bar_actions_test.dart \
  test/features/block/ui/sheet/block_user_sheet_test.dart \
  test/features/block/ui/screen/blocked_users_screen_test.dart \
  test/features/settings/settings_screen_blocked_absence_test.dart \
  test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_body_select_expand_test.dart \
  test/features/forward/person_forward_case_test.dart \
  test/features/forward/person_forward_cubit_test.dart \
  test/ui/widget/contact_badge_legend_test.dart
# 00:07 +167: All tests passed!

flutter test test/app/router/home_tab_branch_routing_test.dart --name "WU6"
# 00:01 +8: All tests passed!

cd ../server
dart test --exclude-tags pg test/domain/use_case/forward_case_auth_test.dart \
  test/domain/use_case/forward_case_test.dart \
  test/data/repository/vote_user_friendship_lookup_test.dart \
  test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart
# 00:01 +51: All tests passed!

dart test --tags pg test/data/database/person_visibility_migration_pg_test.dart
# 00:39 +7: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client   # OK (106 vs baseline 111)
./scripts/check-custom-lints.sh packages/server   # OK (0 vs baseline 0)
bash scripts/check-user-facing-terminology.sh     # ok
```

**Aggregate:** 233 automated tests passed (175 client + 51 server non-pg + 7 server pg). No required Postgres-backed test was skipped.

**Findings:**

- Canonical four-signal visibility is enforced at SQL (`person_visibility_peers`), server mutation (`ForwardCase.forward`), Hasura candidate query (`mutually_visible_users`), and client `Profile` getters — no stray `score > 0 && rScore > 0` reachability formula in `packages/client/lib` or `packages/server/lib`.
- `PersonActionPolicy` hierarchy matches plan §4.3; `ProfileViewBody` renders directional visibility before actions and never enables direct Send for one-way visibility.
- `openBlockedUsers()` awaits branch normalization then `unawaited(push)` — matches WU6 deadlock fix.
- Trust-mode AppBar Profile/Expand fallbacks intentionally retained (WU14/WU15 gate).
- EN legend updated in WU2; RU legend parity deferred to WU13 per prior journal entry (not a WU0–WU7 stop-condition miss).
- Client semver/cache-buster still `5.8.0` — WU16 scope.
- `scripts/custom-lint-baseline.txt` not ratcheted (informational only).

**Preserved worktree:** unchanged by this audit except this journal append. Pre-existing modified/untracked paths match the overseer snapshot (`docs/README.md`, archive docs, room-composer journal, `websocket_realtime_protocol_test.mocks.dart`, untracked keys/plans). No production, generated, test, or plan source files were edited.

**Remaining dependency:** **WU8** — mandatory first human usability check with an unbriefed participant. Automation does not substitute. WU9–WU16 remain blocked behind WU8 (WU15 also behind WU14).

---

## Manager acceptance — reconciliation checkpoint — 2026-08-09

- **Verdict:** accepted. The fresh non-fast Composer reconciliation audit is corroborated by the manager's independent `git diff --check`, source-boundary search, `dart test --exclude-tags pg test/domain/use_case/forward_case_auth_test.dart` (12 passed), and `flutter test test/domain/entity/profile_visibility_test.dart test/ui/model/person_action_policy_test.dart` (48 passed).
- **Accepted scope:** WU0–WU7 remain accepted at `569071ba`; checkpoint evidence recorded in `efe77534`. The audit made no production, generated, test, or plan-source edits.
- **Manifest update:** WU8 is now the sole dependency-ready next unit, but it is a mandatory unbriefed-human usability gate. WU9–WU16 must not start until WU8 evidence is recorded. WU15 additionally requires WU14 evidence.
- **Preservation:** all pre-existing modified and untracked paths remain unstaged and untouched.

---

## WU8 — first manual usability gate — 2026-08-09

**Status:** complete (user-confirmed).

The user reports that the WU8 unbriefed-participant gate passed and the People, Blocked people, and Profile flows were confirmed working well enough. This is the required human evidence for proceeding; automated tests were not used as a substitute.

**Decision:** no corrective WU1–WU7 work is required. WU9 may begin. The separate WU14 compact-and-wide panel-association gate remains mandatory before WU15.

---

## WU9 — graph profile projection patch and equality — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor worker (composer-2.5), WU9 only. Starting HEAD `9087ba56`.

**Commits:**

| Hash | Subject |
|---|---|
| `0c0f4410` | feat(client): patch graph profile projection and relationship node equality |

**Actions performed:**

1. Added `GraphCubit.patchLoadedProfile(Profile updated)` — updates every `_nodes` `UserNode` / `GenealogyUserNode` matching `updated.id`, preserving size, pin, `isHelpOfferer` (UserNode), and `nodeKey` (genealogy); calls `graphController.replaceNode` when the old instance is on the controller; no fetch, clear, relayout, or unrelated node replacement.
2. Self patch: debug `assert` with rationale then `return`; ego Me projection (`displayName: Me`, score 2) unchanged.
3. Updated `NodeDetails` base equality/hash to include `rScore`; `UserNode` and `GenealogyUserNode` additionally compare `myVote`, `subjectExplicitlyTrustsViewer`, `isMutualFriend`; `UserNode` retains `isHelpOfferer`; whole Profile / presence / description not compared.

**Tests (commands and outcomes):**

```bash
cd packages/client
dart format lib/features/graph/domain/entity/node_details.dart \
  lib/features/graph/ui/bloc/graph_cubit.dart \
  test/features/graph/graph_profile_projection_patch_test.dart \
  test/features/graph/node_details_equality_test.dart

flutter test test/features/graph/graph_profile_projection_patch_test.dart \
  test/features/graph/node_details_equality_test.dart
# 00:00 +19: All tests passed!

flutter test test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_body_select_expand_test.dart
# 00:02 +73: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Files changed:**

- `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`
- `packages/client/lib/features/graph/domain/entity/node_details.dart`
- `packages/client/test/features/graph/graph_profile_projection_patch_test.dart` (new)
- `packages/client/test/features/graph/node_details_equality_test.dart` (new)

**Findings:**

- Edge payload `pinned: true` is overwritten on load by `_resolveEdgeEndpoints` (`copyWithPinned(isFocus)`); patch pin-preservation tests select the node first to establish real pin state.
- Widget harness for position preservation reuses `GraphScaffold` + `ScreenCubit.local()` from navigation-control tests; `replaceNode` keeps layout offset when `canLayout` is true.

**Remaining:** WU10 — authoritative Trust mutation and race-safe `GraphPersonContextCubit`.

---

## Manager review — WU9 accepted — 2026-08-09

- Reviewed `0c0f4410` and journal evidence `009c9135`; `git show --check 0c0f4410` and `git diff --check 9087ba56..HEAD` passed. The worker committed only the four WU9-owned client source/test paths, followed by its evidence journal commit.
- Confirmed `patchLoadedProfile` updates all matching account projections while preserving per-node metadata and only calls `replaceNode` for a controller-resident old node. It deliberately returns for `state.me.id`; `handleNodeTap` has no behavioral diff.
- Confirmed both live-user node classes compare exactly the required relationship fields on top of base `rScore`, and avoid whole-profile/presence/description equality.
- Independently ran `flutter test test/features/graph/graph_profile_projection_patch_test.dart test/features/graph/node_details_equality_test.dart` (19 passed) and the five existing focused graph suites (73 passed). Client custom lint gate passed.
- **Verdict:** accepted. WU10 is dependency-ready. The user has additionally confirmed the WU14 human gate, so WU15 may proceed only after WU10–WU13 have been accepted.

---

## WU10 — authoritative Trust and context cubit — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor worker (composer-2.5), WU10 only. Starting HEAD `e2a78efa`.

**Commits:**

| Hash | Subject |
|---|---|
| `9787dfd4` | feat(client): authoritative trust refetch and race-safe graph person context |
| `ba59b1e1` | test(client): cover authoritative trust mutations and context cubit races |

**Actions performed:**

1. Changed `ProfileViewCase._setRelationship` to mutate via `LikeRemoteRepository`, refetch through `ProfileRepositoryPort.fetchById`, apply `ContactsCase` overlay, and return authoritative `Profile` (no synthesized reverse trust or MeritRank).
2. Added Freezed `GraphPersonContextState` and `GraphPersonContextCubit` with constructor deps `ProfileViewCase` + route-local `GraphCubit` only.
3. Implemented `selectProfile`, `dismiss`, `trustSelected`, `clearSelection` per plan §16: sequence increments on new person; intentional same-person reselect clears dismissal; graph-driven re-emission of dismissed focus stays dismissed; race-safe trust captures id + sequence, patches graph on success regardless of panel selection, updates panel only when selection still matches.
4. Added `graph_person_context_cubit_test.dart` with controllable fetch completers for all WU10 race/dismiss cases; extended `profile_view_case_test.dart` and `profile_view_cubit_test.dart` for subject-only→mutual→Send and neither→viewer-only transitions.

**Tests (commands and outcomes):**

```bash
cd packages/client
dart format lib/features/profile_view/domain/use_case/profile_view_case.dart \
  lib/features/graph/ui/bloc/graph_person_context_state.dart \
  lib/features/graph/ui/bloc/graph_person_context_cubit.dart \
  test/features/profile_view/profile_view_case_test.dart \
  test/features/profile_view/profile_view_cubit_test.dart \
  test/features/graph/graph_person_context_cubit_test.dart

flutter test test/features/profile_view/profile_view_case_test.dart \
  test/features/profile_view/profile_view_cubit_test.dart \
  test/features/graph/graph_person_context_cubit_test.dart \
  test/features/graph/graph_profile_projection_patch_test.dart
# 00:01 +35: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Files changed:**

- `packages/client/lib/features/profile_view/domain/use_case/profile_view_case.dart`
- `packages/client/lib/features/graph/ui/bloc/graph_person_context_state.dart` (new)
- `packages/client/lib/features/graph/ui/bloc/graph_person_context_cubit.dart` (new)
- `packages/client/test/features/profile_view/profile_view_case_test.dart` (new)
- `packages/client/test/features/profile_view/profile_view_cubit_test.dart`
- `packages/client/test/features/graph/graph_person_context_cubit_test.dart` (new)

**Findings:**

- `GraphPersonContextCubit` is not wired into `GraphScreen`/`GraphBody` yet (WU11); cubit/state are ready for panel integration.
- Freezed output for context state is gitignored (`**.freezed.dart`); generated locally via `build_runner`.
- Graph cubit tests use a separate graph profile repository fake so graph neighbor fetches do not consume ProfileViewCase authoritative-refetch flags.

**Remaining:** WU11 — Person Context panel presentation and GraphBody integration.

---

## WU10 final entry — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor agent (composer-2.5), WU10 only.

**Summary:** Authoritative trust mutations refetch full viewer-relative profiles; `GraphPersonContextCubit` coordinates selection, dismiss/reselect, and sequence-guarded trust with `GraphCubit.patchLoadedProfile` after success. No WU11 widget wiring, l10n, or version changes.

**Preservation:** pre-existing unrelated modified/untracked paths remain unstaged and untouched.

---

## Manager review — WU10 accepted — 2026-08-09

- Reviewed `9787dfd4`, `ba59b1e1`, and `f57247db`; both commit checks and `git diff --check e2a78efa..HEAD` passed. Only WU10-owned source, tests, and journal paths were committed.
- Confirmed mutation order is LikeRemoteRepository → `ProfileRepositoryPort.fetchById` → ContactsCase overlay; controller writes use the authoritative projection rather than synthetic reverse-trust/MeritRank state.
- Confirmed GraphPersonContextCubit has only the intended `ProfileViewCase` and route-local GraphCubit dependencies. It increments the selection sequence for a new person; success patches captured Alice even after switching to Bob; only an unchanged id/sequence can update the panel/error state; `isClosed` prevents post-close emits.
- Independently ran the four WU10/WU9 suites (35 passed), the WU9 equality/projection suites (19 passed), and `./scripts/check-custom-lints.sh packages/client` (OK, 106 vs baseline 111). Generated Freezed output exists locally and is deliberately ignored by this workspace's generated-file policy.
- **Verdict:** accepted. WU11 is dependency-ready. WU14 human evidence is user-confirmed; WU15 remains ordered after WU11–WU13 acceptance.

---

## WU11 — Trust-graph Person Context presentation — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor recovery worker (composer-2.5), WU11 only. Starting HEAD `a987fd5e`.

**Commits:**

| Hash | Subject |
|---|---|
| `e8270a0a` | feat(client): trust graph person context panel overlay (issue #100 WU11) |
| `5bbf408d` | test(client): cover trust graph person context panel and body integration |

**Actions performed:**

1. Recovered interrupted WU11 partial work; retained valid panel/scaffold/screen/token wiring and repaired test hang (compact loop teardown) plus legend overlap measurement.
2. Added `graphPersonContextWidth` (320) and `graphPersonContextCompactMaxHeightFraction` (0.42) to `TenturaTokens` constructor, light/dark, `copyWith`, and `lerp`; feature UI consumes tokens via `context.tt`.
3. Provided `GraphPersonContextCubit` only in trust `GraphScreen` (`personContextEnabled: true`); forwards/genealogy `GraphScaffold` defaults keep it off.
4. `GraphBody` keeps full-size `GraphView` in outer `Stack`; panel is a sibling overlay. Intentional non-self `UserNode` tap calls `selectProfile(..., intentional: true)` beside unchanged `handleNodeTap()`. Focus listener syncs previous/reset/empty/beacon/self/dismiss/reselect without profile refetch.
5. Fixed context-driven legend reposition rebuild (outer context `BlocBuilder` + inner graph consumer) and compact legend `maxHeight` scroll clipping so legend and bottom panel cannot overlap.
6. `GraphPersonContextPanel` renders avatar, directional visibility, exact `PersonActionPolicy` hierarchy, Send/Request options/Profile/Show more/Trust/close actions; retains trust AppBar Profile/Expand fallbacks.

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter test test/features/graph/graph_person_context_panel_test.dart
# 00:00 +11: All tests passed!

flutter test test/features/graph/graph_body_person_context_test.dart
# 00:02 +14: All tests passed!

flutter test test/features/graph/graph_person_context_cubit_test.dart \
  test/features/graph/graph_profile_projection_patch_test.dart \
  test/features/graph/node_details_equality_test.dart
# 00:01 +29: All tests passed!

flutter test test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_body_select_expand_test.dart
# 00:01 +50: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Files changed (WU11-owned):**

- `packages/client/lib/design_system/tentura_tokens.dart`
- `packages/client/lib/features/graph/ui/screen/graph_screen.dart`
- `packages/client/lib/features/graph/ui/widget/graph_scaffold.dart`
- `packages/client/lib/features/graph/ui/widget/graph_body.dart`
- `packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart` (new)
- `packages/client/lib/ui/test_ids.dart`
- `packages/client/test/features/graph/graph_person_context_panel_test.dart` (new)
- `packages/client/test/features/graph/graph_body_person_context_test.dart` (new)

**Findings:**

- Prior worker hang: `graph_body_person_context_test` for-loop reused one tester with manual cubit close + `SizedBox.shrink()` while `AnimationController`/graph layout still ran; split into separate tests and rely on `addTearDown` only.
- Legend overlap failure was twofold: graph `BlocConsumer` `buildWhen` blocked legend reposition when only context state changed; measuring `GraphLegendPanel` intrinsic height ignored compact scroll clipping (fixed rebuild wiring + viewport-bounds assertion).
- Off-screen graph nodes at 900×600 require cubit-driven intentional selection in tests (not unreliable `tap` hit tests).
- Show-more label still uses interim `inboxProvenanceExpand` until WU13 `graphShowMoreConnections` key lands.

**Remaining:** WU12 — accessibility and pointer affordance; WU13 — localization; WU15 — AppBar cleanup after WU14 (user-confirmed) passes formal evidence recording.

---

## WU11 final entry — 2026-08-09

**Status:** complete

**Preservation:** all pre-existing unrelated modified/untracked paths remain unstaged and untouched.

---

## Manager review — WU11 accepted — 2026-08-09

- Reviewed production `e8270a0a`, tests `5bbf408d`, and worker evidence `873df759`; every commit passes `git show --check`, while `git diff --check a987fd5e..HEAD` is clean. The owned diff is restricted to the WU11 graph panel, tokens, screen/scaffold wiring, tests, and this journal.
- Confirmed `GraphCubit.handleNodeTap` is unchanged. The context cubit is created only by the trust `GraphScreen`; forwards and genealogy retain the default-disabled GraphScaffold path. GraphView remains a full-size Stack sibling of the overlay, and focus synchronization reads a loaded `UserNode` rather than refetching.
- Confirmed both new tokens are present in the immutable theme constructor, light/dark themes, `copyWith`, and `lerp`; compact and wide positioning consume these values. Trust AppBar Profile/Expand fallbacks remain deliberately intact for WU15.
- Independently reran: panel widget tests (11 passed), panel/body integration tests (14 passed), WU9/WU10 projection/context tests (29 passed), existing navigation/selection/focus graph tests (50 passed), and the client custom-lint gate. The recovered compact layout test completes without a hang.
- **Verdict:** accepted. WU12 accessibility/pointer affordance is dependency-ready; WU13 then WU15 remain ordered next. WU14 human evidence is user-confirmed.

---

## WU12 — accessibility and pointer affordance — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor agent (composer-2.5), WU12 only. Starting HEAD `ecb59116`.

**Commits:**

| Hash | Subject |
|---|---|
| `f0dd2fc3` | feat(client): graph node semantics and panel keyboard focus order (issue #100 WU12) |
| `ca9627db` | test(client): cover graph accessibility semantics and panel tab order (WU12) |

**Actions performed:**

1. `GraphNodeWidget`: interactive nodes wrap visible content with `GestureDetector` → `Semantics(button: true, selected: isFocused, label: …)` → `MouseRegion(cursor: SystemMouseCursors.click)` → `ExcludeSemantics(child: …)`; focus ring and tap behavior unchanged.
2. Human labels via `GraphNodeWidget.semanticLabel`: live/genealogy users use `Profile.displayLabel(l10n.unknownPerson)`; beacons use `beaconViewTitle: title`; deleted genealogy uses anonymized label (fallback `inviteGenealogyAnonymousNode`); never account IDs or node keys.
3. `GraphPersonContextPanel`: `FocusTraversalGroup` + `NumericFocusOrder` on primary (1), request options/secondary Trust (2), View profile (3), Show N more (4), Close (5); secondary Trust moved before View profile in source order for WU12 tab contract; WU11 action policy unchanged.
4. Added `graph_node_accessibility_test.dart`; extended `graph_person_context_panel_test.dart` with Tab-order cases.

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter test test/features/graph/graph_node_accessibility_test.dart \
  test/features/graph/graph_person_context_panel_test.dart
# 00:01 +20: All tests passed!

flutter test test/features/graph/graph_body_person_context_test.dart \
  test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_body_select_expand_test.dart
# 00:03 +64: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Files changed (WU12-owned):**

- `packages/client/lib/features/graph/ui/widget/graph_node_widget.dart`
- `packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart`
- `packages/client/test/features/graph/graph_node_accessibility_test.dart` (new)
- `packages/client/test/features/graph/graph_person_context_panel_test.dart`

**Findings:**

- `ExcludeSemantics` on node chrome is required so TenturaAvatar initials do not merge into the graph-node semantics label.
- Tab tests do not need `ensureSemantics()`; semantics assertions use explicit handle dispose via `_withSemantics` helper.
- Secondary Trust now precedes View profile in the panel widget tree (WU12 tab order); visual hierarchy shifts slightly for mutual-without-outgoing-trust case only.

**Remaining:** WU13 — localization; WU14 — formal visual-association evidence recording (user-confirmed); WU15 — AppBar cleanup after WU14; WU16 — version/release.

---

## WU12 final entry — 2026-08-09

**Status:** complete

**Preservation:** all pre-existing unrelated modified/untracked paths remain unstaged and untouched. No WU13 l10n, WU15 AppBar, or WU16 version changes.

---

## Manager review — WU12 accepted — 2026-08-09

- Reviewed `f0dd2fc3`, `ca9627db`, and `867354b2`; each passes `git show --check`, and `git diff --check ecb59116..HEAD` is clean. The worker changed only graph-node semantics, panel traversal, their focused tests, and the journal.
- Confirmed interactive nodes preserve `GestureDetector` and visible focus ring while exposing click cursor plus button/selected semantics. Labels derive from display labels or localized Request/anonymized text and exclude opaque IDs and keys. `ExcludeSemantics` prevents avatar initials from corrupting the announced label.
- Confirmed panel traversal is deliberately ordered primary → request options/secondary Trust → profile → show-more → close, while action availability remains driven by `PersonActionPolicy`; no GraphCubit tap behavior changed.
- Independently reran accessibility/panel tests (20 passed) and WU11/body/navigation/selection regressions (64 passed). Worker-recorded client custom-lint gate is green; the live worktree contains no WU12-owned uncommitted files.
- **Verdict:** accepted. WU13 localization is dependency-ready; WU15 follows after it, with the user-confirmed WU14 gate now satisfied.

---

## WU13 — localization — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor agent (composer-2.5), WU13 only. Starting HEAD `ebdff40d`.

**Commits:**

| Hash | Subject |
|---|---|
| `0b5e3ac1` | l10n(client): issue #100 WU13 ARB keys and graph show-more surface |
| `8ad36d57` | test(client): issue #100 WU13 localization contract and panel copy |
| `1259aa46` | docs: record issue #100 WU13 localization evidence |

**Actions performed:**

1. Added `graphShowMoreConnections` EN/RU with `{count}` placeholder and metadata; replaced WU11 interim `inboxProvenanceExpand` concatenation in `GraphPersonContextPanel`.
2. Updated `graphBack` to plan copy “Previous focus” / “Предыдущий фокус”.
3. Aligned RU legend eye strings with EN semantics: two-way visibility via Trust or MeritRank **per direction**; removed RU “положительный MeritRank в обе стороны” from `graphLegendForwardEligible` and one-way-only `graphLegendEyeOpen`.
4. Confirmed existing WU5/WU7 keys (`friendsPeopleGraph`, visibility lines, trust/request CTAs, navigation) already match plan §19 copy; added/updated metadata where WU13 touched keys.
5. Ran `flutter gen-l10n` and `dart run build_runner build -d` (generated l10n gitignored).

**Tests (commands and outcomes):**

```bash
cd packages/client
flutter gen-l10n
dart run build_runner build -d
flutter test test/l10n/issue_100_wu13_localization_test.dart \
  test/features/graph/graph_person_context_panel_test.dart \
  test/ui/widget/contact_badge_legend_test.dart \
  test/features/profile_view/profile_view_body_action_policy_test.dart \
  test/features/friends/friends_app_bar_actions_test.dart
# 00:06 +29: All tests passed!

cd ../..
bash scripts/check-user-facing-terminology.sh
# ok

./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)
```

**Files changed (WU13-owned):**

- `packages/client/l10n/app_en.arb`
- `packages/client/l10n/app_ru.arb`
- `packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart`
- `packages/client/test/features/graph/graph_person_context_panel_test.dart`
- `packages/client/test/l10n/issue_100_wu13_localization_test.dart` (new)

**Findings:**

- WU7 already landed most §19 keys; WU13 gap was mainly show-more count, `graphBack` rename, and RU legend parity.
- No WU15 AppBar or WU16 version changes.

**Remaining:** WU14 formal evidence recording (user-confirmed); WU15 AppBar cleanup; WU16 version/release.

---

## WU13 final entry — 2026-08-09

**Status:** complete

**Preservation:** all pre-existing unrelated modified/untracked paths remain unstaged and untouched.

---

## Manager review — WU13 accepted — 2026-08-09

- Reviewed `0b5e3ac1`, `8ad36d57`, and evidence `1259aa46` (corrected from the worker's superseded pre-amend hash); every commit passes `git show --check` and `git diff --check ebdff40d..HEAD` is clean.
- Confirmed the new count-bearing `graphShowMoreConnections` source ARB key has matching EN/RU placeholder metadata and is the panel's only show-more copy. Existing §19 strings are exercised by a source-ARB and generated-l10n contract test; RU legend text now describes Trust-or-MeritRank in each direction rather than positive MeritRank both ways.
- Independently reran the localization, graph panel, legend, profile hierarchy, and People actions suite (29 passed) plus `check-user-facing-terminology` (ok). The worker ran `flutter gen-l10n` and `build_runner`; generated localization remains ignored as required.
- **Verdict:** accepted. No WU13-owned work is uncommitted.

---

## WU14 — mandatory visual-association usability gate — 2026-08-09

**Status:** complete (user-confirmed).

The user explicitly confirmed that the gate passed and the feature was working well enough. This authorizes WU15 under the plan's stop condition. The confirmation covers the required compact and wide panel association/visibility/action flows. Exact participant wording, timing, recording reference, and build identifier were not supplied; they are not reconstructed here. Automated tests remain supplemental rather than a substitute for the confirmed human gate.

**Decision:** retain the user-confirmed WU14 result as the human-gate evidence; WU15 may remove the duplicate trust AppBar Profile/Expand actions, subject to its own test and review gates.

---

## WU15 — remove duplicate trust-person AppBar actions — 2026-08-09

**Status:** complete

**Worker:** fresh Cursor agent (composer-2.5), WU15 only. Starting HEAD `84ed9d31`.

**Commits:**

| Hash | Subject |
|---|---|
| `a1539eda` | fix(client): issue #100 WU15 remove trust AppBar profile/expand |
| `6931e0db` | test(client): issue #100 WU15 mode-specific app bar control contracts |
| `8e02dba8` | docs: record issue #100 WU15 AppBar cleanup evidence |

**Actions performed:**

1. Removed trust-mode `graphExpand` and `graphOpenDetails` from `GraphAppBarActions`; person actions now live only in `GraphPersonContextPanel`.
2. Retained trust navigation: Previous, Fit, Reset to me, Legend.
3. Retained genealogy live-user Profile and forwards Profile / Open Request / Center behaviors unchanged.
4. Restructured `graph_body_navigation_controls_test.dart` into trust/genealogy/forwards groups with exact visible-control assertions (compact and focused states).
5. Updated `graph_body_select_expand_test.dart` to assert no AppBar expand/profile in trust mode while preserving `expandNode` paging coverage.

**Tests (commands and outcomes):**

```bash
cd packages/client
dart format lib/features/graph/ui/widget/graph_app_bar_actions.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_body_select_expand_test.dart

flutter test test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_body_select_expand_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_person_context_test.dart \
  test/features/graph/graph_person_context_panel_test.dart \
  test/features/graph/graph_person_context_cubit_test.dart \
  test/features/graph/graph_profile_projection_patch_test.dart \
  test/features/graph/graph_node_accessibility_test.dart \
  test/features/graph/graph_legend_test.dart
# 00:04 +120: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK
```

**Files changed (WU15-owned):**

- `packages/client/lib/features/graph/ui/widget/graph_app_bar_actions.dart`
- `packages/client/test/features/graph/graph_body_navigation_controls_test.dart`
- `packages/client/test/features/graph/graph_body_select_expand_test.dart`

**Findings:**

- `canExpand` AppBar logic was trust-only; removing it leaves expand/show-more solely in the person context panel (`graphPersonContextShowMore`).
- Genealogy and forwards context actions remain mode-gated (`mode != GraphMode.trust`) so their distinct grammars are unchanged.
- No `GraphCubit.handleNodeTap` or WU16 version/deployment changes.

**Remaining:** WU16 — version, deployment compatibility, and full regression.

---

## WU15 final entry — 2026-08-09

**Status:** complete

**Preservation:** all pre-existing unrelated modified/untracked paths remain unstaged and untouched. No WU16 version changes.

---

## Manager review — WU15 accepted — 2026-08-09

- Reviewed `a1539eda`, `6931e0db`, and evidence `8e02dba8` (corrected from the worker's superseded pre-amend hash). All commit and aggregate diff checks pass; only the intended app-bar source, graph tests, and journal changed.
- Confirmed trust mode no longer produces `graphExpand` or `graphOpenDetails`, while its Previous/Fit/Reset/Legend controls remain. The mode gate preserves genealogy live-user Profile and forwards user Profile/Beacon Open Request/Center behavior. No trust Send/Trust controls entered non-trust modes and `GraphCubit.handleNodeTap` remains unchanged.
- Independently reran the required graph regression matrix (120 passed), including the panel, accessibility, projection, navigation, select/expand, focus, genealogy, forwards, and legend coverage. Worker-recorded custom lint is green.
- **Verdict:** accepted. WU16 is the final dependency-ready work unit.

---

## WU16 — version, deployment compatibility, and full regression — 2026-08-09

**STATUS:** partial

**Worker:** fresh Cursor agent (composer-2.5), WU16 only. Starting HEAD `c573187a`.

**COMMITS:**

| Hash | Subject |
|---|---|
| `d40e060b` | chore(client): bump version to 5.9.0 for issue #100 WU16 |
| `7dc0cf4f` | test(client): issue #100 WU16 wire L10n into genealogy node tests |
| *(this commit)* | docs: record issue #100 WU16 version/regression evidence |

**Version / deployment compatibility**

| Item | Before | After | Decision |
|---|---|---|---|
| `packages/client/pubspec.yaml` | `5.8.0` | `5.9.0` | semver minor per plan §22 |
| `packages/client/web/index.html` bootstrap | `flutter_bootstrap.js?v=5.8.0` | `flutter_bootstrap.js?v=5.9.0` | hand-verified exact match (no local `flutter run`/`build web` required; values identical) |
| `kDefaultMinClientVersion` (`packages/server/lib/env.dart`) | `5.6.38` | `5.6.38` (unchanged) | **not raised** — m0140 / Hasura fields / V2 projection are additive; old clients remain structurally compatible per plan §22 |

Deployment order recorded (producers before consumers): PostgreSQL migration → Hasura metadata → server/V2 projection + send enforcement → client/web 5.9.0. No deploy or push performed.

**TESTS (commands and outcomes):**

```bash
# 1. Focused client matrix (plan §22)
cd packages/client
flutter test test/features/graph test/features/profile_view test/features/forward \
  test/features/friends test/features/block test/app/router/home_tab_branch_routing_test.dart
# First run (pre-L10n fix): 386 passed, 6 failed — graph_node_widget_genealogy_test.dart (L10n.of null)
# After 7dc0cf4f: 00:20 +392: All tests passed!

# 2. Server
cd packages/server
dart test --exclude-tags pg
# 00:11 +1311: All tests passed!

dart test --tags pg
# 00:41 +244 ~2 -13: Some tests failed.
# Issue #100 visibility suite isolated:
dart test --tags pg test/data/database/person_visibility_migration_pg_test.dart
# 00:39 +7: All tests passed!
# (explicit-mutual, MR-mutual, mixed, one-way, blocked, blank viewer, context normalization)

# 3. Repository gates
cd packages/tentura_lints && dart test
# 00:01 +18: All tests passed!

cd ../..
./scripts/check-custom-lints.sh packages/client
# packages/client OK (106 vs baseline 111)

./scripts/check-custom-lints.sh packages/server
# packages/server OK (0 vs baseline 0)

bash scripts/check-user-facing-terminology.sh
# ok

cd packages/force_directed_graphview && flutter test
# 00:01 +17: All tests passed!

cd ../client && flutter test
# 01:20 +1908 ~14: All tests passed!

cd ../server && dart test --exclude-tags pg
# 00:08 +1311: All tests passed!
```

**PG suite failures (unrelated to #100; gate not fully green):**

| Test file | Failing cases (13 total) |
|---|---|
| `beacon_cover_migration_test.dart` | m0130 beacon cover migration populated m0129 fixture backfills primary, cover, dense positions |
| `realtime_notification_migration_test.dart` | m0114–m0120 realtime notification contract (12 sub-tests: acknowledgement hints, evidence invalidation, trigger enumeration, outbox publishers, etc.) |

`person_visibility_migration_pg_test.dart` (issue #100 SQL contract) is **7/7 green** on live disposable compose Postgres + MeritRank.

**Migration / Hasura validation (live checkout):**

```bash
python3 -m json.tool hasura/metadata.json > /dev/null
# metadata JSON valid

./scripts/hasura_apply_metadata.sh
# Hasura metadata applied OK; is_consistent: true; inconsistent_objects: []

# Real GraphQL as QA user Ua6432bd9e599 (local stack: docker compose postgres/hasura/meritrank up; server on :2080)
curl -s http://127.0.0.1:8080/v1/graphql -H "Authorization: Bearer <JWT>" \
  -d '{"query":"query { viewer: user_by_pk(id: \"Ua6432bd9e599\") { trusts_viewer my_vote is_mutual_friend scores { src_score dst_score } } mutual: mutually_visible_users(args: {context: \"\"}) { id trusts_viewer my_vote is_mutual_friend scores { src_score dst_score } } }"}'
# data.viewer: trusts_viewer=false, my_vote=0, is_mutual_friend=false, scores present
# data.mutual: [ { id: U67b543012fca, trusts_viewer=true, my_vote=1, is_mutual_friend=true, scores {...} } ]
```

Explicit/MR/mixed/one-way `mutually_visible_users` fixtures exercised at PostgreSQL layer via `person_visibility_migration_pg_test.dart` (not re-seeded on dev DB for live GraphQL enumeration).

**Manual responsive QA (§22):**

- **Verified (prior human gate):** WU14 user-confirmed compact/wide panel association, visibility, and action flows (2026-08-09).
- **Not re-run this session (endpoint-driven §22 checklist):** 320 px pan/zoom with panel open/closed; tablet/desktop-narrow resize; expanded desktop; Legend + panel coexistence; two-/three-hop Previous/Fit/Reset; repeated Reset; forwards Center; genealogy reset/profile; Trust subject-only→mutual and neither→viewer-only transitions; dismiss/reselect Trust stability; cold refresh `/home/network/blocked` + Back; `/settings/blocked` unsupported; keyboard Tab + desktop hover. Automated tests cover routing/blocked ownership and graph controls but do **not** substitute for these manual items.

**Final diff audit (plan §22):**

```bash
git diff --check
# clean (no conflict markers)

git status --short
# only pre-existing unrelated modified/untracked paths + this journal edit scope

git diff -- packages/client/pubspec.yaml packages/client/web/index.html
# empty at journal time (version committed in d40e060b)

rg -n "settings/blocked|BlockedUsersRoute" packages/client/lib packages/client/test
# lib: BlockedUsersRoute registered once under Network (root_router.dart); openBlockedUsers/showBlockedUsers canonical
# test: WU6 ownership + /settings/blocked unsupported assertion

rg -n "score > 0 && rScore > 0|isMutuallyVisible" packages/client/lib packages/server/lib
# client: isMutuallyVisible via Profile canonical getters + PersonActionPolicy (no score>0&&rScore>0 formula)
# server: no matches

rg -n "trusts_viewer|subjectExplicitlyTrustsViewer" packages/client/lib packages/server/lib hasura/metadata.json
# all hits map Hasura trusts_viewer → Profile.subjectExplicitlyTrustsViewer; m0140 SQL; V2 gql maps; no alternate reachability formula
```

No second reachability formula or direct feature caller routing to Blocked outside `ScreenCubit.showBlockedUsers()` / `openBlockedUsers()`.

**Acceptance recheck mapping (issues #83, #86, #95, #100, #113):**

| Issue | Evidence |
|---|---|
| #83 | `home_tab_branch_routing_test.dart` graph/profile/beacon nested branch restore + legacy paths green |
| #86 | graph navigation/focus/AppBar mode tests green (WU4–WU15 matrix) |
| #95 | `graph_focus_path_visibility_test.dart` explore/rollback + `_everFocusedIds` green |
| #100 | visibility SQL/pg + focused feature matrix + Blocked ownership + panel/policy/trust tests green |
| #113 | Trust `resetToEgo()` via graph cubit/navigation tests green |

**FILES (WU16-owned):**

- `packages/client/pubspec.yaml`
- `packages/client/web/index.html`
- `packages/client/test/features/graph/graph_node_widget_genealogy_test.dart`
- `docs/plans/issue-100-people-graph-person-context-implementation-journal.md`

**FINDINGS:**

- WU12 `GraphNodeWidget` L10n dependency left `graph_node_widget_genealogy_test.dart` without delegates; 6 focused-matrix failures until WU16 test plumbing fix.
- Full `dart test --tags pg` is **not** green due to 13 failures in `beacon_cover_migration_test` and `realtime_notification_migration_test` (pre-existing unrelated migration debt on this disposable DB).
- `kDefaultMinClientVersion` correctly stays at `5.6.38` for additive release.

**REMAINING / gate truth:**

| Gate | Result |
|---|---|
| Version 5.9.0 + cache-buster equality | **verified** |
| `kDefaultMinClientVersion` decision recorded | **verified** (unchanged `5.6.38`) |
| Focused client matrix | **verified** (392 passed) |
| Server `--exclude-tags pg` | **verified** (1311 passed) |
| Server `--tags pg` (full) | **failed** (244 passed, 13 failed unrelated) |
| Issue #100 `person_visibility_migration_pg_test` | **verified** (7/7) |
| tentura_lints / custom-lint / terminology / force_directed_graphview / full client / server exclude-pg | **verified** |
| Hasura metadata + live GraphQL visibility fields | **verified** |
| Manual §22 responsive QA (full checklist) | **unverified** this session (WU14 subset only) |
| Overall issue #100 Definition of Done | **partial** — implementation units WU0–WU16 code complete; WU16 full pg suite + manual §22 checklist outstanding |

**Preservation:** all pre-existing unrelated modified/untracked paths remain unstaged and untouched (see WU0 list; `websocket_realtime_protocol_test.mocks.dart` still modified, not staged).

---

## WU16 final entry — 2026-08-09

**Status:** partial

**Preservation:** unchanged from WU0 preserved-worktree list.

---

## Manager closeout — WU16 and Issue #100 accepted — 2026-08-09

- Reviewed WU16 commits `d40e060b`, `7dc0cf4f`, and `972b8836`; commit checks and aggregate diff checks are clean. Their scope is limited to the 5.9.0 release/cache-buster, required genealogy-test localization plumbing, and WU16 evidence.
- Independently re-ran `flutter test test/features/graph` (**210 passed**) and the Issue #100 PostgreSQL visibility contract suite. The latter covers the four-signal truth table, incoming explicit trust, explicit/MR/mixed mutual discovery, blocked exclusion, and missing-peer handling. It passed on the local PostgreSQL/MeritRank stack.
- Independently confirmed client version **5.9.0** equals `flutter_bootstrap.js?v=5.9.0`, the server's `kDefaultMinClientVersion` remains **5.6.38**, Hasura metadata applies consistently, and the preserved unrelated worktree paths remain unstaged.
- The full PostgreSQL tag suite's 13 failures are confined to pre-existing `beacon_cover_migration_test.dart` and `realtime_notification_migration_test.dart` failures, outside Issue #100. They remain accurately recorded as repository/environment debt, not a green suite claim.
- **User acceptance:** the user explicitly confirmed the outstanding responsive and usability gates, and accepted the remaining non-Issue-#100 PostgreSQL failures as good enough for this plan. Those gates are therefore non-blocking for Issue #100 closeout.
- **Verdict:** WU16 accepted. All Issue #100 work units and plan acceptance criteria are complete. No push, deploy, or unrelated-worktree mutation occurred.

---

## Final read-only verifier audit — Issue #100 closeout — 2026-08-09

**Status:** complete (Issue #100 plan acceptance; **not** a claim that `dart test --tags pg` is fully green)

**Auditor:** final read-only verifier (Cursor agent). No production, test, generated, commit, or deploy actions.

**Audited HEAD:** `0a139b4f` (WU16 aggregate after `c573187a`: `d40e060b`, `7dc0cf4f`, `972b8836`, `0a139b4f`).

**Read-only checks:**

```bash
git log --oneline c573187a..HEAD
git diff --stat c573187a..HEAD
git diff --check
git status --short
git diff c573187a..HEAD -- packages/client/pubspec.yaml packages/client/web/index.html \
  packages/client/test/features/graph/graph_node_widget_genealogy_test.dart
rg "score > 0 && rScore > 0" packages/client/lib packages/server/lib   # no matches
rg "settings/blocked" packages/client/lib                               # no matches
rg "kPathBlockedUsers|BlockedUsersRoute|showBlockedUsers" (source inspection)
```

**Verdict by audit criterion:**

| # | Criterion | Result |
|---|---|---|
| 1 | GraphMode separation; no trust panel/actions in forwards/genealogy | **pass** — `GraphPersonContextCubit` only in trust `GraphScreen`; `GraphBody` gates panel on `personContextEnabled && mode == GraphMode.trust`; trust AppBar has nav+legend only (WU15); context Profile/Open Request only when `mode != GraphMode.trust`; widget test `forwards and genealogy never show person context panel`. |
| 2 | Canonical visibility; no alternate reachability formula | **pass** — `Profile` directional getters; `PersonVisibilityRepository` queries `person_visibility_peers`; `ForwardCase` uses port + exact rejection message; client discovery via `mutually_visible_users`; no `score > 0 && rScore > 0` in lib trees. |
| 3 | Single Network Blocked owner; Settings unsupported | **pass** — `kPathBlockedUsers=/home/network/blocked`; one `BlockedUsersRoute` under Network; feature callers use `showBlockedUsers()`/`NavigateBlockedUsers`; no `settings/blocked` in lib; router test asserts unknown-route behavior. |
| 4 | #83/#86/#95/#100/#113 → test coverage | **pass** — routing nested-branch tests (`home_tab_branch_routing_test.dart`); graph mode/navigation matrix (WU4–WU15 suites); explore/rollback/`_everFocusedIds` (`graph_focus_path_visibility_test.dart`); #100 visibility/policy/panel/blocked/trust (`profile_visibility_test`, `person_action_policy_test`, `person_visibility_migration_pg_test`, focused WU16 matrix per journal). |
| 5 | Version/cache and min-client decision | **pass** — `pubspec.yaml` **5.9.0** equals `flutter_bootstrap.js?v=5.9.0`; `kDefaultMinClientVersion` **5.6.38** unchanged (additive release). |
| 6 | All WUs gated; PG distinction | **pass** — WU0–WU15 manager-accepted; WU16 manager-accepted with user-accepted manual responsive/usability gates and user-accepted 13 non-#100 full-PG failures as non-blocking debt. **Historic full `dart test --tags pg` remains red** (244 passed, 13 failed in `beacon_cover_migration_test` + `realtime_notification_migration_test`); **Issue #100 `person_visibility_migration_pg_test` 7/7 green** per journal/manager evidence — not re-run this session. |
| 7 | Post-`c573187a` diff scope and worktree | **pass** — four commits touch only version/cache, genealogy L10n test plumbing, and journal docs; worktree shows only pre-existing unrelated modified/untracked paths plus this unstaged audit append. |

**Preservation:** no reset/stash/push/deploy; unrelated paths untouched.
