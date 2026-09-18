---
status: ready
kind: implementation-plan
source: docs/plans/issue-110-forward-explicit-architecture.md
source_revision: 3
---

# Issue #110 — Explicit forwarding — implementation plan

This is the execution plan for
[`issue-110-forward-explicit-architecture.md`](issue-110-forward-explicit-architecture.md)
**rev 3**. It is written for a literal model such as Composer 2.5: every unit has
fixed ownership, exact symbols, ordered steps, tests, and a stop condition.

The architecture is normative. An executor must **not** make additional product
choices. If live code contradicts a frozen contract below, stop and record
`BLOCKED` instead of improvising.

> **For agentic workers:** execute units in manifest order. One unit, its
> checks, journal entry, and focused local commit before the next. Do not push.

**Goal:** Make forwarding explicit (personal note + skip + shared sheet), stay
on the Forward screen after send, show a location toast, gate Forward CTAs with
`allowsForward`, and align cancel with the server (including decline and
onward-child).

**Architecture:** Client orchestration on the existing `beaconForward` engine.
Session (skip, flash, filter) lives in cubits. Pure domain helpers for
coverage / effective note / cancel. Small server/GQL deltas only:
`cancelForward` honours `recipientRejected`; `MyForwardRecipient` gains
mandatory `hasOnwardChild` and `recipientRejected` computed from edges already
loaded by `fetchByBeaconId`. No migration.

**Tech stack:** Dart server, V2 GraphQL, Flutter client, Freezed cubit states,
`UiEffect` / `LocalizableMessage`, GetIt `HomeTabReselectCubit`.

## Global constraints

- User-facing copy: **Request** / **Chat**. Internal: Beacon / room. Never add a
  `Request` domain entity.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, `*_g/`, generated l10n). Edit sources, run codegen.
- Feature UI: `context.tt`, `TenturaText`, existing buttons. No raw
  `Color`/`fontSize`/`EdgeInsets` numbers in `features/**`. Match existing
  Forward row hit targets (`minWidth`/`minHeight` 44 already in
  `forward_recipient_row.dart`).
- Preserve unrelated dirty files. Stage explicit paths only. No push, no
  `--force`.
- Do not raise `kDefaultMinClientVersion` (additive GQL fields; old binaries
  still run).
- Client user-visible work ends at version **6.2.0** (UNIT 12). Live start is
  `6.1.1`.
- No new PostgreSQL migration. Latest at plan writing: `m0149`.

---

## 0. Frozen contracts (do not rename)

```dart
// packages/client/lib/features/forward/domain/forward_draft_policy.dart  (NEW)
Set<String> uncoveredRecipientIds({
  required Set<String> selectedIds,
  required Map<String, String> perRecipientNotes,
  required Set<String> skippedPersonalNoteIds,
});
// A selected id is uncovered iff it is not in skippedPersonalNoteIds AND
// (perRecipientNotes[id] is null OR trim is empty).

String? effectiveForwardNote({String? personal, String? shared});
// trim personal; if non-empty return it; else trim shared or null.

bool forwardEdgeIsCancellable({
  required DateTime? recipientReadAt,
  required bool hasOnwardChild,
  required bool recipientHasActiveHelpOffer,
  required bool recipientDeclined,
});
// true iff all four blockers are false / readAt is null.
```

```dart
HomeTabReselectCubit.requestInboxWatching(String beaconId)
// GetIt @singleton. Sets inboxWatchingBeaconId and increments
// inboxWatchingOpenCount. Must be called BEFORE replaceAll to Inbox.
```

```text
MyForwardRecipient.hasOnwardChild: Boolean!     // mandatory
MyForwardRecipient.recipientRejected: Boolean!  // mandatory
```

`hasOnwardChild` computation (server, in-memory, no extra query):

```dart
final childParentIds = {
  for (final e in edges)
    if (e.parentEdgeId != null) e.parentEdgeId!,
};
// for each ego edge:
hasOnwardChild: childParentIds.contains(edge.id)
recipientRejected: edge.recipientRejected
```

Wire skip: **omit key**. Never send `perRecipientNotes[id] = ""`.

Embedded create: `canSubmit` does **not** require `allowsForward`.

Standalone every `forward()` path: **no** `NavigateBack` (including all-paused
early return at `forward_cubit.dart` ~679).

Composer: **visible** on `alreadyInvolved` (D8 superseded 2026-09-02). Do not
hide the composer by filter tab or `lastDeliveredRecipientIds`.

