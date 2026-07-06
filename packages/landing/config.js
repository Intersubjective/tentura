// Runtime config — there is NO build step, so values are read at runtime instead
// of injected by a bundler. Edit per-deploy, or substitute at deploy time (CI sed).
//   apiBase  '' = same origin (landing host proxies /api to Tentura)
//   googleEnabled  show Google OAuth CTA when true (requires server GOOGLE_CLIENT_ID)
//   emailOnlyQa  hide Google in QA sessions that must exercise email auth
//   qaTestLogin  show QA "Test login" button (non-prod deploys only; server must have QA_SIMPLE_LOGIN_MODE=true)
//   sentryDsn '' = analytics disabled (no-op)
//   sentryEnvironment / sentryRelease — Sentry env + release (CI sed at deploy)
//
// Local OAuth dev: match repo-root .env SERVER_NAME (lvh.me :9443).
window.TENTURA = {
  sentryDsn: '',
  sentryEnvironment: '',
  sentryRelease: '',
  apiBase: '',
  googleEnabled: false,
  emailOnlyQa: false,
  qaTestLogin: false,
};
