# ADR 0006: Client Sentry observability (Flutter WASM)

## Status

Accepted (2026-06-24)

## Context

The Flutter client had partial Sentry scaffolding (`sentry_flutter`, `SentryNavigatorObserver`, `sentry_drift`) but no DSN in CI, no release/dist tagging, and no structured error routing. The invite **landing** already reports funnel events to a separate Sentry project via runtime config.

Tentura uses three Sentry projects: **server**, **client** (this ADR), and **landing**. The deployed web app is built with `--wasm --profile --source-maps`.

## Decision

1. **Compile-time client config** via `--dart-define`: `SENTRY_DSN` (GitHub variable `CLIENT_SENTRY_DSN`, omitted when unset), `SENTRY_ENVIRONMENT` (explicit per deploy job, e.g. `dev`), `SENTRY_RELEASE=tentura@<semver>`, `SENTRY_DIST=<git-sha>`. Skip `SentryFlutter.init` when DSN is empty (local/CI without the var).

2. **Release vs dist**: `SENTRY_RELEASE` is `tentura@<clientVersion>` only; `SENTRY_DIST` is the commit SHA. Do **not** encode SHA in the release string as `+sha` — the `sentry_dart_plugin` treats the suffix after `+` as `dist`, which would mismatch SDK-only `release` assignment.

3. **SDK options**: `sendDefaultPii=true`, `tracesSampleRate=1.0` (revisit when traffic grows), `captureFailedRequests=false` (API failures flow through the classified `Logger` SEVERE bridge instead of duplicate HTTP auto-capture). Benign drops: `ConnectionUplinkException`, `AuthSessionLostException`, `SocketException`.

4. **User scope**: `AuthCubit` listener sets `SentryUser(id: currentAccountId)`; cleared on sign-out.

5. **Log bridge** (non-debug): `Logger.root` SEVERE+ → `captureException` / `captureMessage` (filtered); INFO/WARNING → breadcrumbs. Structured Sentry Logs (`enableLogs`) off.

6. **SentryWidget** wraps the root only on the Sentry-initialized path (not debug overlay path).

7. **Source-map upload deferred**: Sentry supports DWARF for WASM, not source maps; dart2wasm emits source maps. Official WASM symbolication is unsupported; only a non-stable community workaround exists. Errors are captured now; stack frames remain minified until we switch to dart2js or Sentry ships WASM source-map support. The `sentry:` pubspec block (`org`, `project: tentura-client`) is kept for future `dart run sentry_dart_plugin` enablement.

8. **Distributed tracing deferred**: GraphQL uses raw `gql_http_link` `HttpLink` without `SentryHttpClient`; `tracePropagationTargets` alone would be a no-op. Revisit with server Sentry (instrument link + CORS for `sentry-trace` / `baggage`).

## Consequences

- Deployed WASM builds report to the **client** Sentry project when `CLIENT_SENTRY_DSN` is set; without it, Sentry is fully disabled (no SDK overhead from empty DSN init).
- Stack traces in Issues are minified on WASM until symbol upload is enabled via dart2js or future WASM support.
- Some code paths both `log.severe` and rethrow may double-report (bridge + auto integration); acceptable for now.
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