Watching CTA compact: tab 1, **do not** set `_selectedWatchingBeaconId`.
Expanded: set it if the item is still in `state.watching`.

D13: snapshot edge-count at **push**; nudge after **pop** only if count
increased.

D15: do not emit `pendingMovedNudge` when `toStatus == InboxItemStatus.watching`.

---

## 1. Live baseline and stop conditions

At plan-writing time (2026-08-14):

```text
latest migration                    m0149
packages/client/pubspec.yaml        6.1.1
packages/client/web/index.html      flutter_bootstrap.js?v=6.1.1
packages/server/lib/env.dart        kDefaultMinClientVersion = '6.0.0'
architecture                        rev 3
```

Before UNIT 00, re-read those values. Stop with `BLOCKED` when:

- a new migration `m0150` already exists **and** this plan would add another;
- `ForwardCubit.embedded` / `beacon_create_screen.dart` send path has been
  rewritten so publish no longer precedes `forward()`;
- `HomeTabReselectCubit` is no longer a GetIt `@singleton`;
- `InboxCubit` has been registered in GetIt (then D9 must be re-derived);
- an owned file has unrelated local modifications that cannot be preserved by a
  narrow edit.

A changed Git HEAD alone is not a blocker.

This plan owns, until implementation is authorized, only:

```text
docs/plans/issue-110-forward-explicit-architecture.md
docs/plans/issue-110-forward-explicit-implementation-plan.md
docs/README.md
```

Implementation additionally owns the paths listed per unit. It does **not** own
unrelated dirty files already in the worktree.

---

## 2. Executor contract

1. Units in manifest order. Complete one unit, run its Verify block, append the
   journal, focused local commit, then the next unit.
2. Preserve pre-existing modified/untracked files. Never reset, stash, or stage
   unrelated paths.
3. Create `docs/plans/issue-110-forward-explicit-implementation-journal.md` in
   UNIT 00.
4. If live code contradicts a frozen contract, stop that unit. Line-number drift
   is not a contradiction.
5. Server use cases depend on ports only. Client `lib/domain/` must not import
   `data/` or `ui/`. Cubits must not import `data/service/`.
6. After Dart source edits in a unit, run
   `./scripts/check-custom-lints.sh packages/client` and/or
   `./scripts/check-custom-lints.sh packages/server` on the package you
   touched if you edited `lib/`.
7. `bash scripts/check-user-facing-terminology.sh` before UNIT 13 closeout if
   copy changed.
8. Tests tagged `pg` use an isolated disposable database. Never reset shared
   `postgres`.

