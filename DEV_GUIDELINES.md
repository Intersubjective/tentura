# Development guidelines

Project-specific conventions beyond what lives in `.cursor/rules/`.

## Initial load on detail and list screens (spinner)

When a screen's cubit loads data asynchronously after navigation, the first frame must not paint "success" UI built from empty or placeholder domain objects (that causes wrong actions, empty titles, and layout flashes).

**Do this:**

1. **State** — Start with `status: StateStatus.isLoading` (or equivalent) until the first fetch completes. Do not default to `StateIsSuccess()` while `beacon`, `author`, or similar fields are still placeholders.
2. **Body** — Use `BlocBuilder` with `buildWhen: (_, c) => c.isSuccess || c.isLoading` (or a superset that includes loading when the UI must react). When `state.isLoading`, show:

   ```dart
   const Center(
     child: CircularProgressIndicator.adaptive(),
   )
   ```

3. **Consistency** — Follow the same pattern as `InboxScreen`, `MyFieldScreen`, `MyWorkScreen`, `RatingScreen`, and `BeaconViewScreen`. A thin linear progress indicator under the app bar can supplement this for in-place reloads; it is not a substitute for hiding bogus content on the **initial** load.

**Rationale:** A centered adaptive progress indicator is the project default for \u201cdata not ready yet.\u201d It avoids rendering ownership-specific controls (e.g. Commit vs owner actions) against `Profile()` / empty ids.

## Layer boundaries & keeping them (client + server)

These are **project invariants**. Stricter checks live in `.cursor/rules/architecture.mdc` and `quick-reference.mdc`; **automation** is in `packages/tentura_lints` and CI.

### Server (`packages/server`)

- **Domain use cases** depend on **`domain/port/*`** types only — **not** on concrete `data/repository` classes. Repositories **`implement`** ports and register with Injectable **`as: …Port`** (dev/prod envs); tests bind fakes the same way.
- **Use cases** extend **`UseCaseBase`** and take **`env` + `logger`** where that base exists in the package.
- **Quick check:** `rg "package:tentura_server/data/repository" packages/server/lib/domain` should return **no hits**.

### Client (`packages/client`)

- **`lib/domain/`** (shared root domain) must **not** import `package:tentura/.../data/` or `.../ui/`. Enforced by **`custom_lint`** in **`packages/tentura_lints`** (`no_domain_to_data_or_ui_import`). *Note:* feature folders named `domain/` under `features/*/domain/` are not the same path — still follow the same **spirit** (no upward imports to data/ui types from domain code).
- **`lib/**/ui/bloc/*_cubit.dart`** must **not** import `package:tentura/.../data/service/`. Use **repositories** or **`features/*/domain/use_case/*_case`**. Lint: **`no_cubit_to_data_service_import`**.
- **Orchestration:** When a cubit coordinates **multiple repositories** or **streams**, add or extend a **`@singleton`** `*Case` in `features/<feature>/domain/use_case/` and inject it (optional ctor param + `GetIt.I` fallback) so the cubit stays thin.
- **Immutable cubit state:** Never mutate lists/maps **on** `state` (no `state.items.add`, `state.likes[id]=`, in-place `sort`, etc.). Always **`emit(state.copyWith(...))`** with **new** collection instances.
- **Images:** Picker/cropper types stop in **data**; **`ImageRepository`** exposes domain **`ImagePicked`** (or equivalent) at pick boundaries.
- **Fixtures:** Prefer **`lib/data/repository/mock/data/`** for shared JSON/Dart stubs used by tests and mocks.

### CI

- The GitHub workflow runs **`dart analyze --fatal-infos`** (server) and **`flutter analyze --fatal-infos`** (client) **before** tests. New work should stay clean under those flags (or fix pre-existing debt in the same area you touch).
- **Server Postgres integration tests** (see `packages/server/README.md` § Tests) are skipped in CI when no database is available; they run locally against dev Postgres. Do not add a Postgres service to the main pipeline unless the integration surface grows materially.

## Ferry custom scalars (Hasura)

Every Hasura `scalar` type that appears in query **responses** must have a
`type_overrides` entry in **both** `ferry_generator|graphql_builder` and
`ferry_generator|serializer_builder` in `packages/client/build.yaml`.

