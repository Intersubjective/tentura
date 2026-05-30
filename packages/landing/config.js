// Runtime config — there is NO build step, so values are read at runtime instead
// of injected by a bundler. Edit per-deploy, or substitute at deploy time (CI sed).
//   apiBase  '' = same origin (landing host proxies /api to Tentura)
//   appBase  absolute WASM-app origin (subdomain); CI sets APP_BASE for dev/prod
//   sentryDsn '' = analytics disabled (no-op)
window.TENTURA = {
  sentryDsn: '',
  apiBase: '',
  appBase: 'https://app.dev.tentura.io/',
};