Journal entry template:

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
REMAINING: <specific work, or none>
```

---

## 3. Unit manifest

| Unit | Purpose | Depends on | Suggested commit |
|------|---------|------------|------------------|
| 00 | Journal and baseline | — | `docs: start issue 110 implementation journal` |
| 01 | Pure coverage / note / cancel helpers | 00 | `feat: add forward draft policy helpers` |
| 02 | Server `cancelForward` honours `recipientRejected` | 00 | `fix(server): refuse cancel after recipient decline` |
| 03 | `MyForwardRecipient` hasOnwardChild + recipientRejected | 01–02 | `feat: expose ego-edge cancel flags on involvement` |
| 04 | Map flags onto `ForwardCandidate` / `ForwardLoad` | 03 | `feat: plumb forward cancel and toast flags` |
| 05 | `ForwardCubit` session: skip, wire, stay, force-reload | 04 | `feat: keep forward screen after send` |
| 06 | Picker: skip, sheet, controllers, D14 chrome | 05 | `feat: explicit personal-note skip on forward` |
| 07 | Location toast + Watching intent on `HomeTabReselectCubit` | 05 | `feat: forward location toast opens Inbox Watching` |
| 08 | Inbox consumes Watching intent; D15 | 07 | `feat: land Open-in-Watching on the Watching tab` |
| 09 | D13 offer-help snapshot on Inbox + BeaconView | 05 | `feat: nudge offer-help after a new forward edge` |
| 10 | CTA inventory (`allowsForward`) | 00 | `fix: hide Forward when the request cannot be forwarded` |
| 11 | Person-forward stay, skip/sheet, **add** cancel | 03–07 | `feat: person-forward stay and cancel` |
| 12 | Client 6.2.0 + web cache-buster | 06–11 | `chore: release explicit-forward client 6.2.0` |
| 13 | Plan-wide closeout | 02, 12 | `test: close issue 110 implementation` |

Do not parallelize: involvement DTO, `ForwardCandidate`, cubit, and picker
overlap.

---

## UNIT 00 — Journal and baseline

**Owns:** the journal only.

1. Record `git rev-parse HEAD`, branch, `git status --short`, migration tail
   (`ls packages/server/lib/data/database/migration/m014*.dart`), client
   version, `web/index.html` `?v=`, `kDefaultMinClientVersion`.
2. Copy the unit manifest into the journal as unchecked items.
3. Record architecture source **rev 3**.
4. Do not alter or stage any pre-existing non-journal file.

**Acceptance:** journal exists; baseline matches §1 or differences are recorded
without guessing.

---

## UNIT 01 — Pure domain helpers

**Owns:**

```text
packages/client/lib/features/forward/domain/forward_draft_policy.dart          new
packages/client/test/features/forward/forward_draft_policy_test.dart           new
```

1. Create the three functions exactly as in §0. No classes, no Flutter imports,
   no `ForwardCandidate` dependency.
2. Tests (table-driven):
   - uncovered: selected `{a,b}`, notes `{a: "hi"}`, skip `{}` → `{b}`;
   - skip removes from uncovered even if notes has `"  "` or `"typed"`;
   - empty/whitespace personal is uncovered unless skipped;
   - `effectiveForwardNote(personal: " p ", shared: "s")` → `"p"`;
   - `effectiveForwardNote(personal: "  ", shared: "s")` → `"s"`;
   - `effectiveForwardNote(personal: null, shared: null)` → `null`;
   - cancellable: all false/null → true;
   - each blocker alone → false (`readAt` non-null, `hasOnwardChild`,
     `recipientHasActiveHelpOffer`, `recipientDeclined`).
3. Do not wire to cubits yet.

**Verify:**

```bash
cd packages/client && flutter test test/features/forward/forward_draft_policy_test.dart
```

**Acceptance:** all cases pass; the file has no Flutter import.

---

## UNIT 02 — Server cancel refuses decline

**Owns:**

```text
packages/server/lib/domain/use_case/forward_case.dart
packages/server/test/domain/use_case/forward_case_test.dart
```

1. In `cancelForward`, after the existing `recipientReadAt` check and before
   `existsWithParent`, add:

```dart
if (edge.recipientRejected) return false;
```

   Use the field already on `ForwardEdgeEntity`. Do not add an inbox round-trip.
2. In `group('cancelForward — eligibility')`, add a test
   `returns false when recipientRejected` that stubs
   `_forwardEdge(..., recipientRejected: true)` and expects `isFalse` with
   `verifyNever(forwardEdgeRepo.cancel)`.
3. Do not change help-offer or `existsWithParent` tests.

**Verify:**

```bash
cd packages/server && dart test test/domain/use_case/forward_case_test.dart --name "cancelForward"
```

**Acceptance:** new test fails before the `if`, passes after; existing
eligibility tests still pass.

---

## UNIT 03 — Involvement DTO cancel flags (mandatory)

**Owns:**

```text
packages/server/lib/domain/entity/gql_public/beacon_involvement_result.dart
packages/server/lib/domain/use_case/beacon_involvement_case.dart
packages/server/lib/api/controllers/graphql/custom_types.dart
packages/server/lib/api/controllers/graphql/mappers/gql_v2_dto_maps.dart
packages/server/test/domain/use_case/beacon_involvement_case_test.dart
packages/client/lib/data/gql/schema.graphql
packages/client/lib/features/forward/data/gql/beacon_involvement_data.graphql
packages/client/lib/features/forward/data/repository/forward_repository.dart
packages/client/test/features/forward/forward_repository_involvement_test.dart
```

1. Add to `MyForwardRecipientResult`: `required this.hasOnwardChild`,
   `required this.recipientRejected` (both `bool`).
2. In `BeaconInvolvementCase.asMap`, when iterating `edges`, compute
   `childParentIds` from the same list as in §0. For each
   `edge.senderId == currentUserId` row, set the two bools. Cancelled edges are
   already excluded by `fetchByBeaconId`.
3. GraphQL: add non-null `hasOnwardChild` and `recipientRejected` to
   `gqlTypeMyForwardRecipient` and to `myForwardRecipientToGqlMap`.
4. Client `schema.graphql` type `v2_MyForwardRecipient`: add

```graphql
hasOnwardChild: Boolean!
recipientRejected: Boolean!
```

5. Query `beacon_involvement_data.graphql`: select the two new fields under
   `myForwardedRecipients`.
6. Run client codegen: `cd packages/client && dart run build_runner build -d`
   (and `flutter gen-l10n` only if you touch arb later).
7. Extend `BeaconInvolvementData` with:

```dart
Map<String, bool> myForwardedRecipientHasOnwardChild,
Map<String, bool> myForwardedRecipientRejected,
```

   Fill them in `mapBeaconInvolvement` from `r.hasOnwardChild` /
   `r.recipientRejected`. Default missing keys to `false` only if the generated
   type is nullable — they must be non-null on the wire.
8. Tests:
   - server: ego edge with a child (`parentEdgeId` of another fetched edge =
     ego id) → `hasOnwardChild == true`; sibling without child → false;
     `recipientRejected` copied from the edge;
     other-sender edges still absent from `myForwardedRecipients`.
   - client repository map test: generated builder includes the two fields.

**Stop:** do not add a SQL migration or `existsWithParent` N+1 per edge.

**Verify:**

```bash
cd packages/server && dart test test/domain/use_case/beacon_involvement_case_test.dart
cd packages/client && flutter test test/features/forward/forward_repository_involvement_test.dart
```

---

## UNIT 04 — Candidate / load flags

**Owns:**

```text
packages/client/lib/features/forward/domain/entity/forward_candidate.dart
packages/client/lib/features/forward/domain/entity/forward_load.dart
packages/client/lib/features/forward/domain/use_case/forward_case.dart
packages/client/test/features/forward/forward_compute_involvement_test.dart
packages/client/test/features/forward/forward_repository_involvement_test.dart
```

1. Add to `ForwardCandidate` (defaults false / null):

```dart
@Default(false) bool hasOnwardChild,
@Default(false) bool recipientDeclined,
@Default(false) bool recipientHasActiveHelpOffer,
```

   `recipientReadAt` and `forwardEdgeId` already exist.
2. When mapping candidates in `ForwardCase.loadForwardCandidates`, set:

```dart
hasOnwardChild: involvement.myForwardedRecipientHasOnwardChild[p.id] ?? false,
recipientDeclined: involvement.rejectedIds.contains(p.id) ||
    (involvement.myForwardedRecipientRejected[p.id] ?? false),
