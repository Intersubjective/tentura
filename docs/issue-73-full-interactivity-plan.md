# Issue 73: Full Interactivity and Deterministic Convergence Plan

Status: Final after critique loop 3; implementation in progress. Revised
2026-07-14: live Graph updates de-scoped — a stale open Graph is accepted (see
AD-8 and the section 18 scope-change note).
Issue: https://github.com/Intersubjective/tentura/issues/73
Scope: `packages/client`, `packages/server`, integration tooling, architecture docs
Terminology: user-facing Request / Chat; internal Beacon / Room

## 1. Outcome

Tentura must behave as one continuously converging application across screens,
tabs, devices, and users. A committed server-side change that is relevant to a
signed-in user must cause every active affected projection to converge without a
manual page refresh. If a live signal is missed because the app, WebSocket, or
Postgres listener was disconnected, reconnection or foreground resume must
deterministically revalidate server truth. Repeated signals may cause repeated
idempotent reads, but must never duplicate domain rows, messages, counters, or UI
effects.

The implementation keeps the server as the source of truth. Real-time messages
are invalidation hints, not a second data model and not commands to reproduce
server business rules in the client.

## 2. Issue 73 requirements

The issue records these observed failures:

- newly forwarded Requests do not reliably appear in the recipient Inbox;
- help offers and author responses do not reliably update for both sides;
- Chat messages may be committed but remain invisible to the recipient;
- contact and relationship changes leave People, Profile, and Graph stale;
- Request lifecycle changes leave Inbox, My Work, and detail stale;
- Inbox contents and activity counters can remain stale;
- users cannot distinguish failed, pending, and committed-but-not-synchronized
  actions.

Acceptance criteria carried into this plan:

1. A forwarded Request appears in the recipient Inbox without refresh.
2. Help offers and author coordination responses update for all affected users.
3. New Chat messages appear while Chat or another app screen is open.
4. Contact and visibility changes update People and Profile. Graph is exempt
   (2026-07-14 scope change): an open Graph may go stale; it renders fresh
   authoritative data on route entry and manual refresh.
5. Request status changes update Inbox, My Work, and detail.
6. Reconnect and resume perform deterministic catch-up without duplicate data or
   one-shot UI effects.
7. Automated multi-client coverage proves the critical forward -> offer -> Chat
   -> closure path.
8. Every critical mutation exposes a visible pending state, prevents accidental
   duplicate submission, surfaces failure through the existing `UiEffectPort`
   error boundary, and converges after committed success. Live-channel status is
   not used as a substitute for command-result UX.

## 3. Constraints and non-goals

### Required constraints

- Preserve Clean Architecture dependency direction. Domain types and ports do
  not import data, UI, Ferry, Drift, WebSocket, or Flutter types.
- Repositories return domain entities and translate transport/persistence data.
- Cubits consume use cases for multi-repository or stream orchestration.
- No generated file is edited by hand; codegen is run after source changes.
- No Hasura GraphQL subscriptions and no periodic HTTP polling.
- No UI route-result refresh plumbing such as `Navigator.pop(true)`.
- No derived Request status, counts, visibility, or responsibility logic on the
  client event bus.
- Existing optimistic updates remain limited to values authored verbatim by the
  current user and are reconciled from server truth.
- Background refresh is silent when usable state is already displayed.

### Non-goals

- Exactly-once network delivery. The guarantee is at-least-once invalidation plus
  idempotent projection convergence.
- A global normalized client entity cache or Redux-like application store.
- Offline writes or conflict resolution for concurrent offline mutation.
- Replacing BLoC/Cubit, Ferry, Drift, or the V2 WebSocket.
- Treating push notifications as the live-state transport. FCM remains an
  attention mechanism; WebSocket invalidation plus catch-up owns convergence.
- Live updates for the open Graph screen (2026-07-14 scope change). Graph is a
  transient visualization the user is not supposed to linger on; it renders a
  fresh authoritative snapshot on route entry and manual refresh, and an open
  Graph may go stale.

## 4. Current-state audit

### 4.1 Existing transport

The current live path is:

```text
Postgres AFTER trigger
  -> pg_notify('entity_changes', JSON)
  -> PgNotificationService LISTEN connection
  -> WebsocketRouterBase
  -> all authenticated sessions in payload.user_ids
  -> RemoteApiClientWs.webSocketMessages
  -> InvalidationService
  -> repository/use-case stream
  -> Cubit refetch
```

Relevant implementation:

- server listener: `packages/server/lib/data/service/pg_notification_service.dart`;
- server fan-out: `packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart`;
- session index: `packages/server/lib/api/controllers/websocket/session/websocket_session_handler_base.dart`;
- client transport: `packages/client/lib/data/service/remote_api_client/remote_api_client_ws.dart`;
- client parser/router: `packages/client/lib/data/service/invalidation_service.dart`;
- current protocol documentation: `DEV_GUIDELINES.md`, Entity invalidation.

This transport is appropriate for invalidation hints. TCP/WebSocket order is
sufficient within a connection because consumers refetch snapshots. A durable
per-event replay log is not necessary to meet issue 73 if every loss boundary
emits a catch-up barrier that refetches current server truth.

### 4.2 Existing strengths

- `WebsocketSessionHandlerBase` indexes every authenticated session by user, so a
  remote event can already reach multiple tabs/devices for a user when that user
  remains in `user_ids`.
- `InvalidationService` buffers for 500 ms and deduplicates entity IDs.
- `BeaconRepository` maps remote beacon invalidations to
  `RepositoryEventInvalidate`.
- `ForwardRepository` exposes help-offer and forward streams.
- room mutations have `BeaconRoomInvalidation` and a session-local
  `BeaconRoomLocalChangeBus`.
- `RoomCubit` has a queued single-flight reload path.
- `BeaconViewCubit` has a full-fetch gate plus targeted room-slice refreshes.
- `MyWorkCubit` has a fetch sequence guard and per-Beacon debounce.
- Inbox and My Work already silently refetch for several room/read streams.
- server writes generally use transactions and many trigger-carrying V2 writes
  use `TenturaDb.withMutatingUser`.

### 4.3 Confirmed architectural gaps

#### Loss and resume gaps

- `RemoteApiClientWs` re-authenticates after reconnect but emits no catch-up
  request to projections.
- `RemoteApiClientWs` constructs a socket only from `setAuth`; the cookie-session
  `setSessionAuth` path inherited from `RemoteApiClient` never starts one. The
  seed path also creates/listens to the socket before `super.setAuth` has finished
  installing credentials, while signup asks for a pre-account auth-request token.
  Realtime startup is therefore missing for a primary web auth path and racy for
  another; it needs an explicit post-auth account binding rather than another
  implicit mixin override.
- local `web_socket_client` 0.2.1 closes itself terminally after its reconnect
  timeout. `RemoteApiClientWs` has no `onDone` supervisor to construct a new
  instance, so an outage beyond that timeout can disable live updates until the
  next auth transition even if ping/pong logic is otherwise correct.
- foreground/background lifecycle does not revalidate live projections.
- the web `LifecycleHandler` listens for visibility changes but performs no work.
- `PgNotificationService` reconnects its LISTEN connection, but clients are not
  told to revalidate changes committed during that listener gap.
- invalidations have no typed domain-level catch-up event.

#### Echo-suppression gap

`notify_entity_change()` removes `tentura.mutating_user_id` from the recipients.
That assumes the originating screen updated every projection. It did not and
cannot update another tab/device for the same account. The room-local bus fixes
some same-process projections but not another process and not non-room entities.
Suppression must therefore stop being user-wide. The mutation actor ID remains
useful metadata, but all affected user sessions must receive the invalidation.

#### Server entity coverage gaps

The latest generic function in migration `m0072` covers:

- `beacon`, `help_offer`, `forward`;
- `room_message`, `participant`, `fact_card`, `blocker`, `activity_event`;
- `coordination_item`, `person_capability_event`.

The admission event trigger in `m0113` maps admission changes to `help_offer`.

Missing state-bearing entities include:

- `inbox_item` for server corrections and same-account status changes;
- `user_contact` for private contact-name synchronization across sessions;
- `vote_user` and `user_trust_edge` for friendship/visibility changes;
- `user` profile changes relevant to open Profile/People views;
- `beacon_room_message_reaction`;
- `polling_act` and poll changes;
- `notification_outbox` for notification feed/count convergence.
- `beacon_room_seen` for same-account read-watermark convergence.

Three current functions publish `entity_changes` and suppress the actor:

- `notify_entity_change()` from `m0072`;
- `notify_coordination_change()` from `m0063` for help-offer coordination;
- `notify_help_offer_admission_event_change()` from `m0113`.

All three must be replaced or routed through identical recipient, actor, chunking,
and failure-containment semantics. The historical `commitment_entity_notify` was
already dropped by `m0063`, and the coordination-item-message trigger was dropped
by `m0072`; the new migration must test the live trigger/function inventory rather
than speculate about orphaned triggers.

#### Client consumer gaps

- `BeaconViewCubit` listens to forward, help-offer, and room streams but not
  `BeaconRepository.changes`; a remote lifecycle update can leave detail stale.
- `InboxCubit` has several direct dependencies and no global reconnect/resume
  catch-up.
- `MyWorkCubit` has no reconnect/resume catch-up.
- `RoomCubit` has no reconnect/resume catch-up.
- `ContactsCase` only refreshes on account switch or explicit local calls.
- `FriendsCubit` reacts to local Like and contact-store events only.
- `ProfileCubit` reacts to local profile repository events only.
- `ProfileViewCubit` coordinates three repositories directly and listens only to
  capability changes.
- `ProfileSharedBeaconsCubit` only fetches at route creation/manual refresh.
- `GraphCubit` coordinates several repositories directly and has no live event
  subscription. The missing live subscription is accepted (2026-07-14 scope
  change: a stale open Graph is fine); the multi-repository coordination
  remains a structural exception outside issue 73.
- `NotificationCenterCubit` only fetches on route entry and local mark-read.
- `NewStuffCubit` is a derived local cursor store; it only becomes correct after
  Inbox/My Work report a newly fetched projection.
- several cubits allow overlapping async fetches without sequence or single-flight
  protection, allowing an older response to overwrite newer state.

#### Test gap

Existing lifecycle integration tests use one Flutter app and repeatedly log out
and in as different users. They prove server workflows but not simultaneous
delivery to an already-open second client. There is no automated disconnect,
missed-change, reconnect, or duplicate-count assertion.

### 4.4 Bookkeeping repair baseline

The debug **Recalculate counters** repair path (`userRecalculateBookkeeping`) is
merged on `main` as of 2026-07-14. It provides a manual repair for admitted-offer
coordination gaps and inbox projection drift; issue 73 must **preserve** the
existing `BookkeepingRefreshSignal` wiring in `InboxCase`, `MyWorkCase`, and
`MyWorkCubit` when touching those files.

At the 2026-07-14 baseline: custom lint tests and all 1,185 client tests pass
(14 skipped); client and server analyze exit zero; server bookkeeping unit tests
pass. Issue 73
verification must not regress or remove bookkeeping refresh behavior.

## 5. Architectural decisions

### AD-1: invalidation hints plus authoritative snapshot convergence

Every live signal carries only enough information to identify affected server
truth:

```dart
enum RealtimeEntityKind { /* closed, typed wire mapping */ }

final class RealtimeEntityChange {
  const RealtimeEntityChange({
    required this.kind,
    required this.aggregateId,
    required this.operation,
    required this.source,
    this.actorUserId,
  });
}
```