Without an override Ferry generates a `G<Scalar>` wrapper class whose
`DefaultScalarSerializer` casts the raw JSON value to `String?`.
This works only when the wire format is already a string (e.g. `uuid`).
For numeric scalars (`smallint`, `float8`) Hasura sends JSON integers /
numbers, so the cast crashes silently and the Ferry stream never emits \u2014
resulting in hanging Futures and infinite spinners.

| Scalar | Dart type | Needs custom serializer? |
|--------|-----------|--------------------------|
| `timestamptz` | `DateTime` | Yes (`TimestamptzSerializer`) |
| `smallint` | `int` | Yes (`SmallintSerializer`) — see below |
| `float8` | `double` | Yes (`Float8Serializer`) — see below |
| `uuid` | `String` | No |
| `Upload` | `MultipartFile` | Yes (`UploadSerializer`) |

**Why `smallint` and `float8` still need serializers after `type_overrides`:** mapping
them to `int` / `double` fixes Ferry’s broken `G<Scalar>` wrappers for **typical**
Hasura responses (JSON numbers). MeritRank plugin fields (`mr_*` functions) feed
computed relationships such as `mutual_score` (`user.scores`, `beacon.scores`, …).
For those paths Hasura often emits `float8` (and sometimes `smallint`) as **JSON
strings** (e.g. `"95"`). `built_value` then expects a `num` and throws
`String is not a subtype of num`. `Float8Serializer` and `SmallintSerializer`
deserialize both wire shapes: register them under `custom_serializers` in
`ferry_generator|serializer_builder` only (see `packages/client/build.yaml`).
Details: `packages/server/WORKAROUNDS.md` section 3.

When adding a **new** Hasura custom scalar to the schema, add the
corresponding `type_overrides` entry before running codegen.
If the Dart type is not a JSON primitive, or the same GraphQL scalar can arrive
as both number and string (MeritRank / computed fields), also add a
`custom_serializers` entry (see `TimestamptzSerializer`, `Float8Serializer`).

## V2 direct routing (client → Tentura, bypassing Hasura)

Operations implemented on the Tentura V2 server must be called at
`/api/v2/graphql`. The client’s `_V2RoutingLink` in
`packages/client/lib/data/service/remote_api_client/build_client.dart`
routes by **operation name**: if the name is in `_tenturaDirectOperationNames`,
the request goes to V2; otherwise it goes to Hasura V1 (`/api/v1/graphql`).

When adding a new V2 server query or mutation:

1. Add the client-side **operation name** (from the `.graphql` file) to
   `_tenturaDirectOperationNames` in `build_client.dart`.
2. Ensure the V2 GraphQL schema defines every type and field the client selects.
   If the query uses shared fragments (e.g. `UserModel` on `user`), V2 must
   expose matching GraphQL types and field names (aligned with Hasura’s schema
   from which Ferry is generated).
3. No Caddy change is required for routing: `/api/v2/graphql` is already
   proxied to Tentura in production (`Caddyfile`) and in local web dev
   (`packages/client/web_dev_config.yaml`).

## Invite, landing, and deep links

Flutter web uses **hash routing** (`#/…`). Landing → app handoff must use explicit
hash paths (e.g. `#/accept-invite/<code>`), not root query params like `?invite=`.

| Route | Constant | When |
|-------|----------|------|
| Basic invite URL | `/invite/<code>` (server/landing) | Share + static preview |
| Signup-with-invite | `kPathSignUp` (`/sign/up/<code>`) | New user; invite consumed at signup |
| Accept-invite | `kPathAcceptInvite` (`/accept-invite/<code>`) | Signed-in user; preview + confirm + REST accept |

Deep-link normalization lives in `invite_deep_link.dart` and `root_router.dart`.
Landing CTAs in `packages/landing/main.js`. Full flow diagrams and corner cases:
[`docs/invite-signup-landing-flow.md`](docs/invite-signup-landing-flow.md).

## Entity invalidation (real-time)

Near-real-time updates for entity changes (beacons, help offers, forwards) are
delivered via lightweight **invalidation signals** over the existing V2 WebSocket
(`/api/v2/ws`). This is **not** Hasura GraphQL subscriptions and **not** HTTP
polling.

### Data flow

```
PG trigger (AFTER INSERT/UPDATE/DELETE)
  → NOTIFY entity_changes (JSON: entity, id, user_ids)
  → PgNotificationService (packages/server/…/pg_notification_service.dart)
  → WebsocketRouterBase._onEntityChangeNotification
  → WebsocketPathEntityChanges.fanOutEntityChange (targets sessions by user_ids)
  → WS message to client
  → InvalidationService (packages/client/…/invalidation_service.dart)
  → Repository emits RepositoryEventInvalidate / HelpOfferInvalidated
  → Cubit refetches via existing fetch()
```

