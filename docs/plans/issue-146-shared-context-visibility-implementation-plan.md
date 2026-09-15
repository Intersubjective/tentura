---
status: draft
kind: implementation-plan
issue: 146
---

# Shared-context visibility — implementation plan

**Status:** rev 2, ready for execution. No implementation performed yet.

**No legacy-client support.** Tentura has no production users. The web build is the
only client, and `kDefaultMinClientVersion` forces every browser onto the released
version (T16). So nothing in this plan keeps old clients working: no compatibility
shims, no aliases kept "for old clients", no soft-fail responses chosen for
compatibility. Server and client changes ship together in one release.
**Date:** 2026-09-15. **Live-code baseline:** `8b62f67eb` plus the working tree of
branch `issue-146-shared-context-visibility`.
**Architecture (binding):**
[`issue-146-shared-context-visibility-architecture.md`](issue-146-shared-context-visibility-architecture.md)
(rev 4). Decisions D1–D8 live there. This plan does not re-decide them.
**Issue:** [#146](https://github.com/Intersubjective/tentura/issues/146).

---

## 0. How to use this plan (read fully before Task 00)

This plan is written for an implementer that executes one task at a time and does not
redesign anything. Follow these rules:

1. **Order.** Execute tasks in numeric order. Do not start a task until the previous
   task's "Done when" list is fully true and committed.
2. **Journal.** Keep `docs/plans/issue-146-shared-context-visibility-journal.md`
   (created in Task 00). After each task, append: task id, files changed, commands
   run with their exact result lines (pass/fail/skip counts), deviations, commit hash,
   and the next task id.
3. **No redesign.** If a named symbol, file or SQL body differs from this plan, stop
   and record the difference in the journal. Adapt only mechanically (for example a
   different free migration number). If the difference changes *behavior*, stop and
   ask the product owner.
4. **Unrelated edits.** The branch carries many unrelated modified and untracked
   files (see `git status`). Never `git add -A`, `git add .`, `git stash`,
   `git reset` or `git checkout -- <file>` on paths you did not create or change in
   the current task. Stage task-owned paths explicitly.
5. **Generated files.** Never hand-edit `*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
   `*.config.dart`, `_g/*.gql.dart` or `lib/ui/l10n/*.dart`. Regenerate them instead
   (commands in §0.2).
6. **Tests are the gate.** A task that owns a `-t pg` test is not done if that test
   was *skipped*. If local Postgres is not reachable, start it (§0.2) or stop and say so.
   Never mark a skipped test as passed.
7. **Superseded tests.** Some existing tests encode the old behavior (listed per task).
   Change their expectations to the new rule and rename them to describe the new
   rule. Never delete such a test without putting an equivalent assertion of the new
   behavior in its place.
8. **Commits.** One focused commit per task, conventional-commit style
   (`fix(server): …`, `feat(client): …`, `docs: …`). The commit body names the task id
   (`issue-146 T03`).

### 0.1 Path abbreviations

| Prefix | Means |
|---|---|
| `R/` | repo root package `tentura_root` (`lib/`, `test/` at repo root) |
| `S/` | `packages/server/lib/` |
| `ST/` | `packages/server/test/` |
| `C/` | `packages/client/lib/` |
| `CT/` | `packages/client/test/` |
| `MIG/` | `packages/server/lib/data/database/migration/` |

### 0.2 Commands (always wrapped; copy exactly)

```bash
# server unit tests (no Postgres)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg <test paths>

# server Postgres tests (needs local Postgres from docker compose)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test -t pg <test paths>

# root package tests
./scripts/run_with_test_cleanup.sh --timeout 10m -- dart test <test paths>

# client tests
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env <test paths>

# lints (the only valid analyzer check; see AGENTS.md § Verify)
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client

# codegen
cd packages/server && dart run build_runner build -d      # DI (Injectable) after new @Injectable classes
cd packages/client && dart run build_runner build -d      # Ferry / Freezed / Injectable
cd packages/client && flutter gen-l10n                    # after .arb edits

# user-facing wording guard
bash scripts/check-user-facing-terminology.sh

# local infra for pg tests and Hasura (see DEVELOPMENT.md)
docker compose up -d   # Postgres, Hasura, MeritRank, MinIO
./scripts/hasura_apply_metadata.sh
```

Never run bare `flutter test` / `dart test` in the background. Never use
`flutter analyze` or `dart analyze <subdir>` to check lints.

### 0.3 Task map

| Phase | Tasks | Behavior change |
|---|---|---|
| 0: local defects | T00–T04 | bug fixes only |
| 1: explicit access level | T05–T07 | none (parity) |
| 2: hierarchy context | T08–T10 | D1, D2, D5, D6 |
| 3: co-participant bond | T11–T13 | D3, D4 |
| 4: client UX, docs, release | T14–T16 | UX + docs |

### 0.4 Fixed constants used everywhere

`BeaconStatus` smallint codes (`R/domain/entity/beacon_status.dart`): open 0,
cancelled 1, deleted 2, draft 3, reviewOpen 5, closed 6, needsMoreHelp 7,
enoughHelp 8. Bond-active statuses = `allowsCoordination` = {0, 5, 7, 8}.

`beacon_participant`: `role = 1` is steward (`BeaconParticipantRoleBits.steward`);
`room_access = 3` is admitted (`RoomAccessBits.admitted`).

**Access-reason bitmask** (shared by SQL, server and client; never renumber):

| Bit | Value | Reason |
|---|---|---|
| 0 | 1 | author |
| 1 | 2 | steward (`beacon_steward` row, or participant `role = 1`) |
| 2 | 4 | admitted (participant `room_access = 3`) |
| 3 | 8 | forwarded (active inbound forward edge) |
| 4 | 16 | applied (active help offer, `status = 0`) |
| 5 | 32 | discovered (D11, trust-only) |
| 6 | 64 | contextChild (member of the immediate parent), from phase 2 |
| 7 | 128 | contextAncestor (member of some descendant), from phase 2 |

**Access level:** 0 author, 1 member, 2 observer, 3 stranger.
Level = 0 if bit 0; else 1 if bits 1–2; else 2 if bits 3–7; else 3.

---

## Phase 0 — local defects

### T00 — Preflight and journal

**Goal:** confirm the baseline and create the journal. No production code.

Steps:
1. `git branch --show-current` must print `issue-146-shared-context-visibility`.
2. Confirm these still exist (use Serena `find_symbol` or grep):
   - `S/data/repository/beacon_hierarchy_repository.dart`: `listChildren`,
     `loadParentReference`, `loadCapabilities`, `_loadAdmissionFacts`.
   - `S/api/controllers/graphql/query/query_beacon_hierarchy.dart`:
     `QueryBeaconHierarchy.beaconChildren`, `beaconParentReference`.
   - `S/domain/use_case/coordination_case.dart`: `helpOffersWithCoordination`.
   - `S/domain/use_case/beacon_fact_card_case.dart`: `list`.
   - `S/domain/beacon_visibility.dart`: `BeaconVisibility.canReadLinkedDetail`.
   - `MIG/_migrations.dart`: last entry of `_allMigrations` is `m0169`.
3. Record the highest migration number. Tasks below use `m0170`–`m0173`. If
   those are taken, use the next free numbers, and record the mapping in the journal.
4. Start local infra (§0.2). Run the baseline suites and record the counts:
   - `ST/domain/beacon_visibility_test.dart`, `ST/domain/beacon_hierarchy_policy_test.dart`
     (unit);
   - `ST/data/repository/beacon_hierarchy_visibility_pg_test.dart`,
     `ST/data/repository/beacon_access_sql_parity_test.dart`,
     `ST/api/beacon_hierarchy_hasura_parity_test.dart` (`-t pg`).
   Pre-existing failures are recorded as baseline, not fixed.
5. Create the journal file with a header, the baseline results, and "next: T01".

Done when: journal exists with baseline counts. Commit only the journal:
`docs: start issue-146 implementation journal`.

---

### T01 — `beaconChildren`: authorize the parent and filter each child

**Why:** architecture §3.3/2. Today anyone who knows a parent id can list its
children.

Files: `S/data/repository/beacon_hierarchy_repository.dart` (`listChildren`),
`ST/data/repository/beacon_hierarchy_repository_pg_test.dart` (or a new
`ST/data/repository/beacon_children_authorization_pg_test.dart`).

The port signature does not change: `listChildren` already receives `viewerId`.

Steps:
1. At the top of `listChildren`, before the page query, run:
   ```sql
   SELECT public.beacon_can_read_linked_detail($1, $2) AS allowed
   ```
   with `$1 = parentBeaconId`, `$2 = viewerId`. If `allowed` is false, return
   `const BeaconHierarchyPage(summaries: [])` (see `R/domain/entity/beacon_hierarchy_page.dart`).
   Do not throw: the client treats an empty page as "no children".
   *Why `linked_detail` and not `can_read_content`:* in phase 0 it is the predicate
   that still lets parent members see every child. T09 turns it into an alias of
   `can_read_content`, and T10 renames the call.
2. Add the viewer as a new bind variable. Its index is `$3` without a cursor and `$5`
   with one. Build the index from `variables.length + 1` rather than hard-coding it.
3. Add this row filter to the `WHERE` clause, after the status filter and before the
   cursor SQL:
   ```sql
     AND NOT public.block_hides(b.user_id, $V)
     AND (
       (b.status <> 2 AND public.beacon_can_read_linked_detail(b.id, $V))
       OR (b.status = 2 AND public.beacon_effective_admission($1, $V))
     )
   ```
   Here `$V` is the viewer placeholder from step 2. The second branch keeps the
   deleted-child tombstone rule ("admitted parent viewers not blocked by the child
   owner").
4. Tests (`-t pg`, using `BeaconHierarchyFixture` / `BeaconHierarchyTopology`:
   A→B→C, A→D):
   - a stranger (`frankId`, no access to A) gets an empty page for A;
   - an admitted member of A gets B and D;
   - a viewer blocked by D's owner does not get D;
   - a deleted child appears in the `deleted` group only for admitted members of A.

Done when: the new tests pass (not skipped), the existing hierarchy pg tests pass,
and server lints are clean. Commit: `fix(server): authorize beaconChildren by viewer`.

---

### T02 — `beaconParentReference`: authorize both ends

**Why:** architecture §3.3/1 and §7.4 (Astra finding 2).

Files: `S/data/repository/beacon_hierarchy_repository.dart` (`loadParentReference`),
`S/domain/policy/beacon_hierarchy_policy.dart` (only if a helper is needed), a pg test.

Steps:
1. Replace the body of `loadParentReference` with this logic:
   ```text
   if !beacon_can_read_content(childBeaconId, viewerId) → return BeaconParentReference.none
   parentId = loadImmediateParentBeaconId(childBeaconId)
   if parentId == null → return BeaconParentReference.none
   parent = _loadBeaconRow(parentId)
   if parent == null || parent.status == deleted → return BeaconParentReference.unavailable
   if beacon_can_read_linked_detail(parentId, viewerId) →
       return BeaconParentReference(state: available, beaconId: parentId, title: parent.title)
   return BeaconParentReference.unavailable
   ```
   Call each SQL predicate through `_database.customSelect('SELECT public.<fn>($1, $2) AS allowed', …)`,
   the same pattern as `BeaconAccessRepository._callPredicate`. Add a private helper
   `_predicate(String fn, String beaconId, String viewerId)` in this repository. Do not
   inject `BeaconAccessGuard` into a repository.
2. `BeaconHierarchyPolicy.resolveParentReference` and
   `isAdmittedToImmediateParent` may become unused here. Leave them alone; T10 cleans
   them up.
3. Tests (`-t pg`):
   - an admitted member of B who is not a member of A gets `available` with A's id and
     title. This is the #146 scenario 1;
   - a stranger to B gets `none`, even though B has a parent;
   - a viewer who reads B but has no path to A gets `unavailable` with no id or title.
   Before phase 2, "reads B, not admitted to B, no path to A" is for example a
   forward recipient of B.

Done when: the tests pass and the existing hierarchy pg tests pass. Commit:
`fix(server): authorize both ends of the parent reference`.

---

### T03 — Close the involvement leaks in content-only gates

**Why:** architecture §3.3/4. This must land **before** phase 2 widens content access.

Files: `S/domain/use_case/coordination_case.dart`,
`S/domain/use_case/beacon_fact_card_case.dart`, their unit tests under
`ST/domain/use_case/` (find them with `grep -rl "helpOffersWithCoordination\|BeaconFactCardCase" packages/server/test`).

Steps:
1. `CoordinationCase.helpOffersWithCoordination`: replace the existing
   `canReadContent` check with an involvement check:
   ```dart
   if (!await _guard.canReadInvolvement(beaconId: beaconId, viewerId: viewerId)) {
     throw const UnauthorizedException(
       description: 'Viewer cannot read request involvement',
     );
   }
   ```
   `can_read_involvement` already implies content read (m0124), so one check is
   enough. T04 makes the client stop calling this for uninvolved viewers. T03 and T04
   ship in the same release, so no client ever sees the new error in normal use.
2. `BeaconFactCardCase.list`: at the top, require content read. Inject
   `BeaconAccessGuard` if the class does not have it yet. The constructor is
   `@Injectable`, so run server `build_runner` afterwards. Add:
   ```dart
   if (!await _guard.canReadContent(beaconId: beaconId, viewerId: userId)) {
     throw const UnauthorizedException(description: 'Viewer cannot read request content');
   }
   ```
   Keep the existing room-visibility filtering exactly as it is.
3. Update the test doubles and mocks (`dart run build_runner build -d` in
   `packages/server` regenerates `*.mocks.dart`).
4. Unit tests:
   - a content reader without involvement gets `UnauthorizedException` from
     `helpOffersWithCoordination`;
   - an involved viewer still gets rows;
   - a stranger gets `UnauthorizedException` from both methods.
5. Superseded pg test: `beacon_hierarchy_visibility_pg_test.dart` › group
   "non-transitivity …" › `coordination_case helpOffersWithCoordination`. It stays a
   refusal for a hierarchy-only viewer, now through the involvement gate. It must
   still pass unchanged.

Done when: unit tests pass, the pg hierarchy suite is unchanged-green, and lints are
clean. Commit: `fix(server): gate help-offer list by involvement and facts by content`.

---

### T04 — Client: honest profile copy, and no involvement fetches for uninvolved viewers

Files:
- `packages/client/l10n/app_en.arb`, `packages/client/l10n/app_ru.arb`;
- `hasura/metadata.json`;
- `C/data/gql/schema.graphql`, `C/data/gql/beacon_model.graphql`;
- `C/domain/entity/beacon.dart`, `C/data/model/beacon_model.dart`;
- `C/features/beacon_view/ui/bloc/beacon_view_cubit.dart`;
- a test next to `CT/features/beacon_view/beacon_view_initial_load_test.dart`.

Steps:
1. **Copy.** Change only the *values* (keep keys and placeholders) of four strings:

   | Key | EN | RU |
   |---|---|---|
   | `profileVisibilityYouCanSee` | `{name} is in your trust network` | `Пользователь {name} — в вашей сети доверия` |
   | `profileVisibilityCantSeeYou` | `You aren't in {name}'s trust network yet` | `Вас пока нет в сети доверия пользователя {name}` |
   | `profileVisibilityTheyCanSeeYou` | `You're in {name}'s trust network` | `Вы — в сети доверия пользователя {name}` |
   | `profileVisibilityYouDontSeeThem` | `{name} isn't in your trust network yet` | `Пользователя {name} пока нет в вашей сети доверия` |

   Then run `flutter gen-l10n` and `bash scripts/check-user-facing-terminology.sh`.
   Update golden or text tests that assert the old strings. Find them with
   `grep -rn "can't see you yet\|don't currently see\|You can see\|can see you" packages/client/test`.
2. **Expose `can_read_involvement` to the `user` role.** In `hasura/metadata.json`,
   table `beacon`, open the `select_permissions` entry for role `user`, and append
   `"can_read_involvement"` to its `permission.computed_fields` array. The computed
   field already exists on the table. Do not touch the `filter`. Apply it locally with
   `./scripts/hasura_apply_metadata.sh`.
3. **Schema.** In `C/data/gql/schema.graphql`, in `type beacon`, add
   `can_read_involvement: Boolean` next to `can_read_content`, with the same
   docstring style. Add it to `beacon_bool_exp` and `beacon_order_by` next to the
   `can_read_content` entries too, mirroring them. If the local stack is running, you
   may instead re-fetch the schema by introspection, as long as the diff is limited to
   the new field.
4. **Fragment.** Add `can_read_involvement` to `fragment BeaconModel` in
   `C/data/gql/beacon_model.graphql`, below `can_read_content`.
5. **Entity.** In `C/domain/entity/beacon.dart`, add `@Default(true) bool canReadInvolvement,`
   (docstring: "Hasura computed field: viewer may see who is involved"). Map it in
   `C/data/model/beacon_model.dart` next to `canReadContent`:
   `canReadInvolvement: i.can_read_involvement ?? true,`. Run client `build_runner`.
6. **Cubit.** In `BeaconViewCubit._fetchBeaconByIdWithTimeline`, inside the
   `Future.wait([...])` list, replace these three entries when
   `!beacon.canReadInvolvement`:
   - `_case.fetchHelpOffersWithCoordination(beaconId: beaconId)` → `Future.value(const <…>[])`,
     using the exact record list type the cast below it expects;
   - `_case.fetchRoomStateIfAllowed(beaconId)` → `Future<BeaconRoomState?>.value()`;
   - `_case.fetchRoomActivityEvents(beaconId)` → `Future.value(const <BeaconActivityEvent>[])`.

   Keep the list order and the result casts unchanged. Authors and members always have
   `canReadInvolvement == true`, so their behavior is unchanged.
7. **Test:** a cubit test where the fetched beacon has `canReadInvolvement: false`
   asserts that the three case methods are never called and that the state loads
   successfully.

No version bump here. The whole issue ships as one release with a single bump
and a raised minimum client version (T16).

Done when: client tests for the touched features pass, client lints are clean,
terminology check passes, and the Hasura parity test still passes (`-t pg`). Commit:
`fix(client): honest trust-network copy; skip involvement fetches for observers`.

---

## Phase 1 — explicit access level (no behavior change)

### T05 — Shared access enums and the pure server policy

Files (new unless noted):
- `R/domain/entity/beacon_access.dart`;
- `R/test/domain/entity/beacon_access_test.dart` (path `test/domain/entity/` at repo root);
- `S/domain/beacon_access_policy.dart`;
- `ST/domain/beacon_access_policy_test.dart`.

Steps:
1. `R/domain/entity/beacon_access.dart` (pure Dart, no imports beyond `dart:core`):
   ```dart
   /// Viewer's access level to one request (issue #146 architecture §2.1).
   enum BeaconAccessLevel {
     author(0),
     member(1),
     observer(2),
     stranger(3);

     const BeaconAccessLevel(this.value);
     final int value;

     static BeaconAccessLevel fromInt(int? v) => switch (v) {
       0 => author,
       1 => member,
       2 => observer,
       _ => stranger,
     };

     bool get canReadContent => value <= 2;
     bool get isMember => value <= 1;
   }

   /// Why the viewer has access. Bit values are persisted contracts (never renumber).
   enum BeaconAccessReason {
     author(1),
     steward(2),
     admitted(4),
     forwarded(8),
     applied(16),
     discovered(32),
     contextChild(64),
     contextAncestor(128);

     const BeaconAccessReason(this.bit);
     final int bit;

     static Set<BeaconAccessReason> decode(int mask) =>
         {for (final r in values) if (mask & r.bit != 0) r};

     static int encode(Iterable<BeaconAccessReason> reasons) =>
         reasons.fold(0, (m, r) => m | r.bit);
   }

   BeaconAccessLevel beaconAccessLevelFromReasons(int mask) {
     if (mask & 1 != 0) return BeaconAccessLevel.author;
     if (mask & (2 | 4) != 0) return BeaconAccessLevel.member;
     if (mask & (8 | 16 | 32 | 64 | 128) != 0) return BeaconAccessLevel.observer;
     return BeaconAccessLevel.stranger;
   }
   ```
2. `S/domain/beacon_access_policy.dart`:
   - `class BeaconAccessFacts` with required fields: `BeaconStatus status`,
     `bool isBlocked`, `bool isAuthor`, `bool isSteward`, `bool isAdmitted`,
     `bool hasActiveForwardEdgeAsRecipient`, `bool isActiveHelpOfferer`,
     `bool isDiscoverable`, `bool isPublished`, `bool isTrustVisibleWithAuthor`,
     `bool isMemberOfImmediateParent`, `bool isMemberOfDescendant`.
   - `abstract final class BeaconAccessPolicy { static int reasons(BeaconAccessFacts f); static BeaconAccessLevel level(BeaconAccessFacts f); }`.

   `reasons` rules, in this order:
   1. `isBlocked` → 0;
   2. `draft` → `isAuthor ? author.bit : 0`;
   3. `deleted` → 0;
   4. otherwise OR together: author if `isAuthor`; steward if `isSteward`; admitted
      if `isAdmitted`; forwarded if `hasActiveForwardEdgeAsRecipient`; applied if
      `isActiveHelpOfferer`; discovered if `isDiscoverable && isPublished && status.isOpenFamily && isTrustVisibleWithAuthor`;
      contextChild if `isPublished && isMemberOfImmediateParent`; contextAncestor if
      `isPublished && isMemberOfDescendant`.

   `level` = `beaconAccessLevelFromReasons(reasons(f))`.

   **Phase-1 contract:** the caller passes `false` for the two context facts until T09.
   Put that in a doc comment.
3. Tests:
   - root: encode/decode round-trip for all 256 masks; `beaconAccessLevelFromReasons`
     for each single bit and for 0.
   - server `beacon_access_policy_test.dart`: an **exhaustive** sweep over every
     combination of the 11 booleans (2¹¹ = 2048) × all 8 statuses. Assert:
     - **S4-11:** context facts alone never give a level ≤ 1;
     - **S4-02:** `isBlocked` → stranger;
     - drafts give author or stranger only; deleted gives stranger;
     - **parity with today:** with both context facts false **and `isBlocked == false`**
       (`BeaconContentVisibilityFacts` has no block field; SQL applies blocks first),
       `level(f).canReadContent == BeaconVisibility.canReadContent(<matching BeaconContentVisibilityFacts>)`,
       with `isRoomAdmittedOrSteward = isSteward || isAdmitted`,
       `isMutuallyVisibleWithAuthor = isTrustVisibleWithAuthor`, and the other fields
       mapped 1:1;
     - **S4-01 (monotonicity):** turning any one non-block fact from false to true
       never raises the level number.

Done when: root and server unit tests pass. Commit:
`feat(server): add explicit beacon access level policy`.

---

### T06 — SQL: member view, reasons and level (existing reasons only)

Files: new `MIG/m0170.dart`; `MIG/_migrations.dart` (add `part 'm0170.dart';` and
append `m0170` to `_allMigrations`); new `ST/data/repository/beacon_access_level_parity_pg_test.dart`.

`m0170` contents (one string per statement, like `m0155.dart`):

```sql
-- 1. Eligible membership: the ONLY definition of "member" used by context and bond.
CREATE OR REPLACE VIEW public.beacon_member AS
SELECT b.id AS beacon_id, b.user_id AS user_id
FROM public.beacon b
WHERE b.user_id IS NOT NULL
  AND b.status NOT IN (2, 3)
  AND b.published_at IS NOT NULL
UNION ALL
SELECT bs.beacon_id, bs.user_id
FROM public.beacon_steward bs
JOIN public.beacon b ON b.id = bs.beacon_id
WHERE b.status NOT IN (2, 3)
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(b.user_id, bs.user_id)
UNION ALL
SELECT bp.beacon_id, bp.user_id
FROM public.beacon_participant bp
JOIN public.beacon b ON b.id = bp.beacon_id
WHERE (bp.role = 1 OR bp.room_access = 3)
  AND b.status NOT IN (2, 3)
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(b.user_id, bp.user_id);
```

```sql
-- 2. Reason bitmask (phase 1: bits 0..5 only).
CREATE OR REPLACE FUNCTION public.beacon_access_reasons(
  p_beacon_id text,
  p_viewer_id text
) RETURNS integer
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN nullif(btrim(coalesce(p_viewer_id, '')), '') IS NULL THEN 0
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN 0
    WHEN b.status = 3 THEN CASE WHEN b.user_id = p_viewer_id THEN 1 ELSE 0 END
    WHEN b.status = 2 THEN 0
    ELSE
        (CASE WHEN b.user_id = p_viewer_id THEN 1 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_steward bs
            WHERE bs.beacon_id = b.id AND bs.user_id = p_viewer_id
          ) OR EXISTS (
            SELECT 1 FROM public.beacon_participant bp
            WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer_id AND bp.role = 1
          ) THEN 2 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_participant bp
            WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer_id AND bp.room_access = 3
          ) THEN 4 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_forward_edge fe
            WHERE fe.beacon_id = b.id AND fe.recipient_id = p_viewer_id
              AND fe.cancelled_at IS NULL
          ) THEN 8 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_help_offer ho
            WHERE ho.beacon_id = b.id AND ho.user_id = p_viewer_id AND ho.status = 0
          ) THEN 16 ELSE 0 END)
      | (CASE WHEN b.is_discoverable
            AND b.status IN (0, 7, 8)
            AND b.published_at IS NOT NULL
            AND b.user_id IS NOT NULL
            AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')
          THEN 32 ELSE 0 END)
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), 0);
$$;
```

```sql
-- 3. Level derived from reasons.
CREATE OR REPLACE FUNCTION public.beacon_access_level(
  p_beacon_id text,
  p_viewer_id text
) RETURNS integer
  LANGUAGE sql
  STABLE
  AS $$
SELECT CASE
  WHEN r & 1 <> 0 THEN 0
  WHEN r & 6 <> 0 THEN 1
  WHEN r & 248 <> 0 THEN 2
  ELSE 3
END
FROM (SELECT public.beacon_access_reasons(p_beacon_id, p_viewer_id) AS r) s;
$$;
```

```sql
-- 4. Hasura wrappers (table + session arguments, same shape as beacon_get_can_read_linked_detail).
CREATE OR REPLACE FUNCTION public.beacon_get_access_level(
  beacon_row public.beacon, hasura_session json
) RETURNS integer LANGUAGE sql STABLE AS $$
SELECT public.beacon_access_level(beacon_row.id, (hasura_session ->> 'x-hasura-user-id')::text);
$$;

CREATE OR REPLACE FUNCTION public.beacon_get_access_reasons(
  beacon_row public.beacon, hasura_session json
) RETURNS integer LANGUAGE sql STABLE AS $$
SELECT public.beacon_access_reasons(beacon_row.id, (hasura_session ->> 'x-hasura-user-id')::text);
$$;
```

```sql
-- 5. Index for member lookups by user (author branch).
CREATE INDEX IF NOT EXISTS beacon_user_id_published_idx
  ON public.beacon (user_id) WHERE published_at IS NOT NULL;
```

Before step 5, check with `grep -n "ON public.beacon (user_id" MIG/*.dart` whether an
index on `beacon(user_id)` already exists. If it does, drop step 5 and record that.

**Parity test** (`-t pg`, disposable DB via `BeaconHierarchyDisposablePgTarget`, the
same setup as `beacon_hierarchy_visibility_pg_test.dart`):
- Seed users × one request per status. Cover the author, a steward (a `beacon_steward`
  row **plus** a participant with `role = 1`, as production writes both;
  `BeaconRoomRepository.setBeaconSteward`), an admitted participant, a forward
  recipient, a forward sender only, an active help offerer, a withdrawn offerer, a
  discoverable + trust-visible viewer, a stranger, and a blocked viewer.
- Assert for every (beacon, viewer):
  - `beacon_access_level <= 2` ⇔ `beacon_can_read_content`;
  - for non-deleted beacons, `beacon_access_level <= 1` ⇔ `beacon_effective_admission`;
  - `beacon_access_reasons` equals `BeaconAccessPolicy.reasons(facts)` for the same
    facts (context facts `false`).
- Assert `beacon_member` excludes a draft author row, a deleted beacon's participants,
  and a participant blocked by the owner.

Done when: the parity test passes (not skipped) and the existing
`beacon_access_sql_parity_test.dart` passes. Commit:
`feat(server): add beacon_member view and access level SQL`.

---

### T07 — Expose access level and reasons (no UI use yet)

Files: `hasura/metadata.json`, `C/data/gql/schema.graphql`,
`C/data/gql/beacon_model.graphql`, `C/domain/entity/beacon.dart`,
`C/data/model/beacon_model.dart`, `ST/api/beacon_hierarchy_hasura_parity_test.dart`
(or a new `ST/api/beacon_access_hasura_test.dart`).

Steps:
1. Metadata, table `beacon`, `computed_fields`: add two entries shaped exactly like
   the `can_read_linked_detail` entry:
   - `{"name": "access_level", "definition": {"function": {"name": "beacon_get_access_level", "schema": "public"}, "session_argument": "hasura_session", "table_argument": "beacon_row"}}`
   - `{"name": "access_reasons", …"beacon_get_access_reasons"…}`

   Append `"access_level"` and `"access_reasons"` to the `user` role
   `select_permissions[].permission.computed_fields`. Apply locally.
2. Schema: add `access_level: Int` and `access_reasons: Int` to `type beacon` (and to
   the bool_exp/order_by types, mirroring `can_read_content`).
3. Fragment `BeaconModel`: add `access_level` and `access_reasons`.
4. Entity `Beacon`: add `BeaconAccessLevel? accessLevel` (null only for `Beacon`
   values built locally without a server fetch, for example in create flows and test
   fixtures; every `BeaconModel` fetch sets it) and `@Default(0) int accessReasons`. Import from
   `package:tentura_root/domain/entity/beacon_access.dart`. Mapper:
   `accessLevel: i.access_level == null ? null : BeaconAccessLevel.fromInt(i.access_level)`,
   `accessReasons: i.access_reasons ?? 0`. Run `build_runner`.
5. Hasura test (`-t pg`, real user-session query, not admin): for the forward
   recipient fixture, `beacon_by_pk { access_level access_reasons can_read_involvement }`
   returns `2`, `8`, `true`. For the author, `0`, `1`, `true`.

Done when: the Hasura test passes, client builds (`build_runner`), and lints are clean.
Commit: `feat: expose beacon access level and reasons`.

---

## Phase 2 — hierarchy context (D1, D2, D5, D6)

### T08 — Ancestor closure table

Files: new `MIG/m0171.dart` (**this task writes only the closure part; T09 appends to
the same migration file before either is committed**, so m0171 lands as one
migration), `ST/data/repository/beacon_ancestor_pg_test.dart`.

SQL (first statements of `m0171`):

```sql
CREATE TABLE IF NOT EXISTS public.beacon_ancestor (
  beacon_id   text    NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  ancestor_id text    NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  depth       integer NOT NULL CHECK (depth >= 1),
  CONSTRAINT beacon_ancestor_pkey PRIMARY KEY (beacon_id, ancestor_id)
);

CREATE INDEX IF NOT EXISTS beacon_ancestor_ancestor_idx
  ON public.beacon_ancestor (ancestor_id);

CREATE INDEX IF NOT EXISTS beacon_parent_beacon_id_idx
  ON public.beacon (parent_beacon_id) WHERE parent_beacon_id IS NOT NULL;

REVOKE ALL ON TABLE public.beacon_ancestor FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.beacon_ancestor_on_insert()
RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF NEW.parent_beacon_id IS NULL THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.beacon_ancestor (beacon_id, ancestor_id, depth)
  SELECT NEW.id, NEW.parent_beacon_id, 1
  UNION ALL
  SELECT NEW.id, a.ancestor_id, a.depth + 1
  FROM public.beacon_ancestor a
  WHERE a.beacon_id = NEW.parent_beacon_id
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beacon_ancestor_on_insert_trg ON public.beacon;

CREATE TRIGGER beacon_ancestor_on_insert_trg
  AFTER INSERT ON public.beacon
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_ancestor_on_insert();

WITH RECURSIVE chain AS (
  SELECT b.id AS beacon_id, b.parent_beacon_id AS ancestor_id, 1 AS depth
  FROM public.beacon b
  WHERE b.parent_beacon_id IS NOT NULL
  UNION ALL
  SELECT c.beacon_id, p.parent_beacon_id, c.depth + 1
  FROM chain c
  JOIN public.beacon p ON p.id = c.ancestor_id
  WHERE p.parent_beacon_id IS NOT NULL
)
INSERT INTO public.beacon_ancestor (beacon_id, ancestor_id, depth)
SELECT beacon_id, ancestor_id, depth FROM chain
ON CONFLICT DO NOTHING;
```

Parentage is immutable (m0154 `beacon_parent_beacon_id_update_guard`), so there is
no UPDATE trigger. Do not add one.

Tests (`-t pg`), on topology A→B→C, A→D:
- after the migration, rows are exactly (B,A,1), (C,B,1), (C,A,2), (D,A,1);
- inserting a new child E under C adds (E,C,1), (E,B,2), (E,A,3);
- hard-deleting a draft child removes its rows (cascade).

Done when: the tests pass. **Do not commit yet.** Continue with T09 in the same
working state (m0171 must be a single migration). Record "T08 done, uncommitted" in
the journal.

---

### T09 — Context reasons and widened content read

Files: `MIG/m0171.dart` (append), `S/domain/beacon_visibility.dart`,
`S/domain/beacon_access_policy.dart` (doc comment only), tests listed below.

Append to `m0171`:

1. **Redefine `beacon_can_read_content`.** Copy the **exact** current body from
   `MIG/m0169.dart` (the first statement). Then insert these three `WHEN` clauses
   immediately **before** `ELSE false`, in this order:
   ```sql
       WHEN EXISTS (
         SELECT 1 FROM public.beacon_steward bs
         WHERE bs.beacon_id = p_beacon_id AND bs.user_id = p_viewer_id
       ) THEN true
       -- contextChild: member of the immediate parent (D1)
       WHEN b.parent_beacon_id IS NOT NULL
         AND b.published_at IS NOT NULL
         AND EXISTS (
           SELECT 1 FROM public.beacon_member m
           WHERE m.beacon_id = b.parent_beacon_id
             AND m.user_id = p_viewer_id
         ) THEN true
       -- contextAncestor: member of some descendant (D1)
       WHEN b.published_at IS NOT NULL
         AND EXISTS (
           SELECT 1
           FROM public.beacon_member m
           JOIN public.beacon_ancestor a ON a.beacon_id = m.beacon_id
           WHERE m.user_id = p_viewer_id
             AND a.ancestor_id = b.id
         ) THEN true
   ```
   The steward clause aligns content read with `beacon_effective_admission`, which
   already honors `beacon_steward` rows. Record it in the journal as an intentional
   alignment.
2. **Redefine `beacon_access_reasons`.** Same body as m0170, plus two more OR terms
   before the closing `END`:
   ```sql
      | (CASE WHEN b.parent_beacon_id IS NOT NULL AND b.published_at IS NOT NULL
            AND EXISTS (SELECT 1 FROM public.beacon_member m
                        WHERE m.beacon_id = b.parent_beacon_id AND m.user_id = p_viewer_id)
          THEN 64 ELSE 0 END)
      | (CASE WHEN b.published_at IS NOT NULL
            AND EXISTS (SELECT 1 FROM public.beacon_member m
                        JOIN public.beacon_ancestor a ON a.beacon_id = m.beacon_id
                        WHERE m.user_id = p_viewer_id AND a.ancestor_id = b.id)
          THEN 128 ELSE 0 END)
   ```
   `beacon_access_level` needs no change.
3. **Alias the old linked-detail predicate:**
   ```sql
   CREATE OR REPLACE FUNCTION public.beacon_can_read_linked_detail(
     p_beacon_id text, p_viewer_id text
   ) RETURNS boolean LANGUAGE sql STABLE AS $$
   SELECT public.beacon_can_read_content(p_beacon_id, p_viewer_id);
   $$;
   ```
   The alias only keeps T01/T02 server code and the existing tests working until T10.
   T10 removes every caller and drops it.
4. **Register** `m0171` (`part` + `_allMigrations`).

Dart:
5. `S/domain/beacon_visibility.dart`: add two fields to `BeaconContentVisibilityFacts`
   with defaults, `this.isMemberOfImmediateParent = false` and
   `this.isMemberOfDescendant = false`, and OR them into `canReadContent` just before
   the discoverability term. Keep `canReadLinkedDetail` for now; T10 deletes it.
6. Update the `BeaconAccessPolicy` doc comment: context facts are live from m0171.

Tests:
7. New `ST/data/repository/shared_context_visibility_pg_test.dart` (`-t pg`,
   topology A→B→C, A→D). Use explicit fixtures: `alice` member of A only; `bob` member
   of B only; `carol` member of C only; `frank` stranger. Assert
   `beacon_can_read_content` and `beacon_access_reasons`:

   | Viewer | A | B | C | D |
   |---|---|---|---|---|
   | alice (A) | member | contextChild ✅ | ❌ (grandchild) | contextChild ✅ |
   | bob (B) | contextAncestor ✅ | member | contextChild ✅ | ❌ (sibling) |
   | carol (C) | contextAncestor ✅ | contextAncestor ✅ | member | ❌ |
   | frank | ❌ | ❌ | ❌ | ❌ |

   Plus:
   - **S4-10:** after bob leaves B (`room_access = 5`), bob has no access to A, B or C
     and no context bits anywhere;
   - B's owner blocks bob → bob loses access to A and C through B;
   - B deleted → carol loses contextAncestor on B (deleted) *and* bob's membership of
     B grants nothing;
   - a draft child never grants context: a user who authored a *draft* child of A and
     then left A has no access to A (no bit 128; drafts are excluded from `beacon_member`);
   - **S4-14:** bob is not an observer of D (a sibling);
   - **D2:** a context observer can offer help on an open-family child and can forward
     it. Call `HelpOfferCase` and `ForwardCase` through `HierarchyOnlyViewerHarness`.
8. **Superseded tests.** Update these to the new rule; rename them to say what they
   now assert:
   - `ST/data/repository/beacon_hierarchy_visibility_pg_test.dart`:
     - `no transitive linked-detail grant across grandchild` → the grandparent member
       still does **not** see the grandchild; the grandchild member **does** see the
       grandparent (contextAncestor);
     - group `non-transitivity — production call sites refuse hierarchy-only viewer`
       → rename to `hierarchy context observer is an ordinary observer (D2)`. Help
       offer, forward, lineage and invitation now **succeed** for an open-family child.
       `helpOffersWithCoordination` still throws `UnauthorizedException`, because a
       context observer is not involved (T03);
     - `forward_case forward cannot mint child content access` → now asserts the
       forward succeeds and the recipient becomes a `forwarded` observer. The recipient
       gains **no** context bits (S4-10: context comes only from membership);
     - `block hides linked detail in both directions` and
       `revoked parent admission removes linked detail without residue` → keep them,
       asserting on `beacon_can_read_content`.
   - `ST/domain/beacon_visibility_test.dart` group `BeaconVisibility.canReadLinkedDetail`
     → rewrite as `canReadContent` context-fact tests (the grant now **does** change
     `canReadContent`).
   - `ST/api/beacon_hierarchy_hasura_parity_test.dart`: a user-session
     `beacon_by_pk` for bob on A now returns the row, with `access_level = 2` and
     `access_reasons = 128`. The same test must stop asserting the
     `can_read_linked_detail` metadata field; T10 removes it.
9. Extend the T06 parity test to set context facts from the fixture. SQL reasons must
   still equal `BeaconAccessPolicy.reasons`.
10. **Performance gate.** On a local DB with the hierarchy fixture plus `seed_society`
    data if available (`scripts/seed_society`), run
    `EXPLAIN (ANALYZE, BUFFERS) SELECT public.beacon_can_read_content(<id>, <viewer>)`
    for a stranger on a root with ≥ 20 descendants, and on the SQL behind the Inbox
    and My Work lists (copy them from their `.graphql` files via Hasura's
    "Analyze"/generated SQL, or run the Hasura query with `x-hasura-role: user`).
    Record timings before and after m0171 in the journal. **Stop and report** if any
    list query slows by more than 2× or the single-row predicate exceeds 2 ms. Do not
    optimize on your own.

Done when: all listed tests pass (none skipped), the performance numbers are
recorded, and lints are clean. Commit T08 + T09 together:
`feat(server): hierarchy context grants observer access (issue #146)`.

---

### T10 — Hierarchy endpoints use the unified predicate; delete linked-detail code

Files: `S/data/repository/beacon_hierarchy_repository.dart`,
`S/domain/policy/beacon_hierarchy_policy.dart`, `S/domain/beacon_visibility.dart`,
`S/domain/port/beacon_access_guard.dart`, `S/data/repository/beacon_access_repository.dart`,
`hasura/metadata.json`, new `MIG/m0172.dart` (+ registration), and their tests and
mocks. T11's bond migration is therefore `m0173`.

Steps:
1. In `listChildren` and `loadParentReference`, replace every
   `beacon_can_read_linked_detail` call with `beacon_can_read_content` (equivalent
   since T09).
2. **Capabilities.** Change `loadCapabilities` / `resolveCapabilities` so that
   `canListChildren` is true when the viewer can read the parent's content, and
   `canCreateChild` is unchanged (effective admission + `allowsCoordination`):
   - add `required bool viewerCanReadParentContent` to `BeaconHierarchyCapabilityFacts`;
   - compute it in `loadCapabilities` with `beacon_can_read_content(parent, viewer)`;
   - in `resolveCapabilities`, keep the draft and deleted checks first; then, if the
     viewer is not admitted, return
     `BeaconHierarchyCapabilities(canListChildren: facts.viewerCanReadParentContent, canCreateChild: false, denialCode: BeaconHierarchyDenialCode.notAdmitted)`.
     The admitted path is unchanged.
   - Update `ST/domain/beacon_hierarchy_policy_test.dart`: an observer can list but
     not create.
3. **Delete the linked-detail Dart code:** `BeaconVisibility.canReadLinkedDetail`,
   `BeaconLinkedDetailVisibilityFacts`, `BeaconAccessGuard.canReadLinkedDetail`, and
   `BeaconAccessRepository.canReadLinkedDetail`. Then delete the tests that only
   covered them (their behavior is now covered by T09's tests). Regenerate mocks.
4a. **Drop the linked-detail SQL and Hasura field.**
   - `hasura/metadata.json`: remove the `can_read_linked_detail` entry from table
     `beacon` → `computed_fields`. It is not in any role's permission list. Afterwards
     `grep -n can_read_linked_detail hasura/metadata.json` must print nothing.
   - `MIG/m0172.dart`:
     ```sql
     DROP FUNCTION IF EXISTS public.beacon_get_can_read_linked_detail(public.beacon, json);
     DROP FUNCTION IF EXISTS public.beacon_can_read_linked_detail(text, text);
     ```
   - Remove `can_read_linked_detail` from `C/data/gql/schema.graphql` (type, bool_exp
     and order_by entries). The client never selects it; confirm with
     `grep -rn can_read_linked_detail packages/client/lib --include=*.graphql --include=*.dart | grep -v _g/`.
   - Delete or update every server test that still references the function or field
     (`grep -rn "linked_detail\|LinkedDetail" packages/server`).
   - Deploy order is safe: `deploy.sh` starts the server, which runs migrations, and
     then applies `hasura/metadata.json`. Locally, apply the metadata right after the
     migration (`./scripts/hasura_apply_metadata.sh`).
4. If `BeaconHierarchyPolicy.isAdmittedToImmediateParent` or
   `isAdmittedToImmediatePublishedChild` have no production callers left
   (`grep -rn` in `S/`), delete them with their tests. Otherwise leave them.
5. Client: nothing to change. The children section shows when `canListChildren` is
   true, and the create action already follows `canCreateChild`. Verify with
   `grep -rn "canCreateChild\|canListChildren" packages/client/lib`, and record any
   surprise.

Done when: server unit and pg suites for hierarchy/visibility pass, the Hasura
metadata applies with no inconsistencies, no reference to `linked_detail` remains
outside migration history (`m0155`, `m0171`) and docs, and lints are clean. Commit:
`refactor: hierarchy reads use the unified content predicate; drop linked-detail`.

---

## Phase 3 — co-participant bond (D3, D4)

### T11 — Bond SQL and server consumers

Files: new `MIG/m0173.dart` (+ registration); `S/domain/port/person_visibility_repository_port.dart`
(find it with `grep -rn "abstract class PersonVisibilityRepositoryPort" packages/server/lib`);
`S/data/repository/person_visibility_repository.dart`;
`S/domain/port/forward_candidates_repository_port.dart` (find it the same way);
`S/data/repository/forward_candidates_repository.dart`;
`S/domain/use_case/forward_candidates_case.dart`; `S/domain/use_case/forward_case.dart`;
`S/domain/entity/gql_public/user_public_record.dart`;
`S/api/controllers/graphql/custom_types.dart` (`gqlTypeUserPublic`);
`S/api/controllers/graphql/mappers/gql_public_user_maps.dart`; tests.

`m0173` SQL:

```sql
CREATE OR REPLACE FUNCTION public.person_bond(a_id text, b_id text)
RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT nullif(btrim(coalesce(a_id, '')), '') IS NOT NULL
  AND nullif(btrim(coalesce(b_id, '')), '') IS NOT NULL
  AND a_id <> b_id
  AND NOT public.block_hides(a_id, b_id)
  AND EXISTS (
    SELECT 1
    FROM public.beacon_member ma
    JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
    JOIN public.beacon b ON b.id = ma.beacon_id
    WHERE ma.user_id = a_id
      AND mb.user_id = b_id
      AND b.status IN (0, 5, 7, 8)
  );
$$;

CREATE OR REPLACE FUNCTION public.person_bond_peers(p_viewer_id text)
RETURNS TABLE (peer_id text)
  LANGUAGE sql
  STABLE
  AS $$
SELECT DISTINCT mb.user_id::text
FROM public.beacon_member ma
JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
JOIN public.beacon b ON b.id = ma.beacon_id
WHERE ma.user_id = p_viewer_id
  AND mb.user_id <> p_viewer_id
  AND b.status IN (0, 5, 7, 8)
  AND NOT public.block_hides(p_viewer_id, mb.user_id);
$$;

CREATE OR REPLACE FUNCTION public.person_shared_contexts(p_viewer_id text, p_peer_id text)
RETURNS TABLE (beacon_id text, title text)
  LANGUAGE sql
  STABLE
  AS $$
SELECT DISTINCT ON (b.id) b.id::text, b.title::text
FROM public.beacon_member ma
JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
JOIN public.beacon b ON b.id = ma.beacon_id
WHERE ma.user_id = p_viewer_id
  AND mb.user_id = p_peer_id
  AND p_viewer_id <> p_peer_id
  AND b.status IN (0, 5, 7, 8)
  AND NOT public.block_hides(p_viewer_id, p_peer_id)
ORDER BY b.id
LIMIT 20;
$$;
```

**Do not** change `person_are_mutually_visible`, `person_visible_peers_symmetric`,
`constellation_trust_edges`, or the D11 clause (D4).

Dart:
1. `PersonVisibilityRepositoryPort`: add
   - `Future<Set<String>> bondPeerIds({required String viewerId})` (from `person_bond_peers`);
   - `Future<Set<String>> personVisiblePeerIds({required String viewerId, required Iterable<String> peerIds, required String context})`,
     which returns the union of `mutuallyVisiblePeerIds(...)` and the candidates where
     `person_bond($1, peer)` is true. Implement it as one SQL:
     ```sql
     SELECT DISTINCT c.peer_id
     FROM unnest($3::text[]) AS c(peer_id)
     WHERE c.peer_id <> $1
       AND NOT public.block_hides($1, c.peer_id)
       AND (public.person_are_mutually_visible($1, c.peer_id, $2)
            OR public.person_bond($1, c.peer_id))
     ```
   - `Future<List<({String beaconId, String title})>> sharedContexts({required String viewerId, required String peerId})`.
2. `ForwardCase` (the recipient check around the current `mutuallyVisiblePeerIds`
   call, near line 237): switch to `personVisiblePeerIds` with the same arguments.
   Leave `CapabilityProjectionCase._canViewSubject` on the trust-only method
   (architecture rev 3 §6.2: deferred).
3. `ForwardCandidatesCase.fetch`:
   - keep `fetchVisiblePeers` (trust) unchanged;
   - also call `_personVisibility.bondPeerIds(viewerId: viewerId)`. Inject the port if
     the case does not have it yet, then run server `build_runner`;
   - for each bond peer not already in the trust rows, add a
     `ForwardCandidatePeerRow(peerId: id, forwardMr: 0, reverseMr: 0, viewerTrusts: false, trustsViewer: false)`;
   - build the result as today. Set the new `UserPublicRecord.sharesActiveContext` to
     true for every id in the bond set, trust rows included.
4. `UserPublicRecord`: add `final bool sharesActiveContext;` with a constructor
   default `false`. `gqlTypeUserPublic`: add
   `field('shares_active_context', graphQLBoolean)` (nullable, so other producers
   stay valid). `userPublicToGqlMap`: add `'shares_active_context': u.sharesActiveContext`.
5. Tests:
   - `-t pg` `ST/data/repository/person_bond_pg_test.dart`:
     - **S4-12:** bond exists while the shared request is open/reviewOpen and ends at
       closed/cancelled/deleted; ends when one side leaves; blocks kill it; it is
       symmetric;
     - `person_bond_peers` matches `person_bond` over the fixture;
     - `person_shared_contexts` lists only active shared requests.
   - **S4-13 (`-t pg`):** a bond with an author does not make that author's
     *discoverable* unrelated request readable (`beacon_can_read_content` false,
     no bit 32).
   - Unit: `ForwardCandidatesCase` merges bond-only peers and flags them; `ForwardCase`
     accepts a bond-only recipient and rejects a stranger.

Done when: the tests pass and lints are clean. Commit:
`feat(server): co-participant bond widens person visibility for forwarding`.

---

### T12 — V2 query `personSharedContexts`

Files: new `S/domain/use_case/person_context_case.dart` (`@Injectable`, uses
`PersonVisibilityRepositoryPort`); new
`S/api/controllers/graphql/query/query_person_shared_contexts.dart`;
`S/api/controllers/graphql/query/_queries_all.dart`; `custom_types.dart`;
server `build_runner`; a GraphQL contract test next to
`ST/api/beacon_hierarchy_graphql_contract_test.dart`.

Steps:
1. Type `gqlTypePersonSharedContext = GraphQLObjectType('PersonSharedContext', null)`
   with non-null fields `beaconId: String` and `title: String`.
2. Root field `personSharedContexts(userId: String!): [PersonSharedContext!]!`.
   The resolver takes the viewer from `getCredentials(args).sub` and calls
   `PersonContextCase.sharedContexts(viewerId, peerId)`. Return `[]` when
   `viewerId == userId`.
3. Mirror the structure of `QueryBeaconHierarchy.beaconParentReference` exactly
   (input field class, `GetIt` default in the constructor, registration in `_queries_all.dart`).
4. Contract test: the schema exposes the field and types. A resolver test with a mocked
   case returns the mapped list.

Done when: tests pass and lints are clean. Commit:
`feat(server): personSharedContexts query`.

---

### T13 — Client: bond-aware reachability and profile

Files:
- `C/data/gql/schema.graphql` (add `shares_active_context: Boolean` to `type v2_user`;
  add root field `personSharedContexts(userId: String!): [v2_PersonSharedContext!]!`
  and `type v2_PersonSharedContext { beaconId: String! title: String! }`, next to the
  other `v2_` entries);
- `C/data/gql/user_public_model.graphql` (add `shares_active_context`);
- `C/domain/entity/profile.dart` (`@Default(false) bool sharesActiveContext`);
- `C/data/model/user_public_model.dart` (map `i.shares_active_context ?? false`);
- `C/features/forward/domain/entity/forward_candidate.dart`
  (`isReachable => profile.isMutuallyVisible || profile.sharesActiveContext`);
- new `C/features/profile_view/data/gql/person_shared_contexts.graphql`;
- new port `C/features/profile_view/domain/port/person_shared_context_port.dart`
  and repository `C/features/profile_view/data/repository/person_shared_context_repository.dart`
  (`@Singleton(as: …)`, returns `List<({String beaconId, String title})>`);
- `C/data/service/remote_api_client/build_client.dart`: add `'PersonSharedContexts'`
  to `_tenturaDirectOperationNames`;
- `C/features/profile_view/domain/use_case/profile_view_case.dart`: fetch shared
  contexts in `load`, best-effort like `subjectiveTags` (on error use `[]`), and add
  `sharedContexts` to `ProfileViewSnapshot`;
- the profile view state and cubit that carry the snapshot;
- `C/ui/model/person_action_policy.dart`;
- `C/features/profile_view/ui/widget/profile_view_body.dart`;
- `packages/client/l10n/app_en.arb`, `app_ru.arb`.

Steps:
1. GraphQL: `query PersonSharedContexts($userId: String!) { personSharedContexts(userId: $userId) { beaconId title } }`.
2. `PersonActionPolicy.from(...)`: add an optional parameter
   `bool sharesActiveContext = false`. In `_baseFrom`, set
   `isMutuallyVisible = profile.isMutuallyVisible || sharesActiveContext`. If trust is
   not mutual but `sharesActiveContext` is true, `visibilityState` is a new enum value
   `PersonVisibilityState.sharedContext`. Otherwise keep today's states. Add policy
   unit tests.
3. `profile_view_body.dart`: pass `sharesActiveContext: sharedContexts.isNotEmpty`.
   In `_ProfileVisibilitySection._directionalLines`, handle `sharedContext` with two
   lines:
   - `profileVisibilitySharedContext(title)`: EN `You're working together on «{title}»`,
     RU `Вы работаете вместе над «{title}»`. Use the first shared context's title;
   - `profileVisibilitySharedContextNote`: EN `You can see each other until reviews for this request close.`,
     RU `Вы видите друг друга, пока не закончатся отзывы по этому запросу.`

   Add both keys with `@` metadata, like the neighbouring keys. Keep the design-system
   styling of the existing lines; do not add raw styles.
4. `graph_person_context_panel.dart` stays trust-only in this issue. Add a
   `// issue-146: bond not shown here yet` comment only if a reviewer would otherwise
   wonder; do not change behavior.
5. Run `build_runner`, `flutter gen-l10n`, and the terminology check.
6. Tests: `ForwardCandidate.isReachable` for a bond-only profile; the profile view
   cubit/case loads shared contexts and survives a failing fetch; a widget test shows
   the shared-context line.

Done when: client tests for forward/profile pass and lints are clean. Commit:
`feat(client): show co-participant bond on profile and in forwarding`.

---

## Phase 4 — client UX, docs, release

### T14 — Observer reason banner

Files: new `C/features/beacon_view/ui/widget/request_access_reason_banner.dart`;
`C/features/beacon_view/ui/widget/beacon_operational_header_card.dart` (next to
`ClosedRequestBanner(beacon: state.beacon)`); arb files; a widget test.

Steps:
1. The widget takes a `Beacon`. It renders nothing unless
   `beacon.accessLevel == BeaconAccessLevel.observer`. Otherwise it decodes
   `BeaconAccessReason.decode(beacon.accessReasons)` and picks one line by priority:
   - applied → nothing (existing "waiting for author" UI covers it);
   - forwarded → nothing (existing inbox provenance covers it);
   - contextChild or contextAncestor → `requestAccessViaRelatedRequest`: EN
     `You can see this request because you take part in a related request.`, RU
     `Вы видите этот запрос, потому что участвуете в связанном запросе.`;
   - discovered → nothing in this issue.
2. Mirror `ClosedRequestBanner`'s structure and design-system tokens (`context.tt`,
   `TenturaText.*`). No raw colors, sizes or insets (lints enforce this).
3. Widget tests: shown for a context observer; hidden for member, author, and
   forwarded-only observer.

Naming the related request in the banner is out of scope (architecture rev 3 §7.5
allows generic copy).

Done when: the widget tests pass, and client lints plus terminology checks are clean.
Commit: `feat(client): explain hierarchy-context access on the request view`.

---

### T15 — Documentation

Files: `docs/adr/0008-beacon-visibility-and-invite-sharing.md`,
`docs/beacon-visibility-matrix.md`, `CONTEXT.md`,
`docs/plans/nested-requests-implementation-plan.md` (pointer only), the architecture
doc (status line).

Steps:
1. ADR 0008: append `## Amendment B (2026-09-XX): shared-context visibility (#146)`
   with Context, Decision (D1–D8 in one paragraph each at most), and Consequences.
   Replace the last sentence of "Related: beacon nesting" with a pointer to
   Amendment B.
2. Matrix: replace the rows "Parent-only admittee viewing child content" and
   "Child-only admittee viewing parent content" with context-observer rows. Replace
   the "Linked-detail predicate" section with an "Access level and reasons" section:
   the bit table from §0.4 and the rights table from architecture §5. Update "Source
   files" (m0170–m0173).
3. `CONTEXT.md`: in § Beacon visibility & sharing, add the context reasons to the
   list, and replace § Linked-detail visibility with a short "Shared context" paragraph
   (hierarchy reasons + bond, with D4).
4. Nested plan §3.2: add one line at the top of §3.2: "Superseded by
   issue-146 shared-context visibility architecture (D1/D2)."
5. Architecture doc: status → `implemented (rev 4)` once T16 passes.

Done when: the docs render (Markdown tables intact) and terminology check passes.
Commit: `docs: record shared-context visibility (ADR 0008 amendment B)`.

---

### T16 — Release gate

Steps:
1. Bump the client version: **minor** in `packages/client/pubspec.yaml` (new
   user-visible capability). Sync `packages/client/web/index.html` `?v=`. This is the
   only client version bump in the whole issue.
2. **Raise the minimum client version (mandatory).** Set `kDefaultMinClientVersion`
   in `S/env.dart` to exactly the version from step 1. Sync `.env.example` if it has
   the commented example. Follow `DEV_GUIDELINES.md` § Client version gate. This is
   what allows the plan to skip legacy-client support: after deploy, every browser
   reloads onto the new build.
3. Full verification (§0.2): server unit suite, the server pg suites touched by this
   plan, client full suite (45m timeout), both lint runs, terminology check.
4. Manual QA on the local stack (`local-debug` skill): reproduce the #146 scenarios
   with three users on a parent/child pair:
   - an admitted parent helper opens every listed child (observer view, reason banner,
     Offer help works);
   - an admitted child helper opens the parent from the child header;
   - co-participants' profiles show "working together", and the eye badge is open;
   - after the parent closes (review window finished), the bond line disappears,
     unless the reviews created trust.
   Use Playwright `browser_snapshot`, not repeated screenshots.
5. Update the journal with final results and mark the architecture doc implemented.

Done when: every check passes, and QA scenarios 1–4 are confirmed in the journal.
Commit: `chore(client): release shared-context visibility`.

---

## Appendix A — Invariant coverage map

| Invariant (architecture §8) | Covered in |
|---|---|
| S4-09 no listed-but-inaccessible | T01 (children filtered), T02, T09 table test |
| S4-09a no relationship disclosure through ids | T02 (stranger to child → `none`) |
| S4-10 non-transitivity + source eligibility | T09 (leave, block, delete, forward recipient gains no context) |
| S4-11 parentage never admits | T05 exhaustive sweep |
| S4-12 bond lifetime | T11 |
| S4-13 discovery trust-only | T11 |
| S4-14 scope (no siblings/grandchildren) | T09 table test |
| S4-15 SQL/Dart parity | T06, T09 step 9 |

## Appendix B — Deferred from the architecture (do not implement here)

- `BeaconRights` refactor of every use case (architecture rev 3 §7.1). D2 makes
  `canReadContent` the exact gate for read/apply/forward/invite/fork, so the existing
  call sites are already correct.
- Capability-projection subject view on the bond (§6.2): stays trust-only.
- Realtime neighbourhood access invalidation (§7.7). Access is re-checked on every
  fetch. Only live refresh of an already-open screen is missing.
- Naming the related request in the reason banner (§7.5).
- Bond in the graph person panel and in Constellation.

## Appendix C — Change log

- **rev 1** (2026-09-15): initial plan against architecture rev 3.
- **rev 2** (2026-09-15): no legacy-client support (product owner). The involvement
  gate now throws instead of returning `[]`. `beacon_can_read_linked_detail` and its
  Hasura field are dropped in T10 (new `m0172`; the bond migration moves to `m0173`).
  One client version bump, and a mandatory minimum client version raise, in T16.
