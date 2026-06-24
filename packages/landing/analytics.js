// Funnel analytics. Decision (Phase 0): the Sentry browser SDK is the ONLY
// permitted external dependency, and it is loaded from its CDN as a plain
// <script> in index.html (deps-light, no npm). Events fire BEFORE any WASM —
// a first-class Phase 0 deliverable — so the invite funnel is observable
// independent of the app.
const VISIT_KEY = 'tentura_visit_id';
let ready = false;

const BROWSER_EXTENSION_DENY = [
  /extensions\//i,
  /^chrome:\/\//i,
  /^moz-extension:/i,
];

function buildTracePropagationTargets(apiBase, origin) {
  const targets = ['/api/v2/'];
  try {
    const o = new URL(origin);
    targets.push(`${o.origin}/api/v2/`);
  } catch (_) {
    /* invalid origin in tests */
  }
  if (apiBase) {
    try {
      const base = new URL(apiBase, origin);
      targets.push(`${base.origin}/api/v2/`);
    } catch (_) {
      /* invalid apiBase */
    }
  }
  return targets;
}

function stripEventPii(event) {
  if (event.user) {
    delete event.user.email;
    delete event.user.username;
  }
  return event;
}

function randomHex(byteCount) {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function initAnalytics() {
  const cfg = window.TENTURA || {};
  const dsn = cfg.sentryDsn || '';
  const sentryEnvironment = cfg.sentryEnvironment || '';
  const sentryRelease = cfg.sentryRelease || '';
  const Sentry = window.Sentry;
  if (!dsn || !Sentry) return;
  const apiBase = cfg.apiBase || '';
  Sentry.init({
    dsn,
    environment: sentryEnvironment || undefined,
    release: sentryRelease || undefined,
    sendDefaultPii: false,
    tracesSampleRate: 1.0,
    tracePropagationTargets: buildTracePropagationTargets(
      apiBase,
      typeof location !== 'undefined' ? location.origin : 'https://localhost',
    ),
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({
        maskAllText: true,
        maskAllInputs: true,
        blockAllMedia: true,
      }),
    ],
    replaysSessionSampleRate: 1.0,
    replaysOnErrorSampleRate: 1.0,
    ignoreErrors: ['SocketException'],
    denyUrls: BROWSER_EXTENSION_DENY,
    beforeSend: stripEventPii,
  });
  ready = true;
}

export function initVisit({ env, hasCode }) {
  let visitId;
  try {
    visitId = sessionStorage.getItem(VISIT_KEY);
    if (!visitId) {
      visitId = `V${randomHex(16)}`;
      sessionStorage.setItem(VISIT_KEY, visitId);
    }
  } catch {
    visitId = `V${randomHex(16)}`;
  }
  const Sentry = window.Sentry;
  if (Sentry && ready) {
    const scope = Sentry.getCurrentScope();
    scope.setTag('visit_id', visitId);
    scope.setTag('tier', env?.tier ?? '');
    scope.setTag('os', env?.os ?? '');
    scope.setTag('inApp', env?.inApp ? '1' : '0');
    scope.setTag('hasCode', hasCode ? '1' : '0');
  }
  return visitId;
}

export function newAttemptId(kind) {
  const prefix = kind === 'google' ? 'G' : kind === 'seed' ? 'S' : 'A';
  return `${prefix}${randomHex(16)}`;
}

export function setAttemptId(id, method) {
  if (!id) return;
  const Sentry = window.Sentry;
  if (!Sentry || !ready) return;
  const scope = Sentry.getCurrentScope();
  scope.setTag('auth_attempt_id', id);
  scope.setTag('auth_method', method);
}

export function setAccount(accountId) {
  try {
    sessionStorage.removeItem(VISIT_KEY);
  } catch {
    /* storage blocked */
  }
  const Sentry = window.Sentry;
  if (!Sentry || !ready) return;
  Sentry.setUser({ id: accountId });
  Sentry.getCurrentScope().setTag('visit_id', '');
}

export function track(event, data = {}) {
  if (!ready) return;
  const Sentry = window.Sentry;
  Sentry.addBreadcrumb({ category: 'funnel', message: event, data });
  Sentry.captureMessage(`funnel:${event}`, { level: 'info', extra: data });
}

export function trackError(event, err, data = {}) {
  if (!ready) return;
  const Sentry = window.Sentry;
  Sentry.addBreadcrumb({
    category: 'funnel',
    message: event,
    data: { ...data, error: String(err) },
  });
  Sentry.captureException(err, { extra: { funnel_event: event, ...data } });
}

export function resetAnalyticsForTests() {
  ready = false;
}

export function trackOutcome(event, { authOutcome, method, ...rest }) {
  if (!ready) return;
  const Sentry = window.Sentry;
  Sentry.addBreadcrumb({
    category: 'auth_outcome',
    message: event,
    data: { authOutcome, method, ...rest },
  });
  Sentry.captureMessage(`auth:${event}`, {
    level: 'info',
    tags: {
      auth_outcome: authOutcome,
      ...(method ? { auth_method: method } : {}),
    },
    extra: rest,
  });
}
