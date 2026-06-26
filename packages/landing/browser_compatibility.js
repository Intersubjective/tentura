// Mirrors Flutter engine browser_environment.js + loader.js build selection
// for the dart2wasm + skwasm entry (default Tentura web bootstrap).

/** @type {Record<string, boolean>} */
export const DEFAULT_WASM_ALLOW = {
  blink: true,
  gecko: false,
  webkit: false,
  unknown: false,
};

/** @returns {'blink' | 'gecko' | 'webkit' | 'unknown'} */
export function browserEngine() {
  if (
    navigator.vendor === 'Google Inc.' ||
    navigator.userAgent.includes('Edg/')
  ) {
    return 'blink';
  }
  if (navigator.vendor === 'Apple Computer, Inc.') {
    return 'webkit';
  }
  if (navigator.vendor === '' && navigator.userAgent.includes('Firefox')) {
    return 'gecko';
  }
  return 'unknown';
}

export function supportsWasmGC() {
  try {
    const bytes = new Uint8Array([
      0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0,
    ]);
    return WebAssembly.validate(bytes);
  } catch {
    return false;
  }
}

/** @returns {2 | 1 | -1} */
export function webGLVersion() {
  const canvas = document.createElement('canvas');
  canvas.width = 1;
  canvas.height = 1;
  if (canvas.getContext('webgl2') != null) return 2;
  if (canvas.getContext('webgl') != null) return 1;
  return -1;
}

/**
 * Whether Flutter will pick the dart2wasm + skwasm build (default loader).
 * @param {Record<string, boolean>} [wasmAllowList]
 */
export function prefersWasmApp(wasmAllowList = DEFAULT_WASM_ALLOW) {
  const engine = browserEngine();
  const allow =
    wasmAllowList[engine] ?? DEFAULT_WASM_ALLOW[engine] ?? false;
  return supportsWasmGC() && webGLVersion() > 0 && allow;
}

/**
 * @param {object} manifest
 * @param {boolean} [prefersWasm]
 * @returns {string[]}
 */
export function warmUrlsFromManifest(manifest, prefersWasm = prefersWasmApp()) {
  const shared = manifest.sharedPreload ?? [];
  const path = prefersWasm
    ? (manifest.wasmPreload ?? [])
    : (manifest.jsPreload ?? []);
  return dedupeUrls([...path, ...shared]);
}

/** @param {string[]} urls */
export function dedupeUrls(urls) {
  const seen = new Set();
  const out = [];
  for (const u of urls) {
    if (!u || seen.has(u)) continue;
    seen.add(u);
    out.push(u);
  }
  return out;
}
