/// HTML interstitial for OAuth start/callback: register app-cache SW and warm assets.
String renderOAuthWarmupInterstitial({
  required String redirectUri,
  String manifestUrl = '/wasm-preload-manifest.json',
  String serviceWorkerUrl = '/tentura-app-cache-sw.js',
  int maxWaitMs = 800,
}) {
  final safeRedirect = _escapeJsString(redirectUri);
  final safeManifest = _escapeJsString(manifestUrl);
  final safeSw = _escapeJsString(serviceWorkerUrl);
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Signing in…</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; color: #333; }
  </style>
</head>
<body>
  <p>Signing in…</p>
  <script type="module">
import { warmUrlsFromManifest } from '/browser_compatibility.js';

const REDIRECT = '$safeRedirect';
const MANIFEST = '$safeManifest';
const SW_URL = '$safeSw';
const MAX_WAIT = $maxWaitMs;

function go() {
  window.location.replace(REDIRECT);
}

async function warmAssets() {
  if (!('caches' in window)) return;
  try {
    const r = await fetch(MANIFEST, { credentials: 'same-origin' });
    if (!r.ok) return;
    const m = await r.json();
    if (!m?.version) return;
    const cacheName = 'tentura-app-assets-' + m.version;
    const urls = warmUrlsFromManifest(m);
    const cache = await caches.open(cacheName);
    await Promise.all(urls.map(async (url) => {
      try {
        const hit = await cache.match(url);
        if (hit) return;
        const resp = await fetch(url, { credentials: 'same-origin' });
        if (resp.ok) await cache.put(url, resp.clone());
      } catch (_) {}
    }));
  } catch (_) {}
}

async function registerSw() {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register(SW_URL);
  } catch (_) {}
}

const deadline = new Promise((resolve) => setTimeout(resolve, MAX_WAIT));

Promise.race([
  Promise.all([registerSw(), warmAssets()]),
  deadline,
]).finally(go);
  </script>
</body>
</html>
''';
}

String _escapeJsString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
