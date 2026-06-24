# ADR 0009: Landing Sentry observability

## Status

Accepted (2026-06-24)

## Context

The static invite landing (`packages/landing`) is the primary entry for
invite-only signup (email magic link, Google OAuth, seed recovery redirect).
Phase 0 added a minimal Sentry browser SDK funnel (`analytics.js`), but it
could not stitch auth outcomes across page loads, lacked tracing/Web Vitals,
and had no cross-project correlation with the Flutter client or Dart server
Sentry projects (ADR 0006, ADR 0007).

Low traffic (invite-only) justifies high sampling and full masked Session
Replay for silent abandonment, while enumeration-safe email responses must not
leak whether an address is registered.

## Decision

1. **SDK bundle**: `bundle.tracing.replay.min.js@8.39.0` from the Sentry CDN
   (single allowed external script). Tracing at `tracesSampleRate: 1.0`;
   `tracePropagationTargets` scoped to same-origin `/api/v2/*` so server traces
   continue via ADR 0007.

2. **Session Replay**: ON with `maskAllText`, `maskAllInputs`, `blockAllMedia`;
   `replaysSessionSampleRate` and `replaysOnErrorSampleRate` at `1.0` initially.

3. **Release / environment**: `sentryEnvironment` and `sentryRelease` in
   `config.js`, injected at CI deploy (mirroring `sentryDsn` sed).

4. **Funnel backbone**: discrete `captureMessage('funnel:…')` events plus
   breadcrumbs — not a single cross-redirect trace. Client-visible failures use
   `captureException` via `trackError`.

5. **Identity model**:
   - Ephemeral `visit_id` in `sessionStorage` on landing load (scope tag).
   - `auth_attempt_id` + `auth_method` once the user chooses a path.
   - After auth: `Sentry.setUser({ id: accountId })`, clear `visit_id`.

6. **Email `auth_attempt_id`**: server mints via `EmailAuthTransactionEntity.newId`
   and returns `attemptId` unconditionally for every valid JSON
   `/api/v2/auth/email/start` body. Persisted as `email_auth_transaction.id` only
   when a transaction row is created. Magic-link token never exposed.

7. **Google OAuth**: landing creates opaque id, passes to
   `/api/auth/google/start` and `returnTo`; server signs into OAuth state cookie
   and appends to Google `state` query as non-authoritative telemetry
   (`csrf.attemptId`). CSRF verification uses cookie state only.

8. **Seed recovery**: landing puts `auth_attempt_id` on `/recover?…#/recover-seed`;
   WASM client tags client Sentry and sends `X-Tentura-Auth-Attempt-Id` on
   `/api/v2/session/from-bearer` (metadata only — Bearer token is the auth boundary).

9. **Funnel vs outcomes**: client events like `email_start_clicked` mean “user
   tried”; server/client `email_start_outcome`, `google_callback_outcome`,
   `seed_recovery_failed` mean what actually happened.

10. **Cross-project join**: `auth_attempt_id` links landing, client, and server
    Sentry projects. `sendDefaultPii: false` on landing; no email/seed in events.

## Event taxonomy (stable Discover queries)

**Landing funnel actions**: `landing_view`, `preview_loaded`, `preview_error`,
`email_start_clicked`, `email_start_accepted`, `google_start_clicked`,
`seed_recovery_clicked`, `post_signup_view`, `signup_name_saved`,
`signup_name_error`, `onboarding_done`, `onboarding_skipped`.

**Server email**: `email_start_outcome` — `sent`, `invalid_format`, `rate_limited`,
`invite_required_skip`, `mail_unconfigured`, `unexpected_error`.

**Server Google**: `google_start_outcome`, `google_callback_outcome` — `redirected`,
`misconfigured`, `missing_code_or_state`, `missing_state_cookie`, `state_mismatch`,
`token_exchange_failed`, `invite_required`, `credential_conflict`, `success_existing`,
`success_new`, `unexpected_error`.

**Seed**: `seed_recovery_started`, `seed_recovery_failed`,
`seed_recovery_cookie_established` — `invalid_seed`, `remote_sign_in_failed`,
`profile_fetch_failed`, `local_store_failed`, `session_cookie_failed`, `success`,
`unexpected_error`.

## Consequences

- Operators can filter landing funnels by `environment`, `release`, `visit_id`,
  and join auth failures across projects via `auth_attempt_id`.
- Email enumeration safety preserved: response shape is always `{ ok, attemptId }`.
- Replay and tracing sample rates should be lowered when traffic grows.

## Related

- [ADR 0006: Client Sentry observability](./0006-client-sentry-observability.md)
- [ADR 0007: Server Sentry observability](./0007-server-sentry-observability.md)