### WebSocket message format

```json
{
  "type": "subscription",
  "path": "entity_changes",
  "payload": {
    "entity": "beacon",
    "id": "beacon-uuid",
    "event": "update"
  }
}
```

`entity` is one of `"beacon"`, `"help offer"`, `"forward"`, or beacon-room–related
keys such as `"room_message"`, `"participant"`, `"fact_card"`, `"blocker"`,
`"activity_event"` (see migrations using `notify_entity_change(...)`).
`event` is the lowercase Postgres `TG_OP`: `"insert"`, `"update"`, or `"delete"`.

### Fan-out strategy (phase 1)

Relationship-based targeting — the PG trigger embeds the affected user IDs:

| Entity | Notified users |
|--------|----------------|
| `beacon` | Beacon author (`user_id`) |
| `help offer` | Committing user + beacon author (looked up from `beacon`) |
| `forward` | Sender + recipient of the forward edge |

No client-side subscription registration is needed. Phase 2 may add
`watch_authors` subscriptions similar to how `user_presence` tracks `peer_ids`.

### Echo suppression

When a V2 mutation modifies a trigger-carrying table, the originating user
should **not** receive the invalidation signal back (the client already handled
the change locally). Two layers prevent this:

**Server side (primary):** The PG trigger function `notify_entity_change()`
reads `current_setting('tentura.mutating_user_id', true)` and removes that
user from the `user_ids` array before calling `pg_notify`. Server-side
repositories set this GUC inside a transaction via
`TenturaDb.withMutatingUser(userId, () => ...)`. External writes (Hasura,
raw SQL) never set the GUC, so all users are still notified normally.

When adding a new V2 mutation that touches a trigger-carrying table, wrap
the repository call in `_database.withMutatingUser(userId, () => ...)`.

**Client side (residual):** `InvalidationService` buffers incoming IDs using
`rxdart` `bufferTime(500ms)` and deduplicates within each window. This
collapses batch operations (e.g. multi-recipient forwards) into a single
invalidation event per entity ID.

**Beacon room slice:** `beaconRoomInvalidations` is a
`Stream<({String beaconId, BeaconRoomEntityType entityType})>` (see
`features/beacon_room/domain/entity/beacon_room_invalidation.dart`). The WS
`payload['entity']` string is mapped to `BeaconRoomEntityType` before emit;
debouncing deduplicates identical `(beaconId, entityType)` pairs in the same
window. `BeaconViewCase` exposes this stream so UI cubits do not import
`data/service/` directly. `BeaconViewCubit` routes each type to a minimal
subset of `BeaconViewCase` fetches (e.g. `room_message` → room activity list +
unread count only), instead of re-running the full beacon timeline fetch.

### Adding real-time updates for a new entity

**Server side:**

1. Add a PG trigger on the table in a new migration
   (`EXECUTE FUNCTION public.notify_entity_change('entity_name')`).
   The generic `notify_entity_change()` function handles the entity via
   `TG_ARGV[0]`; add an `ELSIF entity_type = '...'` branch that sets
   `entity_id` and `user_ids`.
2. Wrap the repository mutation in `_database.withMutatingUser(userId, ...)`
   so the trigger suppresses the echo back to the originating user.
3. No changes needed in `PgNotificationService` — it listens on the
   `entity_changes` channel generically.
4. No changes needed in `WebsocketPathEntityChanges.fanOutEntityChange` —
   it reads `user_ids` from the payload generically.

**Client side:**

1. Add a new broadcast stream to `InvalidationService`
   (e.g. `Stream<String> get fooInvalidations`).
2. Add a `case` in `InvalidationService._onInvalidation` for the new entity
   key.
3. Inject `InvalidationService` into the relevant repository; listen and emit
   on the repository's existing `changes` stream using
   `RepositoryEventInvalidate` (or an equivalent domain event type).
4. Ensure the cubit already reacts to the repository event stream. If the
   cubit uses an exhaustive `switch`, add the new variant. Add debouncing if
   rapid-fire invalidations are expected.

### What NOT to do

- Do **not** add Hasura GraphQL subscriptions (`gql_websocket_link`,
  `subscription` operations) for this purpose.
