# Development guidelines

Project-specific conventions beyond what lives in `.cursor/rules/`.

**Documentation index:** product and engineering specs are listed in [`docs/README.md`](docs/README.md) (start there for feature context). Vocabulary: [`CONTEXT.md`](CONTEXT.md).

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

These are **project invariants**. Stricter checks live in `.cursor/rules/architecture.mdc` (routed from `AGENTS.md`); **automation** is in `packages/tentura_lints` and CI.

### Server (`packages/server`)

- **Domain use cases** depend on **`domain/port/*`** types only — **not** on concrete `data/repository` classes. Repositories **`implement`** ports and register with Injectable **`as: …Port`** (dev/prod envs); tests bind fakes the same way.
- **Use cases** extend **`UseCaseBase`** and take **`env` + `logger`** where that base exists in the package.
- **Quick check:** `rg "package:tentura_server/data/repository" packages/server/lib/domain` should return **no hits**.
- **Injectable pitfall:** Do **not** put `@lazySingleton` / `@LazySingleton()` **and** `@LazySingleton(as: SomePort)` on the **same** repository class. Injectable registers only the `as:` binding; use cases that inject the **concrete** type then fail at startup (`GetIt: Object/factory with type X is not registered`). Fix: one `@LazySingleton(as: XPort)` + `implements XPort`; domain injects the port only.
- **DI smoke test:** `packages/server/test/app/di_smoke_test.dart` boots prod/dev graphs and resolves `UpdateCoordinationItemCase`, async `BeaconRoomCase`, and `RootRouter` — run via `dart test` after port/DI changes.

### Client (`packages/client`)

- **`lib/domain/`** (shared root domain) must **not** import `package:tentura/.../data/` or `.../ui/`. Enforced by **`tentura_lints`** analyzer plugin (`no_domain_to_data_or_ui_import`). *Note:* feature folders named `domain/` under `features/*/domain/` are not the same path — still follow the same **spirit** (no upward imports to data/ui types from domain code).
- **`lib/**/ui/bloc/*_cubit.dart`** must **not** import `package:tentura/.../data/service/`. Use **repositories** or **`features/*/domain/use_case/*_case`**. Lint: **`no_cubit_to_data_service_import`**.
- **Orchestration:** When a cubit coordinates **multiple repositories** or **streams**, add or extend a **`@singleton`** `*Case` in `features/<feature>/domain/use_case/` and inject it (optional ctor param + `GetIt.I` fallback) so the cubit stays thin.
- **Immutable cubit state:** Never mutate lists/maps **on** `state` (no `state.items.add`, `state.likes[id]=`, in-place `sort`, etc.). Always **`emit(state.copyWith(...))`** with **new** collection instances.
- **Images:** Picker/cropper types stop in **data**; **`ImageRepository`** exposes domain **`ImagePicked`** (or equivalent) at pick boundaries.
- **Fixtures:** Prefer **`lib/data/repository/mock/data/`** for shared JSON/Dart stubs used by tests and mocks.

### CI

- The GitHub workflow runs **`dart analyze --no-fatal-warnings`** (server) and **`flutter analyze --no-fatal-warnings --no-fatal-infos`** (client) **before** tests. Plugin lints (`tentura_lints`) run inside analyze automatically — no separate `custom_lint` step. New work should stay clean under those flags (or fix pre-existing debt in the same area you touch).
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

## Realtime projection convergence

State-bearing server changes are delivered as lightweight invalidation hints on
the V2 WebSocket (`/api/v2/ws`). A hint never contains projection data and never
grants access; it tells an already-authorized client projection to refetch its
authoritative snapshot. This is not a Hasura subscription and not polling.

The machine-checked entity/impact matrix is
[`docs/contracts/realtime-entity-contract.json`](docs/contracts/realtime-entity-contract.json).
Update that manifest with every new wire kind. Client and server architecture
tests fail when a kind lacks a producer, enum mapping, impact, or test evidence.

### Data flow and envelope

```
PG trigger/publisher
  → byte-bounded NOTIFY entity_changes envelope
  → isolate-local PgNotificationService LISTEN
  → authenticated-session fan-out to bounded affected accounts
  → RealtimeSyncPort typed entityChanges
  → owning use case selects affected projections
  → Cubit performs a guarded silent snapshot refresh
```

```json
{
  "type": "subscription",
  "path": "entity_changes",
  "payload": {
    "entity": "beacon",
    "id": "beacon-uuid",
    "event": "update",
    "actor_user_id": "actor-account-id"
  }
}
```

`event` is `insert`, `update`, or `delete`. `user_ids` exists only inside the PG
envelope and is stripped from the client frame. Recipient arrays are normalized,
deduplicated, null-filtered, and split under both the recipient-count and NOTIFY
byte ceilings. Relationship/profile fan-out uses bounded, indexed recipient
queries; there is no client-supplied subject watch or open-screen registry.

### Actor semantics and duplicate control

`TenturaDb.withMutatingUser` sets `tentura.mutating_user_id` for attribution.
SQL always retains that account in `user_ids` and adds it as `actor_user_id`.
During compatibility rollout only, `REALTIME_ACTOR_ECHO_ENABLED=false` makes the
WebSocket router filter the actor's sessions. The final mode is `true`: all of an
actor account's sessions converge through the same server hint as other affected
sessions. Do not reintroduce SQL actor removal or a session-local derived-state
bus.

The client coalesces `(kind, aggregateId)` bursts for 500 ms. Cubits use one
in-flight silent refresh plus at most one queued rerun and reject stale account or
generation results. Command success/failure owns user-visible effects; an echoed
invalidation only reconciles server truth and must not show a second success.