No `BeaconStatus`, unread count, profile visibility result, responsibility count,
or other derived value crosses this boundary. A feature use case maps the hint to
the smallest authoritative query; its Cubit owns presentation loading behavior.

Rationale:

- server business rules remain singular;
- missed intermediate mutations collapse naturally into one current snapshot;
- duplicate invalidations are harmless;
- schema evolution does not require synchronized rich-event versions;
- Ferry/Drift/transport types remain outside domain.

### AD-2: one typed session synchronization boundary

Introduce a shared domain boundary using the existing package conventions:

- entities under `packages/client/lib/domain/entity/realtime/`:
  `RealtimeEntityKind`, `RealtimeOperation`, `RealtimeEntityChange`,
  `RealtimeCatchUp`, `RealtimeCatchUpReason`, and `RealtimeConnectionStatus`;
- `RealtimeSyncPort` under `packages/client/lib/domain/port/`;
- `RealtimeSyncCase` under `packages/client/lib/domain/use_case/` as the
  UI-facing application boundary.

`InvalidationService` becomes the data adapter that implements
`RealtimeSyncPort`. It alone parses WebSocket JSON and maps wire strings to the
closed domain enum. Feature repositories/use cases never parse WebSocket frames.
Existing specialized repository streams may adapt from the typed port during the
migration, but no new feature-specific global bus is introduced.

### AD-3: no user-wide echo suppression

In the final enabled mode, all affected sessions, including every session of the
actor's account, receive the server invalidation. SQL publishers retain
`tentura.mutating_user_id` as `actor_user_id` metadata and include the actor in
`user_ids`. During compatibility rollout only, the WebSocket router applies the
default-off `REALTIME_ACTOR_ECHO_ENABLED` flag and filters sessions whose account
matches a non-null `actor_user_id`; SQL no longer owns the rollout switch.

The current `BeaconRoomLocalChangeBus` becomes redundant after complete server
coverage and is removed only after tests prove same-process latency and behavior.
Same-screen optimistic/server-return updates may remain; duplicate subsequent
invalidations are coalesced and reconciled silently.

This decision fixes the otherwise unsolvable case where account A changes state
in tab 1 while tab 2 is open.

### AD-4: catch-up is a first-class protocol event

A catch-up event means: "one or more invalidation hints may have been missed;
revalidate every active projection you own."

Catch-up reasons:

- authenticated WebSocket reconnected after a previously healthy connection;
- ping/pong liveness timeout forced a reconnect of a half-open socket;
- app/browser returned to foreground/visible state;
- server Postgres LISTEN connection recovered;
- server explicitly requests resync after protocol/deployment change;
- manual diagnostic trigger in debug/QA only.

Catch-up events carry the current account ID and a monotonically increasing
connection epoch. They are keyed by `(accountId, connectionEpoch)` and coalesced
over a short window. They do not enumerate entities. Every active Cubit subscribes
through its feature use case and performs one silent, guarded refresh. A late
event from an old account/epoch is discarded. Local reconnect/resume catch-up
starts immediately. Server listener-recovery catch-up applies randomized 0-3
second client jitter to avoid a synchronized refetch herd; a later catch-up
generation supersedes a not-yet-run older one.

This provides deterministic current-state convergence without a durable event
replay store. If future product requirements need an immutable user-visible event
audit or offline mutation replay, that is a separate ADR and persistence model.

### AD-5: projection owners, not repositories, choose refresh scope

- Data repositories perform queries/mutations, map domain entities, and expose
  source changes.
- Feature use cases merge/filter typed invalidations and orchestrate repositories.
- Cubits decide full versus targeted refresh, preserve usable state, guard stale
  completions, and never show loading flicker for background sync.
- Widgets only render Cubit state and optional connection status.

No repository imports another feature repository just to trigger UI refresh.

### AD-6: explicit convergence and stale-response guards

Every event-driven projection must have one of:

- a single-flight gate with one queued rerun; or
- a monotonically increasing request sequence that prevents stale completion
  emission.

Entity bursts are coalesced by `(kind, aggregateId)` before reaching expensive
projection fetches. Catch-up bursts are coalesced by generation. Background
failure preserves existing state, records diagnostics, and retries at the next
signal/resume/manual action; initial-load failure retains existing retry UI.

### AD-7: live status is user-visible only when actionable

Add a global, non-blocking synchronization status presenter:

- no banner during brief (<2 s) reconnects;
- after the grace window, show localized "Live updates paused. Reconnecting...";
- remove it immediately after authenticated reconnect;
- do not claim "up to date" before authentication;
- never block reads or successful writes merely because the live channel is down;
- Sentry/log breadcrumbs record disconnect duration and catch-up reason.

Command status remains separately owned by the initiating Cubit. Critical command
buttons enter a pending/disabled state until the HTTP result, failures emit the
existing localized `ShowError`, and committed success updates/reconciles the
initiating projection. An invalidation or catch-up may refresh data but must never
create a command success/failure nudge, snackbar, dialog, or navigation effect.

### AD-8: bounded recipients only; an open Graph may go stale (revised 2026-07-14)

Bounded recipient SQL covers actor/edge endpoints, mutual friends, and authorized
shared-Beacon participants. That is enough for direct relationship visibility on
Friends, Profile, and People. It is not enough for every third-party node
currently rendered in a Graph — and that is now accepted: the Graph screen is a
transient visualization the user is not supposed to linger on, so live Graph
updates are a non-goal (section 3). Graph renders a fresh authoritative snapshot
on route entry and manual refresh; while open it may go stale.

Arbitrary client-supplied subject IDs would leak private change timing and
remain forbidden. The previously planned server-granted watch protocol
(watch-grant REST endpoint, signed grants, WebSocket watch registration,
reverse `subjectId -> sessions` indexes, per-session batch intersection) is
removed with this scope change, together with its wire control frames
(section 7.3), security gates, metrics, tests, and rollout switches. If a
future product requirement needs a live third-party projection, that is a
separate ADR and architecture review, not a piecemeal revival of this section.

## 6. Target architecture

```text
SERVER DOMAIN                         CLIENT DOMAIN
mutation use case                     RealtimeSyncPort (owned inward)
  -> repository transaction              ^
       -> state tables                    |
       -> AFTER triggers              RealtimeSyncCase
              |                       /     |       \
SERVER DATA   |                  InboxCase RoomCase Profile/People cases
              v                       |       |       |
entity_changes NOTIFY             InboxCubit RoomCubit Profile/People cubits
              |
SERVER API    v
PgNotificationService -> WebSocket fan-out/control
                              |
CLIENT DATA                  v
RemoteApiClientWs -> InvalidationService -> typed domain events
```

Dependencies point inward:

```text
UI Cubit -> feature use case -> domain ports/entities
data repository/service -> domain ports/entities
server API/data -> server domain ports/entities
```

Production is an N-isolate topology, not one shared in-memory server. Every
isolate owns its own `PgNotificationService` LISTEN connection, router,
authenticated-session index, and presence index. Each
isolate receives the same committed PG notification and fans it out only to its
local sessions. A recovered listener emits catch-up only to sessions on that
recovering isolate because other isolates did not share its loss window.
Metrics carry an isolate/worker label.

## 7. Wire protocol

### 7.1 Entity change

Retain the compatible envelope and add actor metadata:

```json
{
  "type": "subscription",
  "path": "entity_changes",
  "payload": {
    "entity": "room_message",
    "id": "B...",
    "event": "insert",
    "actor_user_id": "U..."
  }
}
```

`id` is always the aggregate ID consumed by the client projection, not
necessarily the changed row primary key. Room-related kinds use `beacon_id`;
relationship/profile kinds emit one envelope per affected endpoint and `id` is
that endpoint user ID; Inbox uses `beacon_id`; notification uses the recipient
account ID.
`actor_user_id` is nullable for Hasura, console, migration, or other writes that
did not set `tentura.mutating_user_id`; client behavior must never infer that a
null actor means "another user".

Unknown entity strings are ignored safely and logged once/rate-limited. Invalid
payloads never terminate the shared stream.

### 7.2 Server catch-up control

```json
{
  "type": "control",
  "path": "entity_changes",
  "payload": {
    "intent": "catch_up",
    "reason": "pg_listener_recovered"
  }
}
```

The server sends this to all authenticated sessions on the isolate whose PG
LISTEN service recovered. Client-side WebSocket reauthentication and app resume
generate the same typed domain catch-up locally.

### 7.3 Projection-watch control

Removed (2026-07-14 scope change). The projection-watch control frames existed
solely to keep an open Graph (and third-party Profile/People subjects) live;
a stale open Graph is now accepted, so the socket carries only entity changes
(7.1) and catch-up control (7.2). The heading is kept so the critique log's
section references stay valid.

### 7.4 Connection transition rules

1. First successful auth in a newly launched process does not require a separate
   catch-up because route/session Cubits perform initial authoritative loads.
2. Once a connection has been authenticated, any disconnected -> authenticated
   transition emits exactly one coalesced `webSocketReconnected` catch-up.
3. After signup, seed signin, or cookie-session signin succeeds and returns the
   authoritative user ID, `AuthRemoteRepository` calls an explicit
   `bindRealtimeAccount(accountId)` transport method. Drop/signout calls unbind.
   Rebinding disposes the old socket, invalidates all prior
   `(accountId, connectionEpoch)` state, and prevents a late
   old-account transition from refreshing new-account projections.
4. Foreground resume emits catch-up even when the socket library reports it stayed
   connected, because browsers can suspend timers/network delivery.
5. A server listener recovery broadcasts catch-up because NOTIFY is intentionally
   lossy while LISTEN is absent.
6. `RemoteApiClientWs`, which owns ping, pong, and the socket, maintains the pong
   deadline. On expiry it closes/disposes the terminal `WebSocket`, explicitly
   constructs a new one, and authenticates through the normal connection path;
   it does not expect a socket closed with `close()` to reconnect itself. Rule 2
   then emits catch-up through the typed adapter.
7. If the concrete socket exhausts its own reconnect timeout and its connection
   stream closes, the same account/epoch-scoped supervisor schedules a fresh
   socket with capped jittered backoff. Intentional unbind/disposal invalidates
   the captured epoch and never resurrects a socket.
8. Physical connection is not authenticated readiness. Auth-frame construction,
   token refresh, send, and acknowledgement run under a 10-second completion
   deadline for the current `(accountId, connectionEpoch)`. A build/send failure,
   deadline, or server auth-error frame retries authentication with capped
   jittered backoff. After three consecutive failures, the supervisor disposes
   and reconstructs the socket through rule 7. All async connection callbacks
   catch failures; a healthy-but-unauthenticated socket cannot remain parked.

## 8. Entity and projection impact matrix

