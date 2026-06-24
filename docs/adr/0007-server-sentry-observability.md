# ADR 0007: Server Sentry observability (Dart API)

## Status

Accepted (2026-06-24)

## Context

Tentura runs a pure-Dart server (`dart build cli`) in multiple isolates (web workers + task worker). Errors were previously handled with `print`/`runZonedGuarded` only; `Logger.root` had no listeners. Client Sentry (ADR 0006) deferred distributed tracing until the server could continue inbound `sentry-trace` / `baggage` headers.

Three Sentry projects exist: **server**, **client**, and **landing**.

## Decision

1. **SDK**: `sentry` ^9.22.0 in `tentura_server`. Skip `Sentry.init` when `SERVER_SENTRY_DSN` is empty (local, tests, deploys without the var).

2. **Init topology**: `Sentry.init` in the main process (`bin/tentura.dart`) and inside each worker isolate (`serveWeb`, `serveTask`) via shared `initSentry(appRunner:)`. Hub is isolate-local.

3. **Release vs runtime config**:
   - Baked into the image at CI build: `SENTRY_RELEASE=tentura-server@<semver>`, `SENTRY_DIST=<git-sha>` (`Dockerfile_build`, `Dockerfile.server`).
   - Runtime env (VPS / `compose.prod.yaml`): `SERVER_SENTRY_DSN`, optional `SENTRY_TRACES_SAMPLE_RATE` (default `1.0`). Sentry `environment` reuses existing `Env.environment` (`dev` / `prod` / `test`).

4. **Logging**: `Logger.root` → formatted stdout sink always; when Sentry enabled, SEVERE+ → capture, INFO/WARNING → breadcrumbs.

5. **Request transactions**: Shelf middleware starts a per-request transaction on a cloned request `Hub`. Excluded: `/health`, `/graphiql`, `/api/v2/ws`. GraphQL operation name renames the transaction in `GraphqlController` after the body is parsed (middleware must not consume the body).

6. **Distributed tracing**: Parse inbound `sentry-trace` and `baggage`; build `SentryTransactionContext.fromSentryTrace(...)`. **Propagation-context seeding is required**: set `hub.scope.propagationContext.traceId` (and baggage/sample state) before `startTransactionWithContext`, because the SDK overwrites the transaction trace id from the scope propagation context. Implemented in `sentry_trace_propagation.dart`; covered by `sentry_trace_continuation_test.dart`.

7. **Request-local scope**: Per-request `SentryRequestContext` (cloned `Hub` + transaction + sanitized `SentryRequest`) lives in `request.context`. Never use global `Sentry.configureScope` for request user/IP — Shelf serves concurrent requests in one isolate.

8. **GraphQL capture**: Report catch-all errors and `ExceptionBase` whose code is an `unspecified*` variant (code spaces 1000/1100/1200/1300/1400). Named domain rejections (auth, validation, coordination) are not captured.

9. **PII**: `sendDefaultPii=true`; middleware attaches `SentryUser(id: jwt.sub, ipAddress: …)` and sanitized `SentryRequest`. `beforeSend` strips `Authorization`, `Cookie`, `Set-Cookie`, and request bodies.

10. **Benign drops**: `SocketException`, connection reset / broken pipe, client WebSocket disconnect noise.

11. **Client activation (ADR 0006 follow-up)**: Both Hasura and V2 `HttpLink`s use `SentryHttpClient(captureFailedRequests: false)`. `tracePropagationTargets` lists the public origin and GraphQL paths derived from `SERVER_NAME`. End-to-end server transactions complete on Tentura V2; Hasura receives propagation headers but is not Sentry-instrumented.

## Consequences

- Deployed server containers report to the **server** Sentry project when `SERVER_SENTRY_DSN` is set on the VPS.
- Release/dist tagging is automatic from CI-built images; operators only configure DSN and optional sample rate.
- Trace continuation depends on seeding propagation context — a subtle SDK behavior documented here and tested.
- Hasura-routed GraphQL calls emit client spans and headers but do not produce server-side Tentura transactions unless the operation is in the V2 direct set.

## Related

- [ADR 0006: Client Sentry observability](./0006-client-sentry-observability.md)
