> **Superseded** by [`nested-requests-implementation-plan.md`](nested-requests-implementation-plan.md) — ask/promise/blocker coordination-item threads retired in favor of General-only Discussion and nested child requests; see [`nested-requests-implementation-journal.md`](nested-requests-implementation-journal.md).

# Request Threads — implementation plan

**Authority:** [`request-threads-architecture.md`](request-threads-architecture.md), rev 6.
**Execution model:** one unit per fresh composer-2.5 context, starting from the previous unit's
accepted commit. The architecture document supplies decisions; this document supplies only their
ordered implementation. Do not edit the architecture document while executing this plan.

The repository state quoted below is the 2026-08-14 baseline. When a prior unit mechanically moves a
file, the later unit names the post-move path and says which quoted baseline body arrived there.
Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.schema.dart`, and
Ferry `_g/`) are outputs, never edit targets.

## Unit table

| ID | Kind | One-line goal | Files touched | Depends on | Verification command |
|---|---|---|---|---|---|
| 01 | removal | Delete the resolution feature and its My Work review counter; add the only migration, `m0149`. | Resolution client/server symbols, `m0149`, responsibility projections, l10n, client/server version gate files | none | `cd packages/server && dart test --tags pg test/data/database/m0149_resolution_removal_migration_test.dart && cd ../.. && ./scripts/check-custom-lints.sh packages/server && ./scripts/check-custom-lints.sh packages/client && cd packages/client && flutter test && cd ../.. && bash scripts/check-user-facing-terminology.sh` |
| 02 | pure refactor | Mechanically move `features/beacon_room` to `features/beacon_threads` with no behavior edit. | `packages/client/lib/features/beacon_room/**` → `.../beacon_threads/**`, matching tests/imports, repository/use-case names | 01 | `./scripts/check-custom-lints.sh packages/client && cd packages/client && flutter test` |
| 03 | additive | Add the server's authorized, item-driven `beaconThreads` query and preview projection. | Server thread entity, coordination-item port/repository, room case/query, GraphQL custom types, server tests | 02 | `cd packages/server && dart test test/domain/use_case/beacon_threads_case_test.dart && dart test --tags pg test/data/repository/beacon_threads_repository_pg_test.dart` |
| 04 | behavior | Add `markThreadSeen` and return the persisted `RETURNING last_seen_at` watermark. | Server room port/repository/case/mutation and mark-seen tests | 03 | `cd packages/server && dart test test/domain/use_case/beacon_room_case_mark_seen_test.dart && dart test --tags pg test/data/repository/beacon_room_seen_upsert_pg_test.dart` |
| 05 | additive | Generate and map the client thread-list contract without putting it on screen yet. | Client schema, thread GraphQL document/entity/model, renamed repository/case, routing allow-list, tests | 04 | `cd packages/client && dart run build_runner build -d && flutter test test/features/beacon_threads/beacon_threads_repository_test.dart test/domain/entity/request_thread_test.dart` |
| 06 | behavior | Make read watermarks thread-keyed and switch both General and item threads to `markThreadSeen`. | Client watermark store, room case/repository/cubit, GraphQL documents, direct-operation list, tests, patch version | 05 | `cd packages/client && dart run build_runner build -d && flutter test test/features/beacon_threads/room_read_watermark_store_test.dart test/features/beacon_threads/room_cubit_unread_test.dart` |
| 07 | pure refactor | Extract the stale ticker and move `ItemCard` into `beacon_threads` without changing its behavior. | `item_card.dart`, `items_tab.dart`, new public ticker, imports/tests | 06 | `./scripts/check-custom-lints.sh packages/client && cd packages/client && flutter test test/features/beacon_view/beacon_items_tab_accordion_test.dart` |
| 08 | additive | Add `ThreadsCubit`/`ThreadsState` with latest-wins liveness and resolved unread counts. | New thread bloc/state and tests; no production screen switch | 07 | `cd packages/client && dart run build_runner build -d && flutter test test/features/beacon_threads/threads_cubit_test.dart` |
| 09 | additive | Build the boxed Threads list and evolved `ItemCard`, including preview/goldens and all open-question defaults. | Thread list/row/tickers, l10n ARBs, goldens/widget tests, patch version/cache-buster | 08 | `cd packages/client && flutter gen-l10n && flutter test test/features/beacon_threads/threads_list_test.dart test/features/beacon_threads/item_card_golden_test.dart` |
| 10 | additive | Add the shared thread host that serializes `RoomCubit` replacement with an awaited close. | New host bloc/state/widget and lifecycle tests | 09 | `cd packages/client && dart run build_runner build -d && flutter test test/features/beacon_threads/thread_host_cubit_test.dart` |
| 11 | additive | Make beacon view a real nested route host and add the compact/regular thread-detail page. | Beacon route host, router registrations, new thread detail, embedded providers, route tests | 10 | `cd packages/client && dart run build_runner build -d && flutter test test/app/router/request_thread_routing_test.dart test/features/beacon_threads/thread_detail_test.dart` |
| 12 | behavior | Atomically activate Threads, adaptive navigation, deep links, and remove every old Room/ItemDiscussion entry surface. | Beacon view/layout/router/deep-link/My Work files, legacy deletions, test ids/e2e helpers, old server seen aliases, minor version | 11 | `./scripts/check-custom-lints.sh packages/client && ./scripts/check-custom-lints.sh packages/server && cd packages/client && flutter test && cd ../.. && bash scripts/check-user-facing-terminology.sh` |
| 13 | docs | Apply D28's three-sense copy sweep, glossary/spec rewrite, and patch version. | ARBs, server notification/error copy, landing onboarding, terminology/docs, copy tests | 12 | `cd packages/client && flutter gen-l10n && dart run build_runner build -d && cd ../.. && bash scripts/check-user-facing-terminology.sh && ./scripts/check-custom-lints.sh packages/client && ./scripts/check-custom-lints.sh packages/server` |
| 14 | QA | Prove compact, regular, expanded, resize transitions, and the My Work embedded pane end to end. | New adaptive widget/integration tests only | 13 | `docker compose up -d postgres && ./scripts/run_client_integration_web_local.sh integration_test/request_threads_navigation_test.dart` plus the full gates in Unit 14 |

---

## UNIT 01 — Remove the resolution feature (D27) and migrate kind 4 away

### Goal

Delete the propose→accept/reject resolution feature from server and client before any rename or
Threads work. Remove the My Work YOU-line `reviews` segment with no replacement. Add `m0149`, the
only migration in this plan, so persisted `coordination_item.kind = 4` rows cannot reach the now
exhaustive enum. This unit uses **pre-rename `features/beacon_room` paths**; Unit 02 moves the
surviving feature afterward.

This is a visible, breaking removal. Bump client `5.13.0` to `6.0.0`, sync the web cache-buster, and
raise the baked server minimum from `5.13.0` to `6.0.0` (a major bump always raises the gate).

### Depends on

None.

### Files

**Server**

- `packages/server/lib/data/database/migration/m0149.dart` — **new**
- `packages/server/lib/data/database/migration/_migrations.dart` — **edit**
- `packages/server/lib/consts/coordination_item_consts.dart` — **edit**
- `packages/server/lib/domain/use_case/coordination_item/create_resolution_case.dart` — **delete**
- `packages/server/lib/domain/use_case/coordination_item/accept_resolution_case.dart` — **delete**
- `packages/server/lib/domain/use_case/coordination_item/reject_resolution_case.dart` — **delete**
- `packages/server/lib/api/controllers/graphql/mutation/mutation_coordination_item.dart` — **edit**
- `packages/server/lib/api/controllers/graphql/custom_types.dart` — **edit**
- `packages/server/lib/api/controllers/graphql/query/query_coordination_item.dart` — **edit**
- `packages/server/lib/domain/entity/coordination_responsibility_counts.dart` — **edit**
- `packages/server/lib/data/repository/coordination_item_repository.dart` — **edit**
- `packages/server/lib/env.dart` — **edit**
- `.env.example` — **edit**
- `packages/server/test/domain/use_case/coordination_item/resolution_case_test.dart` — **delete**
- `packages/server/test/architecture/transactional_attention_producer_inventory_test.dart` — **edit**
- `packages/server/test/data/repository/coordination_responsibility_repository_test.dart` — **edit**
- `packages/server/test/data/database/m0149_resolution_removal_migration_test.dart` — **new**

**Client**

- `packages/client/lib/domain/entity/coordination_item.dart` — **edit**
- `packages/client/lib/domain/entity/coordination_responsibility.dart` — **edit**
- `packages/client/lib/features/coordination_item/data/gql/coordination_item_create_resolution.graphql` — **delete**
- `packages/client/lib/features/coordination_item/data/gql/coordination_item_accept_resolution.graphql` — **delete**
- `packages/client/lib/features/coordination_item/data/gql/coordination_item_reject_resolution.graphql` — **delete**
- `packages/client/lib/features/coordination_item/data/repository/coordination_item_repository.dart` — **edit**
- `packages/client/lib/features/coordination_item/data/model/coordination_item_model.dart` — **edit**
- `packages/client/lib/features/coordination_item/data/gql/coordination_responsibility_batch.graphql` — **edit**
- `packages/client/lib/features/coordination_item/data/model/coordination_responsibility_model.dart` — **edit**
- `packages/client/lib/features/coordination_item/domain/use_case/coordination_item_case.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/bloc/item_actions_cubit.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/bloc/item_actions_state.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/screen/item_discussion_screen.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/widget/item_discussion_pane.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/widget/coordination_item_overflow_menu.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/widget/coordination_item_edit_sheet.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/widget/item_card.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/bloc/items_tab_cubit.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/widget/items_tab.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart` — **edit**
- `packages/client/lib/features/beacon_room/ui/widget/room_message_tile.dart` — **edit**
- `packages/client/lib/ui/utils/beacon_activity_event_presenter.dart` — **edit**
- `packages/client/lib/ui/utils/beacon_you_presentation.dart` — **edit**
- `packages/client/lib/ui/widget/coordination_item_presenter.dart` — **edit**
- `packages/client/lib/data/service/remote_api_client/build_client.dart` — **edit**
- `packages/client/lib/data/gql/schema.graphql` — **edit**
- `packages/client/l10n/app_en.arb` — **edit**
- `packages/client/l10n/app_ru.arb` — **edit**
- `packages/client/pubspec.yaml` — **edit** (`5.13.0` → `6.0.0`)
- `packages/client/web/index.html` — **edit** (`flutter_bootstrap.js?v=6.0.0`)
- `packages/client/test/domain/entity/coordination_item_involvement_test.dart` — **edit**
- `packages/client/test/domain/entity/coordination_responsibility_test.dart` — **edit**
- `packages/client/test/features/coordination_item/coordination_item_case_test.dart` — **edit**
- `packages/client/test/features/beacon_room/fake_coordination_item_case.dart` — **edit**
- `packages/client/test/ui/utils/beacon_you_presentation_test.dart` — **edit**

In `packages/client/lib/features/beacon_room/ui/widget/room_message_tile.dart`, edit only the real
`CoordinationItemKind.resolution` presentation arm. Its locals named `resolutionWidth` and
`resolutionRow` mean “resolve a layout value” and must survive unchanged.

### Current state

The persisted enum has an executable kind-4 arm:

```dart
// packages/client/lib/domain/entity/coordination_item.dart:5-30
enum CoordinationItemKind {
  plan(1), ask(2), blocker(3), resolution(4), promise(5);
  ...
  static CoordinationItemKind fromInt(int v) => switch (v) {
    ...
    4 => resolution,
    5 => promise,
  };
}
```

The responsibility projection makes reviews a fourth segment:

```dart
// packages/client/lib/domain/entity/coordination_responsibility.dart:32-44,68-82
@Default(0) int reviewOpen,
@Default(0) int reviewNew,
...
bool get hasAny => askOpen + promiseOpen + blockerOpen + reviewOpen > 0;
int get totalNew => askNew + promiseNew + blockerNew + reviewNew;
...
if (reviewOpen > 0) {
  out.add(CoordinationResponsibilityKindCounts(
    kind: CoordinationItemKind.resolution,
    open: reviewOpen,
    newCount: reviewNew,
  ));
}
```

The server has four distinct kind-4 SQL sites inside the responsibility batch, plus two other
resolution-participation queries:

```sql
-- packages/server/lib/data/repository/coordination_item_repository.dart:1243-1259
(ci.kind = 4 AND EXISTS (SELECT 1 FROM coordination_item tgt ...))

-- :1288-1307
... ci.kind = 4 ... AS review_open,
... ci.kind = 4 ... AS review_new,
... ci.kind IN (2, 3, 4, 5) ... AS others_open

-- :1356-1379 and :1477-1499
OR (ci.kind = $6 AND EXISTS (...))
... Variable<int>(coordinationItemKindResolution)
```

`beacon_items_seen` is live in that same query:

```sql
-- packages/server/lib/data/repository/coordination_item_repository.dart:1278-1312
LEFT JOIN beacon_items_seen bis
  ON bis.user_id = $1 AND bis.beacon_id = ci.beacon_id
... COALESCE(ci.published_at, ci.created_at) >
    COALESCE(bis.last_seen_at, '-infinity'::timestamptz) ... AS ask_new
```

The help-offer review chips borrow the deleted enum only for presentation:

```dart
// packages/client/lib/ui/utils/beacon_you_presentation.dart:269-280
BeaconYouOfferReviewSegmentKind.authorReview =>
  BeaconYouSegmentPresentation(
    icon: coordinationKindIcon(CoordinationItemKind.resolution), ...),
...
BeaconYouOfferReviewSegmentKind.helperAwaitingAuthor =>
  BeaconYouSegmentPresentation(
    icon: coordinationKindIcon(CoordinationItemKind.resolution), ...),
```

Those two chip concepts survive. So do `BeaconStatus.reviewOpen`,
`notificationCatUnblocksMe`, `CoordinationItemStatus.superseded`,
`CoordinationItemEventKind.superseded`, `resolutionWidth`, `resolutionRow`, and ordinary prose using
“resolution” to mean resolving a value.

The same room-message file contains both a real feature arm and the unrelated layout locals:

```dart
// packages/client/lib/features/beacon_room/ui/widget/room_message_tile.dart:290-299
static String _coordKindShortLabel(L10n l10n, CoordinationItemKind? k) =>
    switch (k) {
      CoordinationItemKind.plan => l10n.coordinationPlanCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
      null => l10n.coordinationItemCardTitle,
    };

// the same file:1150-1167 and 1489-1773 — unrelated layout-value resolution; keep
final resolutionWidth = ...;
final resolutionRow = ...;
```

### Change

1. Add exactly this migration and register it after `m0148` in both the `part` list and `InMemory`
   list:

   ```dart
   // packages/server/lib/data/database/migration/m0149.dart
   part of '_migrations.dart';

   /// Remove the retired coordination-resolution feature.
   final m0149 = Migration('0149', [
     'DELETE FROM public.coordination_item WHERE kind = 4;',
   ]);
   ```

   Do not add another migration anywhere in this plan. The existing
   `beacon_room_message.thread_item_id ... ON DELETE CASCADE` removes the deleted rows' messages.

2. Delete the three server use-case files, their constructor fields/imports/getters in
   `MutationCoordinationItem`, their three GraphQL mutation fields, and
   `resolution_case_test.dart`. Remove the three operation declarations from the client schema.

3. Delete `coordinationItemKindResolution` and all six server SQL consumers identified above.
   Reduce `_sqlMyResponsibilityOnCi` to ask/promise/blocker only; reduce `others_open` to
   `ci.kind IN (2, 3, 5)`; remove `review_open`/`review_new` columns and row mappings.

4. Preserve the `LEFT JOIN beacon_items_seen bis` and the `ask_new`, `promise_new`, and
   `blocker_new` watermark predicates verbatim. `beacon_items_seen` is a live My Work responsibility
   digest, not thread read state. Do not drop the table, its mutation, or `markBeaconItemsSeen`.

5. Remove `reviewOpen`/`reviewNew` from the server entity, GraphQL type/map, client GraphQL document,
   client model, and `CoordinationResponsibility`. `orderedEntries` becomes ask → promise → blocker;
   `hasAny`, `totalNew`, and `withNewCountsCleared` use only those three.

6. Remove `CoordinationItemKind.resolution` and its `fromInt(4)` arm. Simplify
   `directInvolvementAsSourceOrTarget` to reject only `plan`. Change
   `involvesUserAsSourceOrTarget(String userId)` to the direct check, delete `resolutionParent`, and
   change `filterActiveItemsForUser` to remove `lookupItems`/`byId` and call the simpler method.
   Update the only caller in `items_tab.dart` and both entity tests.

7. Delete the three client GraphQL documents, generated-model wrapper source imports/extensions,
   repository methods, case methods (including `fetchPendingResolutionForItem`), fake methods, and
   the three direct-operation names in `_tenturaDirectOperationNames`.

8. Remove `pendingResolution` from `ItemActionsState`; remove its load/create/accept/reject methods
   from `ItemActionsCubit`. Delete `_PendingResolutionBanner`, the propose sheet,
   `ItemDiscussionOverflowAction.onProposeResolution`, all propose call sites, and resolution-only
   accept/reject arms in `ItemsTab`. `BeaconRoomBody(enableComposer:)` becomes unconditional
   (`enableComposer: true`, or omit the argument if `true` is its default).

9. Remove only resolution switch arms from `item_card.dart`, `room_message_tile.dart`,
   `coordination_item_edit_sheet.dart`, `coordination_item_overflow_menu.dart`,
   `coordination_item_presenter.dart`, and `beacon_activity_event_presenter.dart`. Delete the eight
   resolution l10n keys named in rev 6 and `beaconYouReviewCount` if it has no remaining reader.

10. In `beacon_you_presentation.dart`, keep
    `BeaconYouOfferReviewSegmentKind.authorReview` and `.helperAwaitingAuthor`; replace their borrowed
    resolution icon with `Icons.rate_review_outlined` and keep their info tone. Delete only the now
    impossible `CoordinationItemKind.resolution` switch arms. Extend
    `beacon_you_presentation_test.dart` to assert both offer-review segments still exist and use a
    non-null icon after the enum removal.

11. Update `coordination_responsibility_repository_test.dart` to prove ask/promise/blocker open/new
    counts still honor `beacon_items_seen` and that no reviews fields exist. Update the architecture
    inventory by deleting only the three resolution producer entries.

12. Add an isolated PostgreSQL migration test by copying the disposable-database harness shape from
    `m0148_user_availability_migration_test.dart:14-60`. Its database name must start with
    `tentura_test_` and must not be `postgres`. Seed one kind-4 item with a thread message and one
    kind-2 item, apply `m0149`, and assert: kind 4 is gone, its message cascaded, kind 2 remains, and
    a second `m0149` application is not attempted (migrations are ledgered once).

13. Bump `packages/client/pubspec.yaml` to `6.0.0`, set the source cache-buster to `?v=6.0.0`, set
    `kDefaultMinClientVersion = '6.0.0'`, and sync both numeric mentions in `.env.example`.

14. Use symbol-specific deletion gates, never a bare `rg resolution` or `rg reviewOpen` deletion.
    The unrelated names listed above are required survivors.

### Codegen

```bash
cd packages/server
dart run build_runner build -d
cd ../client
flutter gen-l10n
dart run build_runner build -d
```

Do not edit generated outputs.

### Verify

```bash
cd packages/server
dart test --tags pg test/data/database/m0149_resolution_removal_migration_test.dart
dart test --exclude-tags pg
cd ../..
./scripts/check-custom-lints.sh packages/server

cd packages/client
flutter test test/domain/entity/coordination_item_involvement_test.dart
flutter test test/domain/entity/coordination_responsibility_test.dart
flutter test test/ui/utils/beacon_you_presentation_test.dart
flutter test
cd ../..
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh

! rg -n "CoordinationItemKind\.resolution|coordinationItemKindResolution|CreateResolutionCase|AcceptResolutionCase|RejectResolutionCase|fetchPendingResolutionForItem|pendingResolution|createResolution\(|acceptResolution\(|rejectResolution\(" \
  packages/client/lib packages/client/test packages/client/integration_test \
  packages/server/lib packages/server/test

rg -n "BeaconStatus\.reviewOpen" packages/client/lib packages/client/test packages/server/lib packages/server/test
rg -n "notificationCatUnblocksMe" packages/client/lib packages/client/test packages/client/l10n
rg -n "resolutionWidth|resolutionRow" packages/client/lib/features/beacon_room/ui/widget/room_message_tile.dart
rg -n "BeaconYouOfferReviewSegmentKind\.(authorReview|helperAwaitingAuthor)" \
  packages/client/lib/ui/utils/beacon_you_presentation.dart packages/client/test/ui/utils/beacon_you_presentation_test.dart
rg -n "LEFT JOIN beacon_items_seen|markBeaconItemsSeen" packages/server/lib packages/client/lib
rg -n '^version: 6\.0\.0$' packages/client/pubspec.yaml
rg -n 'flutter_bootstrap\.js\?v=6\.0\.0' packages/client/web/index.html
rg -n "kDefaultMinClientVersion = '6\.0\.0'" packages/server/lib/env.dart
rg -n 'currently 6\.0\.0' .env.example
rg -n 'MIN_CLIENT_VERSION=6\.0\.0' .env.example
```

Passing means all tests/lints are green; the forbidden-symbol search is empty; each survivor search
is non-empty; only ask/promise/blocker responsibility fields remain; and the client version,
cache-buster, baked minimum, and `.env.example` agree at `6.0.0`.

### Done when

No executable client, server, or test path can create, read, accept, reject, count, or render a
coordination resolution; isolated PostgreSQL proves kind-4 deletion and cascade; My Work has exactly
three responsibility segments; help-offer review chips and every unrelated allow-listed symbol
still work.

---

## UNIT 02 — Pure `beacon_room` → `beacon_threads` module rename (D22)

### Goal

Mechanically move the surviving client feature and its tests after Unit 01. Make no logic, copy,
layout, routing, GraphQL operation, or product-behavior change. Unit 01 deliberately used pre-rename
paths; every later client unit uses `features/beacon_threads` paths.

### Depends on

UNIT 01.

### Files

- `packages/client/lib/features/beacon_room/` — **move directory** to
  `packages/client/lib/features/beacon_threads/`
- `packages/client/test/features/beacon_room/` — **move directory** to
  `packages/client/test/features/beacon_threads/` (all Dart tests and six golden PNGs)
- `packages/client/lib/features/beacon_threads/data/repository/beacon_room_repository.dart` — **move**
  to `packages/client/lib/features/beacon_threads/data/repository/beacon_threads_repository.dart`
- `packages/client/lib/features/beacon_threads/domain/use_case/beacon_room_case.dart` — **move** to
  `packages/client/lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart`
- `packages/client/test/features/beacon_threads/beacon_room_case_test.dart` — **move/rename** to
  `beacon_threads_case_test.dart`
- Every path emitted **before the move** by this exact command — **edit** imports/symbols only:

  ```bash
  rg -l 'features/beacon_room|BeaconRoomRepository|BeaconRoomCase' \
    packages/client/lib packages/client/test packages/client/integration_test \
    --glob '*.dart' --glob '!**/*.g.dart' --glob '!**/*.freezed.dart' \
    --glob '!**/*.gr.dart' --glob '!**/*.config.dart' | sort
  ```

### Current state

Before Unit 01, the directory contains 214 files; the test directory contains 37 artifacts (31 Dart
files and six goldens). Imports are package-qualified, for example:

```dart
// packages/client/lib/features/coordination_item/ui/widget/item_discussion_pane.dart:7-8
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
```

The injectable types are declared at:

```dart
// packages/client/lib/features/beacon_room/data/repository/beacon_room_repository.dart
class BeaconRoomRepository ...

// packages/client/lib/features/beacon_room/domain/use_case/beacon_room_case.dart
class BeaconRoomCase ...
```

Storage, wire, and conversation symbols such as `beacon_room_message`, `BeaconRoomBody`, `RoomCubit`,
`BeaconRoomInvalidation`, GraphQL field names, and `roomMessage*` are not module-name mistakes and
must not be renamed.

### Change

1. Use `git mv` for both whole directories. Do not recreate files and do not regenerate goldens.
2. Rename only the repository/use-case source files and client symbols:
   `BeaconRoomRepository` → `BeaconThreadsRepository` and `BeaconRoomCase` →
   `BeaconThreadsCase`. Update their constructors, injection annotations, client references, fakes,
   and test description names mechanically.
3. Rewrite only package import prefixes
   `package:tentura/features/beacon_room/` →
   `package:tentura/features/beacon_threads/`.
4. Do not replace bare `room`, `Room`, `beacon_room`, or user-facing Chat strings. Do not change a
   method body other than the two constructor/class identifier substitutions above.
5. Review `git diff --find-renames --stat`: every source/test file inside the two directories must be
   a rename, except files Unit 01 already deleted or edited.

### Codegen

The Injectable type rename requires client codegen:

```bash
cd packages/client
dart run build_runner build -d
```

No l10n, GraphQL, Drift, or AutoRoute input changes occur in this unit.

### Verify

```bash
test ! -e packages/client/lib/features/beacon_room
test ! -e packages/client/test/features/beacon_room
! rg -n "features/beacon_room|BeaconRoomRepository|BeaconRoomCase" \
  packages/client/lib packages/client/test packages/client/integration_test \
  --glob '*.dart' --glob '!**/*.g.dart' --glob '!**/*.freezed.dart' --glob '!**/*.gr.dart' --glob '!**/*.config.dart'

rg -n "class BeaconThreadsRepository|class BeaconThreadsCase" packages/client/lib/features/beacon_threads
rg -n "class RoomCubit|class BeaconRoomBody|class BeaconRoomInvalidation" packages/client/lib/features/beacon_threads

./scripts/check-custom-lints.sh packages/client
cd packages/client
flutter test
```

Passing means there are no old module paths or old client repository/use-case type names, the room
storage/wire/widget symbols still exist, all 37 surviving test artifacts moved, and the full client
suite remains green with no behavior diff.

### Done when

Git recognizes the feature and test trees as moves, imports and DI use `beacon_threads`, and no
logic/copy/layout/routing line changed.

---

## UNIT 03 — Server `beaconThreads` query and preview contract

### Goal

Add the server query before any client GraphQL work. Return General plus eligible
Ask/Promise/Blocker rows, including counts and one structurally resolved preview object. The row
universe is coordination-item-driven with a synthetic General `UNION ALL`; it is never driven from
messages. Preserve item-only access using the authorization union rule.

### Depends on

UNIT 02.

### Files

- `packages/server/lib/domain/entity/beacon_thread_record.dart` — **new**
- `packages/server/lib/domain/port/coordination_item_repository_port.dart` — **edit**
- `packages/server/lib/data/repository/coordination_item_repository.dart` — **edit**
- `packages/server/lib/domain/use_case/beacon_room_case.dart` — **edit**
- `packages/server/lib/api/controllers/graphql/query/query_beacon_room.dart` — **edit**
- `packages/server/lib/api/controllers/graphql/custom_types.dart` — **edit**
- `packages/server/test/domain/use_case/beacon_threads_case_test.dart` — **new**
- `packages/server/test/data/repository/beacon_threads_repository_pg_test.dart` — **new**

### Current state

The existing query path is too narrow and takes multiple calls:

```dart
// packages/server/lib/api/controllers/graphql/query/query_coordination_item.dart:52-75
await ensureCanCoordinateOnBeacon(...);
final items = await _itemRepository.listByBeacon(...);
return items.map(coordinationItemWithCountsToMap).toList();
```

That guard excludes an item participant who is not a room member. The room case already has the two
pieces of the required union:

```dart
// packages/server/lib/domain/use_case/beacon_room_case.dart:78-95
Future<bool> _canUseRoom(...) async { ... author ... steward ... admitted ... }
bool _isItemParticipant(CoordinationItemRecord item, String userId) =>
  item.creatorId == userId ||
  item.targetPersonId == userId ||
  item.acceptedById == userId;
```

The current item count SQL contains the three semantic-thread unread clauses:

```sql
-- packages/server/lib/data/repository/coordination_item_repository.dart:851-859
WHERE m.thread_item_id = ci.id
  AND ci.kind <> $3
  AND m.author_id <> $2
  AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at)
```

`beacon_room_seen` has **no primary key**. Its real schema is two partial unique indexes created at
`m0072.dart:26-35`; the Drift `primaryKey` declaration is not production DDL. This unit only joins
the table; it must not invent a PK or merge its nullable thread key. `beacon_items_seen` is a separate,
live My Work digest and must not be changed while editing `coordination_item_repository.dart`.

### Change

1. Add plain domain records (no GraphQL/Drift types):

   ```dart
   abstract final class ThreadMessagePreviewKind {
     static const text = 0;
     static const attachment = 1;
     static const planUpdated = 2;
     static const factPinned = 3;
     static const participantStatus = 4;
     static const coordination = 5;
     static const needInfo = 6;
     static const done = 7;
     static const poll = 8;
     static const join = 9;
   }

   final class ThreadMessagePreviewRecord {
     const ThreadMessagePreviewRecord({
       required this.kind,
       this.excerpt,
       required this.hasAttachment,
       this.joinedUserId,
       this.admissionReason,
       this.linkedItemId,
       this.linkedEventKind,
       this.itemKind,
       this.itemTitle,
       this.pollTitle,
       this.factTitle,
       this.factVisibility,
     });
     // Declare the fields with the same names/types. admissionReason is String?.
   }

   final class BeaconThreadRecord {
     const BeaconThreadRecord({
       required this.threadId,
       required this.threadKind,
       required this.unreadCount,
       required this.messageCount,
       this.lastSeenAt,
       this.lastMessageAt,
       this.lastMessageAuthorId,
       this.lastMessagePreview,
       this.item,
     });
     final CoordinationItemWithCounts? item; // null iff General
     // Other fields exactly match the constructor.
   }
   ```

   `factVisibility` is the separate visibility field required for marker 2 versus 3. Do not serialize
   raw `systemPayload` or `systemPayloadJson` into this object.

2. Add one port method:

   ```dart
   Future<List<BeaconThreadRecord>> listThreads({
     required String beaconId,
     required String viewerUserId,
     required bool includeGeneral,
     required bool itemParticipantsOnly,
     required int excerptCharacters,
   });
   ```

3. Implement it as **one SQL statement**. Its row universe must be equivalent to this skeleton:

   ```sql
   WITH eligible_item AS (
     SELECT ci.*
     FROM coordination_item ci
     WHERE ci.beacon_id = $1
       AND ci.kind IN (2, 3, 5)
       AND (
         ($3::boolean = false AND (ci.published = true OR ci.creator_id = $2))
         OR
         ($3::boolean = true AND ci.published = true AND
           (ci.creator_id = $2 OR ci.target_person_id = $2 OR ci.accepted_by_id = $2))
       )
   ), thread_base AS (
     SELECT 'general'::text AS thread_id, 'general'::text AS thread_kind,
            NULL::text AS item_id, NULL::int AS item_kind,
            NULL::timestamptz AS item_updated_at
     WHERE $4::boolean
     UNION ALL
     SELECT ci.id,
            CASE ci.kind WHEN 2 THEN 'ask' WHEN 3 THEN 'blocker' WHEN 5 THEN 'promise' END,
            ci.id, ci.kind, ci.updated_at
     FROM eligible_item ci
   )
   SELECT ...
   FROM thread_base tb
   LEFT JOIN eligible_item ci ON ci.id = tb.item_id
   LEFT JOIN beacon_room_seen s
     ON s.user_id = $2 AND s.beacon_id = $1
    AND s.thread_item_id IS NOT DISTINCT FROM tb.item_id
   LEFT JOIN LATERAL (
     SELECT
       COUNT(*)::int AS message_count,
       COUNT(*) FILTER (WHERE
         m.author_id <> $2
         AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at)
         AND (tb.item_id IS NULL OR tb.item_kind <> 1)
       )::int AS unread_count,
       MAX(m.created_at) AS last_message_at
     FROM beacon_room_message m
     WHERE m.beacon_id = $1
       AND m.thread_item_id IS NOT DISTINCT FROM tb.item_id
   ) counts ON true
   LEFT JOIN LATERAL (
     SELECT m.*
     FROM beacon_room_message m
     WHERE m.beacon_id = $1
       AND m.thread_item_id IS NOT DISTINCT FROM tb.item_id
     ORDER BY m.created_at DESC, m.id DESC
     LIMIT 1
   ) lm ON true
   ...
   ORDER BY (tb.thread_id = 'general') DESC,
            COALESCE(counts.last_message_at, tb.item_updated_at) DESC,
            tb.thread_id ASC;
   ```

   Select `s.last_seen_at AS thread_last_seen_at` into `BeaconThreadRecord.lastSeenAt` for **every**
   row, including General. Select and map every `CoordinationItemRecord` field plus its existing
   `messageCount`, `unreadCount`, and `lastSeenAt`, so `item` can be wrapped in
   `CoordinationItemWithCounts`. The row-level watermark is required by thread-keyed unread
   reconciliation; General has no embedded item from which to recover it. Items with zero messages
   and unpublished viewer drafts must remain because messages are only lateral left joins.

4. The per-item unread predicate has exactly three clauses: watermark, own-author exclusion, and
   `kind <> plan`. The last clause is guarded by `tb.item_id IS NULL OR ...`, so it does **not** apply
   to General. General must include plan messages and match `countRoomMessagesAfter`; do not copy the
   item predicate wholesale.

5. Join only display-safe preview data: attachment existence, linked coordination item kind/title,
   `polling.question AS poll_title`, `beacon_fact_card.fact_text AS fact_title` and its visibility,
   and `system_payload ->> 'joinedUserId'` / `->> 'admissionReason'`. Use
   `LEFT(lm.body, $5)` only for ordinary non-system body text. Never use the JSON payload as excerpt.

6. Map preview codes exactly:

   - null marker + non-empty body → 0; null marker + attachment-only → 1;
   - markers 1..9 → 2,3,3,4,5,6,7,8,9;
   - null marker + non-null `linked_item_id` and `linked_event_kind` → 5 before the ordinary-text arm.

   Throw `StateError` if a persisted last-message family cannot be mapped; do not render a blank
   preview. **Do not define a GraphQL union.** Pinned `graphql_server2` 6.5.0 resolves unions
   structurally and cannot safely distinguish these overlapping shapes.

7. Add `BeaconRoomCase.listThreads`. Compute `roomMember = await _canUseRoom(...)`, then call the
   port with `includeGeneral: roomMember` and `itemParticipantsOnly: !roomMember`. For a room member,
   return General exactly once plus all published eligible items and their own drafts. For a
   non-member, return only published creator/target/accepter items and no General. If that list is
   empty, throw the same `UnauthorizedException(description: 'Room or item thread access required')`
   used by item-thread access. The list is not permission to post; `_canMutateMessage` remains the
   send-time guard.

8. **ASSUMPTION:** Q4 uses `excerptCharacters: 140`. PostgreSQL `LEFT(text, 140)` counts characters,
   not UTF-8 bytes. Do not truncate on the client.

9. Add GraphQL object types `ThreadMessagePreview` and `BeaconThreadRow`; the row includes nullable
   `lastSeenAt: String` from `BeaconThreadRecord.lastSeenAt`, plus one nullable `item` field typed as
   the existing `gqlTypeCoordinationItemRow` instance. Add
   `beaconThreads(beaconId: String!): [BeaconThreadRow!]!` to `QueryBeaconRoom.all`; map the embedded
   item through `coordinationItemWithCountsToMap` from `query_coordination_item.dart`. A second item
   GraphQL type is forbidden.

10. Add domain tests for the authorization union and a disposable isolated PostgreSQL repository
    test. The PG test must cover: General once for a member; no General for an item-only participant;
    inaccessible empty result; published zero-message item; own draft; someone else's draft absent;
    closed item; General includes a plan message; viewer's own message not unread; watermark clause;
    row-level `lastSeenAt` for General and semantic rows; General parity with
    `countRoomMessagesAfter`; all ten preview codes; coordination lifecycle with null marker;
    `admissionReason` string; and absence of raw system payload in `excerpt`.

### Codegen

None. The new server entities are plain Dart, the repository already owns its Injectable
registration, and server GraphQL types are constructed at runtime.

### Verify

```bash
cd packages/server
dart test test/domain/use_case/beacon_threads_case_test.dart
dart test --tags pg test/data/repository/beacon_threads_repository_pg_test.dart
dart test --exclude-tags pg
cd ../..
./scripts/check-custom-lints.sh packages/server

! rg -n "GraphQLUnionType|__typename" \
  packages/server/lib/domain/entity/beacon_thread_record.dart \
  packages/server/lib/api/controllers/graphql/custom_types.dart \
  packages/server/lib/api/controllers/graphql/query/query_beacon_room.dart
rg -n "General row|UNION ALL|thread_base|eligible_item" packages/server/lib/data/repository/coordination_item_repository.dart
rg -n "LEFT JOIN beacon_items_seen" packages/server/lib/data/repository/coordination_item_repository.dart
```

Passing means both focused tests and server lint are green, the PG test names a disposable database
and proves all query-shape cases, the GraphQL preview is one object, and the live
`beacon_items_seen` join still exists.

### Done when

The server exposes a single fat thread-list query whose authorization, inclusion, unread, preview,
and ordering behavior is pinned at the database and use-case boundaries.

---

## UNIT 04 — `markThreadSeen` and effective persisted watermark

### Goal

Add the one thread-list mutation and fix the existing response lie: the mutation must report the
watermark PostgreSQL actually kept. Preserve General's special clamp/floor and semantic-thread
authorization. The route/API sentinel `general` is translated here to `null`; it never reaches any
existing room method as `threadItemId`.

### Depends on

UNIT 03.

### Files

- `packages/server/lib/domain/port/beacon_room_repository_port.dart` — **edit**
- `packages/server/lib/data/repository/beacon_room_repository.dart` — **edit**
- `packages/server/lib/domain/use_case/beacon_room_case.dart` — **edit**
- `packages/server/lib/api/controllers/graphql/mutation/mutation_beacon_room.dart` — **edit**
- `packages/server/test/domain/use_case/beacon_room_case_mark_seen_test.dart` — **edit**
- `packages/server/test/data/repository/beacon_room_seen_upsert_pg_test.dart` — **new**

### Current state

The case currently branches correctly but returns the submitted value:

```dart
// packages/server/lib/domain/use_case/beacon_room_case.dart:570-631
Future<Map<String, Object?>> markBeaconRoomSeen(...) async {
  final inThread = tid != null && tid.isNotEmpty;
  if (inThread) { _rejectPlanItemThread; _canAccessThread; }
  else { _canUseRoom; }
  ... // General latest-message clamp and existing-watermark floor
  await _room.markBeaconRoomSeen(... at: at);
  return {'seenAt': at.toUtc().toIso8601String(), ...};
}
```

The repository write is monotonic for both branches and must be carried over verbatim apart from
`RETURNING`:

```sql
-- packages/server/lib/data/repository/beacon_room_repository.dart:1102-1129
-- General
ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL
DO UPDATE SET last_seen_at = GREATEST(
  beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at
)

-- semantic thread
ON CONFLICT (user_id, beacon_id, thread_item_id)
WHERE thread_item_id IS NOT NULL
DO UPDATE SET last_seen_at = GREATEST(
  beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at
)
```

`beacon_room_seen` has **no primary key**. Those two partial-index inference predicates are required
PostgreSQL syntax, not optional filters.

### Change

1. Change `BeaconRoomRepositoryPort.markBeaconRoomSeen` and its implementation from `Future<void>`
   to `Future<DateTime>`.
2. Keep two SQL statements. Append literal `RETURNING last_seen_at` to each. Execute with
   `customSelect`, require exactly one row, and return
   `row.read<PgDateTime>('last_seen_at').dateTime.toUtc()`. Do not return the submitted `at`.
3. Do not merge the two statements, name a nonexistent PK, omit either `WHERE` inference predicate,
   replace null with `''`, or change either `GREATEST` expression.
4. Have the existing case capture `persistedAt` and return that as `seenAt`. Preserve exactly:
   General `_canUseRoom`, latest-main-message clamp, and existing-watermark floor; semantic
   `_rejectPlanItemThread` + `_canAccessThread` and no clamp/floor.
5. Add a new case entry and resolver:

   ```dart
   Future<Map<String, Object?>> markThreadSeen({
     required String beaconId,
     required String userId,
     required String threadId,
     String? readThroughAtIso,
   }) {
     final normalized = threadId.trim();
     if (normalized.isEmpty) {
       throw ArgumentError.value(threadId, 'threadId', 'must not be empty');
     }
     return markBeaconRoomSeen(
       beaconId: beaconId,
       userId: userId,
       threadItemId: normalized == 'general' ? null : normalized,
       readThroughAtIso: readThroughAtIso,
     );
   }
   ```

   The GraphQL field is `markThreadSeen(beaconId: String!, threadId: String!, readThroughAt:
   String): BeaconRoomSeenResult!`. Its returned `threadItemId` stays nullable in the existing result
   object; the client consumes `seenAt`. Keep the two old GraphQL fields temporarily so main remains
   green until Unit 12 removes them with their last producers.

6. Test `threadId: 'general'` reaches the repository as `threadItemId: null`; a real item id remains
   itself; literal `general` never reaches `_canAccessThread`; General preserves clamp/floor;
   semantic path preserves no clamp/floor; and plan ids remain rejected.
7. The isolated PG test must exercise both conflict targets twice. Submit a newer watermark and then
   a stale one; assert the second mutation response equals the newer stored `last_seen_at` for both
   General and a semantic thread. Also assert the table has no primary-key constraint and both
   partial unique indexes exist.

### Codegen

None.

### Verify

```bash
cd packages/server
dart test test/domain/use_case/beacon_room_case_mark_seen_test.dart
dart test --tags pg test/data/repository/beacon_room_seen_upsert_pg_test.dart
dart test --exclude-tags pg
cd ../..
./scripts/check-custom-lints.sh packages/server

rg -n "RETURNING last_seen_at" packages/server/lib/data/repository/beacon_room_repository.dart
rg -U -n "ON CONFLICT \(user_id, beacon_id\)\s+WHERE thread_item_id IS NULL" \
  packages/server/lib/data/repository/beacon_room_repository.dart
rg -U -n "ON CONFLICT \(user_id, beacon_id, thread_item_id\)\s+WHERE thread_item_id IS NOT NULL" \
  packages/server/lib/data/repository/beacon_room_repository.dart
```

Passing means both stale-write assertions return the stored newer value, both authorization branches
retain their differences, the partial-index targets compile against real PostgreSQL, and server lint
is green.

### Done when

`markThreadSeen` is available for the client, `general` is translated at its entry, and every
successful response reports the effective persisted monotonic watermark.

---

## UNIT 05 — Client thread contract, mapping, repository, and case

### Goal

Consume the already-running server contract in a domain-safe client slice, but do not render it yet.
The repository returns `RequestThread`, never Ferry rows. The message preview is one object with the
same fixed integer discriminator as the server; no GraphQL union is allowed.

### Depends on

UNIT 04.

### Files

- `packages/client/lib/data/gql/schema.graphql` — **edit**
- `packages/client/lib/data/service/remote_api_client/build_client.dart` — **edit**
- `packages/client/lib/features/beacon_threads/domain/entity/request_thread.dart` — **new**
- `packages/client/lib/features/beacon_threads/data/gql/beacon_threads_list.graphql` — **new**
- `packages/client/lib/features/beacon_threads/data/model/request_thread_model.dart` — **new**
- `packages/client/lib/features/beacon_threads/data/repository/beacon_threads_repository.dart` — **edit**
- `packages/client/lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart` — **edit**
- `packages/client/test/domain/entity/request_thread_test.dart` — **new**
- `packages/client/test/features/beacon_threads/beacon_threads_repository_test.dart` — **new**
- `packages/client/test/data/service/remote_api_client/build_client_test.dart` — **edit**

### Current state

Unit 02 moved and renamed the old room repository/case without changing their bodies. Their baseline
API still contains room operations only. The existing coordination item query duplicates all item
fields inline:

```graphql
# packages/client/lib/features/coordination_item/data/gql/coordination_item_list.graphql:18-45
coordinationItemsByBeacon(...) {
  id beaconId kind status source published title body creatorId
  targetPersonId acceptedById targetItemId targetMessageId
  linkedMessageId linkedParentItemId ordering createdAt updatedAt
  resolvedAt cancelledAt staleAt lastRemindedAt staleAfterDays
  messageCount unreadCount lastSeenAt
}
```

`CoordinationItemListModel.toEntity()` at
`coordination_item_model.dart:35-66` is the canonical field conversion. Reuse its mapping; do not
expose generated `GBeaconThreadsList...` types outside `data/`.

### Change

1. Update the committed client schema from the real Unit-03 server shape. Add
   `v2_ThreadMessagePreview`, `v2_BeaconThreadRow`, and the `beaconThreads` query field. Use one
   object, not a union. Include row-level nullable `lastSeenAt: String` and nullable
   `factVisibility: Int` with the other preview fields.
2. Add this query and spell out the embedded `item` fields exactly as the existing item document:

   ```graphql
   query BeaconThreadsList($beaconId: String!) {
     beaconThreads(beaconId: $beaconId) {
       threadId
       threadKind
       unreadCount
       messageCount
       lastSeenAt
       lastMessageAt
       lastMessageAuthorId
       lastMessagePreview {
         kind excerpt hasAttachment joinedUserId admissionReason
         linkedItemId linkedEventKind itemKind itemTitle
         pollTitle factTitle factVisibility
       }
       item {
         id beaconId kind status source published title body creatorId
         targetPersonId acceptedById targetItemId targetMessageId
         linkedMessageId linkedParentItemId ordering createdAt updatedAt
         resolvedAt cancelledAt staleAt lastRemindedAt staleAfterDays
         messageCount unreadCount lastSeenAt
       }
     }
   }
   ```

3. Add `'BeaconThreadsList'` to `_tenturaDirectOperationNames` and its routing test.
4. Add Freezed domain types in one source file:

   ```dart
   enum RequestThreadKind { general, ask, promise, blocker }

   abstract final class ThreadMessagePreviewKind {
     static const text = 0;
     static const attachment = 1;
     static const planUpdated = 2;
     static const factPinned = 3;
     static const participantStatus = 4;
     static const coordination = 5;
     static const needInfo = 6;
     static const done = 7;
     static const poll = 8;
     static const join = 9;
     static const values = <int>{0,1,2,3,4,5,6,7,8,9};
   }

   @freezed
   abstract class ThreadMessagePreview with _$ThreadMessagePreview {
     const factory ThreadMessagePreview({
       required int kind,
       String? excerpt,
       @Default(false) bool hasAttachment,
       String? joinedUserId,
       String? admissionReason,
       String? linkedItemId,
       int? linkedEventKind,
       int? itemKind,
       String? itemTitle,
       String? pollTitle,
       String? factTitle,
       int? factVisibility,
     }) = _ThreadMessagePreview;
   }

   @freezed
   abstract class RequestThread with _$RequestThread {
     static const generalId = 'general';
     const factory RequestThread({
       required String threadId,
       required RequestThreadKind kind,
       @Default(0) int unreadCount,
       @Default(0) int messageCount,
       DateTime? lastSeenAt,
       DateTime? lastMessageAt,
       String? lastMessageAuthorId,
       ThreadMessagePreview? lastMessagePreview,
       CoordinationItem? item,
     }) = _RequestThread;
     const RequestThread._();
     bool get isGeneral => item == null;
     bool get isDraft => item?.published == false;
     bool get isActive => item?.isActive ?? true;
   }
   ```

   Enforce `item == null` iff `threadId == 'general'` in the mapper tests. Branch on `item` presence,
   not `kind`, when deciding whether semantic state exists.
5. In `request_thread_model.dart`, parse `threadKind` exhaustively; reject unknown values. Reject a
   preview `kind` outside 0–9 rather than producing empty copy. Reuse a shared
   `coordinationItemFromFields(...)` helper extracted from `coordination_item_model.dart` so the
   existing list mapper and embedded thread mapper cannot drift. That helper remains in the data
   layer and returns `CoordinationItem`.
6. Add `BeaconThreadsRepository.fetchThreads(String beaconId)` using
   `GBeaconThreadsListReq`; map every row to the domain entity.
7. Add `BeaconThreadsCase.listThreads(String beaconId)` as a thin repository call. Preserve all
   existing room methods in the same case. Do not call `fetchCurrentRootPlan`: its old
   `ItemsTabState.currentCoordinationPlan` has zero readers, while General's `RoomCubit` independently
   loads the live plan.
8. Test General/null-item, General and semantic `lastSeenAt`, all four kinds, dates, nullable preview
   fields, all 0–9 codes, unknown-code failure, and exact embedded item parity with
   `CoordinationItemListModel`.

### Codegen

```bash
cd packages/client
dart run build_runner build -d
```

This generates Ferry and Freezed outputs. Do not hand-edit them.

### Verify

```bash
cd packages/client
flutter test test/domain/entity/request_thread_test.dart
flutter test test/features/beacon_threads/beacon_threads_repository_test.dart
flutter test test/data/service/remote_api_client/build_client_test.dart
cd ../..
./scripts/check-custom-lints.sh packages/client

! rg -n "GraphQLUnionType|__typename" \
  packages/client/lib/features/beacon_threads packages/client/lib/data/gql/schema.graphql
rg -n "'BeaconThreadsList'" packages/client/lib/data/service/remote_api_client/build_client.dart
```

Passing means generated code succeeds, all mapper/routing tests are green, no Ferry type escapes the
data layer, and the preview is structurally one object.

### Done when

The unused client data slice can fetch and map the server's entire fat row in one request, including
all preview families, without altering the shipping screen.

---

## UNIT 06 — Thread-keyed watermark store and client `markThreadSeen`

### Goal

Stop item-thread reads from leaking into General and remove the optimistic-read gap for semantic
threads. Switch both old General and item-thread callers to the one new mutation. A `general` route
sentinel is sent only to `markThreadSeen`; every existing room list/send/fact/plan/state API and
General `RoomCubit` still receives `threadItemId: null`.

This fixes visible unread flicker. Bump `6.0.0` to `6.0.1` and sync the web cache-buster.

### Depends on

UNIT 05.

### Files

- `packages/client/lib/features/beacon_threads/data/gql/mark_thread_seen.graphql` — **new**
- `packages/client/lib/features/beacon_threads/data/gql/mark_beacon_room_seen.graphql` — **delete**
- `packages/client/lib/features/beacon_threads/data/gql/beacon_participant_room_seen.graphql` — **delete**
- `packages/client/lib/features/beacon_threads/data/repository/beacon_threads_repository.dart` — **edit**
- `packages/client/lib/features/beacon_threads/domain/room_read_watermark_store.dart` — **edit**
- `packages/client/lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart` — **edit**
- `packages/client/lib/data/service/remote_api_client/build_client.dart` — **edit**
- `packages/client/lib/data/gql/schema.graphql` — **edit**
- `packages/client/pubspec.yaml` — **edit** (`6.0.0` → `6.0.1`)
- `packages/client/web/index.html` — **edit** (`?v=6.0.1`)
- `packages/client/test/features/beacon_threads/room_read_watermark_store_test.dart` — **edit**
- `packages/client/test/features/beacon_threads/room_cubit_unread_test.dart` — **edit**
- `packages/client/test/features/beacon_threads/beacon_threads_case_test.dart` — **edit**
- `packages/client/test/data/service/remote_api_client/build_client_test.dart` — **edit**

### Current state

Unit 02 moved these bodies unchanged. The watermark store is beacon-only:

```dart
// baseline features/beacon_room/domain/room_read_watermark_store.dart:24-31
final Map<String, DateTime> _readThroughByBeacon = {};
final Map<String, DateTime> _syncedByBeacon = {};
Stream<String> get changes => _changesController.stream;
```

The repository currently splits General and item threads between two mutations:

```dart
// baseline beacon_room_repository.dart:418-449
if (threadItemId == null) { GBeaconParticipantRoomSeenReq(...) }
else { GMarkBeaconRoomSeenReq(... threadItemId ...) }
```

The optimistic observation is explicitly General-only:

```dart
// baseline room_cubit.dart:405-416
if (state.threadItemId == null) {
  _case.observeReadThrough(state.beaconId, latest);
}
```

Deleting that guard is a required numbered change below, not a cleanup note.

### Change

1. Add:

   ```graphql
   mutation MarkThreadSeen(
     $beaconId: String!
     $threadId: String!
     $readThroughAt: String
   ) {
     markThreadSeen(
       beaconId: $beaconId
       threadId: $threadId
       readThroughAt: $readThroughAt
     ) { beaconId threadItemId seenAt }
   }
   ```

   Remove the two old documents and schema mutation fields. Replace their direct-operation names
   with `'MarkThreadSeen'`.
2. Replace beacon-only map keys with this immutable value and key both maps by it:

   ```dart
   @immutable
   final class RoomReadWatermarkKey {
     const RoomReadWatermarkKey(this.beaconId, this.threadId);
     final String beaconId;
     final String threadId;
     @override
     bool operator ==(Object other) =>
         other is RoomReadWatermarkKey &&
         other.beaconId == beaconId &&
         other.threadId == threadId;
     @override
     int get hashCode => Object.hash(beaconId, threadId);
   }
   ```

   Normalize General to `RequestThread.generalId`; semantic ids stay unchanged. The store exposes
   `Stream<RoomReadWatermarkKey> get threadChanges`. Its existing `Stream<String> get changes`
   remains as a compatibility projection of **General keys only**:

   ```dart
   Stream<String> get changes => threadChanges
       .where((key) => key.threadId == RequestThread.generalId)
       .map((key) => key.beaconId);
   ```

   This keeps the still-live Beacon View, Inbox, and My Work General-unread listeners green until
   Unit 12 removes only the Beacon View consumer. Do not emit semantic-thread writes on that legacy
   stream.
3. Make `readThrough`, `syncedAt`, `hasPendingSync`, `observeReadThrough`, `confirmSynced`, and
   `resolveUnread` operate on a `(beaconId, threadId)` key. Preserve per-key monotonic max behavior.
   `confirmSynced` consumes the persisted `seenAt` returned by Unit 04; never substitute the
   submitted timestamp. On both the store and `BeaconThreadsCase`, add a named
   `threadId = RequestThread.generalId` to the existing General-facing public methods so current
   Beacon View, Inbox, My Work, and their tests keep compiling while all internal map access still
   uses a full key. Expose `threadReadWatermarkChanges => _watermark.threadChanges` for
   `ThreadsCubit`.
4. Change the repository to one method:

   ```dart
   Future<DateTime> markThreadSeen({
     required String beaconId,
     required String threadId,
     required DateTime readThroughAt,
   }) async { ... GMarkThreadSeenReq ... }
   ```

5. Change the case mark-seen method to derive
   `threadId = threadItemId ?? RequestThread.generalId`, call the mutation, and confirm the same
   thread-keyed store entry. Keep the public RoomCubit-facing argument nullable so **no existing room
   API or General `RoomCubit` ever receives the literal `general` as `threadItemId`**.
6. **Delete the `if (state.threadItemId == null)` guard** in
   `_advanceReadAnchorToLatestLoaded`. Always call:

   ```dart
   _case.observeReadThrough(
     state.beaconId,
     latest,
     threadId: state.threadItemId ?? RequestThread.generalId,
   );
   ```

   This records an optimistic semantic-thread watermark before `close()` awaits the network flush.
7. Add tests with the same beacon and two item ids proving isolation; semantic observation before
   mutation completion; persisted response confirmation; stale response does not regress; General
   uses the `general` store key but `RoomCubit.state.threadItemId` remains null; item thread A never
   suppresses General or thread B; `threadChanges` emits the full key; and legacy `changes` emits
   General's beacon id but emits nothing for a semantic key.
8. Do not touch `beacon_items_seen`, `markBeaconItemsSeen`, or the Inbox/My Work
   `inbox_room_context_batch.roomUnreadCount` source. Those remain live for other projections.
9. Bump the client and source cache-buster to `6.0.1`. Do not raise
   `kDefaultMinClientVersion`; this patch does not make the Unit-01 client incompatible with the
   server.

### Codegen

```bash
cd packages/client
dart run build_runner build -d
```

### Verify

```bash
cd packages/client
flutter test test/features/beacon_threads/room_read_watermark_store_test.dart
flutter test test/features/beacon_threads/room_cubit_unread_test.dart
flutter test test/features/beacon_threads/beacon_threads_case_test.dart
flutter test test/data/service/remote_api_client/build_client_test.dart
cd ../..
./scripts/check-custom-lints.sh packages/client

! rg -n "GBeaconParticipantRoomSeenReq|GMarkBeaconRoomSeenReq|BeaconParticipantRoomSeen|MarkBeaconRoomSeen" \
  packages/client/lib packages/client/test
rg -n "MarkThreadSeen" packages/client/lib packages/client/test
rg -n "threadItemId == null" packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart
rg -n '^version: 6\.0\.1$' packages/client/pubspec.yaml
rg -n 'flutter_bootstrap\.js\?v=6\.0\.1' packages/client/web/index.html
```

The last search may still find legitimate General-only fact/plan/item-sync branches; it must **not**
find a guard around `observeReadThrough`. Passing also means `pubspec.yaml` and `index.html` agree at
`6.0.1`.

### Done when

Every thread observes and confirms its own watermark, both old seen paths use `markThreadSeen`, the
persisted response is authoritative, and General's nullable room representation is unchanged.

---

## UNIT 07 — Extract the ticker and move `ItemCard` without behavior change

### Goal

Prepare the row for Threads without deleting private behavior from `items_tab.dart`. Move the
request-scoped `ItemCard` into `beacon_threads` and extract `_StaleDeadlineTicker` first. No field,
layout, action, string, or test expectation changes in this unit.

### Depends on

UNIT 06.

### Files

- `packages/client/lib/features/beacon_view/ui/widget/items_tab.dart` — **edit**
- `packages/client/lib/features/coordination_item/ui/widget/item_card.dart` — **move** to
  `packages/client/lib/features/beacon_threads/ui/widget/item_card.dart`
- `packages/client/lib/features/beacon_threads/ui/widget/stale_deadline_ticker.dart` — **new**

### Current state

`ItemCard`'s private presentation helpers live with it:

```dart
// baseline coordination_item/ui/widget/item_card.dart:12-66
enum _ItemHeaderTier { high, medium, low }
const _bodyPreviewThreshold = 60;
String? _formatStaleRemaining(...)
String? _formatStaleOverdue(...)
```

But the timer that refreshes those labels would be deleted with Items:

```dart
// baseline beacon_view/ui/widget/items_tab.dart:686-748
class _StaleDeadlineTicker extends StatefulWidget { ... }
class _StaleDeadlineTickerState extends State<_StaleDeadlineTicker> {
  void _schedule() { ... item.nextStaleOverdueLabelChangeAt(now) ... }
}
```

### Change

1. Move `_StaleDeadlineTicker` byte-for-byte into the new file, make it public
   `StaleDeadlineTicker`, and update only the call site/import.
2. Move `item_card.dart` byte-for-byte to the target feature path. Keep its import of lifecycle
   actions/menu in `features/coordination_item`; that feature still owns mutations.
3. Update `items_tab.dart` imports. Do not change the three constructor invocations or any raw design
   constants yet; Unit 09 performs the intentional row redesign under tests.
4. Verify `git diff --color-moved` shows moves plus identifier/import edits only.

### Codegen

None.

### Verify

```bash
test ! -e packages/client/lib/features/coordination_item/ui/widget/item_card.dart
rg -n "class StaleDeadlineTicker" packages/client/lib/features/beacon_threads/ui/widget/stale_deadline_ticker.dart
! rg -n "class _StaleDeadlineTicker" packages/client/lib
./scripts/check-custom-lints.sh packages/client
cd packages/client
flutter test test/features/beacon_view/beacon_items_tab_accordion_test.dart
flutter test
```

Passing means the full suite is unchanged and the diff contains no behavioral body change.

### Done when

The card and a public stale ticker live in `beacon_threads`, while the shipping Items tab behaves
identically.

---

## UNIT 08 — `ThreadsCubit` latest-wins state and unread reconciliation

### Goal

Add the unused Threads presentation state. Fetch one server list, group on the client, reconcile each
row through the thread-keyed watermark store, and make invalidation refreshes latest-wins. Do not
carry `currentCoordinationPlan`; it has zero readers and General's `RoomCubit` owns its plan.

### Depends on

UNIT 07.

### Files

- `packages/client/lib/features/beacon_threads/ui/bloc/threads_state.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/bloc/threads_cubit.dart` — **new**
- `packages/client/test/features/beacon_threads/threads_cubit_test.dart` — **new**

### Current state

The old bloc fires unawaited fetches and accepts every response:

```dart
// baseline beacon_view/ui/bloc/items_tab_cubit.dart:14-61
_invalidationSub = _beaconRoomCase.beaconRoomInvalidations
  .where((e) => ... roomMessage || coordinationItem || participant || factCard)
  .listen((_) => unawaited(fetch(silent: true)));
...
final items = await _case.listByBeacon(_beaconId);
final currentPlan = await _case.fetchCurrentRootPlan(_beaconId);
...
emit(state.copyWith(... currentCoordinationPlan: currentPlan));
```

It omits `roomSeen`, has no generation check, and makes two reads. Unit 05 already added the one-call
replacement.

### Change

1. Define a Freezed `ThreadsState extends StateBase` with:
   `List<RequestThread> threads`, `bool activeForMeOnly`, `StateStatus status`, `Object? loadError`,
   and derived getters `general`, `active`, `closed`, `drafts`, `firstAccessible`, and
   `threadsTabUnreadCount`.
   Give `ThreadsCubit` the same testable constructor pattern as the class it replaces:

   ```dart
   ThreadsCubit({
     required String beaconId,
     CoordinationItemCase? coordinationItemCase,
     BeaconThreadsCase? beaconThreadsCase,
   }) : _beaconId = beaconId,
        _coordination = coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
        _threads = beaconThreadsCase ?? GetIt.I<BeaconThreadsCase>(),
        super(const ThreadsState()) { ...subscribe... }
   ```
2. Group only in getters/presentation. General is first and never folded. Semantic active rows are
   published and `item.isActive`; closed are published and not active; drafts are the viewer's
   unpublished rows. Plan/plan-step cannot arrive from the server.
3. Resolve every server unread count with
   `BeaconThreadsCase.resolveUnread(beaconId:, threadId:, serverCount:, serverSeenAt:
   thread.lastSeenAt)` before
   emitting. Tab count is resolved General plus resolved **active** semantic rows only. Closed rows
   keep resolved unread for display when their fold is expanded; closed unread is not in the tab
   total.
4. Port ask/promise/blocker lifecycle action methods from `ItemsTabCubit` and have every successful
   mutation call `await fetch(silent: true)`. Inject `BeaconThreadsCase` plus
   `CoordinationItemCase`, satisfying the multi-repository cubit lint via cases.
5. Subscribe to invalidations for this beacon. Include exactly `roomMessage`, `coordinationItem`,
   `participant`, `factCard`, and `roomSeen`.
6. Implement latest-wins with a monotonically increasing `_fetchGeneration`. Capture generation
   before awaiting; discard both success and error when it is not current. Coalesce bursty non-seen
   invalidations into one scheduled silent fetch. A `roomSeen` event bypasses the debounce and
   refreshes immediately.
7. Subscribe to `BeaconThreadsCase.threadReadWatermarkChanges`, filter its full key by beacon, and
   recompute resolved counts from the last server rows without a network call. Do not use the legacy
   General-only `readWatermarkChanges` stream.
8. Test out-of-order completion (older success and older error both discarded), burst coalescing,
   immediate `roomSeen`, zero-message/draft preservation, no plan fetch, General+active badge, closed
   exclusion, and just-left-thread optimistic suppression.
9. `beacon_items_seen` and the inbox room-hints batch are not list sources and remain untouched.

### Codegen

```bash
cd packages/client
dart run build_runner build -d
```

### Verify

```bash
cd packages/client
flutter test test/features/beacon_threads/threads_cubit_test.dart
cd ../..
./scripts/check-custom-lints.sh packages/client

! rg -n "currentCoordinationPlan|fetchCurrentRootPlan" \
  packages/client/lib/features/beacon_threads/ui/bloc/threads_*.dart
rg -n "roomSeen|_fetchGeneration" packages/client/lib/features/beacon_threads/ui/bloc/threads_cubit.dart
```

Passing means all concurrency tests are deterministic, stale responses never emit, and the badge
matches visible active-row policy.

### Done when

An unused but complete Threads bloc can survive realtime races and produce the exact grouped,
watermark-resolved state required by the target UI.

---

## UNIT 09 — Boxed Threads list and evolved `ItemCard`

### Goal

Build the target list without activating it. Evolve the existing moved `ItemCard`; do not create a
parallel `ThreadRow`. Preserve every semantic fact/action, add General plus last-message preview and
relative time, and keep the parent-owned boxed `Column` architecture.

The Q1 label changes an existing shared l10n key and is visible outside the unused list. Bump
`6.0.1` to `6.0.2` and sync the web cache-buster in this unit.

### Depends on

UNIT 08.

### Files

- `packages/client/lib/features/beacon_threads/ui/widget/threads_list.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/widget/item_card.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/widget/thread_message_preview_presenter.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/widget/relative_timestamp_ticker.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/util/thread_accordion_sections.dart` — **new**
- `packages/client/lib/ui/test_ids.dart` — **edit**
- `packages/client/l10n/app_en.arb` — **edit**
- `packages/client/l10n/app_ru.arb` — **edit**
- `packages/client/pubspec.yaml` — **edit** (`6.0.1` → `6.0.2`)
- `packages/client/web/index.html` — **edit** (`?v=6.0.2`)
- `packages/client/test/features/beacon_threads/threads_list_test.dart` — **new**
- `packages/client/test/features/beacon_threads/item_card_golden_test.dart` — **new**
- `packages/client/test/features/beacon_threads/goldens/item_card_collapsed_light.png` — **new golden**
- `packages/client/test/features/beacon_threads/goldens/item_card_collapsed_dark.png` — **new golden**
- `packages/client/test/features/beacon_threads/goldens/item_card_expanded_light.png` — **new golden**
- `packages/client/test/features/beacon_threads/goldens/item_card_expanded_dark.png` — **new golden**

### Current state

The old tab explicitly keeps box layout because nested scrolling broke web:

```dart
// baseline beacon_view/ui/widget/items_tab.dart:205-210
// Parent CustomScrollView owns scrolling; nested ListView caused
// parentDataDirty semantics asserts on web.
return Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  child: Column(...),
);
```

And the parent seam is a box adapter:

```dart
// packages/client/lib/features/beacon_view/ui/widget/beacon_operational_scroll_view.dart:346-350
SliverPadding(
  padding: tabPadding,
  sliver: SliverToBoxAdapter(child: tabBody),
)
```

A `SliverList` cannot be placed inside that `SliverToBoxAdapter`. Unit 09 must keep a `Column`; it
must not introduce a `ListView` either.

### Change

1. Change `ItemCard` to accept `RequestThread thread`. During the unused transition, provide a
   named `ItemCard.semantic({required CoordinationItem item, ...})` adapter used only by old
   `items_tab.dart`; Unit 12 deletes that adapter and the old tab. The production card remains one
   widget implementation.
2. Branch semantic versus General only on `thread.item` presence. General uses
   `Icon(Icons.forum_outlined, color: context.tt.info)`,
   `threadGeneralTitle`, no parties/status/actions, and its preview/count. Semantic rows retain
   kind/status, avatar trail, stale/overdue ticker, expanded body, all ask/promise/blocker actions,
   overflow, unread badge, and focus flash.
3. Add last-message author/excerpt and timestamp to both branches. Resolve author id from
   `BeaconViewState.myProfile` and `roomParticipants`; show `labelYou` for self and participant title
   when present, otherwise omit the author prefix rather than showing a raw id.
4. Present preview codes exhaustively. Text uses `excerpt`; attachment with no text uses the existing
   attachment label; plan/fact/status/coordination/need-info/done/poll/join use existing l10n semantic
   labels plus the safe title/reason fields. Never decode a system payload. An unknown code is
   impossible because the mapper rejects it.
5. Add design-system keys/values:

   - `labelBeaconTabThreads`: `Threads` / `Темы`
   - `threadGeneralTitle`: `General` / `Общее`
   - `threadClosedFoldTitle(count)`: `Closed ({count})` / `Закрытые ({count})`
   - `threadDraftsFoldTitle(count)`: `Drafts ({count})` / `Черновики ({count})`
   - `threadDraftBadge`: `Draft — not a thread yet` / `Черновик — темы ещё нет`
   - `threadNoActiveItems`: `No active threads yet` / `Активных тем пока нет`

   Replace the old hardcoded `'Closed (...)'`. Use `context.tt`, `TenturaText.*`, and existing
   Tentura controls; no raw `Color`, `TextStyle`, numeric `EdgeInsets`, or numeric `BorderRadius`.
   Secondary actions must be keyboard/secondary-tap reachable with hover affordance; not long-press
   only.
6. Keep the three creation CTAs at the top, gated by
   `BeaconViewState.canCoordinateInBeaconRoom`. Keep `activeForMeOnly`, simplified by Unit 01, and
   `AccordionExpansionGroup`/focus-driven expansion.
7. Build order: General; Active fold; Closed fold; Drafts fold. General is never in a fold. Draft taps
   open the existing composer sheet and never call the thread-open callback.
8. **ASSUMPTION (Q1):** change `coordinationPromiseCardLabel` to `Commitment` /
   `Обязательство`; keep wire/code identifier `promise`.
9. **ASSUMPTION (Q2):** drafts are explicitly badged “not a thread yet”, live in a collapsed Drafts
   fold **after** Closed, and open the composer.
10. **ASSUMPTION (Q3):** when only General exists, keep the creation CTAs and show the empty Active
    fold body `threadNoActiveItems`; add no separate first-run paragraph.
11. **ASSUMPTION (Q5):** use a separate coarse `RelativeTimestampTicker` that ticks at the next
    minute boundary; keep `StaleDeadlineTicker` deadline-driven.
12. **ASSUMPTION (Q6):** regular has no visited/selected residue after returning. The selected-row
    indicator exists only while the expanded split is visible.
13. **ASSUMPTION (Q10):** v1 keeps the boxed `Column`; sliver conversion is out of scope. Do not put a
    `SliverList` inside `SliverToBoxAdapter`.
14. Pin collapsed/expanded light/dark goldens and widget tests for General, active, closed unread,
    draft tap, preview families, empty active state, filter, hover/secondary tap, and no raw user id.
    Add `TestIds.requestThread(String threadId) => 'request.thread.$threadId'` and key every General
    and semantic row with it; drafts have no thread id and keep their draft/composer keys.
15. Bump `packages/client/pubspec.yaml` and the source `flutter_bootstrap.js?v=` cache-buster to
    `6.0.2`. Do not raise the `6.0.0` server minimum for this compatible copy/UI patch.

### Codegen

```bash
cd packages/client
flutter gen-l10n
```

Regenerate the four goldens only with:

```bash
flutter test --update-goldens test/features/beacon_threads/item_card_golden_test.dart
```

Open all four generated PNGs and inspect clipping, contrast, text hierarchy, and expanded/collapsed
content before accepting them; a regenerated file is not a pass by itself.

### Verify

```bash
cd packages/client
flutter test test/features/beacon_threads/threads_list_test.dart
flutter test test/features/beacon_threads/item_card_golden_test.dart
cd ../..
./scripts/check-custom-lints.sh packages/client

! rg -n "SliverList|ListView" packages/client/lib/features/beacon_threads/ui/widget/threads_list.dart
! rg -n "Color\(|Colors\.|TextStyle\(|fontSize:|EdgeInsets\.[a-zA-Z]+\([^)]*[0-9]|BorderRadius\.[a-zA-Z]+\([^)]*[0-9]" \
  packages/client/lib/features/beacon_threads/ui
rg -n '^version: 6\.0\.2$' packages/client/pubspec.yaml
rg -n 'flutter_bootstrap\.js\?v=6\.0\.2' packages/client/web/index.html
```

Passing means all list cases and four goldens are green, the list is a boxed Column, and custom UI
lints report no new token violations. `pubspec.yaml` and `web/index.html` must both say `6.0.2`.

### Done when

The unused Threads list visually and behaviorally supersets the old card list, with all assumptions
implemented and no forbidden scroll or design-system shortcut.

---

## UNIT 10 — Shared thread host with awaited cubit handoff

### Goal

Add the single owner of `openThreadId` and the live `RoomCubit`. A selection change must finish the
old cubit's asynchronous `close()` (including mark-seen) before constructing the next cubit. A keyed
`BlocProvider` is explicitly not the mechanism.

### Depends on

UNIT 09.

### Files

- `packages/client/lib/features/beacon_threads/ui/bloc/thread_host_state.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/bloc/thread_host_cubit.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/widget/thread_host.dart` — **new**
- `packages/client/test/features/beacon_threads/thread_host_cubit_test.dart` — **new**

### Current state

`RoomCubit` starts work in its constructor and flushes on close:

```dart
// post-rename packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart
// baseline lines 35-69
RoomCubit(...) : ... {
  _refreshSub = _case.beaconRoomInvalidations.listen(...);
  ...
  unawaited(load());
}

// baseline lines 1082-1090
Future<void> close() async {
  ...
  await markSeenNowIfNeeded();
  return super.close();
}
```

The old `itemDiscussionProviders` creates a keyed `BlocProvider` at baseline
`item_discussion_pane.dart:18-39`. Provider disposal calls `close()` but does not await it, so an
incoming cubit can read before the outgoing watermark persists. The old screen's correct manual
pattern is:

```dart
// baseline beacon_view_screen.dart, _releaseEmbeddedRoomCubit
final c = _roomCubit;
_roomCubit = null;
if (c != null && !c.isClosed) await c.close();
```

### Change

1. Add Freezed state with `String? openThreadId`, `bool switching`, and monotonically increasing
   `int selectionGeneration`. Do not store this field in `BeaconViewScreen.State` or
   `ThreadDetailScreen.State`.
2. `ThreadHostCubit` owns a private `RoomCubit? _roomCubit`, exposes a read-only getter, and receives
   the beacon id plus an injectable/testable factory:

   ```dart
   typedef RoomCubitFactory = RoomCubit Function({
     required String beaconId,
     String? threadItemId,
     DateTime? initialUnreadAnchorAt,
   });

   ThreadHostCubit({
     required String beaconId,
     RoomCubitFactory roomCubitFactory = RoomCubit.new,
   }) : _beaconId = beaconId, _factory = roomCubitFactory,
        super(const ThreadHostState());
   ```
3. Implement serialized selection with one future tail. A generation check without this queue is
   insufficient: two concurrent `select` calls can both observe `_roomCubit == null` while the first
   close is still running. Use this shape, including recovery of the private tail after an error:

   ```dart
   Future<void> _switchTail = Future<void>.value();

   Future<void> select(RequestThread thread) async {
     final generation = state.selectionGeneration + 1;
     emit(state.copyWith(switching: true, selectionGeneration: generation));
     final operation = _switchTail.then((_) async {
       if (isClosed || generation != state.selectionGeneration) return;
       final old = _roomCubit;
       _roomCubit = null;
       if (old != null && !old.isClosed) await old.close();
       if (isClosed || generation != state.selectionGeneration) return;
       final itemId = thread.threadId == RequestThread.generalId
           ? null
           : thread.threadId;
       _roomCubit = _factory(
         beaconId: thread.item?.beaconId ?? _beaconId,
         threadItemId: itemId,
         initialUnreadAnchorAt: thread.lastSeenAt,
       );
       emit(state.copyWith(
         openThreadId: thread.threadId,
         switching: false,
       ));
     });
     _switchTail = operation.then<void>(
       (_) {},
       onError: (Object _, StackTrace __) {},
     );
     return operation;
   }
   ```

   This queue coalesces rapid selections because stale generations return before construction, but
   every already-created outgoing cubit is awaited. Never create one cubit per row.
4. General must construct `RoomCubit(beaconId:, threadItemId: null)`. Literal `general` must never
   reach any existing room API or `RoomCubit` state.
5. Add `clear()` through the same `_switchTail` queue so it cannot race `select`; it awaits the owned
   cubit and leaves `openThreadId: null`. `close()` first invalidates the generation, awaits
   `_switchTail`, then awaits the owned cubit before `super.close()`.
6. `ThreadHost` is a small `BlocBuilder`/`BlocProvider.value` adapter: while switching show the
   adaptive progress indicator; after selection expose exactly the host-owned cubit to the detail
   child. Do not let a nested provider create/dispose it.
7. Tests use a recording fake cubit whose `close()` completes from a `Completer`. Assert the next
   factory call does not occur until completion, rapid A→B→C constructs only the required latest
   cubit after A closes, General passes null, semantic passes the item id, and host close awaits the
   final mark-seen flush.

### Codegen

```bash
cd packages/client
dart run build_runner build -d
```

### Verify

```bash
cd packages/client
flutter test test/features/beacon_threads/thread_host_cubit_test.dart
cd ../..
./scripts/check-custom-lints.sh packages/client

rg -n "await old\.close\(\)|await .*\.close\(\)" packages/client/lib/features/beacon_threads/ui/bloc/thread_host_cubit.dart
! rg -n "create:.*RoomCubit|key:.*openThread" packages/client/lib/features/beacon_threads/ui/widget/thread_host.dart
```

Passing means the controlled completer proves close-before-create and General/null boundaries.

### Done when

One shared host owns at most one live `RoomCubit`, selection is latest-wins but teardown is strictly
serialized, and no keyed-provider disposal race remains.

---

## UNIT 11 — Nested beacon-view route host and real thread detail page

### Goal

Create a genuine parent route whose wrapper encloses both the operational page and
`ThreadDetailRoute`. Put `ThreadsCubit` and `ThreadHostCubit` in that shared wrapper. Add the distinct
compact/regular detail page and hydrate it from the already-loaded thread list. Do not activate row
navigation or delete legacy routes yet.

### Depends on

UNIT 10.

### Files

- `packages/client/lib/features/beacon_view/ui/screen/beacon_view_host_screen.dart` — **new**
- `packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/screen/thread_detail_screen.dart` — **new**
- `packages/client/lib/features/beacon_threads/ui/widget/thread_detail.dart` — **new**
- `packages/client/lib/consts.dart` — **edit**
- `packages/client/lib/app/router/root_router.dart` — **edit**
- `packages/client/lib/app/router/home_tab_branches.dart` — **edit**
- `packages/client/lib/features/my_work/ui/widget/my_work_beacon_view_pane.dart` — **edit**
- `packages/client/lib/features/inbox/ui/widget/inbox_beacon_view_pane.dart` — **edit**
- `packages/client/test/app/router/request_thread_routing_test.dart` — **new**
- `packages/client/test/features/beacon_threads/thread_detail_test.dart` — **new**
- `packages/client/test/features/beacon_view/beacon_view_room_split_contract_test.dart` — **edit**

### Current state

`BeaconViewCubit` is currently created inside the leaf page wrapper:

```dart
// baseline packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart:193-207
Widget wrappedRoute(_) => localScreenCubitScope(
  child: BlocBuilder<ProfileCubit, ProfileState>(
    builder: (...) => BlocProvider(
      create: (_) => BeaconViewCubit(...),
      child: this,
    ),
  ),
);
```

That wrapper is not an ancestor of a sibling route. Putting `openThreadId` “alongside
`BeaconViewCubit`” in this current location would fail. The router currently registers discussion
and view as siblings:

```dart
// packages/client/lib/app/router/home_tab_branches.dart:103-113
AutoRoute(page: ItemDiscussionRoute.page,
  path: 'beacon/view/:beaconId/discussion/:itemId'),
AutoRoute(page: BeaconViewRoute.page, path: 'beacon/view/:id'),
```

The legacy pane owns its own provider lifecycle:

```dart
// packages/client/lib/features/coordination_item/ui/widget/item_discussion_pane.dart:18-39
Widget itemDiscussionProviders({required CoordinationItem item, required Widget child}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => RoomCubit(
        beaconId: item.beaconId,
        threadItemId: item.id,
        initialUnreadAnchorAt: item.lastSeenAt,
      )),
      BlocProvider(create: (_) => ItemActionsCubit(item: item)),
    ],
    child: child,
  );
}
```

That provider stays only for the legacy route during this additive unit. The new nested detail reads
the parent host's cubit instead.

### Change

1. Introduce a parent host while preserving the generated public route name:

   ```dart
   @RoutePage(name: 'BeaconViewRoute')
   class BeaconViewHostScreen extends StatelessWidget
       implements AutoRouteWrapper {
     const BeaconViewHostScreen({
       @PathParam('id') required this.id,
       @QueryParam(kQueryIsDeepLink) this.isDeepLink,
       @QueryParam(kQueryBeaconViewTab) this.viewTab,
       @QueryParam(kQueryBeaconPeopleTabAttention) this.peopleTabAttention,
       @QueryParam(kQueryBeaconSurface) this.surface,
       @QueryParam(kQueryBeaconEntry) this.entry,
       @QueryParam(kQueryCoordinationItemId) this.coordinationItemId,
       @QueryParam(kQueryThreadId) this.threadId,
       @QueryParam(kQueryMessageId) this.messageId,
       super.key,
     });
     // Declare every constructor field. surface/coordinationItemId are temporary
     // compatibility inputs removed with their producers in Unit 12.
     Widget build(BuildContext context) => const AutoRouter();
     Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
       child: BlocBuilder<ProfileCubit, ProfileState>(
         buildWhen: (p, c) => p.profile.id != c.profile.id,
         builder: (context, profileState) => BlocProvider(
           key: ValueKey('BeaconViewCubit:$id:${profileState.profile.id}'),
           create: (_) => BeaconViewCubit(
             myProfile: profileState.profile,
             id: id,
           ),
           child: MultiBlocProvider(
             providers: [
               BlocProvider(create: (_) => ThreadsCubit(beaconId: id)..fetch()),
               BlocProvider(create: (_) => ThreadHostCubit(beaconId: id)),
             ],
             child: this,
           ),
         ),
       ),
     );
   }
   ```

   The wrapper creates `BeaconViewCubit`, starts one `ThreadsCubit.fetch()`, and creates one
   `ThreadHostCubit`. Because `AutoRouter` is the wrapper's child, all nested pages share them. This
   is the architectural change that makes the provider a real ancestor; do not merely add a provider
   to the old leaf wrapper.
2. Remove `@RoutePage` and `wrappedRoute` from the existing `BeaconViewScreen`; keep it as the
   embeddable operational widget with its current constructor. Add a tiny annotated
   `BeaconViewOperationalScreen` in the host file. It uses `@PathParam.inherit('id')` and reads the
   parent's query parameters, then constructs the existing `BeaconViewScreen`, including the
   temporary legacy `surface` and `coordinationItemId` values. This avoids copying the 1,700-line
   state body and keeps all pre-Unit-12 producers working.
3. Register `BeaconViewRoute` as a parent in both the root redirect-target registration and
   `browseDetailChildren`, with these children in this order:

   ```dart
   AutoRoute(page: BeaconViewOperationalRoute.page, path: '', initial: true),
   AutoRoute(page: ThreadDetailRoute.page, path: 'thread/:threadId'),
   ```

   Root remains `/beacon/view/:id`; compact detail becomes
   `/beacon/view/:id/thread/:threadId`. Register the detail only as a child, never as a sibling.
   In the root redirect guard, preserve a matched child instead of forwarding only the parent. Read
   `final matchedChild = resolver.route.children?.firstOrNull`; when it has a `threadId` path param,
   construct the branch target as:

   ```dart
   BeaconViewRoute(
     id: resolver.route.params.getString('id'),
     // copy the existing parent query arguments verbatim
     children: [
       ThreadDetailRoute(
         threadId: matchedChild!.params.getString('threadId'),
         messageId: resolver.route.queryParams.optString(kQueryMessageId),
       ),
     ],
   )
   ```

   Otherwise give it `children: const [BeaconViewOperationalRoute()]`. Add
   `package:collection/collection.dart` for `firstOrNull`. Losing the child here makes a cold detail
   URL silently land on the list, so the route test must cover this exact guard.
4. Define constants `kQueryThreadId = 'thread'` and `kBeaconViewTabThreads = 'threads'` in
   `packages/client/lib/consts.dart` only if Unit 12 has not yet added them; Unit 11 may add them for
   route tests, but it must not remove old constants yet.
5. Add `thread_detail.dart` by extracting the simplified post-Unit-01 semantic header behavior from
   `ItemDiscussionPane` into `ThreadDetail`. In the same new file add renamed copies of the surviving
   post-D27 `ItemDiscussionTitle`, `ItemDiscussionOverflowAction`, and compact column chrome as
   `ThreadDetailTitle`, `ThreadDetailOverflowAction`, and `ThreadDetailColumnChrome`; the overflow
   continues to delegate ask/promise/blocker lifecycle actions to
   `CoordinationItemDiscussionOverflowMenu`. `ThreadDetail` accepts `RequestThread thread`, renders
   the semantic header only when `thread.item != null`, then renders `BeaconRoomBody` from the host
   cubit. `BeaconRoomBody` takes no thread id. Keep the old pane temporarily so the still-registered
   legacy route remains green in this additive unit; Unit 12 deletes both old files atomically. The
   new `ThreadDetail` must not create a `RoomCubit`; it reads the one exposed by `ThreadHost`.
6. Add `ThreadDetailScreen` with fields
   `@PathParam.inherit('id') required String beaconId`,
   `@PathParam('threadId') required String threadId`, and
   `@QueryParam(kQueryMessageId) String? messageId`. It waits for
   `ThreadsCubit`'s first success, finds the accessible row, calls `await host.select(row)`, and then
   renders:

   - compact/regular `Scaffold` with `TenturaTopBar`, an explicit real back button,
     `ThreadDetailTitle`, and `ThreadDetailOverflowAction` for semantic rows;
   - `ClosedRequestBanner` once on compact/regular only;
   - semantic `ItemActionsCubit` only when `item != null`;
   - unconditional composer; no pending-resolution fetch/banner;
   - `prepareThreadScroll(messageId:, coordinationItemId:)` on the selected `RoomCubit`;
   - `onCoordinationSaved: () => context.read<ThreadsCubit>().fetch()`;
   - inner coordination links as selection/route replacement, not nested pushes.

   Make the screen stateful only for an `_allowPop`/`_exitInProgress` lifecycle latch; never put
   `openThreadId` there. Wrap it in `PopScope(canPop: _allowPop)`. The explicit top-bar back and
   `onPopInvokedWithResult` both call one `_closeThenPop` method that sets the reentrancy latch,
   `await context.read<ThreadHostCubit>().clear()`, sets `_allowPop = true`, rebuilds, and then calls
   `context.router.pop()` once. This is lifecycle teardown, not the deleted Room-vs-Items mode
   machine. The test must hold the fake `RoomCubit.close()` completer and prove the route does not
   pop before it completes.

7. General's detail uses request title, no semantic header, and
   `RoomCubit(threadItemId: null)`. The string `general` remains only route/list/mutation addressing.
8. Unknown or inaccessible detail ids fall back to `ThreadsState.firstAccessible`. That is General
   for room members and the first allowed item for item-only viewers. If the list is empty, show the
   existing admission placeholder; never force General.
9. In the parent host, for an explicit `message` with no thread, use
   `BeaconThreadsCase.fetchMessageTarget(beaconId, messageId)` once, derive
   `threadItemId ?? RequestThread.generalId`, then canonicalize. An explicit thread always wins.
10. Direct embedded widgets bypass AutoRoute wrappers. Update My Work and Inbox pane wrappers to
    create the same `ThreadsCubit` and `ThreadHostCubit` above the direct `BeaconViewScreen`. Do not
    store `openThreadId` inside either embedded page State.
11. Keep the old `ItemDiscussionRoute`, `ItemDiscussionScreen`, and `ItemDiscussionPane` unchanged
    temporarily so this unit is green. Unit 12 deletes the route, both source files, and all
    producers atomically.
12. Route tests must prove a cold detail URL builds parent + detail, an ordinary pop reveals one base
    operational page, and no duplicate `BeaconViewRoute` remains.

### Codegen

```bash
cd packages/client
dart run build_runner build -d
```

AutoRoute inputs changed; never edit `root_router.gr.dart`.

### Verify

```bash
cd packages/client
flutter test test/app/router/request_thread_routing_test.dart
flutter test test/features/beacon_threads/thread_detail_test.dart
flutter test test/features/beacon_view/beacon_view_room_split_contract_test.dart
cd ../..
./scripts/check-custom-lints.sh packages/client

rg -n "children:|ThreadDetailRoute|BeaconViewOperationalRoute" \
  packages/client/lib/app/router/root_router.dart packages/client/lib/app/router/home_tab_branches.dart
! rg -n "openThreadId" packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart \
  packages/client/lib/features/beacon_threads/ui/screen/thread_detail_screen.dart
```

Passing means cold and warm routing tests show one parent, one detail, one ordinary pop, and both
pages read the same host instance.

### Done when

The canonical nested detail route exists and shares real ancestor-scoped list/host state, while the
shipping UI and old producers still compile unchanged.

---

## UNIT 12 — Atomic Threads activation, adaptive host, and legacy removal

### Goal

Switch production to `Threads | People | Log`, wire compact/regular pushes and expanded/embedded
splits, repoint every producer, and delete all old Room/ItemDiscussion entry surfaces in the same
unit. No redirect, alias, or fallback URL remains. Bump client `6.0.2` to `6.1.0` and sync the web
cache-buster.

### Depends on

UNIT 11.

### Files

**Edit**

- `packages/client/lib/consts.dart` — **edit**
- `packages/client/lib/app/router/root_router.dart` — **edit**
- `packages/client/lib/app/router/home_tab_branches.dart` — **edit**
- `packages/client/lib/app/router/notification_deep_link.dart` — **edit**
- `packages/client/lib/domain/attention/destination_map.dart` — **edit**
- `packages/client/lib/features/beacon_view/domain/use_case/beacon_view_case.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_state.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/screen/beacon_view_host_screen.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_operational_scroll_view.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart` — **edit**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_view_constants.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/bloc/thread_host_cubit.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/bloc/threads_cubit.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/screen/thread_detail_screen.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/widget/thread_detail.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/widget/threads_list.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/widget/item_card.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/widget/room_message_tile.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/coordination_room_navigation.dart` — **edit**
- `packages/client/lib/features/beacon_threads/ui/widget/beacon_room_body.dart` — **edit**
- `packages/client/lib/features/beacon_threads/domain/coordination_item_room_sync.dart` — **edit**
- `packages/client/lib/features/my_work/ui/widget/my_work_beacon_view_pane.dart` — **edit**
- `packages/client/lib/features/my_work/ui/screen/my_work_screen.dart` — **edit**
- `packages/client/lib/features/inbox/ui/widget/inbox_beacon_view_pane.dart` — **edit**
- `packages/client/lib/ui/test_ids.dart` — **edit**
- `packages/client/integration_test/support/e2e_test_helpers.dart` — **edit**
- `packages/client/test/app/notification_deep_link_test.dart` — **edit**
- `packages/client/test/domain/attention/destination_map_test.dart` — **edit**
- `packages/client/test/app/router/home_tab_branch_routing_test.dart` — **edit**
- `packages/client/test/features/beacon_view/beacon_view_case_orchestration_test.dart` — **edit**
- `packages/client/test/features/beacon_view/beacon_view_room_split_contract_test.dart` — **edit**
- `packages/client/test/features/beacon_view/promise_composer_live_wiring_test.dart` — **edit**
- `packages/client/test/features/beacon_threads/room_message_tile_coordination_test.dart` — **edit**
- `packages/client/pubspec.yaml` — **edit** (`6.0.2` → `6.1.0`)
- `packages/client/web/index.html` — **edit** (`?v=6.1.0`)
- `packages/server/lib/api/controllers/graphql/mutation/mutation_beacon_room.dart` — **edit**
- `packages/server/lib/domain/use_case/beacon_room_case.dart` — **edit**
- `packages/server/test/domain/use_case/beacon_room_case_mark_seen_test.dart` — **edit**

**Delete**

- `packages/client/lib/features/beacon_view/ui/bloc/items_tab_cubit.dart` — **delete**
- `packages/client/lib/features/beacon_view/ui/bloc/items_tab_state.dart` — **delete**
- `packages/client/lib/features/beacon_view/ui/widget/items_tab.dart` — **delete**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_room_surface.dart` — **delete**
- `packages/client/lib/features/beacon_view/ui/widget/beacon_view_room_app_bar_button.dart` — **delete**
- `packages/client/lib/features/coordination_item/ui/screen/item_discussion_screen.dart` — **delete**
- `packages/client/lib/features/coordination_item/ui/widget/item_discussion_pane.dart` — **delete**
- `packages/client/lib/features/beacon_threads/ui/screen/beacon_room_screen.dart` — **delete**
- `packages/client/test/features/beacon_threads/can_nest_item_discussion_test.dart` — **delete**
- `packages/client/test/features/beacon_view/beacon_items_tab_accordion_test.dart` — **delete**

Every deleted path above is exact. Do not delete any additional test merely because its old name says
Room or Items; repoint mixed-behavior coverage such as `promise_composer_live_wiring_test.dart` to
`ThreadsList`.

### Current state

The operational tab body still selects Items and wraps it as a box:

```dart
// packages/client/lib/features/beacon_view/ui/widget/beacon_operational_scroll_view.dart:140-145
kBeaconTabItems => ItemsTab(
  state: state,
  onOpenItemThread: onOpenItemDiscussion,
  focusItemId: focusItemId,
),
...
// :346-350
sliver: SliverToBoxAdapter(child: tabBody),
```

The old screen tracks multiple competing modes (`_roomCubit`, `_activeThreadItem`,
`_embeddedRoomOpen`, route-sync flags) at baseline `beacon_view_screen.dart:216-240`, and creates item
discussion providers in `_buildRoomPane` at baseline `:1114-1159`. These are replaced by the shared
host, not renamed.

Old producers are concrete and finite:

```dart
// destination_map.dart:17-24
'beacon_room' => ... {tab: 'room'}
'beacon_room_message' => ... {tab: 'room', message: target}

// notification_deep_link.dart:14-24
if (dest == 'room') { tab = 'room'; if (item != null) item=...; }

// room_message_tile.dart:47-67 and coordination_room_navigation.dart:23-43
ItemDiscussionRoute(...)
```

### Change

1. Rename `kBeaconTabItems` to `kBeaconTabThreads`; tab index remains 0. Replace the tab widget and
   bloc provider with `ThreadsList`/`ThreadsCubit`. Rename TestIds
   `beaconTabItems` → `beaconTabThreads`; delete `beaconRoomOpen`. Remove the temporary
   `ItemCard.semantic` adapter added in Unit 09; every surviving caller now passes a
   `RequestThread`. The three CTAs remain.
   Rewrite `promise_composer_live_wiring_test.dart` to drive the actual CTA through `ThreadsList`
   and a `ThreadsCubit` fake while retaining its real `BeaconViewCubit` participant-stream proof.
2. Replace all `_roomCubit`, `_activeThreadItem`, `_embeddedRoomOpen`, room exit/reentrancy, split
   route-sync, and nesting fields/methods with reads/calls to the shared `ThreadHostCubit`. Delete:
   `beaconViewRoomRequestedByRoute`, `beaconViewShowsLegacyRoomSurface`, `_urlIndicatesRoom`,
   `_stripRoomFromUrl`, `_scheduleExpandedRoomRouteSync`,
   `_scheduleExpandedRoomPaneRouteFocusIfNeeded`, `_syncActiveThreadHost`, and
   `_activateExpandedRoomSplit`.
3. Expanded invariant: after first successful list, if no selection choose
   `ThreadsState.firstAccessible`; for room members this is General, for item-only viewers it is
   their first allowed item. Right detail is a sibling of the tab content, so People/Log switches do
   not remove it. Render `ThreadDetailColumnChrome` plus the host-owned `ThreadDetail` in that pane;
   wrap semantic selections in `ItemActionsCubit(item: row.item!)`, while General has no actions
   cubit, uses the request title, and has no semantic overflow. Split only when the list has at least
   one row; do not gate it with
   `canNavigateBeaconRoom` or `canCoordinateInBeaconRoom`.
4. Compact `<600` and regular `600–839` row taps push the real nested
   `ThreadDetailRoute(threadId:, messageId:)`. Expanded `>=840` row taps call awaited host selection and
   update `?tab=threads&thread=...`; they do not push.
5. Add a host-level window-class observer outside every `LayoutBuilder`. On expanded→compact with a
   thread selected, schedule one detail push after dependency change. On compact→expanded while on a
   detail child, set that detail State's `_allowPop = true` **without calling `host.clear()`**, then
   pop the child once after the rebuild; the base renders the same host-owned cubit and selected
   thread in the split. Normal user/browser back still follows Unit 11's awaited `_closeThenPop`.
   Guard both dependency-change actions with one in-flight generation in `ThreadHostCubit` so rapid
   resize cannot double-push/pop. A layout callback must never navigate. `openThreadId` remains in
   `ThreadHostCubit`, never either page State; `_allowPop` is only a route-lifecycle latch.
6. Keep `thread` across People/Log on expanded and ignore it on compact. Unknown/inaccessible values
   fall back to `firstAccessible`, then the admission placeholder. Never bounce an item-only viewer
   to General.
7. The My Work embedded split predicate uses the **pane constraints width**, not
   `context.windowClass`. Above threshold, select pane-locally and sync canonical query state. Below
   threshold call one new `onRequestThreadRoute(threadId, messageId)` callback so the host pushes the
   canonical URL. Delete `suppressEmbeddedRoomBack`, `embeddedRoomCloseNonce`,
   `onEmbeddedRoomOpenChanged`, `_notifyEmbeddedRoomOpen`, and their forwarders. Apply the same safe
   route callback to the Inbox pane.
8. Preserve the boxed `Column` from Unit 09. `SliverList` cannot be placed in the existing
   `SliverToBoxAdapter`; do not add a nested `ListView`.
9. Delete the app-bar Chat button and every `onEnterRoomSurface` call. Repoint overflow, status sheet,
   and screen call sites to open/select `RequestThread.generalId`. The status action previously
   phrased “resolve in Chat” must still have a live callback to General.
10. Repoint `room_message_tile.dart` and `coordination_room_navigation.dart` to host selection or
    `ThreadDetailRoute`; delete `canNestItemDiscussionInRoomPane` and its test. An inner item link
    changes selection/replaces sibling detail; it never stacks another detail.
11. For Log rows, use `e.coordinationKind`. Ask/promise/blocker focuses that thread. **Plan and plan
    step rows focus General and call `prepareThreadScroll` with `e.sourceMessageId` as the anchor.**
    Plan remains a live kind excluded from the list; do not drop its tap behavior.
12. `onCoordinationSaved` must call `ThreadsCubit.fetch()` immediately; do not wait for debounced
    invalidation.
13. Rewrite destination producers:

    - `beacon_room` → `?tab=threads&thread=general`;
    - `beacon_room_message` → `?tab=threads&message=<id>` with no thread, so the host resolves the
      actual message target;
    - app link `dest=room&item=<id>` → `?tab=threads&thread=<id>`;
    - app link `dest=room` without item → General.

14. Delete `?tab=room`, `?surface=room`, `kQueryBeaconSurface`,
    `kBeaconSurfaceRoomQueryValue`, `kQueryCoordinationItemId` (actual value `item`),
    `kPathBeaconRoom`, `BeaconRoomRoute`, `ItemDiscussionRoute`, their root and branch registrations,
    and legacy tab aliases `details`, `forwards`, `overview`, `helpOffers`, `activity`, `timeline`.
    Keep `kQueryMessageId = 'message'`. Add no redirect or alias.
15. Delete only beacon-view consumers `BeaconViewState.roomUnreadCount` and
    `_effectiveRoomUnreadCount` plus `BeaconViewCubit`'s `_serverUnreadCount`, `_serverSeenAt`,
    watermark subscription/handlers, snapshot fetches, and the corresponding
    `BeaconViewCase.readWatermarkChanges`, `readThrough`, `resolveRoomUnread`, and
    `fetchRoomUnreadSnapshot` forwarding methods. Remove only that forwarding assertion from
    `beacon_view_case_orchestration_test.dart`. Keep
    `inbox_room_context_batch.graphql.roomUnreadCount`, Inbox, and My Work consumers: that shared
    hints source is live. Also keep `BeaconThreadsCase`'s General compatibility watermark stream and
    helpers from Unit 06 because Inbox and My Work still call them.
16. General always constructs `RoomCubit(threadItemId: null)`. The string `general` must not reach
    list/send/fact/plan/state methods. The server query's authorization union, not a client room
    guard, determines accessible rows.
17. Delete the old server GraphQL `beaconParticipantRoomSeen` and `markBeaconRoomSeen` resolver
    fields and their alias method now that Unit 06 has no producer. Keep `markThreadSeen` and its
    General/semantic branch logic. Update tests; do not alter the two partial-index writes.
18. Update e2e helpers: `enterChatIfNeeded` → `enterGeneralIfNeeded` by tapping
    `beaconTabThreads` then
    `TestIds.requestThread(RequestThread.generalId)`; `enterItemsIfNeeded` →
    `enterThreadsIfNeeded`. Delete the old `if (roomMessageInput is visible) return` shortcut from
    `enterGeneralIfNeeded`: a visible composer may belong to a semantic thread. Instead,
    `sendRoomMessage` first sends in the already-visible current thread, and calls
    `enterGeneralIfNeeded` only when no composer is visible. Change `createCoordinationItem` to return the created
    `RequestThread`: after submit, wait for the row with the submitted title, read its public
    `ItemCard.thread`, and return it. Existing callers may ignore the return; the Unit-14 integration
    test uses `thread.item!.beaconId` and `thread.threadId` for canonical cold URLs. Likewise change
    `sendRoomMessage` to return the sent `RoomMessage`: after submit, wait for the tile containing the
    exact text and return
    `tester.widget<RoomMessageTile>(find.ancestor(of: find.text(text), matching:
    find.byType(RoomMessageTile)).first).message`; existing callers may ignore it. Update all callers.
    The e2e suite is not covered by `flutter test`, so this cannot be deferred.
19. Bump client `6.0.2` and its cache-buster to `6.1.0`. Do not raise the `6.0.0` server minimum: the server API
    remains compatible with the already-gated 6.x client.
20. Add/extend tests for expanded co-visibility across People/Log, first-accessible fallback,
    message lookup canonicalization, compact/regular pop, window-class transitions, pane-width
    embedded behavior, plan-log General focus, direct item focus, and immediate list refresh.

### Codegen

```bash
cd packages/client
dart run build_runner build -d
```

AutoRoute pages were deleted/changed. Do not edit generated routes.

### Verify

```bash
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
cd packages/server
dart test test/domain/use_case/beacon_room_case_mark_seen_test.dart
dart test --exclude-tags pg
cd ../client
flutter test test/app/notification_deep_link_test.dart
flutter test test/domain/attention/destination_map_test.dart
flutter test test/app/router/request_thread_routing_test.dart
flutter test test/features/beacon_threads/thread_host_cubit_test.dart
flutter test test/features/beacon_threads/thread_detail_test.dart
flutter test
cd ../..
bash scripts/check-user-facing-terminology.sh

! rg -n "ItemDiscussionRoute|BeaconRoomRoute|kPathBeaconRoom|tab=room|surface=room|kQueryBeaconSurface|kQueryCoordinationItemId|BeaconParticipantRoomSeen|MarkBeaconRoomSeen" \
  packages/client/lib packages/client/test packages/client/integration_test packages/server/lib packages/server/test
! rg -n "suppressEmbeddedRoomBack|embeddedRoomCloseNonce|onEmbeddedRoomOpenChanged|beaconViewRoomRequestedByRoute|beaconViewShowsLegacyRoomSurface|canNestItemDiscussionInRoomPane" \
  packages/client/lib packages/client/test packages/client/integration_test
rg -n "roomUnreadCount" \
  packages/client/lib/features/inbox packages/client/lib/features/my_work packages/client/lib/features/beacon_threads/data/repository
! rg -n "roomUnreadCount" packages/client/lib/features/beacon_view
rg -n '^version: 6\.1\.0$' packages/client/pubspec.yaml
rg -n 'flutter_bootstrap\.js\?v=6\.1\.0' packages/client/web/index.html
rg -n "kDefaultMinClientVersion = '6\.0\.0'" packages/server/lib/env.dart
```

Passing means all forbidden routing/state symbols are absent from `lib`, `test`, and
`integration_test`; the shared hints consumers remain; full client/server gates are green; and
version/cache-buster agree at `6.1.0`.

### Done when

Threads is the only Request conversation entry, all adaptive modes use the shared awaited host, every
producer emits canonical thread navigation, and no legacy URL/screen/state machine survives.

---

## UNIT 13 — D28 copy, glossary, normative spec, and final patch version

### Goal

Retire user-facing Chat using three distinct senses: one conversation surface → General/Threads;
admission/membership envelope → discussion; fact visibility boundary → discussion. Apply the same
vocabulary to ARBs, server notification/error copy, landing onboarding, and normative docs. Do not
rename internal storage, protocol, environment, method, or historical architecture identifiers.

Bump client `6.1.0` to `6.1.1` and sync the cache-buster.

### Depends on

UNIT 12.

### Files

- `packages/client/l10n/app_en.arb` — **edit**
- `packages/client/l10n/app_ru.arb` — **edit**
- `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart` — **edit**
- `packages/server/lib/domain/notification/beacon_notification_batch_aggregator.dart` — **edit**
- `packages/server/lib/domain/use_case/attention_intent_case.dart` — **edit**
- `packages/server/lib/domain/use_case/beacon_room_case.dart` — **edit descriptions only**
- `packages/server/test/domain/notification/beacon_notification_copy_builder_test.dart` — **edit**
- `packages/server/test/domain/notification/beacon_notification_batch_aggregator_test.dart` — **edit**
- `packages/server/test/domain/attention/attention_intent_case_test.dart` — **edit**
- `packages/server/test/domain/use_case/beacon_room_case_message_mutations_test.dart` — **edit descriptions/test names only where asserted**
- `packages/landing/onboarding.js` — **edit**
- `.cursor/rules/terminology.mdc` — **edit**
- `AGENTS.md` — **edit**
- `CONTEXT.md` — **edit**
- `docs/features/beacon_room.md` — **edit** (replace its entire body)
- `docs/README.md` — **edit**
- `packages/client/pubspec.yaml` — **edit** (`6.1.0` → `6.1.1`)
- `packages/client/web/index.html` — **edit** (`?v=6.1.1`)

### Current state

The glossary currently assigns the whole workspace to Chat:

```markdown
<!-- .cursor/rules/terminology.mdc:10-15 -->
| Layer | Primary object | Coordination workspace |
| User-facing | Request / Requests | Chat |
Russian: запрос / запросы; workspace чат.
```

The ARB value matcher, not a remembered count, defines the sweep:

```bash
jq -r 'to_entries[] | select((.key|startswith("@")|not) and
  (.value|type=="string") and (.value|test("[Cc]hat"))) | .key' \
  packages/client/l10n/app_en.arb
jq -r 'to_entries[] | select((.key|startswith("@")|not) and
  (.value|type=="string") and (.value|test("чат";"i"))) | .key' \
  packages/client/l10n/app_ru.arb
```

The RU substring matcher also matches unrelated words such as `получатель` and `начать`. Those false
positives are an explicit survivor allow-list below, not copy to rewrite.

### Change

1. Edit the glossary **only in this unit**:

   | Level | EN | RU | Use |
   |---|---|---|---|
   | primary object | Request | запрос | unchanged |
   | whole conversation space | discussion | обсуждение | admission, membership, access, fact visibility |
   | one conversation | thread | тема | tab rows; built-in row is General / Общее |

   `.cursor/rules/terminology.mdc` retains a single workspace column and sets it to discussion. Sync
   the same table/invariant in `AGENTS.md` and `CONTEXT.md`. Never introduce a `Request` domain entity.
2. Rewrite `docs/features/beacon_room.md` in place as the normative Threads behavior: three tabs
   Threads/People/Log; General plus Ask/Commitment/Blocker; active/closed/draft rules; union access;
   compact/regular detail routes; expanded and embedded split; per-thread unread; no resolutions;
   discussion admission/fact visibility. Remove the false Items + separate Room architecture.
3. Update `docs/README.md`'s feature description and terminology-check description. Do not edit
   `request-threads-architecture.md`; its historical revision prose remains authoritative context.
4. Free “discussion” from its old one-item meaning in the same ARB edit:

   - delete retired `coordinationItemDiscussionTitle`;
   - `coordinationItemDiscussionComposerHint` → `Write in the thread…` /
     `Написать в тему…`;
   - `beaconRoomActionOpenThread` → `Open thread` / `Открыть тему`.

5. **Surface sense — use General or Threads, never discussion blindly.** Update these exact key
   families: `beaconSituationOpenRoom`, `beaconBlockersPanelAskInRoom`,
   `beaconCloseSheetActionResolveRoom`, `beaconDefinitionLastRoomChangeLabel`, `beaconRoomTitle`,
   `beaconRoomOpen`, `beaconRoomBackToChat`, `beaconRoomStripOpenBlockerHint`,
   `inboxCardRoomUnread`, `inboxCardRoomCurrentLine`, `inboxCardRoomLastChange`,
   `updatesFallbackTitleRoomMessagePosted`, `updatesFallbackBodyRoomMessagePosted`,
   `updatesFallbackBodyStaleReminder`, `updatesFallbackBodyCommitmentRedirected`, and
   `notificationSettingsInAppCoordinationDesc`. General-specific counts/current-line copy says
   General; multi-thread notifications say thread/Threads.
6. **Admission/membership sense — discussion.** Update these exact keys:
   `introPage2Text`, `notificationCatCoordinationDesc`,
   `beaconViewRoomAccessUnavailableBanner`, `coordinationResponseRoomAdmits`,
   `coordinationResponseRoomNoAdmission`, `coordinationInviteToRoomRow`, `beaconRoomNoAdmission`,
   `beaconClosurePanelBodyReview`, `beaconPeopleLensRoomMembersHeading`,
   `beaconHudActEffectReviewOffers`, `beaconHudActEffectForward`,
   `beaconHudConfirmCloseNowBody`, `helpOfferAdmissionAcceptHint`,
   `helpOfferAdmissionDeclineHint`, `beaconStatusRowOutcomeClosed`, `beaconHeaderRoomCount`,
   `helpOfferAdmissionRemove`, `helpOfferCanReadChat`, `helpOfferRemoveDialogTitle`,
   `helpOfferRemoveKeepsParticipationNote`, `helpOfferRemovedWithReason`,
   `helpOfferPreviousRemoveContext` (RU), `beaconRoomSemanticParticipantJoined`,
   `beaconRoomParticipantJoinedAutoAdmit`, `beaconRoomParticipantJoinedByActor`,
   `coordinationCreatePromiseNoTargets`, `beaconActivityParticipantRemoved`,
   `beaconActivityParticipantJoined`, `beaconActivityCoordinationFallback`,
   `beaconPeopleStatusRemovedFromChat`, `updatesFallbackTitleOfferAccepted`,
   `updatesFallbackBodyOfferAccepted`, `updatesFallbackTitleOfferRemoved`,
   `updatesFallbackBodyOfferRemoved`, `availabilityUnaffectedNote`, and
   `availabilityPauseSectionDescription`.
7. **Fact-visibility sense — discussion.** Update exactly:
   `beaconRoomPinFactPublic`, `beaconRoomPinFactRoomOnly`, `beaconRoomSemanticRoomFact`,
   `beaconRoomMessagePinnedFactChipPrivate`, `beaconRoomFactCardVisibilityChat`,
   `beaconRoomFactCardActionMakePrivate`, and `beaconRoomFactCardRemoveConfirmBody`. “Thread only” is
   wrong: fact visibility is request/discussion-scoped.
8. Delete obsolete `labelBeaconTabRoom` and `labelBeaconTabItems` keys and metadata.
   `labelBeaconTabThreads` remains Threads / Темы. Keep `notificationCatUnblocksMe` exactly `Resolutions` in EN and
   `Разблокировки` in RU; it is the unblocks category, unrelated to D27.
9. Rewrite user-visible fallback strings in the four server source files. Access/removal copy uses
   discussion; room-message notification copy uses thread; errors become “same thread scope” and
   “Message is not on this request”. Update exact tests. Do **not** rename internal
   `sendChatNotification`, `chatStatusOfflineAfterDelay`, `directedChatTarget`,
   `removedFromChat`/`readmittedToChat`, env `CHAT_OFFLINE_DELAY`, migration identifiers, or test data.
10. Change `packages/landing/onboarding.js:29` from “request's chat” to “request's discussion”.
11. Preserve these RU matcher false positives unchanged:

    `availabilityDeliveredPartialMany`, `availabilityResumeEcho`, `beaconCloseSheetReadyReviewBody`,
    `beaconForwardPersonUnreachable`, `beaconItemsActiveForMeFilterSemantics`, `beaconNeedsHelper`,
    `beaconRecipients`, `beaconRecipientsBlockedBannerBody`, `beaconRecipientsPreselectDropped`,
    `beaconSendRequestBlockedRecipients`, `buttonStart`,
    `coordinationComposerNoTargetWillSaveDraft`, `coordinationComposerTargetGuidance`,
    `coordinationComposerTargetNone`, `forwardOverlaySearchHint`, `notificationQuietHoursEnable`,
    `selectRecipients`.

12. Bump client and cache-buster to `6.1.1`. Do not raise the server minimum for a copy-only patch.

### Codegen

```bash
cd packages/client
flutter gen-l10n
dart run build_runner build -d
```

### Verify

```bash
cd packages/server
dart test test/domain/notification/beacon_notification_copy_builder_test.dart
dart test test/domain/notification/beacon_notification_batch_aggregator_test.dart
dart test test/domain/attention/attention_intent_case_test.dart
dart test test/domain/use_case/beacon_room_case_message_mutations_test.dart
cd ../..

test -z "$(jq -r 'to_entries[] | select((.key|startswith("@")|not) and (.value|type=="string") and (.value|test("[Cc]hat"))) | .key' packages/client/l10n/app_en.arb)"

test "$(jq -r 'to_entries[] | select((.key|startswith("@")|not) and (.value|type=="string") and (.value|test("чат";"i"))) | .key' packages/client/l10n/app_ru.arb | sort | paste -sd, -)" = \
"availabilityDeliveredPartialMany,availabilityResumeEcho,beaconCloseSheetReadyReviewBody,beaconForwardPersonUnreachable,beaconItemsActiveForMeFilterSemantics,beaconNeedsHelper,beaconRecipients,beaconRecipientsBlockedBannerBody,beaconRecipientsPreselectDropped,beaconSendRequestBlockedRecipients,buttonStart,coordinationComposerNoTargetWillSaveDraft,coordinationComposerTargetGuidance,coordinationComposerTargetNone,forwardOverlaySearchHint,notificationQuietHoursEnable,selectRecipients"

! rg -n -i "chat|чат" packages/landing/onboarding.js \
  .cursor/rules/terminology.mdc AGENTS.md CONTEXT.md docs/features/beacon_room.md
! rg -n -i "chat" \
  packages/server/lib/domain/notification/beacon_notification_copy_builder.dart \
  packages/server/lib/domain/notification/beacon_notification_batch_aggregator.dart

rg -n 'notificationCatUnblocksMe.*Resolutions' packages/client/l10n/app_en.arb
rg -n 'notificationCatUnblocksMe.*Разблокировки' packages/client/l10n/app_ru.arb
rg -n '^version: 6\.1\.1$' packages/client/pubspec.yaml
rg -n 'flutter_bootstrap\.js\?v=6\.1\.1' packages/client/web/index.html

bash scripts/check-user-facing-terminology.sh
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
cd packages/client && flutter test
```

Passing means EN has no Chat values, RU has only the exact false-positive key allow-list, server and
landing user copy is clean, internal chat-named APIs remain, the normative docs agree, all gates are
green, and version/cache-buster agree at `6.1.1`.

### Done when

Every user surface consistently distinguishes Request → discussion → thread/General, fact visibility
uses discussion rather than thread, and no broad internal rename or unrelated resolution deletion
occurred.

---

## UNIT 14 — Final adaptive integration and QA

### Goal

Prove the complete plan at real navigation and enforcement boundaries across compact, regular,
expanded, resize transitions, and the My Work embedded pane. This unit changes no production source
and does not mark a manual row passed from code inspection alone.

### Depends on

UNIT 13.

### Files

- `packages/client/test/features/beacon_threads/request_threads_adaptive_test.dart` — **new**
- `packages/client/integration_test/request_threads_navigation_test.dart` — **new**

Use the exact General/Threads helpers already created in Unit 12. Do not edit production or shared
test-support source in this final QA unit.

### Current state

The integration runner is the repository-supported web path:

```bash
# scripts/run_client_integration_web_local.sh:6-14
./scripts/run_client_integration_web_local.sh integration_test/<file>.dart
# starts dependencies and runs flutter drive -d web-server in headless Chrome
```

The final behavior is distributed across Units 03–13; no existing single test exercises all four
adaptive surfaces or a cross-window-class route transition.

### Change

1. Add a deterministic widget harness with surface sizes:
   compact `390×844`, regular `720×900`, expanded `1280×900`, and an expanded My Work shell whose
   embedded beacon pane is tested once below and once above the split threshold.
2. Compact assertions: Threads is tab 0; General is row 0 when accessible; semantic tap pushes
   `/thread/<id>`; back reveals the list exactly once; General's cubit has null thread id; draft tap
   opens composer and never a route.
3. Regular assertions: same push/pop model as compact, no split, and no visited/selected residue
   after return (Q6 assumption).
4. Expanded assertions: first accessible row preselects; right pane remains visible while switching
   People and Log; selecting another row awaits old close; selected indicator moves; URL has
   `tab=threads&thread=...`; no duplicate detail page is stacked.
5. Resize assertions: expanded→compact pushes the selected detail from the host observer, not a
   layout callback; compact detail→expanded pops itself once and shows the same thread in the split;
   rapid resize does not double-push/pop.
6. Item-only authorization fixture: non-admitted creator/target/accepter sees their semantic row and
   no General; unknown thread falls back to their first row; empty access shows the admission
   placeholder. Do not fake this with `canNavigateBeaconRoom`; use the server result fixture shape.
7. Unread assertions: General + active tab badge, closed exclusion until fold display, own messages
   not unread, read-to-bottom optimistic suppression, and no flicker while awaited close/refetch is
   in flight.
8. Log assertions: ask/promise/blocker opens its thread; plan/plan-step opens General and scrolls to
   `sourceMessageId`.
9. My Work embedded assertions: pane width, not window class, selects split; below threshold invokes
   host route callback; above threshold remains pane-local; People/Log keep the right pane.
10. The web integration test uses `bootstrapFixture`, `createAndForwardRequest`, and
    `openRequestFromMyWork`; then `createCoordinationItem` returns the semantic `RequestThread` and
    `sendRoomMessage` inside that selected thread returns its `RoomMessage`. Use
    `launcherId: TestIds.coordinationBlockerCreate` so the fixture creates a published semantic
    thread without requiring a target-picker interaction; tap
    `TestIds.requestThread(thread.threadId)` and wait for `roomMessageInput` before sending. Use those ids for direct
    full-path navigation to `/beacon/view/<beaconId>/thread/general` and for a message-only
    `?tab=threads&message=<messageId>` URL; assert the latter canonicalizes to the semantic
    `threadId`, not General. Exercise a semantic switch, the real top-bar back button, one
    `web.window.history.back()` round-trip, and one My Work embedded selection. The cold-start match
    itself is already pinned by Unit 11's fresh-router test; do not relabel warm `goToPath` as cold.
    Do not use a legacy room URL.
11. Run all PG tests against disposable databases. `m0149`, threads query, and seen-upsert tests must
    assert their database names start `tentura_test_` and are not `postgres`.
12. After automation, perform an interactive visual pass at compact `390×844`, regular `720×900`,
    expanded `1280×900`, and My Work with the embedded pane immediately below/above its threshold,
    in light and dark themes and once at text scale `1.3`. Check row clipping, 48dp tap targets,
    focus/hover affordances, pane persistence, composer reachability, and back behavior. Keep every
    matrix row `PENDING` until that exact surface is observed; never infer a manual pass from widget,
    DOM, golden, or documentation evidence. Report unavailable rows as pending with the exact
    environment blocker.

### Codegen

None.

### Verify

```bash
docker compose up -d postgres

cd packages/server
dart test --exclude-tags pg
dart test --tags pg test/data/database/m0149_resolution_removal_migration_test.dart
dart test --tags pg test/data/repository/beacon_threads_repository_pg_test.dart
dart test --tags pg test/data/repository/beacon_room_seen_upsert_pg_test.dart
cd ../..

cd packages/tentura_lints
dart test
cd ../..
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh

cd packages/client
flutter test test/features/beacon_threads/request_threads_adaptive_test.dart
flutter test
cd ../..
./scripts/run_client_integration_web_local.sh integration_test/request_threads_navigation_test.dart

! rg -n "ItemDiscussionRoute|BeaconRoomRoute|kPathBeaconRoom|tab=room|surface=room|CoordinationItemKind\.resolution|coordinationItemKindResolution" \
  packages/client/lib packages/client/test packages/client/integration_test \
  packages/server/lib packages/server/test
```

Passing means every command exits 0 and each adaptive assertion was actually executed. If Chrome or
PostgreSQL infrastructure is unavailable, report that exact gate pending; do not convert DOM,
widget, or documentation evidence into an integration pass. Manual matrix rows pass only from the
interactive observations in step 12.

### Done when

All automated unit, PG, lint, Flutter, terminology, and web integration gates pass; compact, regular,
expanded, resize, and My Work embedded behavior each has causal test evidence; every manual matrix
row has an observed pass (otherwise the unit remains pending); and the final forbidden-symbol gate
is empty across both production and tests.

---

## Consolidated assumptions

These are the only rev-6 §16 questions that remain open. Each is also marked `ASSUMPTION:` inside
its owning unit. Q7–Q9 and Q11–Q13 are closed decisions and are implemented, not assumed.

| Question | Owning unit | Concrete default |
|---|---|---|
| Q1 — Promise label | UNIT 09 | User-facing `Commitment` / `Обязательство`; wire/code remains `promise`. |
| Q2 — Draft treatment/order | UNIT 09 | Explicit “not a thread yet” badge; collapsed Drafts fold after Closed; tap opens composer. |
| Q3 — General-only empty state | UNIT 09 | Keep CTAs and show the empty Active fold line; no extra first-run paragraph. |
| Q4 — Excerpt length | UNIT 03 | Server truncates to 140 Unicode characters. |
| Q5 — Timestamp buckets | UNIT 09 | Separate minute-boundary relative-time ticker; stale-deadline ticker remains deadline-driven. |
| Q6 — Regular selected affordance | UNIT 09 | No visited/selected residue after returning; selected indicator is expanded-only. |
| Q10 — Sliver architecture | UNIT 09 | v1 keeps the boxed `Column`; no `SliverList` in `SliverToBoxAdapter`, no nested `ListView`. |