| Wire kind | Server source | Aggregate ID | Recipients | Client projections |
|---|---|---|---|---|
| `beacon` | `beacon` | beacon ID | author, active offerers, active forward recipients/other involved users | detail, Inbox, My Work, profile shared Requests |
| `forward` | `beacon_forward_edge` | beacon ID | sender, recipient, author, affected active chain users as required by visibility | Inbox, detail People/forward graph, My Work |
| `help_offer` | help offer + admission event + help-offer coordination | beacon ID | offerer, author/stewards, admitted affected users | detail People, Inbox, My Work, Chat access |
| `inbox_item` | `inbox_item` | beacon ID | row account | Inbox/detail inbox context, counters |
| `room_message` | Chat message | beacon ID | author plus admitted/currently authorized room users | Chat, detail activity/unread, Inbox/My Work hints |
| `room_reaction` | message reaction | beacon ID via message | authorized room users | Chat reactions |
| `room_poll` | poll/polling act | beacon ID via linked message | authorized room users | Chat poll results |
| `participant` | participant row | beacon ID | author, changed user, authorized room users | Chat access/people/presence, detail, Inbox/My Work |
| `fact_card` | fact card | beacon ID | visibility-authorized users | Chat/detail/Inbox/My Work hints |
| `blocker` | legacy blocker source if retained | beacon ID | visibility-authorized users | detail/Inbox/My Work |
| `activity_event` | activity event | beacon ID | visibility-authorized users | detail timeline, My Work last activity |
| `coordination_item` | coordination item | beacon ID | item principals and authorized room users | Items/Chat thread/detail/Inbox/My Work |
| `capability` | person capability event | subject user ID | subject and observer | Profile/People capability cues |
| `contact` | user contact | subject user ID | contact viewer only | all contact-name overlays, Friends, Profile, People, forward picker |
| `room_seen` | `beacon_room_seen` | beacon ID | row account only | same-account Chat watermark, Inbox/My Work unread hints and counters |
| `relationship` | vote/trust edge | one affected endpoint user ID per envelope | both endpoints, bounded mutual/shared-context recipients | Friends, Profile controls, People visibility, forward candidates |
| `profile` | user row | subject user ID | self, bounded mutual/shared-context recipients | Profile, People avatars/names |
| `notification` | notification outbox | account ID | outbox account | notification center and count |

Recipient SQL must use current authorization/visibility concepts, not a new
approximation. Reuse shared SQL helpers where available (`beacon_can_read_content`,
active participant/forward/help-offer rules). Private contact names notify only the
viewer. An invalidation must never grant read access; every refetch remains
authorization checked. Trigger recipient sets must be computable from indexed
database relations. Open-screen awareness is not modeled anywhere: SQL triggers
never see open screens, and there is no watch registry (AD-8, revised). A
projection whose subjects fall outside the bounded recipient sets — most
notably an open Graph — converges on the next route entry or manual refresh.

## 9. Implementation sub-goals

### Phase 0: contract and safety tests

1. Add domain tests for entity-kind parsing/mapping, coalescing, connection
   transition generations, and catch-up reasons.
2. Add server migration contract tests that enumerate every attached trigger and
   assert the final function supports its argument.
3. Add a regression test with each fix in the same change. If a gap test must be
   prepared earlier, commit it skipped/tagged with the exact issue-73 phase and
   enable it in the fixing phase; never land an intentionally red CI suite.
4. When editing `InboxCase`, `MyWorkCase`, or related cubits, preserve the
   merged `BookkeepingRefreshSignal` wiring from the debug recalculate-counters
   feature.

Exit gate: the verified gap inventory and test cases are mapped to phases without
landing red tests on `main`.

### Phase 1: typed client synchronization boundary

Create:

- `packages/client/lib/domain/entity/realtime/realtime_entity_change.dart`;
- `packages/client/lib/domain/entity/realtime/realtime_catch_up.dart`;
- `packages/client/lib/domain/entity/realtime/realtime_connection_status.dart`;
- `packages/client/lib/domain/port/realtime_sync_port.dart`;
- `packages/client/lib/domain/use_case/realtime_sync_case.dart`.

Refactor `InvalidationService` to:

- implement `RealtimeSyncPort`, keep its concrete `@singleton` registration
  while compatibility consumers remain, and expose the same instance through an
  injectable module alias provider; remove the alias/concrete dependency only
  after the last compatibility consumer moves in Phase 5;
- parse all supported wire kinds into domain types;
- expose a broadcast typed entity stream, catch-up stream, and connection status;
- deduplicate `(kind, aggregateId)` bursts;
- guard malformed/unknown frames;
- derive reconnect catch-up only after a previously authenticated connection;
- reset safely on auth account switch/disposal; and
- key all catch-up state by the current account identity/epoch emitted from the
  explicit post-auth bind/unbind lifecycle in `RemoteApiClientWs`.

Refactor `RemoteApiClientWs`, the actual owner of ping/pong and the socket, to:

- depend on a data-layer `RealtimeSocketFactory`/`RealtimeSocket` wrapper rather
  than constructing the concrete `web_socket_client.WebSocket` inline. The
  production adapter wraps that package; deterministic fakes expose connection,
  messages, send, and terminal close without leaking transport types into domain;
- remove socket construction from low-level `setAuth`; add an idempotent
  `bindRealtimeAccount(accountId)` called by `AuthRemoteRepository` only after
  signup, seed signin, or cookie-session signin has returned that authoritative
  ID, plus unbind on drop/signout;
- construct/listen to exactly one socket only after credentials and account
  identity are ready, replacing it atomically on account switch;
- emit transport liveness/authentication transitions that the data adapter maps
  to typed domain connection status;
- catch auth-frame build/send exceptions, recognize server auth-error frames,
  enforce the rule-8 auth acknowledgement deadline, and retry/reconstruct under
  the captured account epoch;
- tolerate non-string and undecodable frames with a rate-limited diagnostic;
  malformed transport frames never escape as uncaught zone errors;
- track pong deadlines in its transport mixin;
- on timeout, dispose the terminal socket, construct a fresh `WebSocket`, and
  re-authenticate rather than calling `close()` and waiting for impossible
  self-reconnection; and
- supervise connection-stream completion: while an account remains bound,
  reconstruct with capped jittered backoff after the package exhausts its own
  reconnect timeout; cancel that supervisor on unbind/disposal; and
- tag transitions with `(accountId, connectionEpoch)` so late old-account events
  are discarded. Socket callbacks capture their creation epoch and no-op when it
  no longer matches the active binding.

Keep temporary compatibility getters for existing repositories until all callers
move; mark them for deletion in Phase 5. Do not let domain import
`InvalidationService`.

Exit gate: old tests remain green; DI/codegen succeeds; new port tests prove
mapping, malformed-frame isolation, account-keyed reconnect generation, and no
duplicate catch-up per transition. Transport-mixin tests
prove pong-timeout socket reconstruction/reauthentication and a late old-account
catch-up cannot affect the new account. Auth repository tests prove signup, seed
signin, and cookie-session signin each bind only after obtaining the user ID,
while failure and signout leave no active realtime binding. A fake-socket test
also closes the connection stream after retry exhaustion and proves the
supervisor creates/authenticates one replacement without a tight loop. Further
fake-socket tests prove a first token refresh failure then success, and a server
auth-error then success, both reach authenticated state with exactly one catch-up;
binary/undecodable frames are ignored without closing streams.

### Phase 2: server fan-out completeness and recovery control

Add migration `m0114` (or the next live migration number at implementation time):

1. Replace `notify_entity_change()` with the complete mapping in section 8.
2. Stop removing the actor from `user_ids` in all three publishers, but add the
   default-off server environment flag `REALTIME_ACTOR_ECHO_ENABLED`. While off,
   `WebsocketPathEntityChanges` filters sessions whose account equals the
   non-null `actor_user_id`; after section 16's compatibility gate it sends them.
   This keeps the migration additive and makes rollback a server configuration
   change rather than a pooled-connection GUC or another database migration.
3. Include `actor_user_id` from `tentura.mutating_user_id` in NOTIFY payload.
4. Normalize/deduplicate/null-filter recipients once, split them into bounded
   chunks (initial maximum 100 IDs, verified against encoded payload bytes), and
   call `pg_notify` once per chunk.
5. Add triggers for Inbox, contact, relationship/trust, profile, reaction, poll,
   `room_seen`, and notification outbox entities.
6. Replace or consolidate all three live publishers: `notify_entity_change`,
   `notify_coordination_change`, and
   `notify_help_offer_admission_event_change`. They must use the same recipient,
   actor, chunking, and exception-containment helper.
7. Wrap payload construction and `pg_notify` invocation in an exception boundary
   that converts catchable per-trigger failures to a warning and metric/audit
   signal. Do not claim this prevents PostgreSQL asynchronous queue exhaustion at
   transaction commit; that remains an explicitly monitored residual risk.
8. Use statement-level transition-table triggers or an explicit transaction bulk
   coalescing mechanism for `vote_user`/`user_trust_edge`; never emit one expensive
   recipient query and NOTIFY per trust row during bulk recalculation.
9. Removed (2026-07-14 scope change): the AD-8 watch-grant case and bounded
   WebSocket watch registration are dropped because a stale open Graph is
   accepted. The item number is kept so the critique log's references stay
   valid.
10. Drop obsolete trigger/function combinations only when verified by an
    enumerated live trigger/function contract.
11. Guard the `beacon_room_seen` UPDATE trigger with
    `OLD.last_seen_at IS DISTINCT FROM NEW.last_seen_at` (or equivalent upsert
    predicate) so no-op writes emit no hint.
12. Index every recipient lookup and document `EXPLAIN` cost.

Server service/API changes:

- `PgNotificationService` exposes a typed recovery stream only after recovery,
  not initial startup;
- its concrete `Connection.open` call is behind a data-internal injectable
  connector seam so unit tests can force error/onDone/recovery deterministically;
  PG-tagged tests still exercise a real LISTEN connection;
- `WebsocketRouterBase` subscribes to recovery and broadcasts the catch-up control
  frame to all authenticated sessions;
- `WebsocketSessionHandlerBase` exposes a read-only iterable/snapshot of
  authenticated sessions for that broadcast;
- fan-out validates payload type, ID, event, and recipients before send;
- fan-out owns the temporary actor-echo compatibility filter and logs/metrics
  its enabled mode without logging user IDs;
- listener-recovery catch-up is marked for client jitter;
- recovery broadcast, session registries, and metrics are explicitly
  isolate-local and labeled by worker/isolate;
- logs/metrics include kind, recipient count, recovery count, and malformed
  payload count without logging private content.
- make pong an unconditional protocol response for authenticated sessions and
  deprecate/remove the `PONG_ENABLED` production knob. Liveness correctness must
  not depend on an environment setting that can force healthy reconnect loops;
  test the unconditional response and remove stale configuration documentation.

