// Background app asset warmup from the static landing (single-origin).
// Registers the app cache service worker and populates the versioned Cache
// Storage bucket used by tentura-app-cache-sw.js.

import { warmUrlsFromManifest } from './browser_compatibility.js';

const MANIFEST_URL = '/wasm-preload-manifest.json';
const SW_URL = '/tentura-app-cache-sw.js';
const MAX_CONCURRENT = 4;

/**
 * Whether to start SW registration and asset downloads.
 * @param {{ env?: { inApp?: boolean }, connection?: { saveData?: boolean, effectiveType?: string } | null }} opts
 */
export function shouldPreloadAppAssets({ env = {}, connection = null } = {}) {
  if (env.inApp) return false;
  if (connection?.saveData === true) return false;
  const et = connection?.effectiveType;
  if (et === 'slow-2g' || et === '2g') return false;
  return true;
}

function scheduleIdle(fn) {
  if (typeof requestIdleCallback === 'function') {
    requestIdleCallback(() => fn(), { timeout: 2000 });
  } else {
    setTimeout(fn, 0);
  }
}

function lowPriorityFetch(url) {
  return fetch(url, { credentials: 'same-origin', priority: 'low' });
}

async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register(SW_URL);
  } catch (_) {
    /* blocked or unsupported */
  }
}

async function fetchManifest() {
  try {
    const res = await lowPriorityFetch(MANIFEST_URL);
    if (!res.ok) return null;
    return res.json();
  } catch (_) {
    return null;
  }
}

function assetUrls(manifest) {
  if (!manifest?.version) return [];
  return warmUrlsFromManifest(manifest);
}

async function warmOneUrl(url, cache) {
  try {
    const req = url.startsWith('/') ? url : `/${url}`;
    if (cache) {
      const hit = await cache.match(req);
      if (hit) return;
    }
    const resp = await lowPriorityFetch(req);
    if (!resp.ok) return;
    if (cache) {
      try {
        await cache.put(req, resp.clone());
      } catch (_) {
        /* quota / private mode */
      }
    }
  } catch (_) {
    /* cancelled navigation, network error */
  }
}

async function warmAssets(urls, cacheName) {
  let cache = null;
  if ('caches' in window && cacheName) {
    try {
      cache = await caches.open(cacheName);
    } catch (_) {
      cache = null;
    }
  }

  let index = 0;
  const workers = Array.from({ length: Math.min(MAX_CONCURRENT, urls.length) }, async () => {
    while (index < urls.length) {
      const url = urls[index++];
      await warmOneUrl(url, cache);
    }
  });
  await Promise.all(workers);
}

async function runPreload(track) {
  const manifest = await fetchManifest();
  if (!manifest) return;
  const urls = assetUrls(manifest);
  if (urls.length === 0) return;
  const cacheName = `tentura-app-assets-${manifest.version}`;
  scheduleIdle(() => {
    warmAssets(urls, cacheName)
      .then(() => {
        track('app_preload_done', {
          version: manifest.version,
          assets: urls.length,
        });
      })
      .catch(() => {});
  });
}

/**
 * Fire-and-forget app asset warmup. Never throws; safe to call before preview fetch.
 * @param {{ env?: object, track?: (name: string, data?: object) => void }} opts
 */
export function startAppPreload({ env = {}, track = () => {} } = {}) {
  const connection =
    typeof navigator !== 'undefined' && navigator.connection
      ? navigator.connection
      : null;

  if (!shouldPreloadAppAssets({ env, connection })) {
    track('app_preload_skipped', {
      inApp: Boolean(env.inApp),
      saveData: connection?.saveData === true,
      effectiveType: connection?.effectiveType ?? null,
    });
    return;
  }

  track('app_preload_start');
  registerServiceWorker().catch(() => {});
  runPreload(track).catch(() => {});
}
