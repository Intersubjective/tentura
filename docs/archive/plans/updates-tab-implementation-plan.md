# Updates Tab — Technical Implementation Plan

Status: **plan — revision 4** (v1 scope reduced; no product code changed). Audience:
implementing developers (task breakdown in Part F). Product source: GitHub issue #80,
re-read through the connected GitHub integration on 2026-07-16 and quoted verbatim in
C0.1 (revision 1's second-hand "restated spec" is retired). Revision 2 rewrote Parts
C–H to resolve the Part I architecture review; revision 3 rechecked those changes
against the live tree and ADR 0008 (Part K). Revision 4 answers the proportionality
review recorded in Part L: issue #80 requires reliable **in-app** unread activity, not
durable multi-channel event delivery, so v1 drops the occurrence store, event-time
audience snapshot tables, and durable channel-job machinery, and re-anchors on
transactional per-recipient receipts in the existing `notification_outbox`. Parts I–K
are retained as historical review records; where they disagree with the current body,
the body and Part L govern.

Terminology reminder: users see **Request** / **Chat**; code keeps `beacon_*` names
(`.cursor/rules/terminology.mdc`). This document says "request (internally: beacon)" once
and uses code names afterwards.

---

# Part A — Current architecture (research findings)

## A1. Realtime / event architecture

One pipeline, server-authoritative, hint-based (payloads carry no derived state; clients
refetch truth):

```
domain mutation (server use case, TenturaDb.withMutatingUser sets actor GUC)
→ PG row change
→ table trigger notify_entity_change('<kind>')  or specialized publisher
→ SQL emit_realtime_entity_change(kind, entity_id, op, user_ids)   [m0114]
→ PG NOTIFY 'entity_changes' (bounded envelope, per-recipient)
→ per-worker LISTEN → WS fan-out to that worker's authenticated sessions
→ client InvalidationService (100 ms batch + (kind, aggregateId) dedup)
→ RealtimeSyncCase.changesFor(kinds) / catchUps
→ feature Cubits refetch their projection
```

- Contract: [`docs/contracts/realtime-entity-contract.json`](contracts/realtime-entity-contract.json)
  (16 wire kinds), enforced by architecture tests on both sides:
  `packages/server/test/architecture/realtime_entity_contract_test.dart`,
  `packages/client/test/architecture/realtime_entity_contract_test.dart`.
- A **`notification` wire kind already exists**: trigger on `notification_outbox`
  (m0114, `notification_outbox_entity_notify`), recipients = `[account_id]`, impacts
  `notification_center`, `notification_count`, `shell_badge`.
- Catch-up: connection epochs; on reconnect/auth the client emits `RealtimeCatchUp`;
  consumers refetch. Server can also demand catch-up (`pg_listener_recovered`).
- Actor echo (`REALTIME_ACTOR_ECHO_ENABLED=true`) delivers invalidations to *all* of the
  actor's own sessions → cross-tab/device convergence already works.
- Ops/runbook: [`docs/realtime-sync-operations.md`](realtime-sync-operations.md)
  (log markers `realtime_event=…`, dashboards, 1.5 s / 3 s convergence budgets).

Key files:

| Concern | File |
|---|---|
| Client transport → domain boundary | `packages/client/lib/data/service/invalidation_service.dart` |
| Client sync façade | `packages/client/lib/domain/use_case/realtime_sync_case.dart` |
| Change/catch-up entities | `packages/client/lib/domain/entity/realtime/*.dart` |
| Connection status UI | `packages/client/lib/ui/bloc/realtime_status_cubit.dart` |
| SQL emitters & triggers | `packages/server/lib/data/database/migration/m0114.dart` |
| Presence (focused sessions, WS `user_presence` path) | `packages/client/lib/data/service/user_presence_service.dart` |

## A2. Current Notification Center (durable per-user store already exists)

The server already has a **durable, per-recipient, deduplicated notification outbox**.
In revision-2 terms this is the per-recipient **receipt/delivery projection**, not the
semantic occurrence itself (see C1):

- Table `public.notification_outbox` (m0096): `id, account_id, category, kind, beacon_id,
  coordination_item_id, actor_user_id, title, body, action_url, priority, created_at,
  read_at, dedup_key, collapsed_count, emailed_at, digested_at`. Unique index on
  `dedup_key WHERE read_at IS NULL` → unread duplicates collapse (`collapsed_count++`,
  timestamp bump).
- `NotificationKind` (14 kinds — `needsMe, promiseMade, coordinationChanged,
  blockerOpened, blockerResolved, roomAccess, newRelay, commitmentEvent, reviewReady,
  roomActivityLowPriority, staleRemind, inviteAccepted, commitmentDeclined,
  commitmentRemoved`) → `NotificationCategory` (`asksOfMe, unblocksMe, coordination,
  connections, ambient`) via single `categoryOf()` map.
- **Recipient policy is pure and centralized**: `BeaconNotificationRecipientResolver`
  (per-kind audience: author, stewards, admitted, active participants, target person,
  forward recipients, review participants; actor always excluded; priority max-wins).
- Dispatch pipeline (`BeaconNotificationService.dispatch`): intent → context → recipients
  → copy (`BeaconNotificationCopyBuilder`, incl. lock-screen-safe variant + per-kind
  `action_url` deep links) → **outbox write for every recipient regardless of channels**
  → push preference gate (category opt-out, quiet hours, snooze, per-beacon mute) →
  FCM batch queue (two priority bands, coalesced copy via
  `BeaconNotificationBatchAggregator`) → immediate-email consideration for `asksOfMe`
  when the user is absent or `pushDelivered == false`; live `_enqueue` actually returns
  true when at least one token was queued, **before** any provider result, so that name
  does not currently prove delivery. Remaining eligible rows may enter the digest.
- **Channel delivery is not durable today.** `FcmBatchQueue` is an in-memory map cleared
  before send and logs failures without requeueing; direct review pushes are
  `unawaited`; immediate-email failures are logged (the later digest may cover some
  email-eligible rows, but is not an attempt ledger). Any target design that promises
  retryable channel sends must add persisted delivery jobs rather than naming this
  pipeline "channel machinery".
- Producers: use cases call `BeaconRoomNotificationPort` methods (`notifyNeedsMe`,
  `notifyPromiseMade`, `notifyBlockerOpened/Resolved`, `notifyForwardReceived`,
  `notifyHelpOfferToAuthor`, `notifyCommitmentDeclined/Removed`, `notifyHelpWithdrawn`,
  `notifyPlanUpdatedToRoom`, `notifyReviewOpened`, `notifyRoomAdmitted`,
  `notifyStaleRemind`, …) implemented by `beacon_room_push_service.dart` →
  `BeaconNotificationService`.
- Read API: server GraphQL extension `notificationsFeed(limit, before)` +
  `notificationsUnreadCount` (query) and `notificationsMarkRead(ids)` /
  `notificationsMarkAllRead` (mutation) —
  `packages/server/lib/api/controllers/graphql/{query,mutation}/…notification_center.dart`,
  guarded by `BeaconAccessGuard` row filtering (`filterBeaconNotifications`).
- Client slice `features/notification_center/`: `NotificationCenterCase`
  (merges repo changes + realtime `notification` kind + catchUps),
  `NotificationCenterCubit/State`, `NotificationCenterScreen` (list + **Mark all read**
  + tap → `markRead` → `RootRouter.openFromNotificationLink(actionUrl)`).
- Entry point: bell icon `_NotificationCenterButton` in the **Inbox top bar**
  (`packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`, ~line 610), badge =
  `NewStuffState.notificationUnreadCount` (= server `unreadActionableCount`, i.e. unread
  `asksOfMe` rows).
- Retention: `deleteSettledOlderThan` (read + old); email digest watermark fields.

**Semantics today: binary read/unread.** `read_at` is set by tap or Mark-all-read;
"actionable" is only a *count filter* (`category = asksOfMe`), not a lifecycle.

## A3. Push pipeline

- **Data-only FCM** (no `notification` field, deliberately —
  [`docs/qa-push-testing.md`](qa-push-testing.md) §"Data-only push payloads");
  the server-generated service worker
  (`packages/server/lib/api/controllers/firebase_sw_controller.dart`) calls
  `showNotification()` in `onBackgroundMessage` and owns `notificationclick` → focuses or
  opens `data.link`.
- Client token lifecycle: `features/notification/` (FcmCase/FcmCubit, register/delete
  token GQL, permissions probes, debug log screen).
- Tap routing: `data.link` (= outbox `action_url`) →
  `RootRouter.openFromNotificationLink()` (native path:
  `packages/client/lib/app/platform/lifecycle_handler_native.dart`).
- `action_url` shapes produced today (`BeaconNotificationCopyBuilder._actionUrl`):
  `/#/beacon/review/:id`, `/#/shared/view?id=:beaconId[&dest=room|people][&item=:itemId]`,
  `/#/` (inviteAccepted).
- Foreground behavior: web SW only fires when the page is unfocused; there is no
  foreground `onMessage` display on any platform → **a focused client never shows an OS
  banner today** (good baseline for the "no push when it was really shown" rule).
- QA: `POST /_qa/send-fcm` one-shot sender.

## A4. Existing attention indicators ("new stuff")

Documented in [`docs/features/new-stuff-indicators.md`](features/new-stuff-indicators.md):

- `NewStuffCubit` (`features/home/ui/bloc/new_stuff_cubit.dart`, @singleton): **local
  Drift cursors** per account (`newStuff:inbox:<id>`, `newStuff:myWork:<id>` in
  `settings`), compared with max-activity timestamps reported by `InboxCubit` /
  `MyWorkCubit` after successful fetches. Tab dots hidden while the tab is active;
  cursor advances when the user *leaves* the tab.
- Tab dots: `InboxNavbarItem` / `MyWorkNavbarItem` wrap icons in `Badge`;
  `NewStuffDot` is the shared dot widget (also used on inbox rows).
- Inbox rows: `InboxRowHighlightKind {none, newForwardActivity, updatedBeaconOnly}` →
  dot + "New"/"Updated" pill in `inbox_item_tile.dart`.
- My Work: tab dot only (`MyWorkCardViewModel.newStuffActivityEpochMs` = max of beacon
  updated/statusChanged, help-offer row updates, coordination updates, item messages);
  **no per-card markers today**. Cards do show a "last event" row
  (`MyWorkLastEvent` + `my_work_last_event_row.dart`) — content, not attention state.
- `NewStuffState.notificationUnreadCount` also feeds the Inbox bell badge (A2).
- **Room messages** have a real read model: server `room_seen` watermark table + wire
  kind (recipients = the row owner across their sessions), client
  `RoomReadWatermarkStore` distinguishing *local read-through* (user reached bottom) from
  *server-confirmed* sync, `resolveUnread()` merging both, unread divider widget, tests
  `room_cubit_unread_test.dart`, `beacon_room_case_test.dart`. This is the in-repo
  precedent for "seen = confirmed visibility, synced across devices".
- Beacon detail has an attention precedent: deep-link query
  `?tab=people&people_tab_attention=1` pulses/highlights the People tab and the first
  unanswered offer **until interaction** (`beacon_people_tab_body.dart`,
  `beacon_operational_scroll_view.dart`).

**Divergence risk found (the "timestamp hacks" the product brief warns about):** four
independent sources of attention truth exist today — (1) local Drift cursors for
Inbox/My Work dots, (2) server `notification_outbox.read_at` for the bell badge,
(3) `room_seen` watermarks for chat unread, (4) one-shot route params
(`people_tab_attention`) for field pulses. They can and do disagree (e.g. reading a
notification doesn't clear the inbox dot; visiting Inbox doesn't mark notifications).

## A5. Request state updates (already-open screens)

`BeaconViewCase` orchestrates refetches from `changesFor({beacon, helpOffer,
coordinationItem, participant, factCard, activityEvent, roomMessage …})` + `catchUps`;
cubits keep the existing snapshot during background sync (generation guards). The
operational header (STATUS / NOW / YOU / ACT — `beacon_hud_derivation.dart`,
`beacon_operational_header_card.dart`) and tabs **Items(0) / People(1) / Log(2)** +
separate **Room surface** re-derive from refetched state. So "field updates without
refresh" already works; what's missing is *field-level change highlighting* and
*acknowledgement*.

Coordination model relevant to "ask/promise/blocker addressed to me":
`CoordinationItemKind {plan, ask, blocker, resolution, promise}` with
`targetPersonId` for directed kinds; `CoordinationItemStatus {open, accepted, resolved,
cancelled, superseded}` (note: **supersession already exists** at the coordination-item
level); `CoordinationItemEventKind` log events power the beacon Log tab and
`MyWorkLastEvent`.

## A6. Navigation branches

`RootRouter` (auto_route) — `HomeRoute` hosts an `AutoTabsRouter` with **four
`EmptyShellRoute` branches**, each with its own nested stack
(`packages/client/lib/app/router/home_tab_branches.dart`):

| Index | Shell | Root page | Path |
|---|---|---|---|
| 0 | `workTabShell` | `MyWorkRoute` | `/home/work` |
| 1 | `inboxTabShell` | `InboxRoute` | `/home/inbox` |
| 2 | `networkTabShell` | `FriendsRoute` | `/home/network` |
| 3 | `meTabShell` | `ProfileRoute` | `/home/profile` |

- All browse detail routes (beacon view, item discussion, review, profile view, graphs,
  rating, notifications, inbox-rejected) are registered **once** in
  `browseDetailChildren()` and reused by every branch → details push onto the *active*
  branch stack; Back returns to the tab's previous position. Exactly the containment
  behavior the Updates branch needs.
- `HomeScreen` renders `NavigationBar` (compact; hidden while a detail is pushed) or
  `NavigationRail` (regular/expanded) from the same destination list; tab reselect resets
  the branch to its root (`resetHomeTabBranchToRoot`, `HomeTabReselectCubit`).
- Index sensitivity: `homeTabShellFor()`/`homeBranchPathPrefixFor()` switch on
  `activeIndex` numbers; `NewStuffCubit.hasNew*Dot` compares `activeHomeTabIndex` to
  hard-coded 0/1; `home_bottom_nav_listener.dart` syncs the index. **Adding a fifth tab
  shifts indices 2/3 → all these sites must change together.**

## A7. Deep-link behavior

Three-stage pipeline (documented in `root_router.dart`):

1. `_transformDeepLink` — normalizes legacy shapes (`/beacon/:id`, `/shared/view?id=…`
   app-links, invite/credential links).
2. `_prefixBrowseBranch` — platform-originated URLs get nested under the owning
   `/home/<tab>` prefix (`homeBranchPathPrefixFor`; warm = active tab wins, cold =
   semantic owner from `_browsePathOwners`; `kPathNotifications` owner = **inbox**).
3. Bare in-app `pushPath` hits root **redirect-target guards** which forward into the
   active branch (`_forwardIntoHomeBranch`, warm-push vs cold-navigate).

Notification taps go through `openFromNotificationLink(rawLink)` (strips `/#`, normalizes,
preserves `dest=room` as `entry=room_notification`, then `pushPath`).

## A8. Multi-tab / reconnect

- Every session of an account receives fan-outs (actor echo included) — convergence
  across tabs/devices is the tested norm (multi-client runner
  `scripts/run_realtime_multiclient_web_local.sh`, five-consecutive-pass release gate).
- Reconnect: connection epoch bump → catch-up event → projections refetch; brief
  disconnects invisible; >2 s shows the paused banner.
- `room_seen` is the model for state acks: mutation → row update → `room_seen` fan-out to
  *your own* other sessions → they adopt the watermark. Local `RoomReadWatermarkStore`
  prevents regressions while the mutation is in flight.

## A9. Commit `9be384bf` (historical Updates placeholder)

Removed 2026-06-23: never-routed `UpdatesScreen` placeholder (AppBar with a
"Mark all as read" stub → "not implemented" snackbar; empty body), dead
`features/updates/data/gql/updated_{beacons,users}_take.graphql` (commented-out calls to
a legacy Hasura `updates(args: {prefix: "B"|"U"})` action), `kPathFavorites`, and l10n
keys `markAllAsRead`, `favorites` (`notImplementedYet` survives). Takeaways:
(1) the old concept was a raw "changed entities" list — **exactly what the new spec
rejects**; (2) nothing worth restoring; (3) the name `features/updates/` is free again,
and l10n context strings `"UpdatesScreen"` still exist in arb files as stale `@context`
comments only. Do not resurrect the GraphQL `updates` action.

## A10. Relevant tests & docs inventory

- Server: `test/architecture/realtime_entity_contract_test.dart`,
  `test/data/database/realtime_notification_migration_test.dart` (pg-tagged),
  notification service/repo tests, `rest/qa_send_fcm.http`.
- Client: `test/architecture/realtime_entity_contract_test.dart`,
  `test/data/service/invalidation_service_test.dart`,
  `test/features/notification_center/notification_center_cubit_test.dart`,
  `test/features/beacon_room/room_cubit_unread_test.dart`, `beacon_room_case_test.dart`,
  beacon_view orchestration tests, `test/app/router/home_tab_branch_routing_test.dart`,
  inbox/my_work cubit tests.
- Integration: `scripts/run_client_integration_web_local.sh` (single-client),
  `scripts/run_realtime_multiclient_web_local.sh` (author/helper + forced missed-event
  recovery). See `docs/local-integration-tests.md`, memory notes on
  `QA_INTEGRATION_TEST_MODE`.
- Docs: `realtime-sync-operations.md`, `features/new-stuff-indicators.md`,
  `qa-push-testing.md`, `Tentura_current_status_quo.md` (§5 surface model),
  `watching-mechanism.md`, `beacon-evaluation-principles.md`,
  `adaptive-router-refactor-plan.md`, `room-coordination-audit.md`.

## A11. Sources of truth and divergence points (summary)

| Signal | Today's truth | Problem |
|---|---|---|
| Bell badge | server `notification_outbox` unread asksOfMe | cleared by tap/Mark-all-read, not by doing the work |
| Inbox tab dot / row pills | local Drift cursor vs fetch max-activity | device-local; unrelated to outbox; can contradict badge |
| My Work tab dot | local Drift cursor | same; no card-level marker |
| Chat unread | server `room_seen` + local read-through | correct pattern, but island |
| Field pulses | route query param | one-shot, not persisted, single field family |
| Push | outbox write + FCM | independent of all of the above once sent |

v1 collapses row 1 into the event-derived Updates projection (badge and feed from one
authorized receipt relation), keeps `room_seen` as the message-level cursor it is
(bridging directed Chat receipts into the same read axis), and keeps push exactly
today's best-effort channel — now fed from a transactionally written receipt. Rows 2–3
(local cursor dots) are deliberately retained unchanged in v1 and unified in the
separately gated increment T-21; row 5 remains a one-shot destination adapter whose
generalization is the highlight increment T-17.

---

# Part B — Messenger presence/read-marker research (external)

What was reviewed and what we take from it:

- **Telegram** — per-dialog monotonic read cursors (`read_inbox_max_id` /
  `read_outbox_max_id` + `unread_count` on the dialog object), synced across devices via
  `updateReadHistoryInbox/Outbox` updates; badge = derived, server-authoritative.
  Take: *cursor-per-container beats per-item flags for high-volume streams* → we keep
  `room_seen` (already a Telegram-style cursor) for Room messages and do **not** create
  per-message Updates events; and *read state changes are themselves realtime updates*
  (our `notification` wire kind already fans out `update` ops on the outbox row —
  mark-seen syncs for free).
  Sources: [dialog constructor](https://core.telegram.org/constructor/dialog),
  [tdesktop api.tl](https://github.com/telegramdesktop/tdesktop/blob/dev/Telegram/SourceFiles/mtproto/scheme/api.tl),
  [read_inbox_max_id explainer](https://medium.com/@jiayu./hello-once-you-have-a-dialog-object-you-can-inspect-its-read-inbox-max-id-and-read-outbox-max-id-282562c1604c).
- **Matrix** — explicit split of *public receipt* (`m.read`), *private receipt*
  (`m.read.private`, v1.4), and *private bookmark* (`m.fully_read`); threaded receipts
  (MSC3771/3773) key receipts by sub-context. Take: *"seen" is private state, distinct
  from social signaling* — Tentura acks are private (no "B saw your change" surfaces in
  v1); and *acks need a scope key* (our `field_target`/thread analog).
  Sources: [Matrix read receipts & notifications](https://patrick.cloke.us/posts/2023/01/05/matrix-read-receipts-and-notifications/),
  [MSC2285 private read receipts](https://github.com/matrix-org/matrix-spec-proposals/blob/main/proposals/2285-hidden-read-receipts.md),
  [Matrix v1.4 release](https://matrix.org/blog/2022/09/29/matrix-v-1-4-release/).
- **GitHub notifications** — the closest product analog to `seen ≠ resolved`: inbox rows
  have **read/unread** (visibility state) *and* **Done** (triage/resolution state, with
  `is:done` archive); "Done" is what empties the inbox, reading alone does not.
  Take: read/unread and Done are independent axes. Issue #80 chooses **unread** for the
  Updates badge; a future separately named "Needs you" projection may use settlement,
  but the GitHub work-queue count is not imported into v1.
  Source: [Managing notifications from your inbox](https://docs.github.com/en/subscriptions-and-notifications/how-tos/viewing-and-triaging-notifications/managing-notifications-from-your-inbox).
- **In-repo precedent** — `RoomReadWatermarkStore` already encodes the delivered <
  rendered/read-through < server-confirmed distinction and monotonicity rules; the
  Updates design generalizes exactly this pattern to events.

Distilled model used in Part C (per event, per recipient) — **two independent axes, not
one ladder**. The GitHub precedent above already makes read/unread and Done orthogonal;
revision 1 collapsed them into one status enum, which the review (I4) rejected:

```
read axis:       delivered (transport fact, not persisted)
                   < rendered (client fact, not persisted)
                   < seen (persisted seen_at: opened/acknowledged — monotonic)
settlement axis: unsettled | resolved / dismissed / superseded
                 (independent facts; not persisted in v1 — see C0.2 D-5)
```

We deliberately do **not** persist `delivered`/`rendered` per row (Matrix/Telegram don't
either); idempotent catch-up + server-authoritative rows make them unnecessary. If
delivery diagnostics are ever needed, they belong in logs/metrics, not the data model.

---

# Part C — Target architecture (Revision 4)

> **Revision note (2026-07-16).** Revision 3 resolved the Part I findings with an
> occurrence/receipt/delivery topology. The Part L proportionality review found that
> topology internally consistent but out of proportion to issue #80: most of its
> guarantees (replayable projection, durable multi-channel delivery, event-time audience
> history, erasure rewriting) are notification-platform requirements the issue never
> makes. Revision 4 keeps every correction that protects the in-app product contract and
> cuts the rest. The full revision-3 design remains in git history and Part K as the
> starting point for the deferred delivery/audit increment (T-20).

## C0. Product contract and resolved decision gates

### C0.1 The product contract (issue #80, verbatim requirements)

Title: *"[P1][UX] Add an in-app activity/notification surface with reliable unread
counters"*. Required event types (minimum):

1. request forwarded to me;
2. new help offer on my request;
3. author response to my offer;
4. Room mention or message relevant to me;
5. Room admission/removal;
6. request status changed;
7. review became available;
8. relationship/contact state changed.

Acceptance criteria (verbatim):

- Provide a persistent in-app activity surface accessible from navigation.
- Each event links to the exact request/person/state requiring attention.
- Unread counts are derived from unread events, not stale local increments.
- Opening/acknowledging an event updates all badges consistently.
- Empty Inbox/activity states never show a non-zero badge.
- Reconnect and multi-tab use do not duplicate counts.
- Users can control noisy event classes while safety/obligation events remain visible.

Everything in v1 is a direct technical interpretation of this text. Note what the text
does **not** promise: durable or retryable push/email delivery, an auditable event
history, replayable projections, or cross-channel delivery bookkeeping. Extensions in
either direction (settlement/work-queue, dwell acknowledgement, search — and now also
the delivery/audit platform) are explicitly deferred, separately gated increments (C14)
requiring their own product approval.

### C0.2 Decision gates D-1…D-8 (resolved; D-2/D-3/D-7 revised in revision 4)

| Gate | Decision |
|---|---|
| D-1 | **The nav badge is unread** (the logical seen axis over the authorized receipt relation: `COALESCE(seen_at, read_at) IS NULL` during compatibility, then `seen_at IS NULL` after T-19). Unresolved-work tracking ("Needs you") is deferred to increment T-16 and, if approved, ships under its own name and count — never as the unread badge. |
| D-2 | **Canonical v1 store = the per-recipient receipt in the existing `notification_outbox`, extended in place** (`seen_at`, source-event identity, typed destination, suppression/preference class, access policy). No `attention_occurrence`, no `attention_occurrence_recipient`, no `attention_channel_delivery`/throttle tables in v1. The occurrence → receipt → delivery-job topology remains the recorded *target* shape for the day durable multi-channel delivery or audit/replay becomes product scope (increment T-20); ADR 0010 (T-00) records both the target shape and why v1 defers it. |
| D-3 | **Receipt writes are transactional with the domain mutation.** The producing use case owns one transaction through a domain-owned `MutatingUnitOfWorkPort`; recipient resolution, per-recipient policy, copy, and the per-recipient outbox writes run inside it. Kinds whose mutation destroys the audience source (decline/removal) resolve recipients **before** the destructive statement, in that same transaction — the committed receipt rows *are* the event-time snapshot, so no separate audience-history table is needed. Channel sends (FCM/email) stay post-commit and best-effort, exactly today's pipeline. No projector, no sweeper: with a synchronous write there is no replay window for audiences to drift in. |
| D-4 | **Mandatory/safety-obligation events cannot be suppressed.** Every receipt carries `suppression_class` (`mandatory` \| `standard` \| `noisy`) plus nullable `in_app_preference_class`. Only contract-declared noisy preference classes are mutable. Existing `NotificationCategory` remains the push/email grouping and is not reused for in-app muting because one category currently contains both mandatory and noisy projections. |
| D-5 | **Read state and settlement are separate axes.** v1 persists only the read axis (`seen_at`, nullable, monotonic). Settlement facts (`settlement_kind`, `settled_at`, `settled_by_*`) are **not in the v1 schema** — they arrive with increment T-16 as their own expand-only migration. |
| D-6 | **The badge/group unit is one visible unread receipt row** — exactly the cards the feed shows (write-time collapse already merges repeats, so rows ≈ cards). No `group_key`. A typed `attention_thread_key` is introduced together with the settlement increment. |
| D-7 | **v1 ships:** feed + unread badge + exact destinations + open/explicit acknowledgement (incl. mark-all-seen) + in-app noisy-class preferences with mandatory visibility + realtime/catch-up/multi-tab correctness + producers for all 8 required event classes. **v1 defers:** settlement workflow, field-level dwell highlights, search/advanced filters, non-required extra kinds — and, per Part L: durable channel-delivery jobs (T-20), the occurrence/audit store (T-20), per-beacon card markers and tab-dot unification (`NewStuffCubit` and its Drift cursors stay untouched in v1; T-21), and any new retention/erasure machinery (T-22). |
| D-8 | **The old Notifications bell/route is removed only in the flip release (T-15)** — the same release that enables Updates after parity and invariant tests pass. T-08…T-14 use a default-off compile-time QA flag; T-15 removes that flag and ships the new surface unconditionally while deleting the old chrome. New T-05 event producers are likewise deployed dormant behind a default-off server env gate for QA, then T-15 enables them unconditionally and removes that gate. |

### C0.3 Non-negotiable invariants (revision 4)

1. For every **activated** contract producer, domain success guarantees the durable
   in-app receipt: receipt writes commit in the same transaction as the domain change,
   so receipt durability equals mutation durability. (T-05 types activate at T-15;
   before that their deploy-only gate defines them as dark.)
2. Channel delivery (push/email) stays post-commit and best-effort with today's exact
   semantics; a channel failure can never roll back the domain action or lose the
   in-app receipt. Retryable/durable channel delivery is explicitly **not** promised in
   v1 (deferred, T-20) — and v1 must not silently regress today's channel behavior
   either (regression suite, Part E).
3. Read acknowledgement and obligation settlement are independent monotonic facts (v1
   ships only the first).
4. The navigation badge formula is the named product contract "unread visible receipts",
   not an incidental SQL expression.
5. A positive badge and every feed view derive from the **same** destination-aware
   authorized receipt relation; the Unread view is the mechanical witness for the
   unread count.
6. Recipient policy is explicit (`AttentionPolicy.project` over event type + recipient
   reasons); no kind-only helper decides recipient-specific outcomes.
7. Source-event identity, UX collapse, and any future grouping/supersession use
   distinct, documented identities.
8. Realtime frames are hints; one attention use case performs guarded account-scoped
   refresh with a bounded budget.
9. Peer UI features depend on the attention application slice, never on Updates UI.
10. Mixed old/new clients and server rollback stay correct until the explicit contract
    phase and `MIN_CLIENT_VERSION` decision.
11. Every issue-required event class has a real producer, exact destination, preference
    class, and automated coverage entry in the compact machine-readable contract.
12. No old user-visible source of attention truth is removed before its replacement
    proves parity end to end in the same release.

(Revision 3's invariants 13–14 — event-time audience immutability under replay and
immutable queued-send context — existed only to make the asynchronous projector and the
durable delivery queue safe. With neither in v1, they move to T-20's acceptance
criteria.)

## C1. Data model: extend the outbox in place (server)

Conceptual shape (D-2/D-3):

```
domain mutation ──(same transaction)──► notification_outbox rows
                                        one per recipient; read state, typed
                                        destination, policy classes on the row —
                                        the committed row IS the event-time snapshot
                                             │  post-commit, best-effort
                                             │  (today's pipeline, unchanged)
                                             ▼
                              push preference gate → FcmBatchQueue → FCM
                              immediate-email consideration → email / digest
```

Migration **m0115** (next free number after the live m0114), **expand-only — no index
drops, no destructive statements, no trigger changes**:

```sql
ALTER TABLE public.notification_outbox
  ADD COLUMN seen_at              timestamptz,
  ADD COLUMN source_event_key     text,
  ADD COLUMN destination_kind     text,
  ADD COLUMN target_entity_id     text,
  ADD COLUMN presentation_key     text,
  ADD COLUMN presentation_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN in_app_preference_class text,
  ADD COLUMN suppression_class    text NOT NULL DEFAULT 'standard'
    CONSTRAINT notification_outbox__suppression_chk
    CHECK (suppression_class IN ('mandatory', 'standard', 'noisy')),
  ADD COLUMN access_policy        text NOT NULL DEFAULT 'legacy'
    CONSTRAINT notification_outbox__access_policy_chk
    CHECK (access_policy IN (
      'legacy', 'beacon_content', 'beacon_tombstone', 'recipient_safe', 'profile'
    )),
  ADD CONSTRAINT notification_outbox__preference_class_chk CHECK (
    in_app_preference_class IS NULL OR suppression_class = 'noisy'
  ),
  ADD CONSTRAINT notification_outbox__beacon_policy_chk CHECK (
    access_policy NOT IN ('beacon_content', 'beacon_tombstone') OR beacon_id IS NOT NULL
  ),
  ADD CONSTRAINT notification_outbox__recipient_safe_chk CHECK (
    access_policy <> 'recipient_safe' OR (
      presentation_key IS NOT NULL AND presentation_key IN (
        'room_member_removed', 'offer_declined', 'offer_removed'
      )
    )
  ),
  ADD CONSTRAINT notification_outbox__new_shape_chk CHECK (
    source_event_key IS NULL
    OR (destination_kind IS NOT NULL AND presentation_key IS NOT NULL)
  );

-- No backfill in m0115: the live row trigger would emit once per historical row.
-- m0116 performs it after the statement-level publisher cutover (C6/T-01b).

CREATE INDEX notification_outbox__unread
  ON public.notification_outbox (account_id, created_at DESC, id DESC)
  WHERE COALESCE(seen_at, read_at) IS NULL;
CREATE INDEX notification_outbox__feed_v2
  ON public.notification_outbox (account_id, created_at DESC, id DESC);
-- The existing unique index on (dedup_key) WHERE read_at IS NULL stays untouched;
-- see C12 for why the transition never swaps it.

ALTER TABLE public.notification_preference
  ADD COLUMN muted_in_app_event_classes text[] NOT NULL DEFAULT '{}';
```

Notes:

- **`notification_outbox` is a receipt, not the event.** All new code, docs, and entity
  doc comments describe it as the per-recipient attention receipt. Rows written before
  m0115 keep `source_event_key IS NULL` (legacy receipts — feed/badge treat them
  normally).
- **`source_event_key`** names the immutable source event (message id, help-offer id,
  activity-event/transition id — the same identity recipes revision 3 designed), built
  and parsed only by one versioned codec
  (`domain/notification/attention_identity.dart`). It is identity **metadata, not a
  uniqueness mechanism**: with transactional writes, receipt-write idempotency equals
  the producing mutation's idempotency, which is exactly today's per-kind status quo
  (C8). Its v1 jobs: the room bridge (which message a directed-Chat receipt currently
  points at), `collapse: none` recipes, diagnostics — and it is the forward-compatible
  seed for the T-20 occurrence store, so no second identity rewrite is needed later.
- **Typed destination** (`destination_kind` + `target_entity_id`) replaces parsing
  `action_url` for the Updates feed; `action_url` remains the push/legacy channel link.
- **`presentation_key` + `presentation_payload`** carry per-recipient allowlisted,
  sanitized structured facts for client-side l10n rendering (EN/RU); server
  `title`/`body` remain push-channel copy and the fallback for keys a stale client does
  not know. Allowlists and byte bounds are enforced in code with focused tests, not in
  the contract file (Part L #5). Free-form Chat/offer bodies are referenced by
  authorized source id, never copied into the receipt.
- **`access_policy`** makes authorization destination-aware (unchanged from revision 3
  — this is load-bearing for required classes 3 and 5): normal Request receipts use the
  ADR-0008 predicates; the tightly allowlisted `recipient_safe` terminal receipt
  survives the very access loss it reports, with sanitized copy and a safe destination.
  ADR 0010 records this explicit ADR-0008 amendment; the pg test asserts the DB
  allowlist equals the contract's.
- **`in_app_preference_class`** is a stable, contract-owned mute key such as
  `coordination_churn` or `request_progress`; null on non-mutable rows (D-4).
- **What v1 deliberately does not add** (each returns only with the increment that
  needs it): `attention_occurrence`, `attention_occurrence_recipient`,
  `attention_channel_delivery`, `attention_channel_throttle`, content hashes,
  `recipient_reasons` audit columns, `surfaces`, `expires_at`, storage immutability
  guards, erasure/scrub workflows (T-20/T-21/T-22, Part L #1/#2/#6).
- `beacon_activity_events` remains the Request Log/audit projection. Where such a row
  already represents the transition, its stable id is the `source_event_key` source;
  both are recorded in the same use-case transaction.
- The unread predicate during the transition window is
  `COALESCE(seen_at, read_at) IS NULL` (C12).

## C2. Write path: transactional dispatch (no projector)

The live path (`unawaited(...)` dispatch after the repository mutation, per-recipient
outbox loop with a catch-all, per-repository `withMutatingUser` transactions) makes
Notification Center persistence best-effort — a successful mutation can silently lose
its receipt. Issue #80's one reliability promise is exactly this receipt, so revision 4
fixes it at the source instead of adding replay machinery around it (Part L #2):

1. **Use-case-owned transaction through an inward port (prerequisite refactor, T-03).**
   Server domain code must not import `TenturaDb`. It owns a narrow
   `MutatingUnitOfWorkPort.run(actorUserId?, action)`; the data adapter delegates to
   `TenturaDb.withMutatingUser` (or a system transaction when the actor is null).
   Producing repository commands become transaction-neutral, or expose explicitly named
   `…InTransaction` variants during the migration; the plan does **not** assume
   arbitrary nested drift transactions join correctly. A pg integration test proves one
   connection/transaction and actor-GUC scope.
2. **In-transaction receipt materialization.** Inside that unit, after (or, for
   destructive kinds, straddling) the domain writes, the use case calls
   `AttentionDispatchPort.record(intent)`, which within the same transaction:
   - loads context and resolves recipients (`BeaconNotificationRecipientResolver`,
     refactored in T-02 to return **full** reason sets — it stays the single audience
     policy home);
   - for decline/removal/admission-loss kinds, resolves recipients **before** the
     destructive statement, as declared per kind in code next to its test — same
     transaction, so there is no window in which the audience can drift;
   - runs `AttentionPolicy.project` per recipient (C3);
   - upserts receipts via the existing collapse mechanics (C8) with the new columns
     (source identity, typed destination, presentation, policy classes);
   - returns the per-recipient channel decisions (who is push/email eligible, with the
     already-built copy) to hand off after commit.
   Reads inside the transaction are bounded: the resolver audiences are the existing
   per-kind sets, and the one broad audience (`requestStatusChanged` watchers) is
   bounded and write-collapsed (Part D, R-1). No external I/O runs inside the
   transaction.
3. **Channels strictly after commit, best-effort (status quo).** The use case hands the
   materialized channel decisions to the existing pipeline: push preference gate →
   `FcmBatchQueue` (in-memory, coalescing, at-most-once) → immediate-email
   consideration → digest. Behavior, coalescing, and cooldowns are unchanged from
   today. A crash between commit and send loses at most channel attempts — exactly
   today's exposure, now with the receipt guaranteed. Making this leg durable is the
   entire scope of increment T-20.

Failure contract (tested by injection, Part E):

| Failure point | Outcome |
|---|---|
| domain write fails | transaction rolls back; no receipts, no sends |
| any receipt write fails | same transaction → domain change rolls back too (atomicity is symmetric and deliberate) |
| producer invoked twice inside one action (bug) | `dedup_key` collapse absorbs the duplicate while unread |
| domain action legitimately performed twice | two receipts — faithful reporting; per-kind domain idempotency is unchanged from today |
| crash after commit, before channel send | receipt durable and correct; push/email attempt lost (documented status-quo channel semantics) |
| push/email provider failure | logged, not retried (status quo); never affects domain rows or receipts |

The migrated producers **delete** their `unawaited(notifyX(...))` calls. Completion is
proved by an explicit call-site inventory, not only the `BeaconNotificationService`
name: `BeaconRoomNotificationPort`, `BeaconNotificationPort`, and
`InviteAcceptedNotificationPort` calls in `AuthCase`, `CredentialAuthCase`,
`InvitationCase`, `HelpOfferCase`, `ForwardCase`, `CoordinationCase`, every
`coordination_item/*Case`, `EvaluationCase`, and `BeaconRoomCase`; new lifecycle and
relationship producers are separately covered by T-05. Every call is migrated or
deliberately listed as non-attention.

## C3. Recipient projection policy (one explicit function)

`categoryOf(kind)`-style global helpers cannot express recipient-specific outcomes
(review I5). One policy owns the projection, evaluated at write time inside the
transaction; its outputs are persisted on the receipt, so nothing is ever re-derived
from later relationship state — the receipt is the snapshot:

```dart
AttentionPolicy.project({
  required String eventType,
  required String recipientId,
  required Set<AttentionRecipientReason> recipientReasons, // full set, from resolver
  required RecipientRoleFacts role, // in-memory facts from the same transaction
}) => ReceiptProjection(
  category,            // existing NotificationCategory (kept for push prefs compat)
  suppressionClass,    // mandatory | standard | noisy   (D-4)
  inAppPreferenceClass,// nullable; only noisy contract classes are mutable
  accessPolicy,        // legacy | beacon_content | beacon_tombstone | recipient_safe | profile
  destination,         // canonical deep-link destination + target entity (C9)
  presentationKey,     // client l10n key family (C11)
  presentationPayload, // per-recipient allowlisted/sanitized structured facts
);
```

- The same event type may project differently per recipient (e.g. `blockerOpened` →
  `mandatory` for the affected target, `standard` for stewards;
  `requestStatusChanged` → `standard` for active participants, `noisy` for watchers).
- `AttentionRecipientReason` is the attention-domain type; the legacy notification
  reason enum is translated at the adapter boundary.
- **Compact machine-readable contract:** `docs/contracts/updates-event-contract.json`
  lists every event type with exactly five facts: **producer command, recipient
  category(-ies), destination family, muteability (suppression/preference class), and
  covering-test pointer** — the same weight class as the proven
  `realtime-entity-contract.json`. Server and client architecture tests both consume
  it. Identity recipes, collapse recipes, audience-resolution queries, and payload
  allowlists live in code next to focused tests, not in the contract (Part L #5): a
  contract that owns SQL and payload schemas becomes a second implementation language
  and drifts.

## C4. Read model: one authorized relation

The live badge bug class (guard-filtered feed vs unguarded `unreadActionableCount`) is
eliminated structurally (review I7): **one SQL-level authorized relation** defines what
a recipient can see, and every projection derives from it.

- `visible_attention_receipts(account_id)` — one data-layer query builder/SQL function
  combining:
  - `account_id` match;
  - destination-aware access: `beacon_content` calls the existing
    `public.beacon_can_read_content(beacon_id, account_id)` from ADR 0008;
    `beacon_tombstone` calls `beacon_can_read_tombstone`; `profile` is a
    contract-allowlisted, recipient-addressed, sanitized relationship/invite receipt
    whose destination independently uses the existing profile query/guards and falls
    back neutrally if the target disappeared; `recipient_safe` is allowed only for the
    allowlisted, sanitized terminal events addressed to this account; `legacy`
    preserves today's rule (`beacon_id IS NULL OR beacon_can_read_content(...)`). The
    existing SQL↔Dart visibility parity suite is extended; no third authorization
    implementation is introduced;
  - in-app preference suppression: `suppression_class <> 'noisy' OR
    in_app_preference_class IS NULL OR in_app_preference_class NOT IN (account's muted
    set)` (C10) — mandatory rows are structurally unfilterable;
  - normal receipts whose Request was deleted or access was revoked disappear from feed
    and badge together. The specifically addressed, copy-sanitized removal receipt is
    the deliberate exception needed to report the access-loss event itself.
- Derived from that one relation, in SQL (never post-filtered after pagination):
  - `attentionFeed(view, cursor)` — the one read API. Each call returns
    `{unreadSummary, page}` computed in **one repository statement/transaction**, so
    the badge number and the list the user is looking at cannot come from different
    database moments. `view ∈ {all, unread}`; pages are ordered
    `(created_at DESC, id DESC)` with an opaque composite cursor; authorization inside
    the query keeps pages full and cursors meaningful. `unreadSummary` is
    `{unreadTotal}` — the surface booleans and per-beacon marker lookups of revision 3
    are deferred with the markers increment (T-21, Part L #4); there is no separate
    compound `attentionSnapshot` operation to cache or invalidate.
- Invariant (tested at unit, pg, and e2e level): for every account and preference
  state, `unreadTotal` equals the count of rows returned by the authorized relation
  with the current compatibility-aware unread predicate (C12), and **`unreadTotal > 0`
  implies the first page of the Unread view is non-empty**. The All view remains
  chronological and may legitimately have newer seen rows on its first page. Entering
  from a non-zero shell badge selects Unread. Deleted/revoked normal rows and the safe
  terminal exception are covered explicitly.

## C5. Acknowledgement model (v1: open / explicit ack)

Per D-1/D-7 the v1 read rule is deliberately simple — exactly what the issue asks:

- `seen_at` is monotonic: set once, never cleared, independent of any future settlement
  axis.
- **Triggers:** (a) opening an event (card tap navigates → the tapped receipt is marked
  seen); (b) explicit per-item "Mark seen"; (c) **Mark all seen** over the same
  currently authorized/preference-visible relation as the active feed (muted noisy
  history remains unread and can reappear on unmute). The legacy feed/count/mark-all
  handlers delegate to the same relation/ack port during dual-write, so an old client
  marks every row it can actually display rather than clearing hidden data; (d) the
  **room bridge**: when a `beacon_room_seen` watermark advances, a server-side hook
  marks directed Chat receipts seen only in the same
  `(account_id, beacon_id, thread_item_id)` scope whose **latest collapsed source
  message** (the message `source_event_key`/`target_entity_id` currently points at) has
  `created_at <= last_seen_at` — so an older watermark cannot clear a collapsed receipt
  containing a newer directed message. General Chat unread remains the `room_seen`
  cursor; it is not copied into per-message attention rows.
- **No visibility/dwell acknowledgement in v1** (T-17). Informational cards are cleared
  by open, per-item ack, or mark-all.
- Optimistic local state: `AttentionAckStore` (client), modeled on
  `RoomReadWatermarkStore`'s monotonicity but **partitioned by account id and reset on
  every account id change** (review I9).
- Dual-write during transition: new ack paths set `seen_at` **and** `read_at`; the
  legacy `markRead`/`markAllRead` handlers set both too (C12). Old clients on other
  devices therefore keep correct counts.

## C6. Realtime delivery, catch-up, and the invalidation budget

The wire kind `notification` is kept. The statement-level publisher cutover survives
revision 4 on its own narrow merits (Part L #7): **mark-all-seen ships in v1**, and the
live row trigger (m0114) emits one PG notification per outbox row, so a 500-row
mark-all would emit 500 frames. This is a targeted bulk-acknowledgement optimization,
independent of any occurrence/delivery design; it is sequenced as its own migration
(m0116/T-01b) before the ack API ships.

- **Account-scoped aggregate id (m0116/T-01b, separate from expand-only m0115).**
  Dedicated statement-level publisher functions emit kind `notification` with
  `entity_id = account_id` (recipients `[account_id]`). INSERT/UPDATE/DELETE triggers
  use transition tables and emit once per distinct account touched by the SQL
  statement. The UPDATE publisher joins old/new rows by id and emits only when
  seen/read/collapse or user-visible projection columns changed; `emailed_at`/
  `digested_at` bookkeeping never wakes UI. Deployed old clients are safe: hint-based
  doctrine means they refetch projections on any `notification` invalidation and use
  the aggregate id only for dedup. The migration replaces the old row trigger
  atomically; no committed state has both publishers.
- **One refresh owner.** The client `AttentionCase` (C7) is the only subscriber that
  turns `notification` hints into queries: it coalesces pending hints into one
  `attentionFeed` head refresh (summary + first page of the active view), guaranteeing
  **at most one in-flight refresh plus one queued rerun**. The case normalizes cached
  rows by receipt id, replaces the feed head, and removes moved/acknowledged duplicates
  from older pages. Feature cubits never issue their own refetches from WS hints.
- **Numeric acceptance budget** (tested, not asserted in prose): acknowledging 1, 50,
  and 500 receipts produces exactly one PG notification per affected account per SQL
  statement, ≤ 2 snapshot refreshes per open client, and convergence within the
  existing realtime budgets (1.5 s same-device echo / 3 s cross-device).
- Catch-up and actor echo are unchanged correctness mechanisms: reconnect/epoch bump →
  head refetch; stable row ids keep re-renders idempotent.
- Contract updates: `docs/contracts/realtime-entity-contract.json` — T-08 adds
  `updates_feed`/`updates_badge` to the `notification` impacts alongside the existing
  entries; T-15 removes `notification_center` with the old center. Both architecture
  contract tests update in the same change each time.

## C7. Client architecture: attention slice + Updates presenter

Cross-feature state does not live in a presentation feature (review I9):

- **`packages/client/lib/domain/attention/`** (UI-independent application slice) owns
  `AttentionRepositoryPort`, `AttentionAccountPort`, entities, and cases;
  `lib/data/repository/attention_repository.dart` implements the repository port. The
  shared-domain lint forbids `lib/domain/**` from importing `data/**`/`ui/**`:
  - entities: `AttentionReceipt`, `AttentionSummary`;
  - `AttentionCase` (@singleton): merges repository changes + realtime `notification`
    kind + catch-ups; owns the guarded head-refresh coordinator (C6), the
    `AttentionAckStore` (account-partitioned, reset on every account change), and
    commands `markSeen(ids)`, `markAllSeen()`;
  - narrow selectors: `unreadSummary` stream (shell badge) and `feedPages` for the
    Updates screen. The page cache is normalized by receipt id and reset on account
    generation. (`unreadForBeacons` and surface selectors are deferred to T-21 with the
    markers/dots increment.)
  - `AttentionAccountPort` is implemented by the auth/session boundary, so the shared
    slice does not depend on `features/auth/ui` or `AuthCubit`.
- **`features/updates/`** is a pure presenter: `UpdatesScreen`, `UpdatesFeedCubit`
  (thin — projects `AttentionCase.feedPages`, holds scroll/view UI state),
  `UpdatesCard`, empty states. It owns no cross-feature state.
- The home shell consumes `AttentionCase.unreadSummary` for the Updates badge; nothing
  imports anything from `features/updates/`.
- **`NewStuffCubit` and its Drift cursors are retained unchanged in v1** (Part L scope
  cut): Inbox/My Work tab dots and row pills keep their local-cursor semantics, and the
  My Work empty-state CTA keeps `inboxNeedsMeCount`. Only two things change at the
  flip: the `notificationUnreadCount` field and its `unreadActionableCount` plumbing
  retire with the bell they feed, and the cubit's hard-coded active-tab index
  comparisons derive from `HomeTabSpec` (T-09). Unifying the dots onto attention truth
  is increment T-21, with its own parity plan.

## C8. Identity, collapse, and duplication (each identity has one job)

| Identity | Lives on | Job | Uniqueness |
|---|---|---|---|
| `source_event_key` | receipt | names the immutable source event: room bridge target, `collapse: none` recipes, diagnostics, T-20 seed | none in v1 (metadata) |
| `dedup_key` | receipt | **write-time UX collapse only** while unread | existing partial unique index, unchanged |
| row `id` | receipt | wire/dedup/ack identity | PK |

- **Idempotency is provided by transactionality, not by a new unique index** (Part L
  #2/#3): a receipt commits iff its producing mutation commits, so a retried *failed*
  mutation re-runs everything atomically and a *succeeded* mutation that runs twice is
  a per-kind domain idempotency question — the same one the live system already
  answers for all 14 kinds. Revision 3's always-unique occurrence `idempotency_key`
  guarded an asynchronous projector's replays; with no replay machinery, the "seen-
  retry hole" reduces to "the domain action really happened twice", which two receipts
  report faithfully.
- The **index/upsert mechanism** remains compatible, but new rows use a versioned
  `AttentionCollapseKey` codec, not today's `account|NotificationCategory|beacon|item`
  recipe. Category is too broad: `requestStatusChanged`, `relayReceived`, and
  coordination churn can share a category and beacon while being different cards. Each
  kind declares `collapse: none` (key includes `source_event_key`) or a typed family +
  subject such as `request_progress|beaconId` or `directed_room|beaconId|threadId` — in
  code, next to its test. Different families never collapse merely because their push
  category matches.
- Collapse refresh contract: on collapse the receipt updates `collapsed_count`,
  `created_at` (bump), `source_event_key` (latest), `actor_user_id`, `title`/`body`,
  destination/target, presentation key/payload, and policy classes; it never resurrects
  a seen row (a new row is created instead — behavior identical to today).
- **No supersession in v1** (D-6): under unread semantics a newer `blockerResolved`
  does not need to retire an unread `blockerOpened`; both are honest unread events.
- **No read-time grouping in v1**: the feed is the flat receipt list, ordered by the
  composite cursor — pagination-stable by construction.
- Delivery duplication (WS + catch-up + push) remains solved for in-app state by
  identity: all three carry/lead to the same receipt row id.

## C9. Navigation, routing, deep links

- **`HomeTabSpec`** (new, single source): an enum-keyed spec carrying index, path,
  shell route, root page, reselect target, and deep-link ownership.
  `homeTabShellFor`, `homeBranchPathPrefixFor`, `resetHomeTabBranchToRoot`,
  `home_bottom_nav_listener`, reselect cubit, and all active-tab comparisons (including
  `NewStuffCubit`'s) derive from it — the fifth tab is added by adding one spec entry,
  and the index fragility class dies with the refactor (review I13). This lands before
  the tab is visible (T-09).
- Fifth branch (target order `My Work → Inbox → Updates → Network → Profile`):
  `kPathUpdates = '/home/updates'`, `updatesTabShell`, branch registered with
  `browseDetailChildren()` so details push inside the Updates branch (existing
  containment mechanics). The destination is **not rendered while the client release
  flag is off** (D-8).
- Five destinations is the **v1 product cap**, not a universal platform maximum
  (Material 3 specifies three to five for the navigation bar; current Apple HIG
  recommends five or fewer by default). Record the chosen cap in
  `Tentura_current_status_quo.md` §5 at flip time.
- **Deep links encode a canonical domain destination**, never a home-tab ownership
  choice: `action_url` keeps its existing beacon/review/profile shapes. Branch choice
  happens at navigation time: push-originated and Updates-originated opens prefer the
  Updates branch (`openFromNotificationLink(preferUpdatesBranch: true)` /
  `openFromUpdate`); old links and non-Updates entry points keep active-branch
  behavior.
- Exact-destination targeting: `destination_kind` + `target_entity_id` map to
  lens/anchor via one client table (`domain/attention/destination_map.dart`); the
  existing `people_tab_attention` one-shot param continues to work unchanged in v1.
- Directed Chat destinations add a distinct `message=<messageId>` query parameter;
  existing `item=<coordinationItemId>` keeps its current meaning and is never
  overloaded with a message id. The room data boundary hydrates an authorized target
  message by id when it is outside the initially loaded page, then feeds the existing
  `RoomCubit.prepareThreadScroll(messageId: …)` path. Pre-T-11 clients rebuild the
  normalized Room query from known keys and therefore drop unknown `message` safely,
  opening the Chat root rather than failing.
- Each kind declares a typed fallback in code: if a target or access disappears,
  navigation resolves to a sanitized terminal/tombstone state that explains what
  changed; it must not silently open an unrelated root. `recipient_safe` removal rows
  use this path and never expose Request content the recipient can no longer read.
- Legacy `/notifications` URL: `RedirectRoute` → `kPathUpdates`, shipped in the flip
  release together with the bell removal.
- Updates list restores scroll position and view state on Back (`PageStorageKey` +
  cubit state, existing precedent).

## C10. Preferences: noisy classes vs mandatory visibility

The issue requires in-app control of noisy classes with safety/obligation events always
visible; the live preference model gates push/email only. v1 adds the in-app dimension
(review I1/I6):

- `NotificationPreferencesEntity` gains `mutedInAppEventClasses`
  (`Set<AttentionPreferenceClass>`, persisted alongside the existing push/email
  category sets). The stable class registry comes from the event contract and contains
  only muteable/noisy families; a mandatory or standard projection has no mutable key.
  This avoids the category bug: today's `coordination` category includes both mandatory
  `blockerOpened` projections and noisy churn.
- Muting hides matching `noisy` receipts from feed **and** badge identically (same
  relation, C4) without marking them seen: unmuting restores history. Unread growth of
  a muted class is bounded by write-time collapse (≈ one row per beacon per class), so
  v1 needs no `expires_at` machinery; if long-horizon growth ever matters, it is a
  retention decision (T-22), not a v1 schema column.
- UI: the existing `notification_settings` feature gains an "In app" section keyed by
  user-facing noisy event classes. Mandatory/safety behavior is explained in copy, not
  rendered as a misleading disabled toggle for a mixed push category.
- Push opt-out continues to affect only the channel; the receipt always exists
  (tested: preference-safety suite, Part E).

## C11. Copy & localization

- Client renders card copy from the receipt's `presentation_key` + allowlisted
  `presentation_payload` + authorized joined names via l10n keys (EN/RU). User-facing
  copy says **Request/Chat** (`scripts/check-user-facing-terminology.sh` stays in every
  UI task's acceptance).
- Server `title`/`body` remain push-oriented channel copy and the fallback for event
  types a stale client doesn't know.
- Because v1 has no search, there is no server-side text-matching surface; the future
  search increment must search a structured projection of authorized receipt
  presentation payload, not `title||body` (T-18).

## C12. Rollout & compatibility (expand → dual-write → flip → contract)

1. **Expand (T-01):** m0115 as written in C1 — additive only. The old dedup partial
   index and the old `ON CONFLICT (dedup_key) WHERE read_at IS NULL` SQL keep working
   because nothing about `read_at` changes. Server rollback to a pre-m0115 binary is
   safe: new columns are nullable/defaulted and ignored.
2. **Publisher cutover (T-01b):** m0116 replaces the row trigger with the
   statement-level account-scoped publisher (C6), then backfills `seen_at = read_at`
   under the new publisher (at most one aggregate hint per affected account, never one
   per historical row).
3. **Dual-write server (T-02…T-06):** one server release writes both read models —
   legacy `markRead`/`markAllRead` also set `seen_at`; new `attentionMarkSeen` also
   sets `read_at`. Unread predicate: `COALESCE(seen_at, read_at) IS NULL`, which stays
   exact in every mixed state (including rows read by an old binary during a rollback
   window). `markAllRead` still means every row the legacy feed can display. Legacy
   feed/count/mark-all are moved onto the authorized relation/ack port without changing
   their GraphQL shape — closing today's guard/count split **before** the flip.
4. **Shadow proof (T-07):** do not compare unlike products. Shadow telemetry reports:
   (a) zero mismatch between old and dual-write read axes over the **same legacy
   predicate**; (b) separately labeled expected deltas by authorization, new event
   class, and in-app mute. Only unexplained mismatch must be zero across the QA soak.
5. **Hidden client slice (T-08…T-14):** a default-off compile-time
   `UPDATES_TAB_ENABLED` QA flag controls the complete vertical slice. While off, no
   fifth destination or attention queries exist and old chrome owns all user-visible
   truth. The T-05-only event producers are also default-off in production builds
   during this phase (`ATTENTION_V1_NEW_PRODUCERS_ENABLED`); QA/release-proof
   environments enable both gates.
6. **Flip release (T-15):** remove the compile-time flag, ship Updates unconditionally,
   remove the server new-producer gate and enable those producers unconditionally, and
   remove bell + old route + `features/notification_center/`. `NewStuffCubit` stays
   (C7). Rollback ordering is explicit: first set the producer env true on the already
   deployed gated server and pass the old-client compatibility smoke; then deploy the
   server binary with the gate removed, then release the unconditional client.
7. **Contract (T-19, after adoption + `MIN_CLIENT_VERSION` bump per
   `.cursor/rules/versioning.mdc`):** retire `notifications*` GraphQL fields, stop
   writing `read_at`, swap both the collapse index and transition unread indexes to
   `seen_at IS NULL` (create-new-then-drop-old, in that order), simplify the unread
   predicate, drop the legacy dispatch path.
- **Mixed-version tests** (Part E): old markRead/new read, new ack/old count, legacy
  direct-enqueue receipt/new query reader, server rollback after m0115, two devices on
  different client versions.
- Old pushes in the wild carry old `action_url`s — unchanged pipeline handles them.
- **Retention: v1 is neutral.** The existing `deleteSettledOlderThan` sweep and email
  digest watermarks continue unchanged; the new columns ride along on existing rows and
  add no orphanable tables. Account deletion keeps its current behavior. A broader
  retention/erasure policy (scrubbing retained copies that mention a deleted account,
  windows per class, noisy-unseen expiry) is a separate privacy/retention decision —
  increment T-22 (Part L #6). v1 must not make current retention behavior worse; it
  does not have to make it better.

## C13. Telemetry & diagnostics

- Server markers mirroring `realtime_event=…`: `attention_event=receipt_write`
  (`kind`, `recipients`, `collapsed`), `attention_event=ack` (`rows`, `bulk`),
  `attention_event=shadow_mismatch` (T-07), `attention_event=summary_query` p95.
  Counts/error codes only, no content.
- Client: dev-flagged debug panel showing server summary vs optimistic ack set; ack
  batch logs; convergence timing added to the multi-client artifacts.
- Dashboards must answer: unread p95 per account, summary-query p95, and
  invalidation-budget compliance (PG notifications and refetches per bulk ack).

## C14. Deferred increments (gated, design constraints recorded)

Each ships only with its own approval and tests; none blocks v1.

- **T-16 Settlement / "Needs you"** (product gate: D-1 extension). Adds the independent
  settlement axis per review I4: `settlement_kind`
  (`resolved|dismissed|superseded|legacy_archived`), `settled_at`, `settled_by_*`, DB
  CHECKs; typed `attention_thread_key` + supersession subjects; domain resolution hooks
  inside the T-03 transaction boundary; a separately labeled "Needs you" count.
  Pre-launch rows get `legacy_archived` or an eligibility cutoff — never a fabricated
  `resolved`.
- **T-17 Field-level highlights + visibility acknowledgement.** Design-system decision
  first (new `TenturaTokens` attention tokens + a reviewed `TenturaChangeHighlight`
  component); platform focus/visibility evidence behind a port feeding a pure
  `SeenAckCase`; motion/a11y constraints carry over as acceptance criteria.
- **T-18 Search & advanced filters.** Bounded/indexed projection over structured
  authorized receipt presentation payload, escaped input, stable opaque cursors,
  EXPLAIN evidence, authorization-before-search tests. The v1 feed ships with only the
  two fixed views (All / Unread).
- **T-20 Occurrence store + durable channel delivery** (the revision-3 D-2/D-3 design:
  `attention_occurrence`, event-time recipient snapshots, `attention_channel_delivery`
  jobs with lease/retry/dead-letter, throttle reservations, projector + sweeper,
  immutable send context). Product trigger: a real commitment to reliable push/email
  delivery, or audit/replay becoming product scope. Revision 3 (git history) and Part K
  are its design record; `source_event_key` is its ready-made identity seed, so
  adopting it later is an expand migration, not a rewrite.
- **T-21 Attention-derived tab dots + per-beacon card markers.** Retires
  `NewStuffCubit`/Drift cursors, adds `surfaces`, `unreadForBeacons`, and the bounded
  marker projection; requires first moving `inboxNeedsMeCount` to an Inbox-owned
  operational stream (it is not attention state) and its own parity plan — the same
  discipline T-15 applies to the bell.
- **T-22 Retention & account-erasure policy for notification data.** Windows per class,
  neutral retained-copy recipes for deleted accounts, noisy-unseen expiry if collapse
  bounds ever prove insufficient. A privacy/compliance decision on its own track; v1
  only promises not to worsen current behavior.
- **Extra kinds** (`relaySucceeded`, watcher-facing progress expansions beyond the
  required status class): individually, with audience-bound tests.

---

# Part D — Event coverage matrix (issue #80 → producers)

Source of truth is the compact `docs/contracts/updates-event-contract.json` (created in
T-00, enforced by architecture tests on both packages); this table is its human-readable
rendering. Identity recipes, collapse recipes, and audience-resolution details live in
code next to each producer's tests (C3). **Every one of the eight required classes has a
real producer task in v1** — T-04/T-05 acceptance is keyed to this matrix.

Suppression classes: **M** = mandatory (never suppressible), **S** = standard,
**N** = noisy (in-app mutable). Seen rule in v1 is uniform: open / explicit ack /
mark-all / room bridge (C5).

| # | Issue class | Producer (use case → event_type) | Recipients (reasons) | Class | Exact destination | Covered by |
|---|---|---|---|---|---|---|
| 1 | Request forwarded to me | `forward_case` → `relayReceived` (today `newRelay`) | forward recipients | S | beacon view root | existing, migrated in T-04 |
| 2 | New help offer on my request | `help_offer_case` → `helpOfferSubmitted` (today `commitmentEvent`) | author (M), stewards (S) | M/S | beacon view `tab=people` + offer target | existing, migrated |
| 3 | Author response to my offer | `help_offer_case` → `offerAccepted` (today `roomAccess`), `offerDeclined` (`commitmentDeclined`), `offerRemoved` (`commitmentRemoved`) — the full response taxonomy, enumerated | affected helper | M | accepted → `tab=room`; declined/removed → target in `tab=people` when still authorized, otherwise sanitized terminal fallback (`recipient_safe`) | existing, migrated |
| 4 | Chat mention / message relevant to me | `BeaconRoomCase.createMessage` → `roomMessagePosted` — **new producer** (T-05): explicit mention, reply to recipient's message, or another declared directed semantic target; stores message/thread identity for exact routing + room bridge. Ordinary admitted-member traffic creates **no Updates receipt** and remains solely in Chat's `room_seen` unread model. | mentioned/replied/directed target (S) | S | beacon view `dest=room&message=<messageId>[&item=<threadItemId>]` | **new** |
| 5 | Chat admission/removal | same events as #3 accepted/removed | affected member | M | admission → `tab=room`; removal → people target when authorized, otherwise sanitized terminal fallback | existing, migrated |
| 6 | Request status changed | all interactive transition use cases (`BeaconCase`, `CoordinationCase`, `EvaluationCase`) plus a new actor-null `AttentionExpirySweepCase` invoked by `TaskWorkerCase` for time-driven review expiry → `requestStatusChanged` — **new producer** (T-05) covering every transition for active participants, not only inbox stance holders | author/helpers/admitted (S); inbox stance holders needs_me/watching (N, collapse per beacon, no push) | S/N | beacon view root (status target) | **new** |
| 7 | Review became available | `EvaluationCase` → `reviewOpened` (today `reviewReady`) | admitted participants | M | `/beacon/review/:id` | existing, migrated |
| 8 | Relationship/contact state changed | `UserTrustEdgeCase.setUserVote` when a positive reverse edge already exists → `mutualConnectionFormed`, plus invite-acceptance use cases → `inviteAccepted` — **new/migrated producers** (T-05). This covers a meaningful user-visible state transition without exposing unilateral unsubscribe/negative actions. `ContactCase` is explicitly excluded: it edits a viewer-private label and notifying the subject would leak private data. | counterpart whose connection just became reciprocal; inviter whose invite was accepted | S | profile view of counterpart | **new** (+ existing invite) |

Retained producers outside the minimum set (already live, same pipeline, migrated in
T-04): `needsMe` (M — addressed ask is an obligation), `blockerOpened` (M for affected
target, S otherwise), `blockerResolved` (S), `promiseMade`/withdrawn (S),
`coordinationChanged` (N — plan/NOW churn is the canonical noisy class), `staleRemind`
(M — obligation reminder).

The apparent conflict between Part B's "do not create per-message Updates events" and
issue class 4 is resolved narrowly: only directed/relevant messages project receipts;
the general Chat stream remains cursor-based. This avoids duplicating every room message
into receipts and removes the largest unbounded fan-out.

Presentation: one card = avatar → localized one-line what-changed → request title
context line → whole-card tap (single CTA; multi-CTA decisions belong to the settlement
increment). Outcome icons are design-system vector icons, never emoji.

---

# Part E — Test strategy

Everything listed is in-scope for v1 unless marked for an increment.

**Transactional write / failure injection (server, pg-tagged):**
- domain write failure → no receipts; any receipt write failure → domain rollback
  (symmetric atomicity);
- destructive kinds (decline/removal/admission loss) resolve their audience **before**
  the destructive statement: the removed/declined recipient still gets the receipt, and
  a member admitted in a concurrent transaction does not;
- duplicate producer invocation inside one action collapses via `dedup_key`; a
  legitimately repeated domain action (close→reopen→close, remove→re-admit→remove)
  produces distinct receipts;
- UoW/GUC proof: domain writes + receipt writes share one DB transaction and actor GUC
  without a domain import of `TenturaDb`;
- channel hand-off runs strictly post-commit; an injected channel failure never affects
  domain rows or receipts.

**Channel-behavior regression (semantics unchanged from today):** push preference gate,
quiet hours/snooze/per-beacon mute, `FcmBatchQueue` coalescing bands, immediate-email
consideration, and digest selection behave identically when fed from the transactional
dispatch — asserted against the existing suites, not re-specified.

**Concurrency:** concurrent `markSeen` and collapse-upsert on one receipt;
mark-all-seen racing a new insert (new receipt stays unread); room-bridge watermark
advance racing a new directed-room receipt.

**Authorization / count equivalence:**
- extend the existing ADR-0008 SQL-function ↔ `BeaconVisibility` parity fixtures;
  assert the receipt relation calls those functions rather than duplicating the
  predicate;
- revoked access/deleted Request/removed actor: normal receipt leaves feed+badge;
  allowlisted removal event remains as sanitized `recipient_safe`; no other event can
  select that policy; introspected DB presentation-key allowlist exactly matches the
  event contract;
- exact count equality over the authorized unread relation; positive total ⇒ non-empty
  **Unread** first page across preference states; summary and page in one
  `attentionFeed` response come from one statement (no cross-moment mismatch).

**Pagination:** equal timestamps, collapse-bump reordering, inserts between page
fetches, cursor stability across acknowledgements, and receipt-id normalization removes
the old-page duplicate when a collapsed row moves into the refreshed head.

**Compatibility matrix (C12):** old markRead → new unread predicate; new ack → old
count; legacy direct-enqueue receipt → new query reader; server rollback after m0115;
two devices on different client versions (multi-client runner variant). With the server
producer gate off, every T-05 command produces zero new receipt side effects; after
T-15 activation, an old client can render/ack the compatible legacy projection and
opens a safe Chat/profile root when it does not understand the new exact-anchor query.

**Account lifecycle (client):** direct account switch A→B (non-empty→non-empty) resets
ack store, feed, summary; stale ack response from the prior account generation is
dropped; scroll/view state isolated per account. Server-side: account deletion behavior
is unchanged by m0115 (columns only, no new tables/FKs) — asserted, not redesigned.

**Load / refetch budget (C6):** bulk ack of 1 / 50 / 500 rows ⇒ exactly one PG
notification per affected account per SQL statement and ≤ 2 refreshes per client;
convergence within realtime budgets; channel bookkeeping columns stay silent.

**Preference safety:** muted noisy event class hidden from feed+badge and restored on
unmute; mandatory class visible under every preference state; API accepts only the
contract's muteable `AttentionPreferenceClass` keys; mixed legacy push categories do
not control in-app visibility; muted-class unread growth stays collapse-bounded (≈ one
row per beacon per class); push opt-out leaves receipts intact.

**Coverage contract:** architecture test (both packages) walks the compact
`updates-event-contract.json`: every issue class → concrete producing command,
recipient category, destination family, muteability, and covering test. A private
`ContactCase` label change is asserted not to produce a receipt; ordinary non-directed
Chat messages are asserted not to produce one. Adding an event type without a contract
row fails the build. Presentation-payload allowlists (keys only, no free-form message
text, byte bounds) are asserted by focused code-level tests next to the policy.

**Migration (extend `realtime_notification_migration_test.dart`, pg):** m0115
idempotence and no-backfill/no-notify behavior; **old collapse-index predicate and old
`ON CONFLICT … WHERE read_at IS NULL` SQL still function after migration**; m0116
publisher cutover leaves no interval with both row and statement triggers, emits per
distinct account on visible changes, stays silent on channel bookkeeping, and backfills
`seen_at = read_at` with at most one aggregate hint per account.

**Client unit/widget:** `AttentionCase` (hint coalescing, ≤1+1 refresh rule, catch-up,
account reset), `AttentionAckStore` monotonicity/reconciliation, `UpdatesFeedCubit`
(thin projection, pagination, scroll restore), `UpdatesNavbarItem` badge (0 hides, 3
shows "3", cap "99+", tabular figures, semantics label), card variants + empty states,
responsive sweep (compact 375, landscape ~640×360, expanded rail +
`TenturaContentColumn`; `textScaler` 1.3/2.0), destination map (every contract row →
resolvable route).
Architecture test: `lib/domain/attention/**` has no data/UI imports and concrete
`AttentionRepository` is bound only as `AttentionRepositoryPort`.

**Router:** fifth branch containment, `HomeTabSpec` derivations (no hard-coded index
comparisons remain — enforced by a grep-level test), `/notifications` redirect,
push-origin → Updates-branch navigation, reselect reset.

**Release proof (gates the flip, T-14):** real local multi-client browser journey with
both QA gates enabled — helper offers → author badge 1 → open from Updates → exact
destination → badge 0 everywhere ≤ 3 s; forced missed-event recovery shows no duplicate
cards and correct badge; background tab acks nothing; empty feed shows zero badge for a
fresh account and for an account whose only normal receipts lost access; room-removal
journey shows one sanitized terminal receipt without leaking Request content;
Inbox/My Work dots (still `NewStuffCubit`-driven) keep behaving exactly as before the
flip.

Terminology & lints: `scripts/check-user-facing-terminology.sh`; design-system lints via
`cd packages/tentura_lints && dart test`.

---

# Part F — Implementation tasks

Phases gate each other; each task ends green (`flutter analyze`, targeted tests,
lints).

### Phase 0 — Contract

**T-00. Product contract, ADR, compact event coverage contract.**
Record the D-1…D-8 resolutions (C0) as the product decision record; write
`docs/adr/0010-attention-receipt-extension.md` (0001–0009 already exist): the
extend-the-outbox decision, the deferred occurrence/receipt/delivery target topology
and why v1 defers it (Part L), the transactional-dispatch boundary, the ADR-0008
`recipient_safe` amendment, and why private contact labels/ordinary Chat traffic are
excluded. Create the compact `docs/contracts/updates-event-contract.json` covering
Part D (producer, recipient category, destination, muteability, test per event type);
add the architecture tests on both packages that consume it (initially asserting the
*current* producer gaps as `pending`, flipped to enforced in T-05). Retention/erasure
policy is explicitly **not** gated here — it is the separate T-22 decision; T-00 only
records that v1 keeps current retention behavior.
Acceptance: contract JSON reviewed against issue #80 line-by-line; deviations: none.

### Phase 1 — Server foundation (invisible)

**T-01. m0115 expand-only migration + entities.**
Schema per C1 (receipt columns + constraints + transition indexes + preference column).
Literally expand-only: no backfill, no trigger changes, no index drops.
Tests: migration suite per Part E (incl. old-index/old-SQL survival); both realtime
contract tests stay unchanged here.

**T-01b. m0116 realtime publisher cutover + backfill.**
In one migration transaction, create the account-scoped statement-level
transition-table triggers from C6 and replace the old row trigger (no committed state
with both publishers), then backfill `seen_at = read_at` under the new publisher.
Justified on its own by mark-all-seen (C6); independent of any occurrence design.
Tests: actual PG notification count/content for INSERT/UPDATE/DELETE and 1/50/500-row
updates; channel-only changes silent; server rollback after m0116 still works.

**T-02. Ports split + policy + authorized relation.**
Narrow ports instead of growing `NotificationOutboxRepositoryPort`:
`AttentionDispatchPort` (in-transaction receipt materialization, C2),
`AttentionQueryPort` (`attentionFeed(view, cursor)` → `{summary, page}` in one
statement, over `visible_attention_receipts`), `AttentionAckPort` (`markSeen`,
`markAllSeen`, room bridge; dual-writes `read_at`). `MutatingUnitOfWorkPort` belongs to
the domain; its data adapter owns `TenturaDb`. Implement `AttentionPolicy.project`
(C3) + refactor the resolver to return full reason sets. The authorized relation calls
ADR-0008 SQL functions; it does not re-express `BeaconAccessGuard` rules.
Tests: policy table-driven from contract JSON; pg tests for relation/access-policy
allowlist, one-statement summary+page, pagination, ack idempotency; extend the existing
visibility parity suite.
Out of scope: producers, GraphQL.

**T-03. Use-case transaction boundary + transactional dispatch.**
Move transaction ownership up through `MutatingUnitOfWorkPort`, converting affected
repository commands to transaction-neutral/explicit in-transaction variants. Split
`BeaconNotificationService.dispatch` into the in-transaction receipt path
(context/recipients/policy/copy/upsert) and the post-commit channel hand-off with
**unchanged channel semantics**. Keep all current producer calls on the legacy path in
this deployable step; exercise the new path with synthetic/pilot fixtures only.
Tests: failure-injection suite (Part E), one-transaction/GUC pg proof, channel-behavior
regression suite; legacy behavior stays green.

**T-04. Migrate existing kinds through transactional dispatch.**
All Part D "existing, migrated" rows: per kind, one atomic cutover that records the
receipt inside the use-case transaction and deletes the corresponding legacy
`unawaited` call — no deployable commit leaves a producer with neither path or both
paths. Destructive kinds declare and test their pre-mutation audience resolution.
Cover the complete C2 inventory (`AuthCase`, `CredentialAuthCase`, `InvitationCase`,
`HelpOfferCase`, `ForwardCase`, `CoordinationCase`, every coordination-item case,
`EvaluationCase`, `BeaconRoomCase`); `ContactCase` remains explicitly non-producing.
Tests: per-kind projection assertions, table-driven from the contract.

**T-05. New producers: `roomMessagePosted`, `requestStatusChanged`,
`mutualConnectionFormed`/`inviteAccepted`.**
Per Part D #4/#6/#8: directed mention/reply/semantic targeting only, exhaustive
status-transition inventory (incl. actor-null `AttentionExpirySweepCase` wired into
`TaskWorkerCase`), reciprocal-connection formation + invite acceptance. Unilateral
removal/negative/private-label changes are explicitly non-producing. Flip coverage
contract from `pending` to enforced. Deploy behind `ATTENTION_V1_NEW_PRODUCERS_ENABLED`
(default false outside QA); T-15 removes the gate.
Tests: identity recipes (repeat-after-reversal), destructive-transition audience,
watcher audience bound/collapse/no-push, mention/reply parse, ordinary-Chat and
`ContactCase` non-producers.

**T-06. GraphQL v2 + preferences API.**
Thin controllers delegating to the T-02 ports: `attentionFeed(view, cursor)` (returns
summary + page), `attentionMarkSeen(ids)`, `attentionMarkAllSeen`, preference
read/update with `mutedInAppEventClasses` (unknown/non-muteable keys rejected), and an
authorized bounded `roomMessageTarget(beaconId, messageId)` query for exact-link
hydration. **Register every new operation in `_tenturaDirectOperationNames`**
(`build_client.dart`) — runtime requirement. Input bounds: id-list ≤ 200, cursor
opaque/validated. Legacy `notifications*` fields unchanged in shape, now dual-writing
`seen_at` and served from the authorized relation (C12 step 3). The API returns receipt
presentation key/payload and typed destination fields.
Tests: controller auth scoping, payload allowlists, input bounds, contract tests;
legacy-field regression suite.

**T-07. Shadow parity + budget proof.**
Shadow-compare like-for-like legacy read-axis predicates; separately classify expected
authorization/new-class/mute deltas; require zero **unexplained** mismatch. C4
invariant/safe-terminal suite; C6 invalidation-budget tests at 1/50/500.
Acceptance: zero unexplained mismatches across QA soak; budget numbers recorded in
`realtime-sync-operations.md` addendum.

### Phase 2 — Client slice (dark behind QA compile-time flag)

**T-08. Attention application slice.**
`lib/domain/attention/` ports/entities/cases + data implementation per C7 (GQL docs +
codegen, `AttentionCase`, `AttentionAckStore` with per-account partition/reset,
normalized page cache, head-refresh coordinator, `unreadSummary`/`feedPages`
selectors). Bind concrete repositories to domain-owned ports; add the
no-domain-to-data architecture assertion. Add `Env.updatesTabEnabled` from
`bool.fromEnvironment('UPDATES_TAB_ENABLED')`, default false; gate construction/
subscription as well as rendering so a disabled build performs no attention queries.
Update the realtime contract impacts (+`updates_feed`, `updates_badge`) with both
architecture tests.
Tests: Part E client-unit list (coalescing, ≤1+1, catch-up, account lifecycle).

**T-09. `HomeTabSpec` refactor (no visible change).**
Introduce the spec; derive all shell/path/index/reselect/deep-link sites — including
`NewStuffCubit`'s active-tab comparisons — from it; router tests prove four-tab
behavior identical; grep-test bans raw index comparisons. (`NewStuffCubit` itself is
retained; no operational-count migration is needed in v1 — that moved to T-21.)

**T-10. Updates screen (flagged).**
`features/updates/` presenter: feed list (flat cards, All/Unread views), empty states
("Nothing new" default; per-view neutral no-results), pagination, pull-to-refresh with
stale-content-visible, scroll restore, l10n EN/RU, established initial-load treatment
(no new skeleton convention). Design-system lints + responsive/a11y sweep.

**T-11. Fifth branch + exact-destination routing (flagged).**
Branch registration per C9, `openFromUpdate`,
`openFromNotificationLink(preferUpdatesBranch: true)` for push taps, destination map,
new `message` query param kept distinct from coordination `item`, target hydration into
`RoomCubit.prepareThreadScroll`, `/notifications` redirect prepared but shipped in
T-15.
Tests: router suite per Part E, including a directed message older than the initial
page and an unauthorized message-id negative case.

**T-12. Acknowledgement flows.**
Open-ack on card tap, per-item Mark seen, Mark all seen, optimistic store
reconciliation, room-bridge verification client-side.
Tests: ack semantics + multi-tab convergence (simulated fan-out).

**T-13. In-app preferences UI.**
`notification_settings` gains an In-app section (contract-owned noisy event classes
toggleable; mandatory/safety behavior explained separately).
Tests: widget + API integration; preference-safety suite.

### Phase 3 — Proof

**T-14. Full-stack release proof.**
Integration + multi-client suites per Part E "release proof"; mixed-version matrix;
budget/convergence artifacts. The QA artifact records both the client flag and server
new-producer gate as enabled. Five consecutive multi-client passes (existing release
gate discipline).

### Phase 4 — The flip (one release)

**T-15. Enable + replace.**
Remove `UPDATES_TAB_ENABLED`/its client `Env` field, remove the server
`ATTENTION_V1_NEW_PRODUCERS_ENABLED` gate while making T-05 producers unconditional,
and ship the fifth tab with unread badge. Delete bell button +
`NotificationCenterRoute` + `features/notification_center/`; `/notifications` redirect
live; remove `NewStuffState.notificationUnreadCount` and its `unreadActionableCount`
plumbing (dead with the bell). **`NewStuffCubit`, its Drift cursors, and
`InboxRowHighlightKind` are explicitly retained** (T-21 owns their retirement). Update
realtime contract impacts (−`notification_center`), docs (status-quo §5,
`features/new-stuff-indicators.md` gains a scope note, not a superseded pointer).
Gate: T-14 green, T-07 unexplained shadow mismatch zero, issue #80 acceptance criteria
pass in the release-proof journey.
Deployment order/rollback: enable the producer env on the gated server, run the
old-client smoke, deploy the unconditional server, then roll out the client; a server
rollback with the retained env still records every T-05 receipt.

### Phase 5 — Gated increments (each separately approved)

**T-16. Settlement / "Needs you"** (C14).
**T-17. Field highlights + visibility acknowledgement** (C14).
**T-18. Search & filters** (C14).
**T-19. Legacy contract phase** (C12 step 7; requires `MIN_CLIENT_VERSION` bump:
retire `notifications*` fields, `read_at` writes, collapse + unread index predicate
swaps create-before-drop, legacy dispatch removal).
**T-20. Occurrence store + durable channel delivery** (C14; the deferred revision-3
topology, gated on a real delivery/audit product requirement).
**T-21. Attention-derived tab dots + card markers** (C14; retires `NewStuffCubit` with
its own parity plan).
**T-22. Retention & account-erasure policy** (C14; separate privacy/retention
decision).

Dependency graph: T-00 → T-01 → T-01b → T-02 → T-03 → {T-04, T-05} → T-06 → T-07;
T-06 → T-08 → {T-09…T-13} → T-14 → T-15;
T-15 → {T-16, T-17, T-18, T-19, T-20, T-21, T-22} (each independently gated; T-19
depends on adoption/`MIN_CLIENT_VERSION`, not on the optional product increments).
Phases 0–3 ship continuously as behavior-compatible foundation or dark code; Phase 4 is
the one-way activation/removal cutover.

---

# Part G — Risks and open questions

Risks:

- **R-1 Mutation-transaction growth**: recipient resolution + per-recipient receipt
  writes now run inside the domain transaction. Audiences are the existing per-kind
  resolver sets; the one broad audience (`requestStatusChanged` watchers) is bounded,
  noisy-class, per-beacon collapsed, and asserted by its producer test. No external I/O
  in the transaction. If a future kind ever needs an unbounded audience, that is the
  T-20 trigger, not a reason to widen this transaction.
- **R-2 Transaction-boundary refactor regressions**: mitigated by a domain-owned UoW
  port, transaction-neutral/explicit in-transaction repository methods, a real pg
  transaction/GUC proof, and per-use-case tests. No correctness claim rests on assumed
  nested drift behavior.
- **R-3 Fifth-tab index regressions**: eliminated structurally by `HomeTabSpec` (T-09)
  plus the grep-test ban on raw index comparisons.
- **R-4 Fan-out volume** (`requestStatusChanged` watchers): bounded audience, noisy
  class, per-beacon collapse, no push. `roomMessagePosted` is directed only; watch
  `pg_notification_queue_usage()` per runbook.
- **R-5 Badge inflation → numbness**: v1 badge is unread (self-limiting via mark-all);
  monitor unread p95; the mandatory/noisy split gives users a lever that doesn't hide
  obligations.
- **R-6 QA-gate drift**: pre-flip builds may enable only the client or only the new
  server producers. T-14 records/asserts both; T-15 removes both gates.
- **R-7 Room-bridge subtleties** (main vs item-thread scope, collapse latest message,
  watermark timestamp): covered by dedicated concurrency tests; failure mode is a
  receipt staying unread (annoying, never clearing a newer message incorrectly).
- **R-8 Channel attempts remain lossy** (accepted, explicit): a crash after commit can
  still lose push/email attempts, exactly as today. This is the deliberate Part L #1
  scope cut — the in-app receipt is guaranteed, channels are not. The
  channel-regression suite guards against silently making today's behavior *worse*;
  making it durable is T-20.
- **R-9 Two attention-truth families persist until T-21** (accepted, explicit): the
  Updates badge/feed are event-derived while Inbox/My Work dots stay local-cursor
  heuristics. This is the reviewer-endorsed trade: the dots are not counts, issue #80's
  counter criteria all land on the event-derived surface, and unifying the dots without
  a parity plan of its own would re-create the rushed-cutover risk (I14) elsewhere.
- **R-10 Safe terminal policy expansion**: `recipient_safe` is a privacy-sensitive
  exception. Contract allowlist + sanitized payload schema + pg negative tests + ADR
  amendment are mandatory; arbitrary producers cannot select it.

Open questions (all deferred-increment scope; none blocks v1):

- **Q-1** Settlement product shape ("Needs you" count, dismissal of obligations,
  multi-CTA cards) — decided with T-16.
- **Q-2** Auto-seen from list visibility / dwell rules — decided with T-17.
- **Q-3** Presence-aware push suppression — later enhancement; needs product + privacy
  sign-off.
- **Q-4** Retention windows and account-erasure recipes for notification data — decided
  with T-22; v1 keeps current behavior.

# Part H — Explicitly flagged alternatives

- **ALT-1 Badge computed server-side** (kept): client-side counting from a feed page
  breaks under pagination and multi-device; `attentionFeed` returns the server summary
  and page from one database moment.
- **ALT-2 Occurrence table vs receipt-only extension:** **reversed in revision 4** —
  v1 extends `notification_outbox` in place and records no separate occurrence. The
  revision-3 arguments for the table (commit-atomic command + audience snapshot that
  exists before receipts are projected) applied to an asynchronous projector; with
  synchronous transactional receipt writes, the receipts themselves are the
  commit-atomic event-time record. The table returns with T-20 if delivery/audit scope
  arrives; `source_event_key` is its migration seed.
- **ALT-3 Direct receipt writes in the domain transaction:** **now adopted** (the
  reviewer's alternative in I3, previously rejected). Revision 3's objection — direct
  writes couple producers to volatile access/preference reads, collapse mutation,
  presentation, and channel-job policy — priced in the durable channel-job machinery.
  Without it, the coupling is: bounded audience reads, one policy function, one copy
  builder, and an upsert — all already invoked per-dispatch today, just off-transaction
  and unguaranteed. Access/preference volatility is a read-time concern regardless
  (C4's relation rechecks authorization on every query), so write-time coupling to it
  does not change what users see.
- **ALT-4 Tab order** (unchanged): `My Work → Inbox → Updates → Network → Profile`;
  reordering is UX-significant and needs product approval.
- **ALT-5 `visibility_detector` package vs custom render objects:** deferred with
  T-17.
- **ALT-6 Best-effort channels vs durable delivery table:** **reversed in revision 4**
  — v1 keeps best-effort channels (the status quo). Revision 3 chose durable jobs to
  avoid "baking a misleading three-channel model into the new occurrence architecture";
  with no new occurrence architecture there is nothing to mislead. Issue #80 promises
  reliable in-app events only; the durable queue (with its leases, throttles, dead
  letters, send-condition dependencies, and immutable send snapshots) is preserved as
  the T-20 design.
- **ALT-7 Ambient Chat receipts vs directed relevance only:** decided for directed
  only (unchanged). General message unread already has the correct cursor model.

---

*Prepared 2026-07-16 (revision 1); revised 2026-07-16 (revision 2) after the Part I
architecture review; re-reviewed and amended as revision 3 the same day (Part K);
reduced to the issue-proportionate v1 scope as revision 4 the same day after the
Part L proportionality review. All revision-4 code observations were re-verified
against the live tree: in-memory non-retrying `FcmBatchQueue` (`_pending` map, 1 s
flush), per-recipient `_writeOutbox` loop with per-row catch, guard-filtered feed vs
unguarded `unreadActionableCount`, `FOR EACH ROW` `notification_outbox_entity_notify`
trigger in m0114, ADRs 0001–0009 present, next migration m0115.*

---

# Part I — Critical architecture review (2026-07-16)

> **Status note (revision 2):** this review of revision 1 is retained verbatim as the
> historical record. Its findings are addressed by the rewritten Parts C–H above;
> Part J maps each finding (and each deliberate deviation) to its resolution. Section
> numbers it cites (C0–C17, T-01–T-20) refer to revision 1's structure.

Review outcome: **not implementation-ready; block T-01 until I16 is resolved and the
affected earlier sections/tasks are revised.** This is intentionally a review section,
not a silent rewrite of Parts A–H. The plan contains valuable reconnaissance, but its
central product semantics, transaction guarantee, event identity, compatibility story,
and rollout slices do not currently agree with one another or with the live code.

The review rechecked the current repository, the actual body of
[GitHub issue #80](https://github.com/Intersubjective/tentura/issues/80), and the relevant
project rules. `gh` remains unauthenticated, but the connected GitHub integration made
the issue body available. All code observations below were re-verified against the live
tree; they are not inferred from the earlier research section.

## I1. Blocking product-contract mismatch: unread is not unresolved work

Issue #80 currently requires a persistent activity surface, exact destinations,
**unread counters derived from unread events**, consistent badge changes when an event
is opened/acknowledged, no non-zero badge over an empty surface, reconnect/multi-tab
deduplication, and user control of noisy classes while safety/obligation events remain
visible.

The plan implements a materially different product:

- The Updates number counts unresolved actionable `group_key`s, including rows already
  `seen`, instead of unread events (C7).
- Merely opening/seeing an actionable event deliberately does not change that number
  (C6/C9), despite the issue making open/ack the badge-clearing action.
- It adds a GitHub-style work queue with `resolved`, `dismissed`, and `superseded`
  semantics that issue #80 does not request.
- It allows every actionable event to be dismissed (C2/P-3), while the issue says
  safety/obligation events must remain visible.
- It contains no in-app preference policy for noisy versus mandatory event classes;
  the existing preference gate controls push delivery only.

This may be a worthwhile product extension, but it is not a technical interpretation
of the current issue. The plan's unnamed “restated product brief” must be attached or
incorporated into the durable product source, and every deliberate deviation from issue
#80 must be approved explicitly.

**Proposal:** make two concepts visibly separate if both are desired:

1. **Unread Updates** — `seen_at IS NULL`; this is the navigation badge required by
   issue #80 and clears when the exact event is opened or explicitly acknowledged.
2. **Needs you** — unsettled obligations; this is a filtered section/count with its own
   label and semantics. It must not masquerade as an unread badge.

Recommended v1: ship the issue's unread contract first. Add unresolved-work tracking
only after product validation, or ship it simultaneously under a clearly named “Needs
you” count. Do not encode the unresolved-work interpretation into the schema before
this decision.

## I2. `notification_outbox` is not one canonical domain event

C0/C3 says there is one canonical event per logical domain change and identifies a
`notification_outbox` row as that event. The live model contradicts this in three ways:

- `_writeOutbox()` creates one row **per recipient**, so one occurrence already has N
  row identities.
- The row stores channel/presentation concerns (`title`, `body`, `action_url`,
  `emailed_at`, `digested_at`) and per-recipient read state. It is a recipient
  projection/delivery outbox, not a domain occurrence.
- `beacon_activity_events` already stores a partially overlapping semantic activity
  log. Calling a third representation “canonical” without defining its relationship to
  this log creates competing event vocabularies.

The distinction matters for idempotency, audit, replay, recipient-policy evolution,
and future channels. The durable conceptual shape should be:

```
domain mutation
  -> AttentionOccurrence       one semantic occurrence / causation id
       -> AttentionReceipt     zero or one per recipient; read/work state lives here
            -> ChannelDelivery zero or more push/email delivery attempts
```

This does not force three physical tables on day one. A compatible first step may keep
recipient rows in `notification_outbox`, but must add an `occurrence_id`/causation id
and describe the row accurately as a per-recipient attention projection. Channel
delivery fields can be split later. What is not acceptable is claiming one canonical
event while relying on unrelated recipient UUIDs.

**Proposal:** add a short ADR before schema work comparing:

- a semantic occurrence plus recipient-receipt table, with the existing outbox retained
  as a channel projection; and
- an in-place transitional model that adds `occurrence_id` and explicitly treats each
  row as a receipt, not the domain event.

The decision is hard to reverse, surprising without context, and a real trade-off, so
the current ALT-2 paragraph is not sufficient documentation.

## I3. The promised transaction boundary does not exist

C0.4, C2, and T-04 promise that event creation/resolution occurs in the same transaction
as the domain action. The current path is explicitly the opposite:

- `MarkAskCase.call()` and `ResolveBlockerCase.call()` call the notification port with
  `unawaited` after their repository mutation.
- `HelpOfferCase.offerHelp()` also uses `unawaited(...catchError(...))`.
- `BeaconNotificationService._writeOutbox()` catches every outbox error and describes
  Notification Center persistence as best-effort.
- repositories call `TenturaDb.withMutatingUser()` around individual operations, so the
  use case does not own one transaction spanning multiple repositories plus attention
  persistence.
- the same dispatch method also performs recipient/context reads and push/email work,
  which must not be pulled into a long database transaction.

Adding `resolveByKey()` to `NotificationOutboxRepositoryPort` and calling it from more
use cases will not make the write atomic. It will only spread notification-persistence
coupling across the domain while retaining partial-commit failure modes.

**Proposal:** choose one consistency model explicitly:

- **Recommended:** the domain use case owns a Unit of Work that atomically writes the
  domain change plus a semantic attention/outbox command. After commit, a dispatcher
  resolves recipients, materializes receipts idempotently, and sends channels. If the
  exact recipient set must reflect occurrence-time authorization, snapshot recipient
  ids/reasons in the atomic command.
- **Alternative:** atomically write domain rows and all recipient receipts in the same
  transaction through a narrow `UserAttentionPort`; dispatch FCM/email strictly after
  commit. This requires a prerequisite refactor because current repository-scoped
  transactions cannot supply that boundary.

Whichever model is chosen, the port belongs to the application/domain client and uses
semantic commands (`HelpOfferSubmitted`, `AskAddressed`, `OfferResponded`), not
`NotificationOutboxRepositoryPort` methods or presentation keys. Add failure-injection
tests proving that a successful domain mutation cannot permanently lose its attention
occurrence, and that a failed channel send cannot roll back the domain action.

## I4. Read state and work state are orthogonal, but `status` collapses them

The plan's own research cites read/unread and Done as distinct axes, then C1 encodes
`unseen | seen | resolved | dismissed | superseded` as one mutually exclusive status.
That loses information immediately:

- a row resolved before being seen can no longer say whether it was ever seen;
- a resolved row cannot later receive a monotonic seen acknowledgement;
- analytics cannot distinguish “resolved unseen” from “resolved after reading”;
- history filters label dismissed and superseded work as “Completed” even though those
  outcomes mean different things; and
- concurrency rules become an artificial state machine rather than independent,
  monotonic facts.

**Proposal:** model independent facts:

```text
seen_at                 nullable; monotonic read/ack axis
settlement_kind         nullable enum: resolved | dismissed | superseded | legacy_archived
settled_at              nullable; required iff settlement_kind is non-null
settled_by_user_id      nullable; audit for user/domain settlements
settled_by_occurrence_id nullable; causation for automatic resolution/supersession
```

“Live obligation” then means `requires_action AND settlement_kind IS NULL`; unread means
`seen_at IS NULL`. Database checks should enforce timestamp/reason consistency. Repository
predicates must be conditional and idempotent under races, but the database—not only Dart
code—must reject invalid text values and impossible combinations.

Backfilling an old read actionable row as `resolved` fabricates a domain outcome. If old
history must not inflate a new work queue, use `legacy_archived`, an eligibility cutoff,
or leave it seen and exclude pre-launch rows. Do not call a migration convenience
“resolved.”

## I5. Policy is recipient-specific; `actionableOf(kind)` and `surface(kind)` cannot work

The live `categoryOf(NotificationKind)` is global per kind. The recipient resolver
calculates a `NotificationRecipientReason`, but `_writeOutbox()` does not persist that
reason and the resolver keeps only one reason when a user qualifies through several
roles. Part D nevertheless makes the same kind actionable for one recipient and
informational for another (for example `blockerOpened` and `promiseMade`). It also maps
surfaces according to a recipient's relationship to the beacon.

Therefore these proposed “pure” functions are under-specified:

- `actionableOf(kind)`
- `groupKeyOf(intent, recipient)` when the persisted recipient reason is absent
- `surface(kind)`
- category remapping that differs for affected participants versus authors/stewards

**Proposal:** define one recipient-projection policy over explicit inputs:

```text
AttentionPolicy.project(
  occurrenceType,
  recipientId,
  recipientReasons,
  role/relationship snapshot,
) -> {
  requiresAction,
  mandatoryVisibility,
  category,
  surfaces,
  expectedAction,
  attentionThreadKey,
  fieldTarget,
}
```

Persist the effective recipient reason(s) or policy result needed for audit. Do not
re-derive historical rows from today's relationship state. Decide this before T-01;
deferring `surfaces` to T-02 means the schema is being created before its central
semantics are known.

Also add a machine-readable Updates event contract consumed by server and client tests.
It should cover occurrence type, allowed target shape, mandatory/noisy policy,
destination family, and client field-target support. A Dart helper plus a duplicated
client enum and a prose table is not a single source of truth.

## I6. Required issue coverage is incomplete

Part D looks broad, but it does not satisfy the issue's minimum event inventory:

- **Relationship/contact state changed** has no Updates event in Part D. `inviteAccepted`
  is only one relationship-related transition and is not a substitute for the broader
  required class.
- **Room mention or message relevant to me** is not wired. The enum
  `roomActivityLowPriority` exists, but there is no live producer in server use cases and
  no implementation task adds one. A generic Room destination also does not guarantee
  an exact message/thread target.
- **Request status changed** is split between `requestClosed` and a phase-gated
  `requestProgressed` audience limited to Inbox stance holders. The plan does not prove
  coverage for active My desk participants across open/wrapping-up/reopened/cancelled
  transitions.
- **Author response to my offer** is modeled mainly as accepted/declined/removal, but
  the actual coordination response taxonomy and “next action required” mapping have not
  been enumerated.
- **Noisy-class controls with mandatory safety/obligation visibility** are absent from
  the data model, API, UI tasks, and acceptance tests. Existing notification preferences
  only gate push/email channels; they do not control the in-app feed.

**Proposal:** replace Part D's informal completeness claim with a coverage matrix whose
rows come directly from issue #80. Each row must name: producer command, occurrence
identity, recipients/reasons, mandatory versus suppressible policy, in-app versus push
preference behavior, exact destination/target, read rule, optional settlement rule,
supersession rule, and a producer test. T-03/T-05 cannot pass until every required row
has a real producer.

## I7. Badge and feed must share authorization and filtering

The issue's “empty Inbox/activity states never show a non-zero badge” criterion is a
known live failure mode. The current code demonstrates why: `NotificationCenterCase.feed()`
post-filters rows through `BeaconAccessGuard`, while `unreadActionableCount()` directly
counts outbox rows without that guard. The plan changes the count formula but does not
make feed, badge, search, and `updatesForBeacons` use one authorized relation.

Post-filtering a limited page is also not pagination-correct: a page can become empty
after guard filtering even though accessible rows exist later, and the cursor advances
over rows the user never received.

**Proposal:** create one server query boundary that defines the authorized attention
receipt set, then derive all of these from it:

- feed/groups;
- unread and needs-you counts;
- Inbox/My desk surface booleans;
- `updatesForBeacons`;
- search/filter results.

Authorization should be applied in SQL or by a correctly over-fetching/cursor-preserving
query service, not after pagination. Access loss/deletion must either redact an allowed
tombstone receipt or settle/exclude it from both feed and badge in the same policy. Add
an invariant test: for every account/filter, a positive badge implies at least one
visible matching group, including deleted, revoked-access, and tombstone scenarios.

## I8. Grouping, idempotency, deduplication, and supersession are conflated

C1/C8 introduces several delimiter-built string keys, but their contracts overlap:

- `dedup_key` is used as write-time UX collapse and is also claimed to make producer
  retries idempotent;
- `group_key` is both presentation grouping and badge identity;
- `resolution_key` locates work to settle;
- `supersede_key` selects prior rows to retire.

A retry after the first row was seen does not conflict with a unique-while-unseen
`dedup_key`, so it can create a duplicate occurrence. Conversely, grouping all rows by
`account|beacon|category` can collapse unrelated obligations into one badge unit. These
are not edge cases; they determine the product's count.

**Proposal:** give each identity one job:

- `idempotency_key`: immutable domain command/occurrence identity; unique regardless of
  read state;
- `occurrence_id`: correlates all recipient receipts for one semantic occurrence;
- `attention_thread_key`: optional stable obligation/conversation identity used by a
  deliberately defined badge/group rule;
- `supersession_subject`: typed subject whose newer occurrence can obsolete an older
  one.

Prefer typed subject columns/value objects over ad-hoc strings such as
`helpOffer|beacon|uid`; at minimum version and centrally encode/decode the key format.
Specify what happens when an unseen collapsed row changes actor, target, field target,
or destination—today's upsert only refreshes a subset of columns.

Feed grouping must be pagination-stable. Group server-side and return a group cursor, or
use an opaque composite `(created_at, id)` event cursor plus an explicit continuation
contract for a group split across pages. “Group consecutive rows on the client” is not
stable across page boundaries or equal timestamps.

## I9. Cross-feature client ownership is misplaced

The proposed `features/updates/` slice owns much more than the Updates screen:

- shell navigation counts;
- Inbox and My desk dots/card markers;
- beacon-detail field highlights and lens markers;
- seen batching and optimistic reconciliation;
- feed/search/history presentation.

That makes a presentation feature the dependency of several peer features. It also
encourages three independent consumers (`UpdatesFeedCubit`, `UpdatesBadgeCubit`, and
`RequestAttentionCubit`) to refetch overlapping projections after every notification
hint.

**Proposal:** split the capability boundary:

- a UI-independent `user_attention`/`attention` application slice owns receipt entities,
  query/command ports, realtime/catch-up reconciliation, and account-scoped optimistic
  acknowledgements;
- `features/updates/ui` is one presenter of that capability;
- home, Inbox, My desk, and beacon view depend on narrow attention use-case selectors,
  not on Updates UI or its cubits.

Use one guarded refresh coordinator/server snapshot per account where projections
overlap; feature Cubits remain thin presenters and do not append derived state from WS
hints. A list gets one bounded attention scope for its visible beacon ids—never one
network-owning Cubit per card.

The new acknowledgement store must clear or partition state on **every account id
change**, not only logout. `RoomReadWatermarkStore` is a useful monotonicity precedent,
but its current auth listener only resets for an empty id and should not be copied
blindly into a multi-account attention store.

## I10. The realtime design can create a refetch feedback storm

`notification_outbox_entity_notify` currently fires after every INSERT, UPDATE, or
DELETE, including channel bookkeeping such as `emailed_at`. The plan adds status updates
for batches of rows and has three client projections independently refetch from the same
wire kind. A seen batch can therefore produce N row invalidations, which trigger feed,
badge, and attention queries, whose own optimistic reconciliation then waits on the same
fan-out.

The existing 100 ms client batching helps burst shape, but it does not by itself prove a
bounded query count because each row has a different aggregate id.

**Proposal:** specify and test the invalidation budget:

- restrict notification UPDATE triggers to UI-relevant column changes; email/digest
  bookkeeping must not refresh the UI;
- consider a statement-level/account-level publisher for bulk acknowledgement and
  settlement, or make the shared attention case coalesce all notification ids into one
  account projection refresh;
- guarantee at most one in-flight refresh plus one queued rerun per projection;
- measure queries and convergence for 1, 50, and 500 acknowledged rows;
- retain actor echo and catch-up snapshot refetch as correctness mechanisms.

T-14's phrase “without refetch storm” needs a numeric acceptance threshold and a test,
not only an orchestration assertion.

## I11. The expand/migrate/contract rollout is not backward-compatible

C13's rollback-safety claim is false for mixed old/new binaries and clients:

- the example SQL drops the old dedup index before creating the replacement, while the
  note claims the reverse;
- old server `markRead()` only writes `read_at`, leaving new `status` at `unseen`, so a
  new unique-while-unseen index can continue collapsing into a row an old client read;
- old writers receive `group_key = ''` from the proposed default, causing unrelated rows
  to share a badge group until repaired;
- new settle/dismiss operations do not clearly update `read_at`, so an old client on
  another device can retain a stale notification count;
- reinterpreting old `notificationsMarkAllRead` so that it intentionally leaves some
  rows active changes the behavior promised by the old UI while the plan calls the old
  contract unchanged; and
- removing the old partial index breaks old `ON CONFLICT ... WHERE read_at IS NULL`
  SQL after a rollback.

**Proposal:** use an explicit zero-downtime sequence:

1. Expand: add nullable/new columns, CHECK constraints, and parallel indexes. Keep the
   old index and old API semantics. Do not use empty-string defaults as compatibility.
2. Deploy a dual-compatible server that writes both read models (or uses a database
   trigger/generated compatibility rule) and can execute both old and new conflict
   paths.
3. Backfill in bounded batches; shadow-compute old/new feed and count invariants and
   report mismatches.
4. Ship the new client behind a release/feature gate; continue compatibility writes for
   old clients and other devices.
5. After adoption and a `MIN_CLIENT_VERSION` decision, contract: retire the old API,
   old index, and eventually `read_at` semantics.

Add mixed-version tests: old mark-read/new read, new settle/old count, old enqueue/new
grouping, server rollback after migration, and two devices on different client versions.

## I12. API/use-case scope is too broad and search is premature

T-02 grows `NotificationOutboxRepositoryPort` into enqueue, lifecycle commands, feed,
badge, attention lookup, email, and retention. T-06 then exposes a broad GraphQL surface,
while the client `UpdatesCase` owns feed, badge, changes, catch-up, acknowledgements, and
dismissal. These abstractions have too many reasons to change.

**Proposal:** split command/query responsibilities into narrow client-owned ports/use
cases, for example:

- record/project attention occurrence;
- acknowledge receipts;
- settle obligations;
- query feed groups;
- query attention summary/live targets;
- dispatch/retain channel deliveries.

GraphQL controllers remain thin and delegate to those use cases. New client operations
must be registered in `_tenturaDirectOperationNames`; T-06/T-07 currently omit this
runtime requirement.

Search adds joins, free-text `ILIKE`, localization mismatch, privacy filtering, and
index/performance work before the core reliability contract is proven. The plan displays
client-localized copy but searches server push-oriented `title/body`; users can therefore
see wording that does not match what the server searched. Defer full search and advanced
filters from v1, or persist a versioned locale-neutral structured payload and define a
bounded/indexed search projection. At minimum require escaped input, max lengths/list
sizes, stable opaque cursors, EXPLAIN evidence, and authorization-before-search tests.

## I13. UI/routing assumptions that need correction

The navigation direction is broadly sound, but future-proofing and several live names
need correction:

- Do not merely update every hard-coded tab integer. Introduce one stable `HomeTabSpec`
  or enum-to-index/path/shell/root-page mapping and derive navigation destinations,
  reselect behavior, deep-link owner, and active-tab comparisons from it. Otherwise the
  fifth tab preserves the same index fragility for the next change.
- The live `WindowClass` values are `compact`, `regular`, and `expanded`, not
  `compact`, `medium`, and `expanded`.
- Theme tokens live on `TenturaTokens`/`context.tt`; there is no live
  `TenturaThemeExtension` symbol.
- There is no live `TenturaFilterChip`; either add a reviewed design-system component
  explicitly or stop naming it as an existing dependency.
- The project initial-load rule requires the established loading treatment and forbids
  painting success UI from empty data. The proposed delayed skeleton is a deliberate
  convention change and needs a design-system decision rather than an incidental task
  acceptance line.
- A custom render-object visibility detector plus focus, route-top, lens, viewport, and
  dwell logic is a large cross-platform subsystem. If retained, isolate platform focus
  behind a port and pass simple visibility evidence into a pure `SeenAckCase`; do not
  leak browser APIs or render objects into domain code. Recommended v1 is exact-event
  open/explicit acknowledgement; add dwell-based field acknowledgement only after the
  unread product semantics are settled.

Deep links should encode a canonical domain destination, not a permanent home-tab
ownership choice. Push/in-app origin may choose the Updates branch at navigation time,
while old links and non-Updates entry points retain normal active-branch behavior.

## I14. The proposed release phases create the two-truth window they claim to avoid

Phase 3 ships the Updates feed and deletes Notifications in T-10/T-11. Seen
acknowledgement does not arrive until T-13, unified badges/markers until T-15, Inbox
parity until T-18, and legacy cleanup until T-19. Therefore the first visible release:

- removes the only existing read/mark-all-read surface;
- exposes a feed that cannot yet apply its final acknowledgement rule;
- retains local cursor dots alongside new event rows;
- does not meet issue #80's consistent-badge acceptance criteria; and
- may not contain required Room/relationship/status producers.

This is not an atomic replacement and should not ship continuously as described.

**Proposal:** deliver a feature-gated vertical slice:

1. Product contract + ADR + machine-readable event coverage contract.
2. Additive server occurrence/receipt foundation and compatibility/shadow queries.
3. Hidden client slice containing feed, unread badge, exact navigation,
   acknowledgement, account reset, realtime/catch-up, and mandatory/noisy policy.
4. Full-stack and mixed-version proof, including empty-feed/count equivalence.
5. In one release, enable the fifth tab, switch Inbox/My desk indicators that have
   parity, and remove the bell/old route only when all issue acceptance criteria pass.
6. Later increments: obligation settlement, field-level dwell highlights, search,
   advanced filters, extra Progress kinds, then legacy cleanup.

A feature flag must not create two user-visible truths: while disabled, old surfaces own
all chrome; while enabled, new surfaces own it. Shadow reads may compare data silently.

## I15. Missing high-value tests and operational proof

Part E is broad but omits tests for the architecture's most dangerous boundaries. Add:

- **atomicity/failure injection:** domain write failure, occurrence write failure,
  receipt projector crash, recipient N failure, push/email failure, retry after commit;
- **concurrency:** seen versus settle, dismiss versus automatic resolve, two enqueues of
  one idempotency key, supersession racing acknowledgement, mark-seen after settlement;
- **authorization/count equivalence:** revoked access, delete/tombstone, actor profile
  removal, no accessible page-one rows, positive count always yields a visible group;
- **pagination:** equal timestamps, group across boundary, collapsed row timestamp bump,
  inserts between page fetches, filter changes during pagination;
- **compatibility:** old/new server and client matrix described in I11;
- **account lifecycle:** direct non-empty account switch, logout/login, stale ack response
  from the prior generation, filter/scroll state isolation;
- **load/refetch budget:** query count and PG notifications for bulk ack/settlement;
- **preference safety:** suppressible in-app class hidden, mandatory class still visible,
  push opt-out does not erase in-app receipt;
- **coverage contract:** every issue-required event has a producer, recipient policy,
  exact resolvable destination, and known client presentation;
- **release proof:** a real local browser multi-client journey with the new tab enabled,
  not only simulated fan-out/unit tests.

Migration tests must assert the actual index predicates and old/new SQL paths, not only
that a trigger fired.

## I16. Required decisions before implementation

These are gates, not questions to leave for a junior implementer inside T-02/T-19:

| Gate | Decision | Reviewer recommendation |
|---|---|---|
| D-1 | Is the nav number unread or unresolved work? | Follow issue #80: unread. Expose “Needs you” separately if approved. |
| D-2 | What is canonical: occurrence, recipient row, or notification delivery? | One semantic occurrence, N recipient receipts, separate channel delivery concern. |
| D-3 | Strong atomic receipts or transactional semantic outbox + projector? | Transactional semantic outbox + idempotent projector/dispatcher, unless occurrence-time recipient snapshots require direct receipt writes. |
| D-4 | Can mandatory/safety obligations be suppressed or dismissed? | No. Persist `mandatoryVisibility`; preferences only suppress permitted classes/channels. |
| D-5 | Are read and settlement separate axes? | Yes; `seen_at` and nullable settlement facts, not one status enum. |
| D-6 | What exactly is a badge/group unit? | Define a domain `attentionThreadKey`; do not infer it from `beacon + category`. |
| D-7 | What ships in v1? | Feed + unread + exact links + preferences + realtime correctness. Defer resolution workflow, field dwell, and search unless explicitly required. |
| D-8 | When can old Notifications/NewStuff be removed? | Only in the release where the corresponding new vertical slice and parity tests are enabled. |

After these decisions, revise C0–C13, Part D, Part E, and T-01–T-20. Do not append
answers only to Part G; they change the model and sequence throughout the plan.

## I17. Proposed corrected invariants for the next plan revision

The next revision should be reviewable against these non-negotiable statements:

1. A domain occurrence has one stable causation/idempotency identity; recipient receipts
   do not pretend to be that occurrence.
2. Domain success guarantees a durable occurrence/attention command; channel delivery
   remains post-commit and retryable.
3. Read acknowledgement and obligation settlement are independent monotonic facts.
4. The navigation badge formula is a named product contract, not an incidental SQL
   `COUNT(DISTINCT ...)`.
5. A positive badge and its feed are derived from the same authorized receipt relation.
6. Recipient reason/policy is explicit; no kind-only helper claims to decide
   recipient-specific actionability or surfaces.
7. Idempotency, UX collapse, attention grouping, and supersession use distinct,
   documented identities.
8. Realtime frames remain hints; one owning attention use case performs guarded,
   account-scoped snapshot reconciliation with a bounded refresh budget.
9. Peer UI features depend on a stable attention application boundary, not on the
   Updates presentation feature.
10. Mixed old/new clients and server rollback remain correct until the explicit contract
    phase and minimum-client decision.
11. Every issue-required event has a real producer, exact destination, preference class,
    and automated coverage entry.
12. No old user-visible source of attention truth is removed before the replacement
    vertical slice proves parity end to end.

## I18. Concrete task-list changes required

At minimum, the next revision should restructure Part F as follows:

- Add **T-00 Product contract and ADR**: resolve D-1–D-8, record occurrence/receipt/
  delivery topology, publish the machine-readable event coverage contract.
- Replace T-01 with an **expand-only schema** that represents independent read/settlement
  axes, occurrence/idempotency identity, recipient policy, constraints, and parallel
  compatibility indexes.
- Split T-02 into narrow **attention command**, **attention query**, and **channel
  delivery/retention** ports; define the authorized base relation and pagination model.
- Replace T-03/T-04 with the selected **transactional occurrence path** and idempotent
  receipt projector (or prerequisite Unit-of-Work refactor), including failure tests.
- Expand producer work to cover **Room relevance, relationship/contact changes, and all
  required status/offer-response transitions** before claiming event completeness.
- Add explicit **in-app preference/mandatory-visibility** API and UI work.
- Put all new V2 operations in `_tenturaDirectOperationNames` and add input bounds plus
  contract tests.
- Split client foundation into a UI-independent **attention application slice** and the
  **Updates presenter**.
- Move feed + badge + exact-link + ack + realtime/catch-up + account-reset into one
  feature-gated release slice. Do not delete Notifications in an earlier task.
- Treat field-level visibility/dwell, unresolved-work settlement, search/filters, and
  Progress expansion as separately gated enhancements.
- Make legacy cleanup contingent on shadow-count parity, mixed-version tests, release
  adoption, and the `MIN_CLIENT_VERSION` contract step.

Only after those changes would “junior-ready, sequential” be accurate.

---

# Part J — Review resolution log (Revision 2, 2026-07-16)

Parts C–H above are the revision the Part I review demanded — a restructuring, not an
appendix. This log exists so the resolution of each finding is traceable. Where
revision 2 deviates from the reviewer's specific recommendation, the deviation and its
reason are stated explicitly.

| Finding | Resolution | Where |
|---|---|---|
| I1 unread ≠ unresolved | Adopted. v1 badge is unread per issue #80 (re-read verbatim into the plan; the unnamed "restated brief" is retired). Settlement/work-queue is a gated increment with its own name and count. | C0.1, C0.2 D-1, C5, C14/T-16 |
| I2 outbox is not the canonical event | Adopted. New `attention_occurrence` table is the semantic occurrence; `notification_outbox` re-described as per-recipient receipt; channel bookkeeping stays on the receipt transitionally. ADR required before schema work. | C1, T-00, ALT-2 |
| I3 promised transaction doesn't exist | Adopted (reviewer's recommended model): use-case-owned transaction writes domain change + occurrence atomically; idempotent post-commit projector + sweeper; channels after commit; failure-injection contract table. Direct receipt writes rejected as ALT-3 with reasons. | C2, T-03, Part E |
| I4 status enum collapses two axes | Adopted, and taken further: v1 persists **only** `seen_at` (monotonic); no status enum at all. Settlement facts arrive as their own expand migration with T-16, using the reviewer's exact column shape incl. `legacy_archived` (no fabricated `resolved` backfill — v1 backfills only `seen_at = read_at`). | C1, C0.2 D-5, C14 |
| I5 kind-only policy can't work | Adopted. `AttentionPolicy.project(occurrenceType, recipientId, recipientReasons, roleSnapshot)`; resolver extended to full reason sets; reasons/surfaces/class persisted per receipt; machine-readable `updates-event-contract.json` consumed by both packages' architecture tests. Decided before schema use, not deferred to T-02. | C3, T-00, T-02 |
| I6 required coverage incomplete | Adopted. Part D is now a coverage matrix keyed 1:1 to the issue's eight classes; new v1 producers for room mention/relevance (`roomMessagePosted`), all request status transitions for active participants (`requestStatusChanged`), and relationship/contact changes (`contactStateChanged`); offer-response taxonomy enumerated; in-app noisy/mandatory preference policy added to model, API, UI, and tests. | Part D, T-05, C10, T-13 |
| I7 badge and feed must share authorization | Adopted. One `visible_attention_receipts` relation (authorization + suppression in SQL, never post-pagination) feeds feed, summary, per-beacon lookups; guard-parity property test; invariant "positive badge ⇒ visible row" tested at three levels. | C4, T-02, T-07, Part E |
| I8 conflated identities | Adopted. Idempotency moved to the occurrence (unique always — the seen-retry hole is closed structurally); `dedup_key` narrowed to UX collapse with a specified column-refresh contract; v1 drops `group_key`/`supersede_key` entirely (flat feed, composite cursor — pagination-stable by construction); typed thread/supersession identities arrive with T-16 where they first affect a count. | C8, C1 |
| I9 client ownership misplaced | Adopted. UI-independent `lib/domain/attention/` slice owns receipts, reconciliation, ack store (partitioned + reset on **every** account id change), and selectors; `features/updates/` is a pure presenter; peer features consume selectors, never Updates UI; one bounded scope per visible list. | C7, T-08 |
| I10 refetch feedback storm | Adopted. Account-scoped aggregate id for the `notification` kind; column-restricted UPDATE triggers (repo's own `profile`/`room_seen` precedent); single refresh owner with ≤ 1 in-flight + 1 queued; numeric budget (1/50/500 rows ⇒ ≤ 2 refreshes) as a test, not prose. | C6, T-01, T-07, Part E |
| I11 rollout not backward-compatible | Adopted, simplified further: v1 performs **no index swap at all** — the old dedup index and old conflict SQL stay valid because dual-write keeps `read_at` authoritative-compatible; unread = `COALESCE(seen_at, read_at) IS NULL`; `markAllRead` keeps its exact legacy meaning (mark-all-seen returns in v1, so no reinterpretation exists); explicit expand → dual-write → shadow → flip → contract sequence; mixed-version test matrix. | C12, C5, T-19, Part E |
| I12 over-broad API + premature search | Adopted. Ports split into recorder/projection/query/ack (channel/retention separate); thin controllers; `_tenturaDirectOperationNames` registration and input bounds are task acceptance items; search deferred to T-18 against a structured `payload` projection (the localized-copy-vs-server-copy mismatch dissolves with it). | C3/C4 ports in T-02, T-06, C14 |
| I13 UI/routing corrections | Adopted. `HomeTabSpec` single mapping + grep-test ban on raw indices; live names corrected (`WindowClass.regular`, `TenturaTokens`/`context.tt`; no `TenturaFilterChip` — v1 needs no chips row); established initial-load treatment kept (no new skeleton convention); dwell/visibility subsystem deferred behind a port design; deep links encode canonical destinations with branch preference applied at navigation time. | C9, C14, T-09, T-10 |
| I14 two-truth release window | Adopted. Feature-gated vertical slice; Phase 4 (T-15) is the single atomic flip: tab enabled, dots/markers switched, bell/route/cursors deleted — same release, gated on full-stack proof and zero shadow mismatches. While the flag is off, old surfaces own all chrome; shadow reads compare silently. | C12, T-15 |
| I15 missing high-value tests | Adopted. Part E rewritten around the review's list: failure injection, concurrency, authorization/count equivalence, pagination, mixed-version, account lifecycle, refetch budget, preference safety, coverage contract, real-browser release proof, index-predicate migration assertions. | Part E |
| I16 decision gates | All eight resolved in the plan body (not appended to Part G): D-1 unread; D-2 occurrence/receipt/channel; D-3 transactional outbox + projector; D-4 mandatory never suppressible; D-5 separate axes (settlement not in v1 schema); D-6 badge unit = visible unread receipt; D-7 v1 scope per issue; D-8 removal only in the flip release. | C0.2 |
| I17 corrected invariants | Adopted verbatim as the plan's own invariant list (with v1 scoping noted on #3). | C0.3 |
| I18 task-list restructure | Adopted: T-00 contract/ADR; expand-only T-01; split ports T-02; transactional path T-03; producer completeness T-04/T-05; preference work T-06/T-13; direct-operation registration in T-06; attention slice vs presenter split T-08/T-10; one flip release T-15; gated increments T-16–T-18; contingent contract phase T-19. | Part F |

Deliberate deviations from the reviewer's recommendations (with reasons):

1. **Settlement columns are absent from the v1 schema**, not merely orthogonalized
   (I4 proposed the full column set now). Adding nullable columns later is a cheap
   expand-only migration; encoding an unapproved product into the schema is exactly what
   I1 warns against. The reviewer's column shape is preserved verbatim in T-16.
2. **`requestStatusChanged` and event-derived card dot markers stay in v1** although
   D-7's recommendation ("feed + unread + links + preferences + realtime") could be read
   as excluding them: "request status changed" is on the issue's *required* list, and
   removing the local Drift cursors at flip without event-derived markers would create a
   new tab-dot/row-pill split truth — the failure mode the issue opened with.
3. **No index swap in the transition at all** (I11 asked for a corrected swap sequence):
   dual-writing `read_at` keeps the old partial index and old conflict SQL fully valid
   until the contract phase, which removes the mixed-binary hazard instead of
   sequencing it.

---

# Part K — Critical re-review of Revision 2 (2026-07-16)

## K0. Outcome

Revision 2 corrected the original product mismatch, but it was still **not safe to hand
to implementation**. The second pass re-read issue #80, ADR 0008, the current channel
services, notification SQL, every legacy notification-port call-site family, the
client domain lint contract, `beacon_room_seen`, routing/tab ownership, and the full
`NewStuffCubit` state. The concerns below were blocking because they affected durability,
privacy, count correctness, or whether the proposed code could compile under the
repository's architecture rules.

Revision 3 applies the proposed fixes directly in Parts A–H. Part J remains a historical
record of how revision 2 answered Part I; where Part J and the current body differ, the
current body and this Part K supersede Part J.

## K1. A retry guarantee without a retryable channel architecture

**Concern.** Revision 2 said channel delivery was retryable while retaining receipt
bookkeeping and the existing pipeline. Live `FcmBatchQueue` clears its in-memory map
before sending and only logs failures; direct review pushes are unawaited; immediate
email logs failures. A crash after projection could still lose every channel attempt.

**Fix applied.** D-2/C1 now model a physical `attention_channel_delivery` table with
leased, idempotently created jobs, retry/backoff/dead state, and operational retention.
Projection commits receipts and jobs together; workers send strictly afterward. The
contract is explicitly at least once and admits provider-accepted/crash duplicates.

## K2. Projection-time recipient lookup loses the people removal events target

**Concern.** Revision 2 asserted that no v1 event needs an occurrence-time recipient
snapshot. That is false for room removal, offer decline/removal, and relationship loss:
the destructive mutation removes the membership/state the resolver intended to query.
Worse, filtering every revoked receipt through `beacon_can_read_content` makes the
required removal event invisible by construction.

**Fix applied.** D-3/C1 capture bounded direct-recipient facts/reasons in the domain
transaction; K11 then closes the remaining replay-time drift by generalizing that
correction to a normalized event-time snapshot for every recipient class rather than
retaining any current-state audience expansion.
Receipts carry an access policy. Normal Request data still uses ADR-0008 functions; a
contract-allowlisted, sanitized `recipient_safe` terminal receipt can report the access
loss without revealing Request content. ADR 0010 must record this explicit amendment to
ADR 0008 and its negative privacy tests. Raw occurrence payload is server-internal;
receipt and delivery job carry per-recipient sanitized presentation snapshots, so a
shared occurrence cannot leak full facts through a safe-terminal projection and a later
receipt collapse cannot rewrite an older queued delivery's copy.

## K3. Subject-based “idempotency” would suppress legitimate later events

**Concern.** The example key `v1|type|subject ids` is stable for a subject, not for a
source event. A close→reopen→close or remove→re-admit→remove sequence would silently
drop the second legitimate transition. `projected_at` also did not serialize two
projectors that selected the same unprojected row concurrently. Keeping today's
category-based `dedup_key` recipe would also collapse unrelated new events that happen
to share account/category/Request.

**Fix applied.** Every contract row now names an immutable source-event identity (row,
activity/transition, or command id persisted in the same transaction) and must pass
repeat-after-reversal tests. Projectors claim with `FOR UPDATE SKIP LOCKED` and recheck
under lock; idempotency, collapse, and external at-least-once delivery remain separate
concepts. New receipts use a typed contract collapse family/subject (or `none`) while
retaining the legacy-compatible partial index/upsert mechanism. A canonical
`content_hash` over immutable producer input/source-transition facts makes same-key/
different-command reuse a hard transaction error rather than a silent stale replay;
the immutable audience is stored once and is deliberately not recomputed on a retry.

## K4. The proposed authorization relation duplicated an accepted security decision

**Concern.** Revision 2 proposed translating `BeaconAccessGuard` into another SQL
`EXISTS` predicate. ADR 0008 already chose `beacon_can_read_content`/
`beacon_can_read_tombstone` as shared SQL enforcement adapters and has a Dart↔SQL parity
suite. A third implementation would recreate the drift the ADR was written to prevent;
it would also mishandle non-beacon profile/invite receipts.

**Fix applied.** C4 is destination-aware and delegates to the existing SQL functions.
The existing parity suite is extended. Profile, tombstone, legacy, and tightly
allowlisted safe-terminal policies are explicit instead of being forced through one
beacon-only predicate. `profile` does not invent a new visibility predicate absent from
the live model: the addressed receipt is sanitized/account-scoped, while navigation
still uses the existing profile query/guard and its typed fallback.

## K5. The badge/feed invariant and refresh snapshot were overstated

**Concern.** A chronological All page can contain 50 newer seen rows while an older
unread row still contributes to the badge, so “positive badge implies unread on the All
first page” is false. Separately fetching summary, feed, and card markers can combine
different database moments even if all use the same base relation. Aggregate realtime
hints cannot identify an “affected page.”

**Fix applied.** The invariant is count equality over the authorized unread relation and
a non-empty first **Unread** page; badge entry selects Unread. `attentionSnapshot`
returns summary + active head + bounded markers atomically. The client refreshes the
head, normalizes all pages by receipt id, and removes stale duplicates after collapse
reordering.

## K6. Category-level in-app muting cannot express the proposed policy

**Concern.** Existing `NotificationCategory.coordination` contains mandatory
`blockerOpened` projections and noisy coordination churn. A
`mutedInAppCategories` API would either forbid muting the main noisy category or present
a toggle that only partially does what it says.

**Fix applied.** In-app preferences use contract-owned
`AttentionPreferenceClass` keys that exist only for muteable/noisy families. Existing
categories remain push/email controls. Mandatory rows have no mute key and bypass the
filter structurally. Noisy receipts carry a bounded expiry so a permanently muted class
does not accumulate invisible unread rows forever; unmuting restores only unexpired
history.

## K7. Row triggers only moved the bulk storm to the server

**Concern.** Setting `entity_id = account_id` lets clients deduplicate 500 row-trigger
frames, but PostgreSQL still emits 500 notifications. Revision 2's stated PG-count
acceptance could not pass.

**Fix applied.** C6/T-01 require statement-level transition-table triggers that emit
once per distinct affected account and inspect old/new visible columns. Tests assert PG
notification count and client refresh count independently for 1/50/500-row updates.

## K8. The client boundary violated the repo's dependency rule and the deletion plan
removed unrelated behavior

**Concern.** Placing `AttentionCase` under `lib/domain` next to a concrete data
repository did not say that the case depends on a domain-owned port; a direct concrete
import would fail `no_domain_to_data_or_ui_import`. Also, `NewStuffCubit` owns
`inboxNeedsMeCount/inboxLoadComplete`, which drives My Work's empty-state CTA. Deleting
the whole cubit without moving that projection breaks behavior unrelated to attention.

**Fix applied.** C7/T-08 define domain-owned repository/account ports and an architecture
test. T-09 first moves the operational Inbox count to an Inbox-owned application stream
and active-tab state to the shell. T-15 deletes only after the My Work regression test
proves the CTA survives; `AttentionCase` does not become a new god object.

## K9. Two proposed producers contradicted the domain and the research

**Concern.** Revision 2 projected every ordinary Chat message to all admitted members,
despite Part B correctly choosing a cursor for high-volume streams. It also named
`ContactCase` as a counterpart-notification producer, but that case edits a
viewer-private label; notifying the subject would leak private data. Its proposed Chat
URL also put a message id in `item`, which the live client reserves for a coordination
item, and assumed the target was in the initially loaded page.

**Fix applied.** `roomMessagePosted` projects only explicit mentions, replies, and other
contract-declared directed semantic targets; ordinary traffic remains in `room_seen`.
Relationship coverage is mutual-connection formation and invite acceptance through
`UserTrustEdgeCase`/auth/invitation paths. Unilateral removal/negative actions and
private contact-label edits are non-producing in v1. Directed links use a new `message`
parameter, retain `item` for thread/coordination identity, and hydrate an authorized
off-page target before invoking the existing message-scroll path.

## K10. Transaction and rollout assumptions were not executable contracts

**Concern.** “Move `withMutatingUser` into the use case” would make server domain import
data infrastructure unless inverted through a port, and assumed nested drift
transactions would join without proof. The producer list omitted real legacy callers in
auth, credential auth, `BeaconRoomCase`, coordination, and individual coordination-item
cases. The shadow gate compared legacy `asksOfMe` with new all-category unread (guaranteed
non-zero deltas), and the flip both deleted fallback code and claimed a disableable
flag. The new ADR was also assigned the already-used number 0001, and occurrence/job
retention was absent. “Five is the platform maximum” also overstated current guidance:
Material specifies 3–5 for its navigation bar, while Apple recommends five or fewer by
default and describes adaptive/overflow patterns.

**Fix applied.** C2/T-02/T-03 introduce a domain-owned UoW port, explicit
transaction-neutral methods, a pg transaction/GUC proof, and a complete port-call-site
inventory. Shadowing compares like-for-like read axes and classifies expected policy
deltas; only unexplained mismatch gates release. T-08…T-14 use a QA compile-time flag,
which T-15 removes during the unconditional cutover. The ADR is 0010, retention and
account-deletion policy gate T-01, and T-19 no longer incorrectly depends on optional
T-16…T-18 product increments. C9 now records five as Tentura's v1 cap rather than a
universal platform limit.

## K11. “Non-destructive” projection-time audiences still make replay nondeterministic

**Concern.** Capturing only removal/decline targets fixed the obvious destructive case,
but revision 3 initially left stewards/watchers to projection-time lookup. That still
changes history based on worker timing: after a crash, a participant who left can miss
an event they were eligible for, while one who joined later can receive an event from
before they joined. The same durable occurrence could therefore produce a different
audience after retry, which is incompatible with auditability and deterministic replay.

**Fix applied.** D-3/C1/C2 now persist a normalized
`attention_occurrence_recipient` snapshot with full reasons and minimal versioned role
facts in the domain transaction for every occurrence. Broad audiences use set-based
snapshot inserts; the contract records their query and fan-out budget and forbids
silent truncation, plus an explicit pre/post-mutation capture phase so removals snapshot
before deleting their source row. Projection rechecks current access/preferences, but never recomputes
who the historical occurrence addressed. Failure, delayed-projection, join/leave, and
same-input-retry-after-join/leave tests make this boundary executable; a different
producer-input hash for the same identity still fails.

## K12. Queued delivery depended on a receipt that collapse is allowed to rewrite

**Concern.** Freezing only `delivery_payload` was insufficient. A later collapse also
rewrites the receipt's occurrence, access policy, destination, category, and target. A
worker that re-read those fields could authorize or suppress an old queued send using
the latest event's context. The schema also described email waiting for push without a
persisted dependency, and `ON DELETE CASCADE` could erase a pending job during cleanup.
Sending each durable job independently would also discard the live queue's coalescing
and turn a reliability change into a push-volume regression.

**Fix applied.** Each delivery job now snapshots category, access policy, beacon,
destination/target, sanitized presentation, and a typed `send_condition`; workers use
that immutable context while rechecking current policy. Composite audience and
receipt/account FKs prevent cross-recipient jobs, deletion is restrictive, and storage
guards permit only delivery-state bookkeeping updates. The email worker can now model
the intended `push not provider-accepted OR recipient absent` decision against a sibling
push job instead of treating token enqueue as delivery. A leased throttle row preserves
the existing account/category cooldown across concurrent
workers. The durable push worker claims and terminalizes batches using the existing
account/beacon/priority-band aggregation semantics. Tests cover collapse-before-send,
dependency outcomes, coalescing, cooldown races, lease recovery, and cleanup.

## K13. The “expand-only” migration also claimed to replace a live trigger

**Concern.** m0115 was called additive while T-01 simultaneously replaced row-level
notification publishing with statement-level transition tables. Keeping both triggers
would double invalidations; removing the old one is a behavior cutover, not an expand-
only schema operation.

**Fix applied.** T-01/m0115 is now literally additive. T-01b/m0116 performs the publisher
replacement in one migration transaction, updates the realtime contract, proves that
no committed both-trigger state exists, and tests old-client/server-rollback behavior.
This preserves a clean rollback argument without hiding an operational cutover inside
the schema expansion.

## K14. Immutability and account erasure contradicted each other

**Concern.** The storage guard initially allowed only `projected_at` to change, while
the retention contract promised to scrub user-linked source data on account deletion.
An occurrence may still be retained for other recipients, so neither blanket
immutability nor immediate row deletion can satisfy both promises. Recomputing or
validating the old content hash after a privacy scrub would also be meaningless.

**Fix applied.** C1/C12 define one audited system-only erasure path: delete the departing
account's jobs/receipts/audience rows in FK order, and, where another recipient still
retains the occurrence, scrub the approved user-id-bearing source fields, set
`privacy_scrubbed_at`, neutralize retained receipt copy/destinations, and suppress
unsent jobs that could carry stale identity. The original hash becomes a non-replayable
insertion fingerprint; normal application writes remain immutable. Account-deletion
tests prove no retained title/body/presentation/job/role payload leaks the deleted
account.

## K15. The read-state backfill would have triggered a deployment-time storm

**Concern.** m0115 initially ran one bulk `seen_at = read_at` update while the live
unrestricted row trigger was still installed. That would emit one realtime notification
per historical read receipt during migration. The proposed `seen_at IS NULL` partial
indexes also did not match the mixed-binary `COALESCE(seen_at, read_at) IS NULL` query
after a server rollback created read-at-only rows.

**Fix applied.** m0115 performs no backfill and creates transition indexes on the exact
coalesced unread predicate. T-01b/m0116 first replaces the publisher, then backfills
under the statement trigger, yielding at most one aggregate hint per affected account.
T-19 replaces both collapse and unread transition indexes with seen-only predicates
after old binaries are excluded. Migration tests assert notification counts and exact
index predicates across rollback-created mixed rows.

## K16. “Invisible foundation” would already change production notifications

**Concern.** The dependency summary called phases 0–3 invisible, but T-05 added real
status, directed-Chat, and relationship producers before the client flip. Those rows are
readable by the legacy Notification Center and their channel jobs can push/email old
clients. That is a production behavior launch, not dark foundation, and it bypasses the
T-14 release gate.

**Fix applied.** T-05 now deploys only the new producer call sites behind a default-off
server gate; migrated existing kinds remain behavior-compatible. QA enables that gate
together with the client flag for T-14. T-15 removes both gates and makes the complete
product unconditional. Mixed-version tests prove old clients can still render/ack the
legacy projection and safely fall back when they do not understand an exact-anchor
parameter.

## K17. Readiness judgment

With these amendments, the plan is architecture-ready to begin at **T-00**, not at the
schema. T-00 is intentionally a hard review gate: ADR 0010, the machine-readable event
contract, payload/access allowlists, identity recipes, and retention windows must be
approved before m0115. No implementer is authorized to weaken those decisions inside a
later task merely to make a test pass.

---

# Part L — Proportionality review of Revision 3 and its resolution (Revision 4, 2026-07-16)

## L0. Outcome and precedence

A third review accepted revision 3 as internally consistent but found it
**overengineered around a notification-platform rewrite**: issue #80 requires reliable
in-app unread activity, not durable, replayable, multi-channel event delivery. Its
verdict — reduce v1 scope before calling the plan junior-ready — is **adopted**.
Revision 4 rewrote Parts C–H accordingly. Each finding below was re-verified against
the live code before being accepted; none was accepted on authority alone.

Precedence: Parts I–K are historical review records of revisions 1–2. Where they (or
Part J's resolution log) prescribe machinery that revision 4 removed, the current
Parts C–H and this Part L govern. The revision-3 text remains in git history as the
design record for the deferred T-20 increment.

## L1. Durable channel jobs, retries, throttles, immutable send snapshots — **cut (adopted)**

**Finding.** D-2/C1 added `attention_channel_delivery`, leasing, retry/dead-letter
state, email→push dependency jobs, cooldown reservations, cleanup ordering, and
delivery-copy immutability — internally consistent (the live `FcmBatchQueue` really is
an in-memory map that drops failures; verified), but justified only by a retry promise
issue #80 never makes. The issue promises reliable **in-app** events.

**Reasoning.** The entire job topology existed to serve revision 3's invariant 2
("immediate channel delivery is a durable, post-commit, at-least-once job") — a
self-imposed requirement. Once receipts are transactional (L2), channels can keep
today's exact best-effort semantics with zero product regression: a crash after commit
loses at most a push attempt, which is precisely today's exposure. Cutting the jobs
also dissolves K12's immutable-send-context problem, the throttle table, the
restrictive-FK cleanup ordering, and the delivery dashboards — none of which have an
in-app observable effect.

**Fix.** Invariant 2 rewritten (C0.3); jobs/throttle tables removed from m0115 (C1);
post-commit best-effort hand-off specified in C2 step 3; a channel-behavior
*regression* suite added so v1 provably doesn't make today's channels worse (Part E);
the durable design preserved verbatim as increment T-20 (C14, ALT-6 reversed); risk
R-8 states the accepted loss window explicitly.

## L2. Occurrence table + full historical-audience snapshots — **cut; transactional receipt writes instead (adopted)**

**Finding.** The occurrence table, recipient-snapshot table, content hashes,
pre/post-mutation capture rules, sweeper, and global UoW refactor solve destructive
transitions and replay determinism — but those problems exist only because the plan
chose an **asynchronous projector**. The current code already resolves recipients and
writes one outbox row per recipient (verified: `dispatch` → resolver → per-recipient
`_writeOutbox` loop); making those writes transactional with the mutation removes the
replay window entirely.

**Reasoning.** Every K11-class hazard (delayed worker sees a changed audience, replay
notifies a later joiner) requires a gap between mutation commit and receipt
materialization. With receipts written in the same transaction there is no gap: the
committed receipt rows *are* the event-time audience snapshot, including for
decline/removal kinds, which simply resolve recipients before the destructive statement
inside the same transaction. The reviewer's "stable idempotency key" is adopted as
`source_event_key` metadata, but v1's actual idempotency mechanism is transactionality
itself: a receipt commits iff its mutation commits, so duplicate-receipt risk reduces
to per-kind domain idempotency — today's status quo. The always-unique occurrence key
guarded projector replays that no longer exist. Revision 3's own ALT-3 rejection
("couples producers to volatile policy") priced in the channel-job machinery cut in L1;
without it the in-transaction work is bounded reads + one policy function + an upsert.

**Fix.** D-2/D-3 rewritten (C0.2); occurrence/recipient tables removed from m0115 (C1);
C2 rewritten as transactional dispatch with a simplified failure table; C8 re-derives
the identity story (`source_event_key` = metadata + T-20 seed; `dedup_key` = collapse
only; no unique-always index); ALT-2/ALT-3 reversed with reasons (Part H). The
`MutatingUnitOfWorkPort` refactor **survives** in reduced form — it is the reviewer's
own recommendation's prerequisite, since per-repository `withMutatingUser` calls cannot
span the mutation and the receipt writes.

## L3. New semantic event store as prerequisite for the tab — **cut (adopted; same decision as L2)**

**Finding.** `notification_outbox` is already the durable, per-user, unread/read,
collapse-capable activity store (verified: m0096 schema, dedup partial index, collapse
upsert). A smaller v1 extends it with `seen_at`, stable event identity, destination
metadata, suppression class, and a correct authorized query.

**Reasoning.** Accepted as the schema-level consequence of L2. The receipt/occurrence
*vocabulary* is kept (the row is documented as a receipt, not "the event") because it
cost nothing and keeps T-20 honest, but no second store exists in v1. The reviewer's
proposed column set is almost exactly revision 3's receipt-column additions minus the
occurrence FK — confirming those columns were the load-bearing part all along.

**Fix.** C1's m0115 is now precisely that extension: `seen_at`, `source_event_key`,
`destination_kind`/`target_entity_id`, `presentation_key`/`presentation_payload`,
`suppression_class`, `in_app_preference_class`, `access_policy`, two transition
indexes, and the preference column. Columns revision 3 wanted for deferred features
(`recipient_reasons` audit, `surfaces`, `expires_at`) were cut with their features
(T-21/T-22).

## L4. `attentionSnapshot` compound atomicity — **reduced to summary + page in one query (adopted)**

**Finding.** Returning summary, feed head, *and* mounted-card markers from one database
moment prevents a fleeting cross-widget mismatch but creates a compound
API/cache/invalidation protocol. The must-have is one authorized receipt relation
shared by feed and unread count; marker-level atomicity is not required by the issue.

**Reasoning.** Accepted. The badge-vs-feed consistency criterion is fully served by
computing `{unreadTotal, page}` in one statement over the shared relation — the pair
the user can actually see disagree. Per-beacon markers were only needed for the
tab-dot/card-marker switchover, which is itself deferred (see L8: `NewStuffCubit`
stays in v1), so the marker projection, `unreadForBeacons`, surface booleans, and the
`visibleBeaconIds` parameter all leave v1 together, coherently.

**Fix.** C4 defines `attentionFeed(view, cursor)` → `{summary, page}` as the one read
API; C6/C7 refresh coordination simplifies to a head refresh; T-06 drops the separate
snapshot operation; markers/dots become increment T-21.

## L5. Machine-readable contract scope — **slimmed to five facts per event type (adopted)**

**Finding.** The proposed contract owned source identities, snapshot SQL, role schemas,
payload allowlists, fan-out budgets, collapse rules, rollout gates, destinations, and
client presentation — a second implementation language that will drift. The existing
realtime contract (verified: compact wire kinds + impacts + test pointers) is the right
weight class.

**Reasoning.** Accepted. The contract's architecture-test value is completeness
enforcement — "every issue class has a producer, a destination, a muteability decision,
and a test" — which needs exactly five facts per row. SQL, identity recipes, collapse
recipes, and payload allowlists are implementation detail whose truth lives in code and
whose enforcement belongs to focused tests next to that code; duplicating them into
JSON creates two sources that must be reconciled forever.

**Fix.** C3 fixes the contract fields to producer command, recipient category,
destination family, muteability, covering test; Part D's intro points identity/
collapse/audience details to code-adjacent tests; T-00 and the coverage-contract test
in Part E are re-scoped to match.

## L6. Account-erasure rewriting and immutability guards — **cut; separate privacy/retention decision (adopted)**

**Finding.** The plan mandated account-deletion scrub workflows rewriting other users'
retained receipts and pending jobs, plus storage immutability guards, as prerequisites
before any schema work (T-00 gated T-01 on them). Neither issue #80 nor the current
outbox model establishes that requirement; it substantially expands the critical path.

**Reasoning.** Accepted. Most of that machinery attached to tables that no longer exist
(occurrence scrubbing, job suppression, content-hash non-replayability). What remains
in v1 is columns on existing rows, which inherit the outbox's current deletion/
retention behavior unchanged — so v1 is retention-neutral by construction, satisfying
the reviewer's one guardrail ("ensure v1 does not worsen current retention"). Whether
Tentura *should* scrub retained copies naming a deleted account is a real
privacy/compliance question — but a product decision on its own track, not an
engineering prerequisite for an unread badge.

**Fix.** C12's retention paragraph declares v1 neutral (existing sweep + digest
watermarks unchanged, no new orphanable tables, asserted in Part E's lifecycle tests);
T-00 no longer gates on retention/erasure approval; increment T-22 owns the policy
decision; Q-4 records it as open.

## L7. Statement-level notification trigger — **kept, with narrowed justification (adopted)**

**Finding.** The trigger cutover is warranted — the live migration really does emit one
notification per outbox row (verified: `FOR EACH ROW` in m0114), so bulk
acknowledgement needs it — but it should stand on that justification alone, not be
bundled with the occurrence/delivery redesign.

**Reasoning.** Accepted, with one scheduling nuance: the reviewer suggests it "can be a
targeted optimization once bulk acknowledgement exists", but mark-all-seen ships *in*
v1 and the `seen_at = read_at` backfill also needs the new publisher first (K15's
storm analysis still holds). So the cutover stays a v1 task — just a self-contained
one, justified entirely by bulk ack + backfill, with no dependency on any removed
machinery.

**Fix.** C6 re-states the narrow justification; T-01b remains its own migration
(m0116) sequenced before the ack API; its tests are unchanged (per-account emission,
channel-bookkeeping silence, no dual-publisher state).

## L8. What the review endorsed — retained, with two scope notes

The reviewer's "proportionate, should stay" list is retained unchanged: `seen_at` as
the unread axis with settlement deferred; one authorized relation for feed and badge
(the live guard/count split is verified and fixed pre-flip in C12 step 3); a single
client refresh owner; in-app noisy-class preferences; directed-only Chat events with
exact message links; `HomeTabSpec`; one visible cutover after full-stack proof.

Two deliberate scope notes on the recommended v1 boundary:

1. **Tab dots stay on `NewStuffCubit` in v1.** The recommended boundary lists the fifth
   tab but not the dot/marker switchover, and L4 removed the marker projection.
   Revision 3 had argued (Part J, deviation 2) that retiring the Drift cursors without
   event-derived markers would split truth — revision 4 resolves that by *not retiring
   them*: the dots keep their current semantics, only the bell (which the Updates badge
   directly replaces) is removed at flip. The issue's counter criteria all concern the
   activity surface's badges, which are fully event-derived. The residual two-family
   state is recorded as accepted risk R-9 and owned by increment T-21.
2. **The UoW port survives the cuts.** Transactional receipts — the reviewer's own
   recommendation — require a transaction that spans the domain write and the receipt
   writes, which per-repository `withMutatingUser` cannot provide. T-03 keeps that
   refactor at the minimum scope the recommendation implies (no projector, no sweeper,
   no recorder).

## L9. Revised v1 boundary (normative restatement)

v1 = transactional per-recipient receipts in the existing `notification_outbox`
+ `seen_at` + one authorized feed/count query (`attentionFeed` → summary + page)
+ in-app noisy-class preferences with mandatory visibility
+ the existing hint-based notification invalidation (statement-level publisher for bulk
ack) + fifth tab + exact links, with the old Notification Center kept until the
vertical slice is proven and removed in the single flip release.

Deferred: occurrence/replay infrastructure and durable channel delivery (T-20),
settlement (T-16), dwell highlights (T-17), search (T-18), tab-dot/card-marker
unification (T-21), retention/erasure policy (T-22), legacy contract phase (T-19).

With this boundary, implementation time goes to the guarantees issue #80 actually asks
the Updates tab to make; the plan is now scoped for hand-off.
