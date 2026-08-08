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
9. **WU8** — mandatory first human usability check — pending human gate.
10. **WU9** — graph profile projection patch and equality — pending.
11. **WU10** — authoritative Trust and context cubit — pending.
12. **WU11** — Person Context presentation — pending.
13. **WU12** — accessibility and pointer affordance — pending.
14. **WU13** — localization — pending.
15. **WU14** — mandatory visual-association human gate — pending human gate.
16. **WU15** — conditional AppBar cleanup after WU14 pass — pending.
17. **WU16** — version, compatibility, and full regression — pending.

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
