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
  <script>
(function () {
  var REDIRECT = '$safeRedirect';
  var MANIFEST = '$safeManifest';
  var SW_URL = '$safeSw';
  var MAX_WAIT = $maxWaitMs;

  function go() {
    window.location.replace(REDIRECT);
  }

  function warmAssets() {
    if (!('caches' in window)) return Promise.resolve();
    return fetch(MANIFEST, { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (m) {
        if (!m || !m.version) return;
        var cacheName = 'tentura-app-assets-' + m.version;
        var urls = [m.mainWasm].concat(m.preload || []).filter(Boolean);
        return caches.open(cacheName).then(function (cache) {
          return Promise.all(urls.map(function (url) {
            return cache.match(url).then(function (hit) {
              if (hit) return;
              return fetch(url, { credentials: 'same-origin' })
                .then(function (resp) {
                  if (resp.ok) return cache.put(url, resp.clone());
                })
                .catch(function () {});
            });
          }));
        });
      })
      .catch(function () {});
  }

  function registerSw() {
    if (!('serviceWorker' in navigator)) return Promise.resolve();
    return navigator.serviceWorker.register(SW_URL).catch(function () {});
  }

  var deadline = new Promise(function (resolve) {
    setTimeout(resolve, MAX_WAIT);
  });

  Promise.race([
    Promise.all([registerSw(), warmAssets()]),
    deadline,
  ]).finally(go);
})();
  </script>
</body>
</html>
''';
}

String _escapeJsString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
