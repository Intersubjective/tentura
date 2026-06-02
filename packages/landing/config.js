// Runtime config — there is NO build step, so values are read at runtime instead
// of injected by a bundler. Edit per-deploy, or substitute at deploy time (CI sed).
//   apiBase  '' = same origin (landing host proxies /api to Tentura)
//   appBase  same-origin WASM app URL; CI sets APP_BASE from CLIENT_SERVER_NAME
//   googleEnabled  show Google OAuth CTA when true (requires server GOOGLE_CLIENT_ID)
//   sentryDsn '' = analytics disabled (no-op)
//
// Local OAuth dev: match repo-root .env SERVER_NAME (lvh.me :9443).
window.TENTURA = {
  sentryDsn: '',
  apiBase: '',
  appBase: '',
  googleEnabled: false,
};
