# ADR 0006: Client Sentry observability (Flutter WASM)

## Status

Accepted (2026-06-24)

## Context

The Flutter client had partial Sentry scaffolding (`sentry_flutter`, `SentryNavigatorObserver`, `sentry_drift`) but no DSN in CI, no release/dist tagging, and no structured error routing. The invite **landing** already reports funnel events to a separate Sentry project via runtime config.

Tentura uses three Sentry projects: **server**, **client** (this ADR), and **landing**. The deployed web app is built with `--wasm --profile --source-maps`.

## Decision

1. **Compile-time client config** via `--dart-define`: `SENTRY_DSN` (GitHub variable `CLIENT_SENTRY_DSN`, omitted when unset), `SENTRY_ENVIRONMENT` (explicit per deploy job, e.g. `dev`), `SENTRY_RELEASE=tentura@<semver>`, `SENTRY_DIST=<git-sha>`. Skip `SentryFlutter.init` when DSN is empty (local/CI without the var).

2. **Release vs dist**: `SENTRY_RELEASE` is `tentura@<clientVersion>` only; `SENTRY_DIST` is the commit SHA. Do **not** encode SHA in the release string as `+sha` — the `sentry_dart_plugin` treats the suffix after `+` as `dist`, which would mismatch SDK-only `release` assignment.

3. **SDK options**: `sendDefaultPii=true`, `tracesSampleRate=1.0` (revisit when traffic grows), `captureFailedRequests=false` (API failures flow through explicit classified reporters instead of duplicate HTTP auto-capture). Benign drops: `ConnectionUplinkException`, `AuthSessionLostException`, `SocketException`.

4. **User scope**: `AuthCubit` listener sets `SentryUser(id: currentAccountId)`; cleared on sign-out.

5. **Explicit issue reporting, breadcrumb log bridge** (non-debug): `reportUserFacingError` and explicit Sentry message reporters create Issues. `Logger.root` records INFO/WARNING/SEVERE logs as breadcrumbs only; log severity does not create Issues. This keeps logging diagnostic and makes Sentry issue ownership explicit at user-facing/error-boundary call sites.

6. **SentryWidget** wraps the root only on the Sentry-initialized path (not debug overlay path).

7. **Source maps on WASM — deferred.** Sentry supports DWARF for WASM, not source maps; dart2wasm emits source maps. Official WASM symbolication is unsupported; only a non-stable community workaround exists. Errors are captured now; stack frames remain minified until we switch to dart2js or Sentry ships WASM source-map support. The `sentry:` pubspec block (`org`, `project: tentura-client`) is kept for future `dart run sentry_dart_plugin` enablement.

8. **Distributed tracing — partially implemented (2026-06 verify).** GraphQL HTTP clients use `SentryHttpClient` when `SENTRY_DSN` is set (`build_client.dart`); `tracePropagationTargets` includes the API origin and V1/V2 GraphQL paths (`sentry_init.dart`). End-to-end trace correlation still depends on server Sentry accepting `sentry-trace` / `baggage` (see ADR 0007) and CORS — treat Issues as minified + optionally linked spans until verified in staging.

## Consequences

- Deployed WASM builds report to the **client** Sentry project when `CLIENT_SENTRY_DSN` is set; without it, Sentry is fully disabled (no SDK overhead from empty DSN init).
- Stack traces in Issues are minified on WASM until symbol upload is enabled via dart2js or future WASM support.
- Sentry Issues are created only by explicit reporters. Logs enrich Issues as breadcrumbs, so callers do not need to know hidden `Logger.severe` side effects.
- Enabling source maps later requires `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, matching `SENTRY_RELEASE`/`SENTRY_DIST` on SDK and plugin, and verifying `url_prefix` against deployed asset paths.

## Enabling source-map upload later (dart2js path)

```bash
flutter build web --release --source-maps   # drop --wasm for readable traces
export SENTRY_AUTH_TOKEN=...
export SENTRY_ORG=intersubjective
export SENTRY_PROJECT=tentura-client
export SENTRY_RELEASE=tentura@2.6.0
export SENTRY_DIST=<git-sha>
dart run sentry_dart_plugin
```

Ensure CI passes the same `SENTRY_RELEASE` and `SENTRY_DIST` dart-defines as the SDK init.