### Catch-up protocol and lifecycle

A catch-up is a reasoned request to refresh currently active projections, not a
replay log. `RealtimeSyncPort.catchUps` carries the account and connection epoch.
Supported reasons cover authenticated reconnect, pong-timeout reconstruction,
PG listener recovery, native resume, restored web visibility, and explicit server
requests. First authentication is quiet; later authentication of the same account
emits one reconnect catch-up. Old-account/old-epoch events are discarded.

When the PG LISTEN connection recovers, that server isolate broadcasts a
`control/entity_changes` frame with `intent=catch_up` to its authenticated
sessions. Native `LifecycleHandler` requests catch-up on `resumed`; web requests
it when `document.visibilityState` becomes `visible`. A live-channel outage over
two seconds shows the non-blocking localized paused banner; HTTP reads and writes
remain available.

### Checklist for a new state-bearing entity

1. Add a forward migration with the generic trigger mapping or a bounded
   specialized publisher. Reuse current visibility rules and indexed relations.
2. Include all affected accounts, including the actor, plus `actor_user_id`.
   Test INSERT/UPDATE/DELETE and lost-authorization snapshots.
3. Add the canonical and any compatibility wire aliases to
   `RealtimeEntityKind.fromWire`; do not add a feature-specific transport stream.
4. Add the manifest row with `genericTriggerArgs`/`specializedPublishers`, client
   enum name, affected projections, and current test evidence.
5. Route the typed change through an owning use case. A Cubit may inject that
   case/port, never `data/service`; a Cubit coordinating two or more repositories
   still requires a `*Case`.
6. Implement a guarded background refresh that retains usable state on failure,
   handles delete/access loss, coalesces bursts, and suppresses stale results.
7. Add server producer/recipient tests, client impact-filter tests, Cubit
   convergence tests, and two-session integration evidence where user-visible.
8. Run both architecture contract tests and the full verification commands.

### What not to do

- Do not add Hasura GraphQL subscriptions or HTTP polling timers.
- Do not parse WebSocket frames outside `InvalidationService`.
- Do not inject `InvalidationService` into features; depend on
  `RealtimeSyncPort`/`RealtimeSyncCase` and domain projection streams.
- Do not append entities directly from hints; refetch and merge/replace by stable
  server IDs.
- Do not create a global derived-state bus or show command effects from an echo.

Operational queries, alert thresholds, and the local runtime procedure live in
[`docs/realtime-sync-operations.md`](docs/realtime-sync-operations.md).

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

Tentura uses **semantic typography** and **width-based layout classes**, not proportional “shrink everything on narrow phones.” Full spec: [`docs/tentura-design-system.md`](docs/tentura-design-system.md).

### Hard floors (logical px)

- **Metadata / secondary** (status lines, hints): minimum **13** — use `theme.textTheme.bodySmall` / `TenturaText.bodySmall`.
- **Body:** minimum **15** — `bodyMedium` / `TenturaText.body`.
- **Primary actions / buttons:** minimum **15** — `labelLarge`.
- **Bottom navigation labels:** **12.5** is the **only** exception below 13 — `TenturaText.navLabel` or equivalent.
- **Do not** use literal font sizes **8, 10, 11, 12** in `packages/client/lib/features/**` or `packages/client/lib/ui/**` (use semantic roles; `tentura_lints` enforces via `dart analyze`).
- **Do not** build `EdgeInsets` from raw numbers (`no_raw_edge_insets`) or `BorderRadius` / `Radius` from raw numbers (`no_raw_border_radius`) in `packages/client/lib/features/**` or `.../ui/**`. Use `context.tt` spacing/radius tokens (or `TenturaSpacing.*` / `TenturaRadii.*`); if none fits, add the token to the design system first. See the `material-3-flutter` skill (`.claude/skills/material-3-flutter/SKILL.md`) and `docs/tentura-design-system.md`.

### WindowClass breakpoints

Drive **density** (padding, gaps, icon size, avatar sizes, button height, app bar / bottom nav chrome, `contentMaxWidth`) from **logical width**:

| Class | Width |
|-------|-------|
| `compact` | &lt; 600 |
| `regular` | 600 ≤ *w* &lt; 840 |
| `expanded` | ≥ 840 |

**Do not** change `TextTheme` font sizes per class — only `TenturaTokens` (via `TenturaResponsiveScope` / `context.tt`).

### Adaptive layout & orientation

Full spec: [`docs/tentura-design-system.md`](docs/tentura-design-system.md) sections **Breakpoints**, **Adaptive layout rules**, **Orientation policy**, and **Full-bleed routes**.

**Layout:** Use `LayoutBuilder` + `windowClassForWidth(constraints.maxWidth)` — not orientation or hardware type. Main tabs: bottom `NavigationBar` when compact, `NavigationRail` when regular/expanded (`home_screen.dart`).

**Content width:** Most screens inherit centered `contentMaxWidth` (560 / 720) from `TenturaResponsiveScope`. Graph routes wrap body in `TenturaFullBleed` to use full viewport width.

**Orientation (phones stay portrait):**

| Platform | Behavior |
|----------|----------|
| Native Android/iOS | `SystemChrome` portrait lock when logical **shortest side** &lt; 600; unlock on tablets; re-applied on metrics change (`app/platform/orientation_policy.dart`) |
| iOS | iPhone plist: portrait only; iPad: all orientations |
| Installed PWA | `web/manifest.json` → `orientation: portrait-primary` |
| Web browser tab | No reliable lock; layout must work in landscape |

Do **not** use `device_info_plus` for orientation on web/PWA.

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