- Do **not** add HTTP polling timers (`Timer.periodic` with `fetch()`).
- Do **not** parse WS messages directly in repositories — all invalidation
  goes through the single `InvalidationService` singleton
  (`packages/client/lib/data/service/invalidation_service.dart`).
- Do **not** put refetch logic in repositories; repositories emit signals,
  cubits own the fetch lifecycle.

## Client version gate (`MIN_CLIENT_VERSION`)

The server announces the minimum acceptable client semver in every WS pong frame:

```json
{"type": "pong", "min_client_version": "1.17.0"}
```

The client (`AppUpdateCubit`) compares this against its own version (`PackageInfo.version`) and shows a non-blocking `MaterialBanner` when it is older. Web shows a **Refresh** button; native shows a **Dismiss** button.

### When to update `MIN_CLIENT_VERSION`

| Client bump | Update `MIN_CLIENT_VERSION`? |
|---|---|
| **Major** (`X.y.z`) | **Always** — breaking API/behaviour change |
| **Minor** (`x.Y.z`) | Only when the old client cannot work with the new server (removed endpoint, new required WS field, etc.) |
| **Patch** (`x.y.Z`) | Rarely — only if the old client is broken against the new server |

Default is `0.0.0`, which disables the check (any client is accepted).

### Where to set it

| Environment | Location |
|---|---|
| Local dev | `.env` (read by `scripts/run-server-local.sh`) |
| Production / VPS | `.env` for all secrets; `compose.prod.yaml` pass-through; optional `compose.override.yaml` for non-secret per-host deltas (see `examples/compose.override.example.yaml`) |
| CI / GitHub | GitHub Environment variable `MIN_CLIENT_VERSION` in the `dev` environment |

### Relevant files

- **Server env:** `packages/server/lib/env.dart` — `minClientVersion` field
- **WS pong:** `packages/server/lib/api/controllers/websocket/session/websocket_session_handler_base.dart` — `onPing`
- **Client stream:** `packages/client/lib/data/service/remote_api_client/remote_api_client_ws.dart` — `minClientVersionStream`
- **Cubit:** `packages/client/lib/ui/bloc/app_update_cubit.dart` — `AppUpdateCubit`
- **Banner:** `packages/client/lib/app/app.dart` — `BlocListener<AppUpdateCubit, …>`

## Typography & responsive design (client)

Tentura uses **semantic typography** and **width-based layout classes**, not proportional “shrink everything on narrow phones.” Full spec: [`docs/tentura-design-system.md`](docs/tentura-design-system.md). Work log: [`docs/typography-overhaul-journal.md`](docs/typography-overhaul-journal.md).

### Hard floors (logical px)

- **Metadata / secondary** (status lines, hints): minimum **13** — use `theme.textTheme.bodySmall` / `TenturaText.bodySmall`.
- **Body:** minimum **15** — `bodyMedium` / `TenturaText.body`.
- **Primary actions / buttons:** minimum **15** — `labelLarge`.
- **Bottom navigation labels:** **12.5** is the **only** exception below 13 — `TenturaText.navLabel` or equivalent.
- **Do not** use literal font sizes **8, 10, 11, 12** in `packages/client/lib/features/**` or `packages/client/lib/ui/**` (use semantic roles; `custom_lint` may enforce).

### WindowClass breakpoints

Drive **density** (padding, gaps, icon size, avatar sizes, button height, app bar / bottom nav chrome, `contentMaxWidth`) from **logical width**:

| Class | Width |
|-------|-------|
| `compact` | &lt; 600 |
| `regular` | 600 ≤ *w* &lt; 840 |
| `expanded` | ≥ 840 |

**Do not** change `TextTheme` font sizes per class — only `TenturaTokens` (via `TenturaResponsiveScope` / `context.tt`).

### Proportional sizing

**Do not** size typography or global UI from `MediaQuery.sizeOf(context).width / N` or similar “design width” ratios. That shrinks already-small text on phones and blows up type on tablets. **Allowed** exceptions: layout that is inherently proportional (e.g. chat bubble `maxWidth: screenWidth * 0.75`, bottom sheet height fractions) — document in the typography journal if non-obvious.

### Accessibility

- **Never** wrap the entire app in `MediaQuery.copyWith(textScaler: TextScaler.noScaling)`.
- **Web:** `packages/client/web/index.html` must use `width=device-width, initial-scale=1.0`, `viewport-fit=cover`; do not set `maximum-scale` or `user-scalable=no`.

