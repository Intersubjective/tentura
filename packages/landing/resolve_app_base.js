/**
 * Resolves the WASM app origin from window.TENTURA.appBase.
 * @returns {string} Normalized base URL with trailing slash.
 */
export function resolveAppBase() {
  const raw = String((window.TENTURA || {}).appBase || '').trim();
  if (!raw) {
    throw new Error(
      'Landing misconfigured: set appBase in config.js (CI) or config.local.js (local dev)',
    );
  }
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`Landing misconfigured: appBase is not a valid URL (${raw})`);
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error(
      `Landing misconfigured: appBase must use http or https (${raw})`,
    );
  }
  if (!parsed.host) {
    throw new Error(`Landing misconfigured: appBase has no host (${raw})`);
  }
  return parsed.origin + '/';
}