Update `TenturaDb.withMutatingUser` documentation: it supplies actor context and a
transaction boundary; it no longer suppresses all of the actor's sessions.
Document the NOTIFY transaction discipline alongside it: a transaction that
fires realtime triggers stays short and must not hold hot locks while waiting
to commit, because NOTIFY serializes notifying commits behind a cluster-global
lock (section 13's commit-serialization residual risk).

Exit gate: PG-tagged tests exercise INSERT/UPDATE/DELETE payload production and
verify SQL always includes actor metadata/recipient. Router tests verify both
compatibility mode (actor sessions filtered) and final mode (actor plus other
affected user sessions receive typed hints). Tests enumerate every
trigger argument and every function that publishes `entity_changes`, cover a
several-hundred-recipient Beacon without exceeding the NOTIFY payload limit for
normal operation, cover bulk trust changes without row-level storms, prove a
no-op `room_seen` upsert emits nothing, and prove PG listener recovery sends one
control event but none at startup.
A two-worker WebSocket integration test proves independent LISTEN delivery,
isolate-local session indexes, and recovery catch-up only on the recovering
worker; if CI cannot launch two workers, the test runs in a dedicated integration
job and the single-isolate unit coverage is explicitly insufficient.

### Phase 3: Request, Inbox, My Work, detail, and Chat convergence

#### Request/detail

- Expose Beacon repository changes through `BeaconViewCase`.
- Subscribe `BeaconViewCubit` and route matching remote beacon invalidations
  through its existing full-fetch gate.
- Merge catch-up through `BeaconViewCase`; catch-up always runs a full guarded
  snapshot, while ordinary room changes retain targeted fetches.
- Ensure lifecycle mutations continue using returned server truth/explicit
  refetch and produce no duplicate snackbars/navigation on echo.

#### Inbox

- Make `InboxCase` the only orchestration dependency for Inbox data changes;
  remove direct `ForwardRepository` dependency from `InboxCubit` by exposing typed
  forward/help events through the case.
- Replace ambiguous `ForwardRepository.forwardCompleted` with two closed
  semantics: `forwardChanges` emits after local command success and remote/echoed
  invalidation for silent projection convergence; `forwardCommandCompleted`
  emits only after this process's successful `forwardBeacon`. Migrate
  Forward/PersonForward/BeaconView/MyWork cases to `forwardChanges`; only Inbox's
  `_fetchAndNotifyIfMoved` consumes `forwardCommandCompleted`. Remote or echoed
  invalidations must never create `pendingMovedNudge`.
- Map `inbox_item`, beacon, forward, help, room, and catch-up impacts in the case.
- Add a request-sequence or single-flight guard to `InboxCubit`.
- Silent event refresh retains current rows and reports updated activity to
  `NewStuffCubit`; errors do not replace usable rows or spam snackbars.

#### My Work

- Add catch-up and any missing entity impacts to `MyWorkCase`.
- Keep `_fetchSeq` and per-Beacon coalescing; coalesce global catch-up once.
- Ensure lifecycle, room hints, responsibilities, and last activity are all
  replaced from one coherent load generation.

#### Chat

- Extend `BeaconRoomEntityType` or replace it with typed shared kinds for reaction
  and poll changes.
- Route room message/reaction/poll/participant/fact/coordination invalidations to
  `RoomCubit` through `BeaconRoomCase`.
- Route `room_seen` to the session watermark owner and Inbox/My Work unread
  projections. A read in one account session must cause other sessions to refetch
  the server watermark without broadcasting private read state to other users.
- Keep refresh and write paths one-way: handling a `room_seen` invalidation may
  read the watermark but must never call `markBeaconRoomSeen`; add a repository/
  Cubit test that would fail on such a feedback-loop write.
- Subscribe Room to catch-up and use the existing queued silent reload.
- Preserve optimistic own-message/reaction UI, then reconcile by stable message
  and reaction IDs; never append fetched messages to existing state without ID
  normalization.
- Refresh presence watch membership after participant changes.

Exit gate: focused Cubit tests cover remote and local-actor echo, coalesced bursts,
stale completion prevention, catch-up, error-with-usable-state behavior, and zero
nudges/snackbars/navigation effects from echoed invalidations.

### Phase 4: relationship, Profile, People, and notifications

#### Contacts

- `ContactsCase` listens to contact invalidations and catch-up, refetches the
  viewer's full contact map, updates Drift cache, then emits one store change.
- Preserve local immediate rename/reset behavior.
- Guard account switches so an old account response cannot overwrite the new
  contact store.

#### Friends and Profile

- Add `FriendsCase` to orchestrate friends, capabilities, invitations, presence,
  contacts, and real-time changes; make `FriendsCubit` depend on it rather than
  five data repositories.
- Replace direct mutation of `state.friends` with immutable map copies.
- Add `ProfileViewCase` for profile, Like, capability, contact, and relationship
  refresh; make `ProfileViewCubit` thin and guarded.
- Own-profile `ProfileCubit` listens through `RealtimeSyncCase`/its use case for
  matching profile invalidation and catch-up.
- `ProfileSharedBeaconsCubit` refreshes on matching beacon/forward/help and
  catch-up signals without full-screen flicker.
- Beacon People remains driven by `BeaconViewCubit`; relationship/profile events
  trigger the minimum People/profile refresh required by its projection.

#### Graph

Removed from issue 73 (2026-07-14 scope change): the Graph screen gets no live
event routing, no realtime subscription, and no watch protocol. It renders a
fresh authoritative snapshot on route entry and manual refresh; an open Graph
may go stale because the user is not supposed to linger there. The `GraphCase`
boundary refactor is therefore no longer required by this plan; the existing
multi-repository `GraphCubit` exception may be cleaned up as separate
structural work.

#### Notification center and counters

- Add a small `NotificationCenterCase` and repository change stream.
- Refresh the open center and any global unread-count owner on notification
  invalidation/catch-up.
- Keep mark-read optimistic by ID; remote echo/catch-up must not re-run UI effects.
- Confirm Inbox/My Work activity reporters update global dots after silent loads.

The `FriendsCase` and `ProfileViewCase` boundary refactors are
independently mergeable changes. Their implementation order must not block the
already-complete Request/Inbox/Chat phases, but Phase 4 is not accepted until
those exceptions are removed and event routing uses the cases.

Exit gate: focused tests prove contact rename in a second session, friendship
add/remove, profile visibility change, notification arrival/read, and
catch-up with no stale overwrite.

### Phase 5: lifecycle UX, cleanup, and documentation

- Native `LifecycleHandler` requests catch-up on `AppLifecycleState.resumed`.
- Web `LifecycleHandler` requests catch-up when `document.visibilityState`
  becomes visible.
- Add a global `RealtimeStatusCubit`/presenter and design-system-compliant delayed
  reconnect banner.
- Remove `BeaconRoomLocalChangeBus` and specialized compatibility streams only
  after all source and consumer tests use the shared boundary.
- Update `DEV_GUIDELINES.md` entity matrix, actor semantics, catch-up protocol,
  checklist for new state-bearing entities, the NOTIFY transaction discipline,
  and the commit-serialization risk with its outbox fallback (sections 13, 16).
- Add an architecture test/lintable manifest requiring every wire kind to have:
  server trigger mapping, client enum mapping, impact mapping, and test.
- Document observability dashboards/log queries and local test procedure.

Exit gate: no production Cubit imports `data/service`; no new multi-repository
Cubit exception; no orphaned local bus; docs match the final protocol.

### Phase 6: automated simultaneous-client proof

Add a Dart `webdriver` multi-session test that reuses the repository's existing
Chromedriver and Flutter web dev-server infrastructure. Do not add an unsupported
Node/Playwright toolchain and do not model two users by logging one app in and
out. Deliver `scripts/run_realtime_multiclient_web_local.sh` in this phase; it
starts one build/server plus Chromedriver, then the Dart driver creates two
independent WebDriver sessions/profiles.

Test setup:

- use `/_qa/integration/bootstrap` for unique author/helper users;
- launch two isolated WebDriver sessions at the same Flutter web build/proxy;
- authenticate one session as author and the other as helper;
- enable Flutter web semantics and use stable accessibility/TestId selectors;
- subscribe to console/network diagnostics and fail on uncaught Flutter errors;
- use condition-based waits, never fixed sleeps for state convergence.

Add a QA-gated V2 integration endpoint beside `/_qa/integration/bootstrap` that
can suspend/resume WebSocket authentication for a specified bootstrapped QA user
and force-close that user's current sessions. Its QA-only in-memory deny entry
creates a deterministic missed-event window; resume removes the entry so the
normal client transport can recreate/authenticate its socket. It is registered
only when the existing QA integration mode and token checks pass, accepts only
users issued by that bootstrap run, returns the number of sessions closed, is
isolate-local for the single-worker local runner, and exposes no production
route. The test confirms suspension/closure before mutating and always clears
the deny entry in teardown.

Critical journey:

1. Keep helper Inbox open. Author creates/publishes/forwards. Assert one matching
   helper Inbox card appears without navigation/reload.
2. Keep author Request People open. Helper offers help. Assert the offer and
   correct response controls appear without navigation/reload.
3. Admit/auto-admit helper. Keep both Chat views open. Helper sends a unique
   message. Assert author sees exactly one bubble and unread/dot state converges.
4. Author changes Request lifecycle/closure. Keep helper My Work/detail open.
   Assert status and card move/update without reload.
5. Use the QA endpoint to force-close the helper's socket, hold reconnect behind
   a test-only reconnect gate, mutate from author during the confirmed gap,
   release the gate, and assert authenticated reconnect/catch-up reaches final
   state equality without duplicate stable IDs/effects. The gate belongs to the
   QA transport harness, not production domain behavior. The number of idempotent
   refetches is not a user-visible exactly-once contract.
6. Exercise a contact/friendship change with Profile already open and assert
   visibility/control convergence.
7. For each critical command, assert pending controls are disabled, a forced HTTP
   failure surfaces the established error UI without a false success effect, and
   successful commit converges without a duplicate effect from its echo.

Keep existing single-client Flutter integration tests for workflow depth. The new
test specifically owns concurrency and reconnect behavior. Add it to the local
integration runner and a CI job with artifacts (screenshots only on failure,
browser logs, server log, and timing) once stable.

Exit gate: the multi-client test passes repeatedly (minimum 5 local consecutive
runs) without reload APIs and fails when live delivery/catch-up is deliberately
disabled.

## 10. Concurrency, ordering, and duplicate rules

- A WebSocket hint never directly appends a domain item; it schedules a snapshot.
- Lists are replaced or merged by stable server IDs with deterministic ordering.
- A silent refresh cannot emit if its request generation is stale.
- A second signal during an in-flight refresh queues at most one rerun.
- One semantic mutation may touch several tables. Projection-level coalescing
  must collapse the resulting burst before network reads.
- UI effects are created only by the initiating command result, never by
  invalidation/catch-up refresh.
- Optimistic data is tagged/identifiable and reconciled against returned/fetched
  stable IDs; failures restore server truth.
- Deletes and lost authorization are valid snapshots: remove inaccessible items,
  close/disable affected controls, and show the existing not-found/access UX.
- Account switch cancels or invalidates all old-account refresh generations.

## 11. Failure and UX behavior

| Situation | Required behavior |
|---|---|
| WebSocket briefly reconnects | no UI flicker/banner; reconnect and catch up |
| WebSocket down >2 s | non-blocking localized live-updates-paused banner |
| HTTP available, live channel down | reads/writes continue; successful command result is shown |
| Background refresh fails with existing data | retain data, log once, retry on next signal/resume/manual action |
| Initial load fails | existing screen error/retry pattern |
| Permission revoked remotely | next hint/catch-up removes/locks projection using authoritative response |
| malformed/unknown event | ignore safely, rate-limited warning/metric |
| PG LISTEN reconnects | server broadcasts catch-up control to every authenticated session |
| duplicate hint/echo | coalesced idempotent refetch; no duplicate row/effect |

## 12. Security and privacy review gates

- Trigger recipient SQL must be reviewed against `CONTEXT.md` visibility rules.
- Contact invalidations target only the viewer; never notify the named subject.
- Wire payloads contain IDs and operation metadata, not private message/contact
  content.
- A hint confers no authorization; all data reads execute existing auth checks.
- Removed users may receive a final invalidation to learn they lost access, but
  the subsequent query must deny/private-filter content.
- Profile/relationship fan-out must avoid global broadcast. Notify endpoints and
  currently authorized shared-context users only; use indexed recipient queries.
- QA socket suspension/closure routes are absent outside QA integration mode and
  require the existing QA token plus a bootstrap-issued user identity.
- Logs do not include message bodies, contact names, tokens, or raw auth frames.

## 13. Observability and performance budgets

Add metrics/log fields for:

- PG notifications by kind and recipient count;
- WebSocket fan-out sends/failures by kind;
- authenticated disconnect duration and reconnect count;
- catch-up count by reason;
- catch-up-driven projection fetch count per client and per 10-second server
  recovery window;
- entity coalescing input/output counts;
- projection refresh duration/failure/stale-drop count;
- unknown/malformed event count.
- `pg_notification_queue_usage()` sampled/alerted server-side, with warning and
  critical thresholds well before PostgreSQL can fail a transaction at commit;
- sampled `pg_stat_activity` waits on the NOTIFY commit lock (heavyweight
  `Lock: object` on database object 0, LWLock `NotifyQueue`), with an alert on
  sustained waiter counts, plus p95 commit latency of write transactions.

Initial budgets to verify under tests/profiling:

- connected live update visible p95 <= 1.5 s on local/staging normal load;
- reconnect/resume convergence p95 <= 3 s after authenticated connection;
- one semantic mutation causes at most one concurrent fetch per active
  projection and at most one queued rerun;
- server listener recovery does not start more than one catch-up fetch per active
  projection per client generation, and 0-3 second jitter spreads aggregate
  recovery load;
- every encoded NOTIFY payload remains below the configured safe byte ceiling,
  including the maximum tested recipient batch;
- notification queue usage remains below the chosen warning threshold in load
  tests; queue exhaustion at commit is a documented residual operational risk,
  not hidden by trigger exception wording;
- NOTIFY commit-lock waits stay in the low single-digit milliseconds at p95
  under load tests; sustained p95 waits above 50-100 ms trigger the section 16
  outbox-fallback decision;
- no loading skeleton replaces usable content during background sync;
- trigger recipient lookup plans use indexes and avoid full user-table scans.

### NOTIFY commit serialization: second residual risk (added 2026-07-14)

`pg_notify` queues notifications in backend memory; the cost lands at commit.
`PreCommit_Notify` takes a single cluster-global exclusive lock on the
notification queue and holds it through the commit's WAL flush so that
notifications enter the queue in commit order. Consequences (see the
pgsql-hackers report referenced in the section 18 addendum):

- all notifying commits serialize cluster-wide; group commit does not apply to
  them, so the write ceiling is roughly 1 / fsync-time (thousands per second
  on local NVMe, 200-500/s on cloud disks with 2-5 ms fsync);
- a transaction that holds ordinary row/table locks while waiting on the
  notify lock extends those locks, stalling transactions that never use
  NOTIFY at all.

Because issue 73 makes practically every write transaction a notifier, this is
a ceiling on total write throughput, not on the realtime subsystem alone. It is
invisible to `pg_notification_queue_usage()` (that catches slow listeners, a
different failure mode) and is watched only by the commit-lock wait metrics
above. At current single-database write volumes the risk is dormant; the
reference report involved ~100 databases at 8000 qps on a shared cluster.

Discipline required of all write paths:

- a transaction that fires realtime triggers stays short and must not hold hot
  locks while waiting to commit; bulk writes (trust recalculation, data
  migrations, `seed_society`) rely on the statement-level coalescing triggers
  and must never emit per-row hints;
- synchronous replication is incompatible with this transport: the lock hold
  time grows to the replication RTT, collapsing the write ceiling. The
  section 16 outbox fallback must be adopted before enabling a synchronous
  standby.

## 14. Verification matrix

### Unit and layer tests

- server trigger/function contract for every wire kind;
- server recipient calculation and actor inclusion;
- PG listener recovery control broadcast;
- client wire parser, unknown/malformed messages, coalescing, connection state;
- each feature case's entity-impact filtering;
- each Cubit's silent refresh, single-flight/sequence behavior, disposal, and
  background error behavior;
- immutable state updates for Friends/Profile surfaces;
- reconnect and resume catch-up generation.
- `room_seen` invalidation does not write another watermark.

### Integration tests

- server PG-tagged trigger-to-NOTIFY tests;
- WebSocket two-session same-account fan-out;
- WebSocket affected-other-user fan-out and unauthorized-user exclusion;
- two-worker independent LISTEN/fan-out plus isolate-scoped recovery behavior;
- client repository/use-case integration with fake typed sync port;
- simultaneous two-WebDriver-session critical journey and QA-forced
  missed-event/reconnect case.

### Required commands

```bash
cd packages/tentura_lints && dart test
cd packages/server && dart run build_runner build -d
cd packages/server && dart analyze --no-fatal-warnings
cd packages/server && dart test --exclude-tags pg
cd packages/server && dart test --tags pg
cd packages/client && flutter gen-l10n
cd packages/client && dart run build_runner build -d
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env
bash scripts/check-user-facing-terminology.sh
bash scripts/check-doc-drift.sh
bash scripts/run_client_integration_web_local.sh
bash scripts/run_realtime_multiclient_web_local.sh
git diff --check
```

For final browser verification, run the real local stack through the repository's
supported web origin/proxy, inspect semantics/DOM and logs, and prove no manual
reload occurred. Generated code is inspected through source/codegen success, not
edited manually.

## 15. Acceptance evidence checklist

| Requirement | Authoritative proof |
|---|---|
| Forward appears in recipient Inbox | two-context test with helper Inbox already open |
| Offer/response updates all affected users | two-context People/detail assertions on both sides |
| Chat message appears live | two open Chat contexts, unique message ID/text count is exactly one |
| Contact/visibility updates surfaces | two-context Profile assertion plus feature tests |
| Request status updates all surfaces | helper My Work/detail remains open during author closure |
| Reconnect catches up | offline context misses mutation, reconnects, reaches final snapshot |
| No duplicates | stable IDs/count assertions after live echo and reconnect |
| Same-account tabs converge | WebSocket/session integration plus optional two-context same-login test |
| Same-account unread converges | one tab reads Chat; the other tab's Inbox/My Work unread state clears after `room_seen` invalidation |
| Command state is trustworthy | pending controls, forced failure UI, committed success, and zero echo-generated effects |
| Architecture remains clean | lints, import checks, Cubits depend on cases/ports |
| UX does not regress | no skeleton flicker on silent refresh; delayed reconnect banner test |

Issue 73 is complete only when every row has current evidence. Passing unit tests
alone or showing one screen refresh is insufficient.

## 16. Rollout and rollback

1. Deploy additive server changes first: compatible envelope fields, byte-safe
   chunking, catch-up control, and new kinds/triggers. SQL
   includes actor recipients, but deploy with router flag
   `REALTIME_ACTOR_ECHO_ENABLED=false` so old-client behavior remains unchanged.
2. Deploy the client version containing the typed boundary and the Phase 3
   `forwardCompleted` command-result/invalidation split. Prove remote forward
   invalidations cannot create `pendingMovedNudge` on that version.
3. Run dev/staging multi-client tests and inspect fan-out, queue, reconnect,
   and projection-fetch metrics. Canary the compatible client while actor
   suppression remains enabled.
4. Set `REALTIME_ACTOR_ECHO_ENABLED=true` only after `MIN_CLIENT_VERSION` is at
   least the first version containing the command/invalidation split and
   active-session telemetry reports zero older versions for 24 hours. This is a
   hard compatibility gate, not an assumption that old behavior is idempotent.
5. Canary actor echo separately with alerting on duplicate effects, WebSocket
   errors, refresh storms, PG trigger latency, and queue usage. Keep the protocol
   envelope backward compatible and gate only optional status UX if needed.
6. Database rollback is another forward migration/configured function version;
   applied raw SQL migrations are not reversed in place. Use separate kill
   switches: disabling `REALTIME_ACTOR_ECHO_ENABLED` restores router-side actor
   filtering without changing SQL or disabling new kinds/catch-up, while per-kind
   switches disable only a faulty new trigger.
7. Designated transport fallback: transactional outbox. If NOTIFY commit-lock
   waits sustainedly exceed the section 13 threshold (p95 above 50-100 ms), or
   write load approaches the measured serialization ceiling, replace the body
   of `emit_realtime_entity_change` — the single emission point since `m0114`
   — with an INSERT into an outbox table via a forward migration, and add a
   server-side dispatcher that reads the outbox (a 100-250 ms poll interval
   fits the p95 <= 1.5 s budget; the client-polling ban does not cover a
   server-internal outbox reader). The wire protocol, the client, and the AD-1
   semantics (at-least-once hints plus idempotent refetch) are unchanged.
   Enabling a synchronous Postgres standby requires this migration first.

## 17. Definition of done

- every issue acceptance criterion has the evidence in section 15;
- every state-bearing entity in section 8 has server production, typed client
  routing, an owning use case/Cubit, and a test;
- reconnect, app resume, and PG listener recovery each trigger convergence;
- actor sessions are no longer excluded from server fan-out after the rollout
  compatibility gate is satisfied;
- no active screen depends on manual page refresh or route re-entry;
- no new layer violation, direct WebSocket parsing, polling, global derived-state
  bus, generated-file edit, or multi-repository Cubit exception exists;
- all verification commands pass and real two-browser runtime behavior is proven;
- docs and issue evidence are current.

## 18. Critique and revision log

This section is append-only for the three required Claude Code critique loops.
Each loop records the verbatim critic output (subject to normal secret/path
redaction), then a concrete revision summary. The plan body is revised after each
critique; later critics review the complete revised file including earlier notes.

### Loop 1

Critique:

Findings verified; hostile critique follows. (Verdict: the
invalidation-plus-catch-up architecture is defensible and most of the audit is
accurate, but the plan ships five High-severity defects: a transaction-aborting
NOTIFY risk, a missed third suppression function plus a false audit claim, a
dropped issue requirement, a missing read-watermark producer that falsifies
section 15's same-account claim, and a UI-effect conflation that AD-3 will
detonate.)

**Severity legend:** H = must fix before implementation; M = fix during the named
phase; L = wording/scope.

#### H1. `pg_notify` can abort the user's write transaction; the plan widens the blast radius

`packages/server/lib/data/database/migration/m0072.dart` wraps every recipient
`SELECT` in `BEGIN/EXCEPTION`, but the final `PERFORM pg_notify(...)` (m0072,
step 6, bottom of `notify_entity_change()`) is bare. Postgres NOTIFY payloads are
hard-capped at approximately 8000 bytes; an oversized `user_ids` array raises
inside an `AFTER` trigger and rolls back the originating mutation. Today's
fan-outs (room participants plus forward chain) already approach risk; section 8
adds `profile` to "users with an active authorized relationship/shared context"
and `relationship` fan-outs that make large arrays routine, and AD-3 stops
removing the actor, growing every array by one or more. Neither section 9 Phase 2
nor section 13 budgets payload size. **Revision:** in the `m0114` function, chunk
`user_ids` into bounded batches (one `pg_notify` per at most approximately 100
IDs), wrap the `PERFORM` in its own exception handler so notification failure can
never fail the write, and add a Phase 2 PG-tagged contract test with a
several-hundred-recipient beacon.

#### H2. Phase 2 misses the third echo-suppressing function; the section 4.3 trigger-inventory claim is false

There are **three** functions publishing to `entity_changes`, all stripping
`tentura.mutating_user_id`: `notify_entity_change()` (m0072),
`notify_help_offer_admission_event_change()` (`m0113.dart:37`), and
`notify_coordination_change()` (`m0063.dart:312`, which emits entity `help_offer`
for `beacon_help_offer_coordination` rows). Section 9 Phase 2 replaces the first
(item 1) and the admission function (item 6) but never names
`notify_coordination_change`, so after Phase 2, coordination writes still
suppress the actor and the same-account second-tab bug AD-3 exists to fix persists
for exactly the help-offer coordination flow issue 73 complains about.
Separately, section 4.3's claim "the final trigger function also no longer
handles the historical `commitment` branch while an old trigger may still
exist" is **wrong**: `commitment_entity_notify` was dropped at `m0063.dart:30`
and `coordination_item_message_entity_notify` at m0072 step 7; no orphaned
trigger exists. **Revision:** replace the speculative section 4.3 sentence with
the verified three-function inventory, and make Phase 2 route all three (or their
replacements) through one shared recipient-normalization/emit path with a
contract test enumerating every function that calls
`pg_notify('entity_changes', ...)`.

#### H3. An observed failure from issue 73 is silently dropped: per-action failed/pending/committed visibility

Section 2 lists "users cannot distinguish failed, pending, and
committed-but-not-synchronized actions" among the issue's observed failures, but
none of the seven carried acceptance criteria covers it, section 15 has no
evidence row for it, and AD-7's reconnect banner is channel-level, not
action-level. A user who taps "offer help" while the WS is up but the HTTP write
fails silently is untouched by this plan. A plan that quotes a failure and then
never addresses or de-scopes it will fail its own Definition of Done honesty
test. **Revision:** either add an explicit, justified non-goal (per-mutation
pending/failed affordances are out of scope because existing command paths
already surface errors via `UiEffectPort.ShowError`, with evidence) or add an
acceptance criterion plus section 15 row for per-action state visibility.

#### H4. Section 15 "Same-account tabs converge" is unachievable: no producer for read watermarks

`beacon_room_seen` (created in m0072) carries the read watermark, has **no**
trigger, and section 8's matrix contains no read-state kind. Client unread
resolution (`InboxCase.resolveRoomUnread` to `BeaconRoomCase.resolveUnread`) is
session-local. Therefore reading Chat in tab A can never clear the unread dot in
tab B, yet section 15 claims same-account tab convergence as acceptance evidence,
and Phase 6 step 3 asserts "unread/dot state converges". **Revision:** add a
`room_seen` wire kind to section 8 (source `beacon_room_seen`, aggregate = beacon
ID, recipients = the row's `user_id` only) with a trigger in `m0114`, or
explicitly exclude same-account unread convergence from section 15 and Phase 6.

#### H5. `forwardCompleted` conflates command results with invalidations; AD-3 turns that into duplicate UI effects

`ForwardRepository` feeds `_forwardCompletedController` both from local mutation
success (`forward_repository.dart:139-141`) and from remote
`InvalidationService.forwardInvalidations` (`forward_repository.dart:61-67`).
`InboxCubit._fetchAndNotifyIfMoved` (`inbox_cubit.dart:113-148`) derives a
user-visible nudge (`pendingMovedNudge`) from that stream. Once AD-3 delivers the
actor's own echo, every forward the user sends re-fires the nudge evaluation from
an invalidation, directly violating section 10's "UI effects are created only by
the initiating command result." Phase 3's Inbox bullet (remove direct
`ForwardRepository` dependency) does not name this split, so an implementer can
satisfy the bullet while preserving the defect. **Revision:** Phase 3 must
explicitly separate a command-result stream (`forwardSucceeded`, fed only by
`forwardBeacon`) from typed forward invalidations exposed via `InboxCase`, and add
a test asserting an echoed forward invalidation produces zero nudges/snackbars.

#### M1. Catch-up trigger enumeration misses zombie connections

AD-4's reasons (reconnect, resume, LISTEN recovery) all presuppose the client
notices disconnection. `RemoteApiClientWs` sends pings (`_onTimer`) but
`_onMessage` uses `pong` only to extract `min_client_version`
(`remote_api_client_ws.dart:154-163`); there is no pong deadline, so a half-open
TCP path leaves the app "connected", receiving nothing, firing no catch-up.
Foreground-resume catch-up masks this only for backgrounded apps, not for a
visible screen. **Revision:** add to Phase 1/5 a pong-liveness watchdog (N missed
pongs causes forced socket close, library reconnect, and the existing
`webSocketReconnected` catch-up) plus a unit test, and list `pong timeout` as a
catch-up reason.

#### M2. Catch-up is a thundering herd with no damping

Section 7.2 broadcasts catch-up to **all** authenticated sessions after LISTEN
recovery, and every active cubit then refetches every active projection at once.
Section 13's budgets measure single-client latency only; section 16.5 alerts on
refresh storms after they happen. **Revision:** specify client-side jitter
(random 0-3 s delay before acting on a server-initiated catch-up; none for local
resume), and add herd metrics (catch-up-driven fetch count per 10 s window) to
section 13 with a budget.

#### M3. Per-row triggers on `vote_user`/`user_trust_edge` will storm under bulk trust writes

MeritRank scores are written via `trust_apply_evidence`/`user_trust_edge`
(m0088), and the merged `userRecalculateBookkeeping` mutation
(`packages/server/lib/api/controllers/graphql/mutation/mutation_user.dart`) can
rewrite many edges in one transaction. A `FOR EACH ROW` trigger per section 9
Phase 2 item 5 means N recipient queries plus N NOTIFYs per recalculation.
**Revision:** for `relationship`, require statement-level triggers with transition
tables (or a bulk-suppression GUC emitting one coalesced invalidation per affected
endpoint), and add a bulk-write fan-out test to the Phase 2 exit gate.

#### M4. Section 8's `relationship`/`profile` recipient rules are not implementable in a trigger

"Broader graph watchers only if authorized" and "users with an active authorized
relationship/shared context" require knowing who is currently watching; the
server has no such registration (the `watch_authors` idea in `DEV_GUIDELINES.md`
is explicitly unbuilt), and a trigger cannot see open screens. As written,
section 8 invites either a global broadcast (banned by section 12) or an unstated
new subscription protocol. **Revision:** define recipients as bounded, computable
sets (edge endpoints; friends via `vote_user`/`user_trust_edge`;
co-participants/shared-Beacon users), explicitly accept third-party Graph
staleness until the viewer's next catch-up/resume, and defer watcher registration
to a separate ADR.

#### M5. Phase 0's "failing client tests" exit gate is unexecutable

`.github/workflows/pipeline.yml` runs `flutter test` on every push to `main`;
landing red tests blocks the pipeline. **Revision:** land gap tests skipped/tagged
with an issue-73 phase reason and flip them in the phase that fixes each gap, or
land test and fix in the same change; reword the exit gate accordingly.

#### L1. Wire-envelope inconsistencies

(a) Section 8's `relationship` row says "payload also carries peer if needed",
but section 7.1 defines a closed envelope. Either add an optional `peer_id` field
or delete the clause. (b) Section 7.1 says notification uses the recipient account
ID or outbox row ID; section 8 says account ID. Pick account ID. (c) State
explicitly that `actor_user_id` is null for Hasura/console-origin writes, so no
client logic may treat null as "not me".

#### L2. Rollout/rollback wording

Section 16.6 "restoring the previous function" implies reversible migrations;
this schema uses forward-only raw SQL migrations. Rollback is a new forward
migration re-creating the m0072 function body. Reword, and name re-enabling actor
suppression as the kill switch.

#### L3. Phase 6 assertion phrasing

"Assert catch-up reaches final server state exactly once by stable IDs" is not
observable for refetch-based convergence; assert final state equality and absence
of duplicate IDs/effects, allowing any number of idempotent refetches. Also,
Playwright `context.setOffline(true)` does not promptly kill an established
WebSocket; the test must force-close it through CDP network emulation/socket
termination or the missed-change precondition is flaky.

#### L4. Phase 4 scope discipline

`GraphCase`/`FriendsCase`/`ProfileViewCase` are justified because they cure real
multi-repository Cubit exceptions, but only event routing is required by issue
73's relationship acceptance criterion. Mark structural refactors as
independently mergeable so a Phase 4 stall cannot hold the other acceptance
criteria hostage.

#### Verdict on lossy invalidation plus snapshot catch-up versus durable replay

**Defensible here, conditionally.** The client has no offline writes, every
projection is refetch-based, and the server snapshot is the sole source of truth.
A durable per-user event log would add cursors, acknowledgements, retention, and a
second data model with no consumer: any missed-event window is fully healed by one
snapshot read, which durable replay would still have to reconcile. The plan's
separate-ADR escape hatch for an audit feed or offline mutation is the right
boundary. The argument stands only if loss-boundary enumeration is complete and
catch-up is affordable. The pong watchdog and catch-up herd damping are therefore
required.

#### What is sound

- The section 4.1 transport description and file paths are accurate, including
  `WebsocketPathEntityChanges.fanOutEntityChange` and the per-user session index.
- The client audit is accurate: web visibility handling is empty; Inbox lacks a
  fetch sequence; My Work has one; Room has single-flight; Beacon View does not
  subscribe to Beacon changes.
- Every named missing entity exists in the current database history.
- AD-1/AD-2 respect the enforced boundaries; the domain-owned port with
  `InvalidationService` as adapter is the correct inversion.
- AD-3's core rationale is correct: user-wide suppression cannot update a second
  tab/device.
- The migration number, QA bootstrap path, test environment file, and verification
  commands match the current repository.
- Rejecting Hasura subscriptions, polling, and a client-derived-state bus matches
  `DEV_GUIDELINES.md`.

Revision:

- Added an eighth acceptance criterion and evidence row for command-level
  pending/failure/committed behavior, separate from live-channel status.
- Corrected the server audit to the three actual suppressing publisher functions
  and removed the false orphaned-commitment-trigger claim.
- Added `room_seen` production/consumption and same-account unread convergence.
- Required bounded byte-safe NOTIFY chunking, notification exception containment,
  a several-hundred-recipient PG test, and a bulk-safe statement/coalesced trust
  trigger design.
- Added pong liveness timeout, reconnect catch-up, server-recovery jitter, herd
  budgets, and watch re-registration.
- Added the bounded active-subject watch protocol so an already-open Graph/Profile
  can react to relevant third-party changes without global broadcast.
- Required command-result and invalidation streams to be separated, specifically
  preventing echoed forwards from generating `pendingMovedNudge` or other UI
  effects.
- Reworded Phase 0 to keep CI green, made structural Phase 4 refactors
  independently mergeable, fixed wire-envelope null/ID semantics, made the
  reconnect test force a real socket loss, and corrected forward-only rollback
  language.

### Loop 2

Critique:

Findings verified against the live tree; hostile critique follows. The Loop 1
revision landed: the three-publisher inventory, chunking/containment direction,
`room_seen` kind, command/invalidation split, and CI-safe Phase 0 all match the
code. The revision nevertheless introduced or exposed four new high-severity
defects: AD-8's registration authorization does not transfer from the presence
precedent and leaks activity metadata, rollout ordering reintroduces the nudge bug
on old clients, Phase 1 assigns the pong watchdog to a component that cannot see
pongs or recreate the socket, and the server design ignores production's
multi-isolate topology.

**Severity legend:** H = must fix before implementation; M = fix during the named
phase; L = wording/scope.

#### H1. AD-8 registration authorization is undefined and leaks activity metadata

The presence path authorizes every requested peer ID server-side against indexed
relations before registering it (`websocket_path_user_presence.dart:44-59` uses
`friendshipLookup.reciprocalPositivePeerIds` and
`coParticipantLookup.coParticipantPeerIds`). No analogous indexed relation exists
for arbitrary third-party Graph nodes because their visibility comes from
MeritRank output. AD-8's statement that use cases register IDs returned by an
authorized query is only a client promise. A malicious session could register
arbitrary user IDs and observe timing of their relationship/profile changes; the
timing is itself private metadata. The plan also lacks watch revalidation after
visibility loss, uses an O(events times sessions) scan if copied from presence,
and would send a full `subject_ids` batch to a session authorized for only one ID.
**Revision:** authorize watches server-side using a server-issued, TTL-bound grant
from the same query that produced the snapshot, or restrict subjects to cheap
server-verifiable relations. Add a reverse `subjectId -> sessions` index,
per-session payload intersection, `subject_ids` byte chunking, expiry/revalidation,
and explicit privacy review gates. Trigger the existing return-to-architecture
escape hatch if grant authorization cannot be cheap.

#### H2. Rollout order reintroduces the nudge defect on deployed old clients

Section 16 says server support may ship before or with client support and calls
old-client effects idempotent. Deployed clients feed remote forward invalidations
into `forwardCompleted` (`forward_repository.dart:61-67`) and derive
`pendingMovedNudge` from it (`inbox_cubit.dart:37-40,113-148`). Removing actor
suppression before those clients contain the Phase 3 split creates a user-visible
effect regression. **Revision:** deploy additive kinds/chunking/new triggers
first; deploy the client command/invalidation split next; remove actor suppression
only after that client version reaches a defined rollout threshold. Tie the
function-version kill switch specifically to this final step.

#### H3. The pong watchdog is assigned to the wrong layer and explicit close is terminal

Phase 1 asks `InvalidationService` to track pongs and force-close the socket. It
only consumes `webSocketMessages`, while `RemoteApiClientWs._onMessage` consumes
pongs internally (`remote_api_client_ws.dart:154-163`). It has no socket handle.
Moreover, `web_socket_client.close()` is terminal; `_dropAuth` nulls the instance,
so "force-close and let the library reconnect" is not implemented behavior.
**Revision:** put the watchdog in `RemoteApiClientWs`, which owns ping/pong and the
socket. On expiry it must dispose and explicitly create a new `WebSocket`, then
authenticate through the normal connection path. Expose typed liveness/status to
the domain port; `InvalidationService` maps it. Test the transport mixin rather
than pretending the adapter owns recovery.

#### H4. The plan models one server process while production uses multiple isolates

`App.run` uses `env.isolatesCount` (`app.dart:35-39`), production derives that
from `workersCount` (`env.dart:372`), and every worker configures its own
`PgNotificationService`, router, session map, presence map, and future watch map.
Tabs for one account can land on different isolates. Entity delivery works because
every isolate independently LISTENs; listener recovery catch-up correctly targets
only sessions on the recovering isolate. Metrics and watch indexes are also
per-isolate. Existing debug tests use one isolate and cannot prove this topology.
**Revision:** document N isolates with one LISTEN/router/session registry each,
scope recovery catch-up to the recovering isolate, label metrics by isolate, and
add a two-worker WebSocket integration proof or a rigorous justification for a
single-isolate test.

#### M1. Trigger exception handling cannot prevent commit-time NOTIFY queue failure

An exception boundary catches payload/recipient failures at `PERFORM pg_notify`,
but Postgres asynchronous queue-full failure may surface at commit, outside the
trigger block. **Revision:** narrow the guarantee to catchable failures, document
queue-full as residual operational risk, monitor `pg_notification_queue_usage()`,
and alert before commit failure becomes possible.

#### M2. `room_seen` will emit for no-op upserts and needs a no-feedback-loop invariant

The mark-seen upsert unconditionally runs `DO UPDATE SET last_seen_at =
EXCLUDED.last_seen_at` (`beacon_room_repository.dart:957-967`), so an AFTER UPDATE
trigger fires even when unchanged. Under actor fan-out this can repeatedly cause
Inbox/My Work refetches. The current code avoids a write loop only because
`_fetchRoomData` does not call `markSeenNowIfNeeded`, an untested invariant.
**Revision:** guard the trigger with `WHEN (OLD.last_seen_at IS DISTINCT FROM
NEW.last_seen_at)` or guard the upsert update; test that a `room_seen`
invalidation may refetch but never performs a mark-seen mutation.

#### M3. The simultaneous-client runner and forced-disconnect mechanism remain undefined

There is no supported Playwright/Node project in the repository. The existing
harness is Flutter Drive plus Chromedriver and drives one app. CDP network
emulation also does not deterministically terminate an established WebSocket.
**Revision:** name the harness. Prefer a Dart `webdriver` two-session runner that
reuses the existing Chromedriver/dev-server infrastructure; choosing Node is an
explicit tooling-policy exception. Add a QA-gated server endpoint alongside
`/_qa/integration/bootstrap` that force-closes a user's WebSocket sessions to
create a deterministic missed-event window and prove cleanup. Mark the new script
in section 14 as a Phase 6 deliverable.

#### M4. Reconnect generation has no account-identity input

`InvalidationService` sees an identity-free state stream; auth frames are consumed
inside `RemoteApiClientWs`. It cannot key generations by account or discard an
old-account reconnect after switch. **Revision:** Phase 1 must inject both typed
connection status and current-account identity (or expose identity through
`setAuth`/`dropAuth` hooks), key generation by `(accountId, connectionEpoch)`, and
test a late old-account catch-up after switch.

#### M5. Domain layout and DI/codegen details contradict project conventions

AD-2 says the boundary lives under `lib/domain/realtime`, while Phase 1 puts the
case in `lib/domain/use_case`. Existing convention is
`domain/entity`, `domain/port`, and `domain/use_case`. Also,
`InvalidationService` must be registered `@Singleton(as: RealtimeSyncPort)` and
codegen rerun. **Revision:** use the conventional paths and make registration plus
codegen part of the Phase 1 exit gate.

#### L1. Relationship aggregate is plural against a single-ID envelope

Section 7 defines one `id`; section 8 says affected endpoint IDs. Emit one
projection invalidation per endpoint (`id` is that endpoint), while a bounded
`subject_ids` batch is used only for watch routing.

#### What now holds up

- The three-publisher inventory and bare `pg_notify` call sites are correct.
- `room_seen` matches the schema and existing write path already supplies actor
  context.
- The forward command/invalidation split names the real defect sites.
- AD-8's replace-not-union and session cleanup correctly mirror presence; only
  authorization/indexing are incomplete.
- The control frame and added fields are backward compatible with old clients.
- Phase 0, forward-only rollback, jitter, and herd budgets are coherent.

Revision:

- Replaced client-attested AD-8 subject lists with short-lived server-issued
  projection grants. The Graph grant re-runs the authenticated
  `public.graph`/`mr_graph` context, other grants reuse existing V2 authorization,
  and registration now has signature/account/TTL/count/byte checks, reverse
  indexes, exact per-session intersections, expiry, cleanup, and a mandatory
  privacy/cost gate.
- Split rollout into additive server support, client command/invalidation split,
  and a separately gated actor-echo enablement. Actor echo waits until
  `MIN_CLIENT_VERSION` enforces the compatible client and telemetry shows zero
  older sessions for 24 hours; its kill switch is independent of new kinds.
- Moved pong deadline/reconstruction responsibility to `RemoteApiClientWs`, made
  socket recreation explicit, and keyed typed connection epochs/catch-up by
  account identity with late-old-account rejection tests.
- Documented N isolate-local LISTEN/router/session/watch topologies and required a
  two-worker integration proof, isolate-labeled metrics, and recovery broadcast
  only on the recovering worker.
- Narrowed notification failure containment to catchable trigger-time errors,
  added `pg_notification_queue_usage()` monitoring as residual commit-risk
  control, and added no-op/no-feedback-loop `room_seen` invariants.
- Chose a Dart `webdriver` two-session harness over an unsupported Playwright
  project and specified a QA-only suspend/force-close/resume endpoint for a
  deterministic missed-event window.
- Aligned domain files and DI with repository conventions and made relationship
  endpoint envelopes singular while reserving `subject_ids` for watch routing.

### Loop 3

Critique:

Findings verified against the live tree; hostile critique follows. The Loop 2
revision landed correctly: server-issued watch grants, the three-step rollout
gate, transport-owned pong/reconstruction responsibility, N-isolate topology,
`room_seen` invariants, and the Dart-webdriver harness all match the code and
the repository's real constraints. Loop 3 finds one remaining High-severity
protocol hole - a connected-but-unauthenticated socket is a permanent loss
boundary that no rule in section 7.4 repairs - plus three Medium executable-gate
defects and three wording/scope corrections.

**Severity legend:** H = must fix before implementation; M = fix during the named
phase; L = wording/scope.

#### H1. A connected-but-unauthenticated socket is a permanent loss boundary; section 7.4 has no rule for auth failure or a missing auth ack

Every catch-up trigger in AD-4/section 7.4 presupposes the socket eventually
reaches the authenticated state. Live code shows two ways it never does, while
the underlying `web_socket_client` connection stays healthy:

- Client side: `RemoteApiClientWs._onConnectionChanged`
  (`packages/client/lib/data/service/remote_api_client/remote_api_client_ws.dart:135-141`)
  sends exactly one auth frame per `Connected`/`Reconnected`. `_buildAuthMessage`
  awaits `getAuthToken()`, which performs an HTTP token refresh and throws on
  transient failure (`remote_api_client_base.dart:171-225`). The exception
  escapes the async stream callback; nothing is sent, nothing retries.
- Server side: `WebsocketRouterBase.onTextMessage` catches the
  `parseAndVerifyJwt` failure from `onAuth` and replies `{"error": ...}` while
  keeping the socket open (`websocket_router_base.dart`, catch in
  `onTextMessage`; `websocket_session_handler_base.dart:185-217`). The client's
  `_onMessage` default branch forwards that error map to `webSocketMessages`
  and the state never becomes `connected` (`remote_api_client_ws.dart:183-184`).

Consequences under the plan as written: `_onTimer` pings only while
`connected` (`remote_api_client_ws.dart:127-131`), so the rule-6 pong deadline
never arms; the package socket is healthy, so the rule-7 supervisor never
fires; rule 2's catch-up requires an authenticated transition that never
happens. Realtime is silently dead for the whole session, and the AD-7 banner
shows "Reconnecting..." forever with no repair path. The concrete trigger is
mundane: a token refresh that fails during the same network blip that caused
the reconnect, with HTTP recovering seconds later.

**Revision:** add rule 8 to section 7.4: after the transport reports connected,
authentication must complete within a deadline (for example 10 s). On deadline
expiry, on an auth-frame build/send exception (including `getAuthToken`
failure), or on a server auth-error frame, retry authentication with capped
jittered backoff under the current `(accountId, connectionEpoch)`; after N
consecutive failures, dispose and reconstruct the socket via the rule-7
supervisor. The catch inside the connection callback is mandatory. Extend the
Phase 1 exit gate with two fake-socket tests: first `getAuthToken` call throws
then succeeds; server replies with an error frame then accepts - both must end
authenticated with exactly one catch-up. AD-7 must not display a permanently
unresolvable "Reconnecting..." state.

#### M1. Phase 1's DI instruction breaks every existing injection of the concrete `InvalidationService`, making its own exit gate unsatisfiable

Phase 1 says: register `InvalidationService` with `@Singleton(as:
RealtimeSyncPort)` and "keep temporary compatibility getters for existing
repositories until all callers move". With injectable, `as:` registers the
instance under the interface type only. `ForwardRepository`
(`packages/client/lib/features/forward/data/repository/forward_repository.dart:52-55`),
`BeaconRepository`, `BeaconRoomRepository`, and others inject the concrete
`InvalidationService`; after the annotation change, generated DI resolves
`RealtimeSyncPort` but `GetIt.I<InvalidationService>()` throws at startup.
Compatibility getters cannot fix an unresolvable type. The Phase 1 exit gate
"old tests remain green; DI/codegen succeeds" is therefore unsatisfiable as
specified.

**Revision:** keep `@singleton` on the concrete class and expose the port via
an `@module` alias provider (`RealtimeSyncPort get realtimeSyncPort =>
GetIt.I<InvalidationService>()` or the injectable module equivalent), removing
the alias in Phase 5 when the last concrete injection dies; or explicitly move
every concrete injection to the port within Phase 1. Name the chosen mechanism
in the plan so the exit gate is executable.

#### M2. The rule-6 pong watchdog reconnect-loops against a healthy server when `PONG_ENABLED=false`

Server pong is conditional: `websocket_session_handler_base.dart:173-180` sends
pong only `if (env.isPongEnabled)`, and `env.dart:233` makes that an env knob
(`PONG_ENABLED != 'false'`, default true but disableable). A deployment with
pongs disabled would hit the Phase 1 pong deadline on every interval and
force-dispose/reconstruct healthy sockets forever. The plan never mentions the
knob.

**Revision:** in Phase 2, make pong unconditional and remove/deprecate
`PONG_ENABLED` (documenting it in the migration/deploy notes), or in Phase 1
arm the pong deadline only after the first pong observed on the current
connection. Add a unit test for the no-pong-configured case either way.

#### M3. AD-8's Graph grant contract names function parameters that do not exist; "exact projection variables" is not reproducible server-side

AD-8 and Phase 2 item 9 say the Graph grant "re-runs the same
`public.graph`/`mr_graph` context as `GraphFetch` using the authenticated
`jwt.sub`, `focus`, `context`, `positiveOnly`, `offset`, and `limit`". Live
`public.graph(focus, context, positive_only, hasura_session)`
(`packages/server/lib/data/database/migration/m0108.dart:33-58`) takes the
viewer from `hasura_session ->> 'x-hasura-user-id'` and calls `mr_graph(...,
0, 100)` with hard-coded offset/limit; the client's `GraphFetch`
(`packages/client/lib/features/graph/data/gql/graph_fetch.graphql`) applies
`order_by: {dst_score: desc}, offset, limit` (default limit 10) in Hasura,
outside the function. There are no offset/limit parameters to pass, and
reproducing Hasura's post-ordering pagination server-side is fragile
(`dst_score` ties make page boundaries nondeterministic) and unnecessary for
authorization.

**Revision:** specify that the grant case invokes `public.graph` (or
`mr_graph` directly) with viewer = `jwt.sub`, `focus`, `context`,
`positive_only` only, and intersects the requested subject IDs with the full
bounded result (<= 100 rows) - a superset of any rendered page - dropping
offset/limit/order from the authorization contract. Also state that `focus`
may be a beacon ID (the query pairs `graph()` with `beacon_by_pk(id: $focus)`)
and that only user-typed node IDs are grantable subjects for
relationship/profile watches.

#### L1. Section 8's `help_offer` row omits its third server source

`notify_coordination_change` (`m0063.dart:312-372`, trigger on
`beacon_help_offer_coordination`) also emits the `help_offer` wire kind, but
the section 8 matrix lists only "help offer + admission event" as the server
source. Phase 2 item 6 names all three publishers, yet section 8 is the
mapping of record that the Phase 2 contract test enumerates per kind.
**Revision:** amend the row's server source to "help offer + admission event +
help-offer coordination" so the per-kind trigger/function contract test covers
all three producers of the same wire kind.

#### L2. "Signing/public-key rotation path" overstates the live key infrastructure

The server holds a single env-injected EdDSA keypair
(`packages/server/lib/env.dart:216-227`, `JWT_PUBLIC_PEM`/private PEM) with no
rotation machinery; the real precedent for the grant is the purpose-bound
(aud + TTL) EdDSA token minting in `oauth_state_codec.dart` and
`auth_google_controller.dart:448-459`. AD-8's "existing server signing/
public-key rotation path" and section 12's "rotation conventions" send an
implementer hunting for rotation plumbing that does not exist.
**Revision:** reword to "reuse the env-injected EdDSA keypair and the
oauth-state purpose-binding precedent (`aud`, TTL, `JWT.verify` against
`env.publicKey`); rotation remains a manual key rollover, which bounds grant
TTLs' revocation story".

#### L3. Transport-level malformed-frame tolerance is unspecified

Section 7.1's "invalid payloads never terminate the shared stream" is assigned
to the adapter, but `RemoteApiClientWs._onMessage` throws `UnsupportedError`
on any non-string frame (`remote_api_client_ws.dart:145-149`) before the
adapter ever sees it - an uncaught zone error per binary/odd frame. Phase 1
rewrites this file anyway. **Revision:** add "tolerates non-string and
undecodable frames with a rate-limited log" to the Phase 1 transport bullet
and its exit-gate tests.

#### What now holds up

- The three-publisher inventory is exact (`notify_entity_change` m0072,
  `notify_coordination_change` m0063:312, `notify_help_offer_admission_event_change`
  m0113:37), and m0113 is the latest live migration, so "m0114 or next number"
  is correct.
- Every state-bearing table section 8 names exists under the exact name:
  `inbox_item` (m0014), `user_contact` (m0085), `vote_user` (m0001),
  `user_trust_edge` (m0088), `beacon_room_message_reaction` (m0036),
  `polling_act` (m0004), `notification_outbox` (m0096), `beacon_room_seen`
  (m0072). `room_poll` routing "beacon ID via linked message" is implementable:
  `beacon_room_message.linked_polling_id` exists and is joinable from
  `polling_act.polling_id` (needs the index Phase 2 item 12 already requires).
- Section 4.3's transport audit is accurate in every checked particular: the
  WS mixin overrides only `setAuth` (cookie-session `setSessionAuth` in
  `remote_api_client_base.dart:103` / `remote_api_client_web.dart:24` never
  starts a socket); the seed path constructs/listens before `super.setAuth`
  installs credentials; signup requests a pre-account auth-request token
  (`auth_remote_repository.dart:39-45`); `web_socket_client` 0.2.1 really does
  close terminally (`_closeWithTimeout()` when cumulative backoff >= timeout).
- The N-isolate topology description matches `env.dart:372`
  (`isolatesCount = isDebugModeOn ? 1 : workersCount`) and `app.dart:37`;
  QA gating (`isQaAuthEnabled`, non-prod + token) is independent of debug mode,
  so two-worker non-debug integration runs can still use QA endpoints.
- The current fan-out drops everything but entity/id/event
  (`websocket_path_entity_changes.dart:12-20`), so adding `actor_user_id`/
  `subject_ids` is additive and old-client compatible, as the rollout assumes.
- The `forwardCompleted` conflation and split are correctly targeted: the
  four non-Inbox consumers (ForwardCubit, PersonForwardCubit, BeaconViewCubit,
  MyWorkCubit) perform silent refetches only, so migrating them to
  `forwardChanges` creates no duplicate UI effects; `pendingMovedNudge`
  derivation sits exactly where Phase 3 says (`inbox_cubit.dart:37-40,113-148`).
- The `room_seen` audit is right: the upsert updates unconditionally under
  `withMutatingUser` (`packages/server/lib/data/repository/beacon_room_repository.dart:951-977`),
  so the m0114 `IS DISTINCT FROM` guard and no-feedback-loop test are the
  correct fixes.
- Section 4.4's bookkeeping baseline is current: the recalculate-counters repair
  path is merged on `main`, and the additive `BookkeepingRefreshSignal` wiring in
  Inbox/My Work must be preserved during issue 73 work.
- The verification commands are executable: `env/test.env`,
  `check-doc-drift.sh`, `run_client_integration_web_local.sh` with its
  auto-downloaded Chromedriver all exist; `run_realtime_multiclient_web_local.sh`
  is correctly marked a Phase 6 deliverable.
- Phase 0's CI-green policy matches `pipeline.yml`; the presence
  replace-not-union and per-user session index precedents in
  `websocket_session_handler_base.dart` are as described; PG listener recovery
  reconnects with backoff and emits nothing at initial startup, matching the
  recovery-stream requirement.

With H1's auth-completion rule added and the three Medium items folded into
their phases, the plan is implementable as specified; no further architecture
review is required.

Revision:

- Added an account/epoch-scoped authentication completion deadline, capped
  retry, server-error handling, and socket reconstruction after repeated auth
  failures, with fake-socket coverage for token and server rejection recovery.
- Kept the concrete `InvalidationService` singleton during migration and added a
  same-instance injectable module alias for `RealtimeSyncPort`, so existing
  repository injection and the Phase 1 green gate remain valid.
- Made authenticated pong responses unconditional and deprecated the
  `PONG_ENABLED` switch so the client watchdog cannot reconnect-loop against a
  healthy intentionally silent server.
- Corrected Graph watch authorization to intersect requested user nodes against
  the full bounded `public.graph` result using only its real inputs; Hasura
  pagination is not part of the authorization contract.
- Added help-offer coordination to the matrix, corrected EdDSA/manual rollover
  wording, and required transport-level non-string/undecodable frame tolerance.

### Scope change 2026-07-14: live Graph updates removed

Product decision, applied after loop 3 with implementation already in progress:
the Graph screen is a transient visualization and the user is not supposed to
linger there, so an open Graph may go stale. It renders a fresh authoritative
snapshot on route entry and manual refresh only.

Removed from the plan body: the Graph scope of acceptance criterion 4, live
Graph event routing and the `GraphCase` requirement (Phase 4), the AD-8
server-granted watch protocol and its wire control frames (section 7.3), the
`subject_ids` envelope field, the watch-grant REST endpoint and WebSocket
registration (Phase 2 item 9), and all watch-related security gates, metrics,
tests, and rollout switches. Bounded recipient fan-out for relationship and
profile changes remains and still serves Friends, Profile, and People. Section
and item numbering is preserved; removed sections carry inline stubs so the
loop 1-3 references above remain resolvable. The critique text above is
untouched and predates this decision.

### Addendum 2026-07-14: NOTIFY commit-serialization risk recorded

External input, a pgsql-hackers production report:
https://www.postgresql.org/message-id/CADWG95t0j9zF0uwdcMH81KMnDsiTAVHxmBvgYqrRJcD-iLwQhw@mail.gmail.com
(~100 databases, 8000 qps, 40-100 notifies/s; commit wait queues of hundreds of
transactions on the NOTIFY queue lock, with cascading stalls when the blocked
committer also held other locks).

Mechanism: `PreCommit_Notify` takes one cluster-global exclusive lock on the
notification queue and holds it through the commit's WAL flush, so all
notifying commits serialize and a waiting committer extends every other lock
it holds. Since `m0114` makes practically every write transaction a notifier,
this is a total-write-throughput ceiling, invisible to
`pg_notification_queue_usage()`.

Plan changes: section 13 now records the serialization ceiling as a second
residual risk with commit-lock wait metrics and a p95 wait budget; Phase 2 and
Phase 5 document the short-notifying-transaction discipline next to
`withMutatingUser` and in `DEV_GUIDELINES.md`; section 16 item 7 designates
the transactional outbox (replacing the body of `emit_realtime_entity_change`
via forward migration plus a server-side dispatcher) as the fallback and as a
hard precondition for synchronous replication;
`docs/production-deploy.md` gains the matching pitfall note. Existing `m0114`
mitigations already in place: a single emission helper, statement-level
coalescing triggers for `vote_user`/`user_trust_edge`, `IS DISTINCT FROM`
guards, and Postgres's own same-payload dedup within a transaction. At current
single-database write volumes the risk is dormant; no architecture change is
required.