### Font

Primary UI font is **Inter** (bundled under `packages/client/fonts/`). Prefer `TenturaText` + `textTheme`; avoid `google_fonts` at runtime for app chrome.

## Flutter web: conditional imports (JS and wasm)

Do **not** gate web-only implementations with `if (dart.library.html)` in
conditional imports. On **Flutter web compiled to wasm**, `dart.library.html`
can be **false** while the app still runs in the browser; the compiler then
links the **default/stub** file instead of your web implementation. If that
stub throws (or no-ops), errors are easy to misread as “server ignored the
upload” or “crop did nothing.”

**Do this instead:** use `if (dart.library.js_interop)` for browser interop
code paths, and implement them with `dart:js_interop` + `package:web` (not
`dart:html`). Example: `packages/client/lib/data/repository/image_repository.dart`
and `read_blob_url_web.dart` / `read_blob_url_stub.dart`.

## Local RAG codebase search

A local semantic search index lets you ask questions like "how does X work" or "where is Y implemented" without reading whole files.

### Setup (once per machine)

```bash
python3 -m venv rag_env
source rag_env/bin/activate
pip install -r rag_requirements.txt
python3 rag_index.py        # builds chroma_db/ locally (~1–2 min with CUDA)
```

`chroma_db/` and `rag_env/` are gitignored — each developer keeps their own local index.

### Querying

```bash
source rag_env/bin/activate
python3 rag_query.py "your question here"
```

Results are ranked by semantic distance. Distance < 1.0 is a strong hit; > 1.2 is likely noise — fall back to grep.

### Keeping the index current

The index is rebuilt from scratch with `python3 rag_index.py`. The indexer respects `.gitignore` at every directory level, so generated files are excluded automatically.

When using Claude Code, the index is updated automatically after any file edit via a PostToolUse hook in `.claude/settings.json`.

## Read-state / unread (single watermark)

Room unread must have **one session-scoped owner** for main-room read-through:

| Layer | Owner |
|-------|--------|
| Local read-through (user reached bottom) | `RoomReadWatermarkStore` (`@lazySingleton`) |
| In-chat divider / count | `RoomCubit` derives from watermark + loaded messages |
| Shell badge / inbox / My Work | `resolveUnread(serverCount, serverSeenAt)` — never manual `clear + refresh` clamps |

### Checklist (new read-state features)

1. **Advance local read-through immediately** when the user reaches the bottom:
   `RoomReadWatermarkStore.observeReadThrough(beaconId, latestLoaded.createdAt)`.
2. **Persist only on confirmed success:** mark-seen mutations return
   `BeaconRoomSeenResult.seenAt`; domain exposes `RoomSeenOutcome` (`Succeeded` /
   `Denied` / `Failed`); call `confirmSynced` only on `Succeeded`.
3. **Pass `readThroughAt`** to mark-seen mutations (latest loaded message timestamp).
4. **Batch unread** uses `InboxRoomContextBatch.lastSeenAt` + `roomUnreadCount`;
   UI resolves via watermark, not raw server count alone.
5. **No cross-feature repository side channels** (e.g. hints repo → inbox repo
   notification streams). Expose watermark `changes` through **use cases**
   (`BeaconRoomCase.readWatermarkChanges`, merged into `InboxCase.localMutations`).
6. **Server SQL:** follow `packages/server/WORKAROUNDS.md` §4 for
   `beacon_room_seen` `customStatement` binding.

Reference implementation: `packages/client/lib/features/beacon_room/domain/room_read_watermark_store.dart`.

## State scopes: route vs session vs persisted

| Scope | Example | Lifetime |
|-------|---------|----------|
| Route / screen | `RoomCubit`, `BeaconViewCubit` | Created per navigation; disposed on pop |
| Session `@lazySingleton` | `RoomReadWatermarkStore` | App process; survives `?tab=room` pushes |
| Server-persisted | `beacon_room_seen.last_seen_at` | Postgres; may lag behind local read-through |

**Rule:** data that must survive route re-entry (read watermarks, debounced
invalidation buffers) belongs in `@lazySingleton` domain services — not in
route-scoped cubits or data-repository session maps.

## Cross-feature events

Avoid **data-repository → data-repository** imports for UI refresh side effects.
Prefer domain/use-case streams (e.g. watermark `changes` merged into
`InboxCase.localMutations`) so features stay decoupled at the data layer.