recipientHasActiveHelpOffer: involvement.helpOfferedIds.contains(p.id),
```

3. Add to `ForwardLoad`:

```dart
@Default(false) bool viewerIsAuthor,
@Default(false) bool viewerHasActiveHelpOffer,
```

   Set `viewerIsAuthor: involvement.beacon.author.id == myId`,
   `viewerHasActiveHelpOffer: involvement.helpOfferedIds.contains(myId)`.
   Keep `hasMyOutgoingForward`.
4. Copy the new fields through every `ForwardCandidate(` test fixture that
   would otherwise break compilation (defaults should save you).
5. Cubit `forward()` toast unit comes in UNIT 07; here only plumb the load.

**Verify:**

```bash
cd packages/client && flutter test test/features/forward/forward_compute_involvement_test.dart test/features/forward/forward_repository_involvement_test.dart
```

---

## UNIT 05 — ForwardCubit stay-on-send

**Owns:**

```text
packages/client/lib/features/forward/ui/bloc/forward_state.dart
packages/client/lib/features/forward/ui/bloc/forward_cubit.dart
packages/client/test/features/forward/forward_cubit_live_sync_test.dart
packages/client/test/features/forward/forward_cubit_candidates_load_test.dart
packages/client/test/features/forward/forward_cubit_edit_reasons_test.dart
```

1. Add to `ForwardState`:

```dart
@Default(<String>{}) Set<String> skippedPersonalNoteIds,
@Default(<String>[]) List<String> lastDeliveredRecipientIds,
```

   Run codegen on the cubit/state files.
2. Replace `beacon.status != BeaconStatus.open` in `forward()` with
   `!beacon.allowsForward`. If `embedded`, **skip this refuse** (draft).
3. Before `forwardBeacon`, if `uncoveredRecipientIds(...)` is non-empty, return
   false without network (no-op).
4. When building `perNotes`, skip ids in `skippedPersonalNoteIds` and skip
   empty trims (already the empty-trim behaviour). **Never** insert `""`.
5. Remove **both** `_emitNavigateBack(result: true)` calls in `forward()`
   (success after network **and** the all-paused early return ~679–696).
   Embedded already skips them; keep it that way.
6. After success with `outcome.deliveredRecipientIds.isNotEmpty`:
   `await reloadCandidates(forceReload: true)`; then emit
   `activeFilter: ForwardFilter.alreadyInvolved`,
   `lastDeliveredRecipientIds: outcome.deliveredRecipientIds`,
   clear `selectedIds`, `perRecipientNotes`, `skippedPersonalNoteIds`, `note`.
7. After success with zero delivered: do **not** change filter; do not set
   flash ids; still no `NavigateBack`.
8. Change `cancelForward` and `saveForwardEdit` from `_loadCandidates()` to
   `reloadCandidates(forceReload: true)`.
9. Tests that expect `NavigateBack` after send:
   - `forward_cubit_live_sync_test.dart` (~291) — invert to `isEmpty`;
     the helper `_NavigateBackClosesCubitPort` may remain for other cases or
     be deleted if unused.
   - Search the cubit tests for `NavigateBack` and invert send-success cases
     only. Embedded tests that already expect no pop stay.
10. Add a cubit test: all-paused early return emits no `NavigateBack` and
    leaves `activeFilter` unchanged.
11. Add a cubit test: skip id with leftover typed note is absent from the
    repository `perRecipientNotes` argument (mock `ForwardCase.forwardBeacon`).

**Verify:**

```bash
cd packages/client && flutter test test/features/forward/forward_cubit_live_sync_test.dart test/features/forward/forward_cubit_candidates_load_test.dart test/features/forward/forward_cubit_edit_reasons_test.dart
```

**Stop:** do not implement skip widgets here. Do not emit D9 messages yet
(`_emitDeliveryMessage` still uses old classes until UNIT 07).

---

## UNIT 06 — Picker skip, sheet, controllers, cancel chrome

**Owns:**

```text
packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart
packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart
packages/client/lib/features/forward/ui/widget/forward_bottom_composer.dart
packages/client/l10n/app_en.arb
packages/client/l10n/app_ru.arb
packages/client/test/features/forward/forward_recipient_picker_test.dart
packages/client/test/features/forward/forward_recipient_host_policy_test.dart
```

1. Skip control: icon-only next to the personal field; tooltip/semantics from
   new arb keys (exact):
   - `forwardSkipPersonalNote`: EN `Skip personal note` / RU `Без личной заметки`
   - `forwardRestorePersonalNote`: EN `Add a personal note` / RU `Добавить личную заметку`
   Hit target ≥44; must not toggle the row checkbox. Re-tap restores the field;
   do not clear cubit text on skip.
2. On Submit, if `uncoveredRecipientIds` is non-empty, show a sheet listing
   **unset** names only. Primary: user types shared → `setNote` → send.
   Secondary: outlined/text `Send without a shared note` → add remaining
   uncovered to `skippedPersonalNoteIds` → send. Empty shared + primary Send
   is forbidden. Dirty dismiss: existing `TenturaSheetDismissGuard`.
   `(i)`: `TenturaInfoHintButton` explaining the shared note goes to everyone
   still without a personal note.
3. After cubit clears draft (UNIT 05), picker `_syncRecipientNoteControllers`
   must dispose unused controllers and set `_sharedNoteController.text = ''`.
   Listen to `selectedIds` / `perRecipientNotes` / skip set.
4. Cancel/edit icons: show iff `candidate.forwardEdgeId != null &&
   forwardEdgeIsCancellable(...)` using the four candidate flags. Stop using
   `forwardEdgeId != null` alone (`forward_recipient_picker.dart` ~649).
5. Show composer on `alreadyInvolved` (D8 superseded). Do not hide by filter.
6. Run `flutter gen-l10n` after arb edits.
7. Widget tests: skip then submit omits that id from notes; sheet appears for
   unset; cancel icon absent when `hasOnwardChild` or `recipientDeclined`.

**Verify:**

```bash
cd packages/client && flutter gen-l10n && flutter test test/features/forward/forward_recipient_picker_test.dart test/features/forward/forward_recipient_host_policy_test.dart
```

---

## UNIT 07 — Location toast and Watching intent

**Owns:**

```text
packages/client/lib/features/forward/ui/message/forward_messages.dart
packages/client/lib/features/forward/ui/bloc/forward_cubit.dart
packages/client/lib/features/home/ui/bloc/home_tab_reselect_state.dart
packages/client/lib/features/home/ui/bloc/home_tab_reselect_cubit.dart
packages/client/test/features/forward/forward_messages_test.dart
packages/client/test/features/home/home_tab_reselect_cubit_test.dart  (create if missing)
```

1. Replace `_emitDeliveryMessage` branching so **one** `ShowMessage` is
   emitted:
   - 0 delivered: keep `ForwardPartialDeliveryMessage` /
     `ForwardPartialDeliveryManyMessage` (no location, no CTA).
   - ≥1 delivered: new `ForwardLocationMessage` extends
     `LocalizableActionMessage` **only when** `!viewerIsAuthor &&
     !viewerHasActiveHelpOffer`; otherwise a `LocalizableMessage` without
     action.
   - Copy must name the place: Watching vs My Work.
   - If `availabilitySkippedCount > 0`, append the existing pause clause to
     the **same** string (reuse the one-name vs count rule already in
     `ForwardPartialDelivery*`).
   Exact EN (Watching, no pause): `Request forwarded. It's in Watching.`
   Exact EN (My Work, no pause): `Request forwarded. It's in My Work.`
   Exact RU: `Запрос переслан. Он во вкладке «Наблюдаю».` /
   `Запрос переслан. Он в «Моей работе».`
   CTA label EN `Open in Watching` / RU `Открыть в «Наблюдаю»`.
2. `onPressed` (Watching only), **in this order**:

```dart
GetIt.I<HomeTabReselectCubit>().requestInboxWatching(beaconId);
unawaited(
  GetIt.I<RootRouter>().replaceAll([
    HomeRoute(children: [inboxTabShell(children: [const InboxRoute()])]),
  ]),
);
```

   Do **not** call `InboxCubit`. Do **not** put a route path in `ForwardCubit`.
3. `HomeTabReselectState`: add `@Default(0) int inboxWatchingOpenCount` and
   `String? inboxWatchingBeaconId`. Codegen.
4. `HomeTabReselectCubit.requestInboxWatching(String beaconId)` emits
   `inboxWatchingBeaconId: beaconId`,
   `inboxWatchingOpenCount: state.inboxWatchingOpenCount + 1`.
   Do not change `bump(HomeTab.inbox)` (still `animateTo(0)`).
5. Tests: watching message has `onPressed`; author/help-offer message has no
   action; mixed delivery is a single `ShowMessage` in cubit effects;
   `requestInboxWatching` increments count.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d && flutter test test/features/forward/forward_messages_test.dart
```

---

## UNIT 08 — Inbox Watching land + D15

**Owns:**

```text
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart
packages/client/lib/features/inbox/ui/bloc/inbox_cubit.dart
packages/client/test/features/inbox/inbox_case_test.dart
```

1. In `_InboxScreenState.initState` (add if missing) and a
   `BlocListener<HomeTabReselectCubit>` with
   `listenWhen: (p, c) => p.inboxWatchingOpenCount != c.inboxWatchingOpenCount`:
   - `DefaultTabController.of(context).animateTo(1)`;
   - if `context.windowClass == WindowClass.expanded` and
     `state.watching.any((e) => e.beaconId == beaconId)` then
     `_selectedWatchingBeaconId = beaconId`;
   - **compact: do not set** `_selectedWatchingBeaconId`.
2. In `InboxCubit._fetchAndNotifyIfMoved`, if `newStatus ==
   InboxItemStatus.watching`, return **without** emitting `pendingMovedNudge`.
   Comment:

```dart
// D9 location toast already explains Needs me → Watching after this
// process's own forwardCommandCompleted. A second snackbar here duplicates it.
```

   Keep the rejected branch.
3. Invert `inbox_case_test.dart` test
   `'local forward command alone may create movement nudge'` to expect
   `pendingMovedNudge` **isNull** after `emitForwardCommandCompleted` when the
   item becomes watching. Rename the test to say watching is silent.
4. Rejected movement test, if any, stays.

**Verify:**

```bash
cd packages/client && flutter test test/features/inbox/inbox_case_test.dart
```

---

## UNIT 09 — Offer-help snapshot (D13)

**Owns:**

```text
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart
packages/client/lib/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart
packages/client/test/features/beacon_view/build_beacon_status_menu_rows_test.dart
```

1. Remove `didForward == true` as the nudge trigger.
2. Before `push(ForwardBeaconRoute(...))`, snapshot:
   - Inbox: `item` / involvement equivalent of “I already have an outgoing
     edge” — use `InboxItem` fields already present (`isForwardedByMe` or
     `my_forward_edges` — **read the live field name**; do not invent). If the
     item has no such field, snapshot `false` and after pop re-fetch the cubit
     item and compare.
   - BeaconView: snapshot `cubit.state.hasForwardedThisBeaconOnce`.
3. `await push` **without** using the bool result.
4. After pop, if `!context.mounted` return. Re-read state. Nudge only if
   snapshot was false (or count `n`) and now true (or count `> n`) **and** the
   existing offer-help eligibility (`_inboxCardAllowsOfferHelp` /
   `!isHelpOffered && !isBeaconMine && allowsNewHelpOfferAsNonAuthor`).
5. Tests: helper or cubit-level — opening and closing Forward without a new
   edge does not nudge; a false→true transition does.

**Verify:**

```bash
cd packages/client && flutter test test/features/inbox/inbox_case_test.dart test/features/beacon_view/beacon_view_offer_help_test.dart
```

If `beacon_view_offer_help_test.dart` does not cover the app-bar path, add a
small unit test next to `build_beacon_status_menu_rows_test.dart` for a pure
function you extract:

```dart
bool shouldNudgeOfferHelpAfterForwardVisit({
  required bool hadOutgoingEdgeBefore,
  required bool hasOutgoingEdgeAfter,
  required bool offerHelpAllowed,
}) => !hadOutgoingEdgeBefore && hasOutgoingEdgeAfter && offerHelpAllowed;
```

Put that function in
`packages/client/lib/features/forward/domain/forward_draft_policy.dart` or a
tiny `forward_offer_help_nudge.dart` beside it. Prefer extracting rather than
widget-testing the router.

---

## UNIT 10 — CTA inventory

**Owns:**

```text
packages/client/lib/ui/widget/card_triage_action_row.dart
packages/client/lib/features/inbox/ui/widget/inbox_item_tile.dart
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart
packages/client/lib/features/inbox/ui/screen/inbox_rejected_screen.dart
packages/client/lib/features/my_work/ui/widget/my_work_cards.dart
packages/client/lib/features/beacon_view/ui/message/help_offer_messages.dart
```

1. Change `CardTriageActionRow.onForward` from `required VoidCallback` to
   `VoidCallback?`. If null, do **not** build `forwardBtn`.
2. Needs me: pass `onForward` only when `item.beacon?.allowsForward == true`.
   Watching already has `showCtaRow: false` — do not add a card Forward CTA.
3. Rejected archive: `onTap` currently pushes `ForwardBeaconRoute` always.
   Push only when `item.beacon?.allowsForward == true`; otherwise leave
   `onTap` null or point it at `onOpenBeacon` only. Do not open Forward on a
   null beacon.
4. My Work footer: `needsForwardCta = !vm.authorHasForwardedOnce &&
   vm.beacon.allowsForward`. Same AND on `BeaconPhasePrimaryAction.forward`
   if that path still pushes Forward without the getter.
5. `HelpOfferedForwardNudgeMessage.onPressed`: if you cannot cheaply read
   `allowsForward` inside the message, leave the push (D6 makes the route
   read-only). Prefer gating only if `Beacon` is already on the message.
6. Overflow menus already use `beacon.allowsForward` — do not “fix” them.

**Verify:**

```bash
cd packages/client && flutter test test/features/inbox test/features/my_work --name "forward" 
```

If no such tests exist, add a one-file test for `CardTriageActionRow` null
`onForward` (no Forward button) and a small test that `needsForwardCta` is
false when `!allowsForward`.

---

## UNIT 11 — Person-forward

**Owns:**

```text
packages/client/lib/features/forward/domain/entity/person_forward_row.dart
packages/client/lib/features/forward/domain/use_case/person_forward_case.dart
packages/client/lib/features/forward/ui/bloc/person_forward_cubit.dart
packages/client/lib/features/forward/ui/bloc/person_forward_state.dart
packages/client/lib/features/forward/ui/screen/person_forward_screen.dart
packages/client/test/features/forward/person_forward_cubit_test.dart
packages/client/test/features/forward/person_forward_screen_test.dart
packages/client/test/features/forward/person_forward_block_test.dart
```

1. Add to `PersonForwardRow`: `forwardEdgeId`, `recipientReadAt`,
   `hasOnwardChild`, `recipientDeclined`, `recipientHasActiveHelpOffer`
   (defaults). Fill from involvement for `personId` (the target person is the
   recipient of ego’s edge).
2. **Add** `PersonForwardCubit.cancelSelectedOr(String beaconId)` calling
   `PersonForwardCase` → existing `ForwardRepository.cancelForward`, then
   `load()`. There is **no** cancel method today; do not skip this because
   architecture said “stays”.
3. On `alreadySent` rows show cancel/edit iff `forwardEdgeIsCancellable(...)`.
   Keep tap-to-open `ForwardBeaconRoute` as an additional action if it still
   makes sense; cancel must be an explicit icon, not the row tap.
4. Remove `NavigateBack` after successful `send()` when
   `deliveredRecipientIds.contains(person.id)`. Invert
   `person_forward_cubit_test.dart` ~332 and ~387 to `isEmpty`.
5. After successful delivery: `await load()`; flash that `beaconId` (add
   `lastDeliveredBeaconId` on state); clear `note`. Availability skip: keep
   current toast, still no pop (already true ~535+).
6. Skip/sheet: one note field. If empty and not skipped at send, show the same
   sheet with one name. Skip → `note: null` on `send()`.
7. `notOpen`: do not change `fetchBeacons(lifecycleStates: openFamily)`. Do
   not load closed beacons.

**Verify:**

```bash
cd packages/client && flutter test test/features/forward/person_forward_cubit_test.dart test/features/forward/person_forward_block_test.dart test/features/forward/person_forward_screen_test.dart
```

---

## UNIT 12 — Client version 6.2.0

**Owns:**

```text
packages/client/pubspec.yaml
packages/client/web/index.html
```

1. Bump `packages/client/pubspec.yaml` `version:` from live `6.1.1` (or
   whatever UNIT 00 recorded) to **6.2.0** (minor: user-visible feature).
2. Set `packages/client/web/index.html` `flutter_bootstrap.js?v=6.2.0`.
   If the live version is no longer `6.1.1`, bump minor from the live value
   (`x.Y.z` → `x.(Y+1).0`) and use that in `?v=`.
3. Do **not** change `kDefaultMinClientVersion`.
4. Run `cd packages/client && dart run tool/verify_web_version_consistency.dart`
   if that tool exists; otherwise visually match pubspec and `?v=`.

**Verify:** `grep` pubspec and `index.html` show the same version.

---

## UNIT 13 — Closeout

**Owns:** journal closeout only (plus any test gap from earlier units).

1. Run:

```bash
cd packages/server && dart test test/domain/use_case/forward_case_test.dart --name "cancelForward"
cd packages/server && dart test test/domain/use_case/beacon_involvement_case_test.dart
cd packages/client && flutter test test/features/forward test/features/inbox/inbox_case_test.dart
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
```

2. Confirm no `NavigateBack` on standalone send in
   `forward_cubit.dart` / `person_forward_cubit.dart` (rg).
3. Confirm `hasOnwardChild` is non-optional in `custom_types.dart` and
   `schema.graphql`.
4. Journal: all units complete or explicitly blocked.

**Acceptance:** commands green; frozen contracts still match the code.

---

## 4. Spec coverage (self-check)

| Architecture | Unit |
|--------------|------|
| D1–D2 skip + omit key | 01, 05, 06 |
| D3 reasons untouched | (no unit) |
| D4 allowsForward + embedded exempt | 05 |
| D5 / §7 CTA inventory | 10 |
| D6 read-only route | 05 refuse + existing screen |
| D7 stay, force-reload, zero-delivery, cancel/edit memo | 05 |
| D8 Involved tab shows composer (superseded hide) | 06 |
| D9 location toast + HomeTabReselectCubit | 07–08 |
| D10 pause not involved | 05 flash set |
| D11 person-forward + **add** cancel | 11 |
| D12 GetIt in message onPressed | 07 |
| D13 snapshot nudge | 09 |
| D14 cancel helper + mandatory GQL flags + server decline | 01–04, 06, 11 |
| D15 watching pendingMovedNudge | 08 |
| Version / cache-buster | 12 |

---

## 5. Out of scope (executor must not do)

Pre-submit who-gets-what wizard · auto-navigate to Watching without the CTA ·
snackbar undo · compact auto-open of watching detail · `Open in My Work` CTA ·
cancel from Inbox Watching cards · new SQL migration · raising
`MIN_CLIENT_VERSION` · purifying `ForwardCase` data imports · renaming Beacon
to Request in code.
