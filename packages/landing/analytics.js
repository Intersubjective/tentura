// Funnel analytics. Decision (Phase 0): the Sentry browser SDK is the ONLY
// permitted external dependency, and it is loaded from its CDN as a plain
// <script> in index.html (deps-light, no npm). Events fire BEFORE any WASM —
// a first-class Phase 0 deliverable — so the invite funnel is observable
// independent of the app.
const cfg = window.TENTURA || {};
const dsn = cfg.sentryDsn || '';
let ready = false;

export function initAnalytics() {
  // `Sentry` global comes from the CDN script; may be absent if blocked/unset.
  const Sentry = window.Sentry;
  if (!dsn || !Sentry) return; // no-op when unconfigured (local/dev)
  Sentry.init({
    dsn,
    tracesSampleRate: 0,
    ignoreErrors: ['SocketException'],
  });
  ready = true;
}

/// Record a funnel step. Safe to call before init (drops silently).
export function track(event, data = {}) {
  if (!ready) return;
  const Sentry = window.Sentry;
  Sentry.addBreadcrumb({ category: 'funnel', message: event, data });
  Sentry.captureMessage(`funnel:${event}`, { level: 'info', extra: data });
}
