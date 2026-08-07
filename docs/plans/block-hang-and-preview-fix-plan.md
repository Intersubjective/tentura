---
status: ready
kind: plan
---

# Fix blocking hang, unscoped invalidation, missing confirmation, and capped-preview gap (issue #111)

**Status:** ready for execution.
**Date:** 2026-08-07.
**Scope:** client-only fix for
[Intersubjective/tentura#111](https://github.com/Intersubjective/tentura/issues/111)
("Make blocking atomic, scoped and immediately visible"), a P0 regression from
the 2026-08-04 usability session (parent #96, DEF-06 in the compact buglist).
No server changes are needed — see §0.3.
**Journal:** [`block-hang-and-preview-fix-journal.md`](block-hang-and-preview-fix-journal.md)
(create on first run; not itself a work unit).

---

## 0. Why this plan exists

### 0.1 The reported symptom

Two failures were reported from the same session (issue #111, DEF-06):

1. After pressing `Block`, the person's profile stayed visible with no
   confirmation that anything happened.
2. Blocking a user with "also hide people they invited" (cascade) enabled
   caused **My People** (the trust graph screen, `GraphCubit`) to hide or hang
   — unrelated direct friends appeared to disappear, and the loading state
   sometimes never resolved.

### 0.2 Root cause, verified against live code (not the transcript's guess)

**Bug A — the GraphQL transport has no timeout, so any server stall becomes a
permanent hang.** `ClientParams.requestTimeout` is threaded all the way from
`RemoteApiService` (`packages/client/lib/data/service/remote_api_service.dart:35`,
`const Duration(seconds: kRequestTimeout)` = 15s,
`lib/consts.dart:55`) down to `buildClient()`
(`packages/client/lib/data/service/remote_api_client/build_client.dart:23`) —
but it is **never applied** to the `Link.from([...])` chain built there
(confirmed: no `.timeout(` anywhere in that file). Every repository call ends
in `remoteApiService.request(req).firstWhere((e) => e.dataSource ==
DataSource.Link)` (`packages/client/lib/data/repository/remote_repository.dart:24-26`,
same pattern in `BlockRepository`). If the server stalls, that `Future` never
completes — no exception, no timeout, nothing.

**Bug B is downstream of Bug A, not a separate defect.** `GraphCubit._fetch()`
(`packages/client/lib/features/graph/ui/bloc/graph_cubit.dart:628-895`) only
ever leaves `StateStatus.isLoading` from its `catch` (line 884) or `finally`
(line 890) blocks. That is already correct — `catch (e)` emits `ShowError(e)`
and resets status. It just never runs, because nothing upstream ever throws
(Bug A). **Fixing Bug A makes the existing catch/finally logic work as
designed; no change to `_fetch()`'s control flow is needed.**

**Why chain-block triggers this more than a plain block:** direct block is one
fast insert (`UserBlockCase.block()`,
`packages/server/lib/domain/use_case/user_block_case.dart:54-81`). Cascade
block defers a subtree walk to `BlockCascadeCase.runDue()`
(`packages/server/lib/domain/use_case/block_cascade_case.dart`), which writes
each cascaded pair through `trust_rebuild_effective_edge` into the embedded
MeritRank engine in batches of up to `blockCascadeBatchSize`
(`packages/server/lib/env.dart:274-277`) — plausibly contending with the
concurrent MeritRank read `public.graph(...)` that My People depends on. This
is a plausible contributing factor but **not required to reproduce the bug**:
Bug A means *any* transient server slowness after *any* block turns into a
permanent spinner. Fixing Bug A removes the failure mode regardless of its
trigger; no server-side profiling or change is part of this plan (see §6).

**The "unrelated friends disappear" half is a separate, proven defect.**
`GraphCubit._onBlockVisibilityChanged`
(`packages/client/lib/features/graph/ui/bloc/graph_cubit.dart:212-249`) fires
on **every** block/unblock event system-wide and unconditionally wipes the
entire client-side graph cache (`graphController.clear()`, `_nodes.clear()`,
`_allEdges.clear()`, …), then re-fetches only a `kFetchWindowSize = 5`
(`packages/client/lib/consts.dart:8`) window around the ego node — regardless
of whether the (un)blocked user has anything to do with what is currently on
screen. Any previously-expanded neighbourhood is lost.

**Missing confirmation (item 1) is also proven and narrow.**
`BlockUserSheetBody._confirmBlock`
(`packages/client/lib/features/block/ui/sheet/block_user_sheet.dart:95-108`)
does only `Navigator.of(context).pop()` on success — no snackbar. Separately,
`ProfileViewCubit` (`packages/client/lib/features/profile_view/ui/bloc/profile_view_cubit.dart`)
subscribes to `_case.projectionChanges(id)` (trust/vote changes) but never to
`BlockCase.changes`, so the profile screen underneath the closed sheet has no
trigger to refresh and reflect the new block state.

### 0.3 "N users will also be blocked" is already shipped — do not rebuild it

Before drafting this plan, `packages/client/lib/features/block/ui/sheet/block_user_sheet.dart`
was read in full and confirmed live: it already runs a debounced
`BlockCase.preview()` call (`:77-93`) against the server's `blockPreview`
V2 query and renders `l10n.blockPreviewCascade(preview.cascadeCandidateCount)`
(`:168`, copy: "{count} additional people would be hidden") whenever the
cascade switch is on. This was built in commit `db3de0b7` ("Add block user
confirmation sheet with cascade preview (S19)"), part of the original
`user-block-implementation-spec.md` S1–S24 delivery
(`docs/plans/user-block-implementation-journal.md`).

The one real gap, confirmed by the user for this plan: the server already
computes `BlockPreview.cascadeCapped`
(`packages/server/lib/data/repository/user_block_repository.dart:311-314`,
true when the real cascade would exceed `blockCascadeMaxRows`, default 5000)
and it flows all the way to the client entity
(`packages/client/lib/features/block/domain/entity/user_block.dart:28`), but
`block_user_sheet.dart` never reads it — a user blocking a huge subtree sees a
flat number with no "at least" qualifier. **This plan's "N users will also be
blocked" work item is P4 below: surface `cascadeCapped`, nothing else.**

## 1. Rules (repo-wide invariants — read before editing)

- Never hand-edit generated files: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, `packages/client/lib/ui/l10n/**`, `**/_g/**`. Only run
  codegen.
- After editing `packages/client/l10n/*.arb`: `cd packages/client && flutter
  gen-l10n` (before any client `build_runner`).
- No raw visual constants in client UI (`Color`, `TextStyle(...)`,
  `EdgeInsets.all(8)`, …) — only design-system tokens (`context.tt`,
  `TenturaText.*`). None of the phases below need new visual constants; reuse
  what the sheet/screen already use.
- Do not widen scope. The delayed (up to ~1 minute) visibility of a fully
  materialized cascade, and any MeritRank write/read contention, are real but
  are explicitly **out of scope** — see §6. Do not attempt to make cascade
  materialization synchronous or add a polling/subscription mechanism as part
  of this plan.
- Preserve all pre-existing uncommitted changes in the working tree (there are
  unrelated in-progress doc/server edits as of plan authoring — diff first,
  edit around them, never revert them).
- This is a client-only plan. Do not touch `packages/server/**` or any
  migration.

## 2. Verification commands

```bash
cd packages/client && flutter analyze
cd packages/client && flutter test
```

Run the relevant subset after each phase (see each phase's **Verification**);
run the full set at the end.

---

## Phase P1 — Wire up the GraphQL transport timeout

**File:** `packages/client/lib/data/service/remote_api_client/build_client.dart`

Add `import 'dart:async';` alongside the existing `import 'dart:developer';`.

Add a new private link, placed **first** in the `Link.from([...])` list at
line 44 so it wraps every downstream link (Dedupe, Auth, Error, V2 routing,
HTTP transport) — a hang anywhere in that pipeline must be caught, not just a
hang in the HTTP call itself:

```dart
/// Uploads stream large multipart bodies over potentially slow connections
/// and must not be capped here — [V2UploadMultipartLink] already carries
/// them unbounded today; this link must not change that. Every other
/// operation must complete or fail within [timeout] instead of hanging the
/// caller (and therefore the UI's loading state) forever.
class _TimeoutLink extends Link {
  _TimeoutLink(this.timeout);

  final Duration timeout;

  static const _unboundedOperationNames = {
    'BeaconAddImage',
    'BeaconStageImage',
    'BeaconSetMedia',
  };

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final stream = forward!(request);
    if (_unboundedOperationNames.contains(request.operation.operationName)) {
      return stream;
    }
    return stream.timeout(
      timeout,
      onTimeout: (sink) => sink.addError(
        mapRemoteFailure(
          TimeoutException('GraphQL request timed out', timeout),
        ),
      ),
    );
  }
}
```

Insert `_TimeoutLink(params.requestTimeout),` as the first element of
`Link.from([...])` (immediately before `_HasuraSetofScalarFixLink()`).

Routing the synthetic error through `mapRemoteFailure` (already imported in
this file for `ErrorLink.onException`, from `auth_loss_classifier.dart`)
matters: `_looksLikeConnectivityFailure`
(`packages/client/lib/data/service/remote_api_client/auth_loss_classifier.dart:110-130`)
already matches the substring `'timeoutexception'` and maps it to
`ConnectionUplinkException` — the app's existing "no internet" UX. Without
this, callers would see a raw, unclassified `TimeoutException` string instead
of the normal connectivity error.

**Acceptance:** any GraphQL operation other than the three named upload
operations that receives no response within `params.requestTimeout` (15s in
production, from `kRequestTimeout` in `lib/consts.dart`) throws a
`ConnectionUplinkException` instead of hanging forever. Upload operations are
completely unaffected (same as before this change).

**Verification:** add
`packages/client/test/data/service/remote_api_client/build_client_test.dart`
using `package:http/testing.dart`'s `MockClient` with a `send()` that returns
a `Future` which never completes (e.g. backed by an uncompleted `Completer`),
built through the real `buildClient()` (inject the mock client — check
whether `_createGraphqlHttpClient()` needs a thin seam to accept an injected
`http.Client` for the test, or construct the `Client`/`HttpLink` directly with
the mock in the test if `buildClient()` itself can't be parameterized without
a broader change; prefer the smallest change that makes the real code path
under test). Assert the resulting `Client.request(...)` stream emits an error
within a few seconds (well under the 15s production timeout — use a short
`requestTimeout` like `Duration(milliseconds: 200)` in the test) rather than
hanging past the test's own timeout. Also assert a request for
`BeaconAddImage` against the same never-responding mock does **not** time out
within that same short window (proving the exclusion list works).

`cd packages/client && flutter test test/data/service/remote_api_client/`

Commit this phase's change on its own before moving to P2.

---

## Phase P2 — Scope block-visibility graph-cache invalidation

**File:** `packages/client/lib/features/graph/ui/bloc/graph_cubit.dart`

`_onBlockVisibilityChanged` currently takes an unused `RepositoryEvent<BlockIntent> _`
parameter (line 212) and unconditionally wipes the cache. `RepositoryEvent.id`
already equals `BlockIntent.blocked.id`
(`packages/client/lib/domain/entity/repository_event.dart:9`,
`packages/client/lib/features/block/domain/entity/user_block.dart:21`), and
`_nodes` is `Map<String, NodeDetails>` keyed by user id (line 185). Use that to
skip the wipe when the affected user isn't part of the currently-loaded graph:

```dart
void _onBlockVisibilityChanged(RepositoryEvent<BlockIntent> event) {
  if (forwardsGraphBeaconId != null) {
    return;
  }
  // A block/unblock event for a user that isn't part of anything currently
  // loaded has nothing to invalidate here — wiping the whole cache in that
  // case is exactly the "unrelated friends disappear" defect (issue #111).
  if (!_nodes.containsKey(event.id) && event.id != _egoNode.id) {
    return;
  }
  _cacheEpoch++;
  ... // rest of the method unchanged
```

Keep everything after that new guard exactly as-is — when the affected user
*is* currently loaded (or is the ego node itself, whose own outgoing edge set
can change on any block), the existing full-wipe-and-refetch-around-ego
behavior is still the correct, simplest way to get a consistent view (the
server's visibility rules for the affected neighbourhood are not something the
client can diff locally). This phase only prevents the wipe when it is
provably unrelated — it does not attempt to make the *relevant* case more
surgical (see §6 for why a fully scoped diff is not attempted here).

**Acceptance:** blocking (with or without cascade) a user who is not currently
present in `_nodes` and is not the ego node does not clear `graphController`,
does not reset `_nodes`/`_allEdges`, and does not trigger a re-fetch. Blocking
a user who *is* currently loaded still refreshes as before.

**Verification:** extend
`packages/client/test/features/block/block_cache_invalidation_test.dart`. The
existing test only asserts `source.calls` increases on `blockCase.emitBlock()`
— add a case using the same `ControllableBlockCase.emitBlock(objectId: ...)`
(`packages/client/test/features/block/support/controllable_block_case.dart:31`)
where `objectId` is **not** the ego id and was never returned by
`_FakeGraphSource.fetch()` (so it can't be in `_nodes`), asserting
`source.calls` does **not** increase and (if easily observable — check what
`GraphCubit` exposes, e.g. via `graphController.nodes` or `cubit.state`) that
previously-loaded nodes are still present after the event.

`cd packages/client && flutter test test/features/block/block_cache_invalidation_test.dart`

Commit this phase's change on its own before moving to P3.

---

## Phase P3 — Block confirmation feedback + live profile refresh

### P3.1 — Confirmation snackbar with a manage link

**File:** `packages/client/lib/features/block/ui/sheet/block_user_sheet.dart`

Add the snackbar helper import: `import 'package:tentura/ui/utils/ui_utils.dart';`
(for `showSnackBar`) and the router import used elsewhere for
`context.router.push(...)`: `import 'package:tentura/app/router/root_router.gr.dart';`
(check the exact import path other features use for `BlockedUsersRoute`, e.g.
`packages/client/lib/features/settings/ui/screen/settings_screen.dart:148`, and
match it).

In `_confirmBlock` (`:95-108`), show the confirmation **before** popping (the
sheet's `context` is still mounted at that point; `showSnackBar` resolves the
ancestor `ScaffoldMessenger`, which outlives the popped sheet route):

```dart
Future<void> _confirmBlock() async {
  setState(() => _blocking = true);
  try {
    await widget.blockCase.block(
      objectId: widget.profile.id,
      cascadeMode: _effectiveCascadeMode,
    );
    if (!mounted) return;
    final l10n = L10n.of(context)!;
    showSnackBar(
      context,
      text: l10n.blockConfirmedMessage,
      action: SnackBarAction(
        label: l10n.blockManageAction,
        onPressed: () => rootNavigatorKey.currentContext?.router
            .push(const BlockedUsersRoute()),
      ),
    );
    Navigator.of(context).pop();
  } on Object {
    if (!mounted) return;
    setState(() => _blocking = false);
  }
}
```

Check whether a root-level navigator key (analogous to `snackbarKey`) already
exists for pushing a route from a snackbar action after the originating sheet
is gone (search `lib/app/` for an existing `GlobalKey<NavigatorState>` used
this way); if none exists, use `context.router.push(const
BlockedUsersRoute())` directly instead — called synchronously inside
`onPressed`, before the sheet's context could be invalidated by anything else,
which is safe because the action only runs when the user taps it, well after
this call stack returns.

**File:** `packages/client/l10n/app_en.arb` / `app_ru.arb`

Add two keys next to the existing `blockConfirmButton`
(`app_en.arb:4814-4817`):

```json
,"blockConfirmedMessage": "Person blocked"
,"@blockConfirmedMessage": {
  "description": "Snackbar confirmation after a successful block."
}
,"blockManageAction": "Manage"
,"@blockManageAction": {
  "description": "Snackbar action linking to the Blocked Users management screen."
}
```

Pick natural Russian equivalents for `app_ru.arb` (e.g. `"Пользователь заблокирован"` /
`"Управление"`). Run `cd packages/client && flutter gen-l10n` after editing.

### P3.2 — Live profile refresh on block/unblock

**File:** `packages/client/lib/features/profile_view/ui/bloc/profile_view_cubit.dart`

`ProfileViewCubit` already injects `_blockCase` (`:79`) and already has the
exact subscribe-then-debounced-silent-refetch pattern for
`_case.projectionChanges(id)` (`:42-47`, `_scheduleSilentFetch` at `:214-223`).
Add a second subscription in the constructor, right after `_projectionSub`:

```dart
_blockChangesSub = _blockCase.changes
    .where((event) => event.id == id)
    .listen((_) => _scheduleSilentFetch(), cancelOnError: false);
```

Declare `StreamSubscription<RepositoryEvent<BlockIntent>>? _blockChangesSub;`
next to the existing `_projectionSub` field (`:81`), import
`package:tentura/domain/entity/repository_event.dart` and
`package:tentura/features/block/domain/entity/user_block.dart` (check if
already imported transitively; add explicitly if analyzer complains), and
cancel it in `close()` (`:96-100`) alongside `_projectionSub`.

**Acceptance:** after `block_user_sheet.dart` successfully blocks the profile
currently open underneath it, that profile screen refreshes (silently, no
loading flash) and reflects the new block state without the user navigating
away and back. Blocking or unblocking any *other* user does not trigger a
refetch on a profile screen that isn't showing that user.

**Verification:** widget test on `block_user_sheet_test.dart` asserting the
snackbar with the "Manage" action appears after a successful block (check the
existing test file's harness first — it likely already pumps a
`MaterialApp`/`Scaffold` around the sheet, which `showSnackBar` needs to find
via `ScaffoldMessenger.maybeOf`). Unit test on a new or extended
`profile_view_cubit_test.dart` asserting a `BlockCase.changes` event for the
cubit's own `id` triggers exactly one additional `_case.load` call (use the
same fake/controllable pattern as `controllable_block_case.dart`), and an
event for a different id does not.

`cd packages/client && flutter test test/features/block/ test/features/profile_view/`

Commit this phase's change on its own before moving to P4.

---

## Phase P4 — Surface the capped cascade count ("N users will also be blocked")

**File:** `packages/client/lib/features/block/ui/sheet/block_user_sheet.dart`

At `:165-172`, the preview block currently renders only
`l10n.blockPreviewCascade(preview.cascadeCandidateCount)`. Branch on
`preview.cascadeCapped`:

```dart
if (_cascadeEnabled) ...[
  Text(
    preview.cascadeCapped
        ? l10n.blockPreviewCascadeCapped(preview.cascadeCandidateCount)
        : l10n.blockPreviewCascade(preview.cascadeCandidateCount),
    style: textTheme.bodyMedium,
  ),
  SizedBox(height: tt.rowGap),
],
```

**File:** `packages/client/l10n/app_en.arb` / `app_ru.arb`

Add next to `blockPreviewCascade` (`app_en.arb:4801-4806`):

```json
,"blockPreviewCascadeCapped": "At least {count} additional people would be hidden"
,"@blockPreviewCascadeCapped": {
  "description": "Impact preview when the cascade candidate count hit the server's cap (block_cascade_candidates / blockCascadeMaxRows) — the real number may be higher than shown.",
  "placeholders": {
    "count": {
      "type": "int"
    }
  }
}
```

Match the `count` placeholder type/shape already used by `blockPreviewCascade`
in the same file. Pick a natural Russian equivalent for `app_ru.arb` (e.g.
`"Будет скрыто не менее {count} человек"` — verify plural handling matches
the existing `blockPreviewCascade` Russian entry's ICU form if it uses one).
Run `cd packages/client && flutter gen-l10n` after editing.

**Acceptance:** with the cascade switch on, if the live preview's
`cascadeCapped` is `true` (subtree candidate count hit `blockCascadeMaxRows`,
default 5000, server-side), the sheet shows "At least N additional people
would be hidden" instead of a flat "N additional people would be hidden" that
implies an exact count.

**Verification:** widget test in `block_user_sheet_test.dart` — supply a fake
`BlockCase.preview()` returning `BlockPreview(cascadeCandidateCount: 5000,
cascadeCapped: true)` and assert the capped copy renders instead of the
uncapped one; and the inverse (`cascadeCapped: false`) still renders the
existing copy unchanged.

`cd packages/client && flutter test test/features/block/ui/sheet/block_user_sheet_test.dart`

Commit this phase's change on its own before moving to P5.

---

## Phase P5 — Full regression pass

Run the full verification set from §2. Re-read this plan's acceptance
criteria for P1–P4 and confirm each against the actual diff (not just "tests
pass") before considering the plan complete:

- P1: transport-level timeout test exists and passes; upload exclusion test
  exists and passes.
- P2: scoped-invalidation test exists and passes; the original
  `block_cache_invalidation_test.dart` case (relevant block still refetches)
  still passes.
- P3: confirmation snackbar test and profile-live-refresh test exist and pass.
- P4: capped/uncapped preview copy test exists and passes.

No server-side test changes are expected or required by this plan (§0.3, §1).

---

## 6. Out of scope / follow-ups

Do not implement these as part of this plan; note them in the journal's final
entry as follow-ups if still relevant when this plan completes:

- **Cascade-materialization freshness.** `BlockCascadeCase.runDue()` is gated
  to run at most once per its task-worker interval
  (`packages/server/lib/domain/use_case/task_worker_case.dart`), so a chain
  block's downstream removal from My People can legitimately lag by up to
  that interval. Nothing currently tells the client "cascade finished,
  refetch" (the `cascadePending` field is only surfaced today in
  `blocked_users_screen.dart:122`, not polled or subscribed to by
  `GraphCubit`). Making this live (polling, a subscription, or a push
  invalidation once the cascade job completes) is a larger, separate
  feature-shaped change — out of scope here.
- **MeritRank write/read contention during cascade batches.** Plausible
  contributor to why chain-block reproduces the hang more often than a direct
  block (§0.2), but unverifiable from source (the MeritRank engine is a
  compiled extension) and not required to fix the reported bug — P1 removes
  the *hang* regardless of its trigger. If it still reproduces after this plan
  ships in a way P1–P2 don't explain, that needs server-side profiling as a
  separate investigation.
- **Fully scoped (diff-based) graph invalidation.** P2 only skips the wipe
  when the affected user is provably unrelated to what's loaded. When the
  affected user *is* loaded, the fix still does a full wipe-and-refetch
  around ego, same as today — a true incremental diff would need
  client-visible information about exactly which edges the server's
  `block_hides` visibility rule removed, which the current API doesn't
  expose. Not attempted here.
