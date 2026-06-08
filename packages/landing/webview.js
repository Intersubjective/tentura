// In-app-webview detection -> two-tier UX.
//   Tier 1 (system browser): full auth CTAs (wired in Phase 1).
//   Tier 2 (in-app webview): "open in your browser" primary CTA.
const UA_IN_APP =
  /(FBAN|FBAV|Instagram|Line\/|Twitter|TikTok|musical_ly|WhatsApp|Telegram|Snapchat|GSA|MicroMessenger)/i;

// Telegram often reuses the system-browser UA; the app injects these globals instead.
export function isTelegramInAppWebview(win = globalThis) {
  return (
    typeof win.TelegramWebview !== 'undefined' ||
    (typeof win.TelegramWebviewProxy !== 'undefined' &&
      typeof win.TelegramWebviewProxyProto !== 'undefined')
  );
}

export function detectEnvironment(signals = {}) {
  const ua = signals.ua ?? (navigator.userAgent || '');
  const win = signals.window ?? globalThis;
  const isIOS = /iPhone|iPad|iPod/i.test(ua);
  const isAndroid = /Android/i.test(ua);
  const uaInApp =
    UA_IN_APP.test(ua) ||
    // Generic Android System WebView marker.
    (isAndroid && /;\s*wv\)/i.test(ua));
  const inApp = uaInApp || isTelegramInAppWebview(win);
  return { isIOS, isAndroid, inApp, tier: inApp ? 2 : 1 };
}

// Android: an intent:// URL hands off to the system browser. There is NO clean
// programmatic iOS escape (Risk #2) — on iOS the explicit "copy link, open in
// Safari" tap is the intended design; do not engineer an escape.
export function androidIntentUrl(href) {
  const u = new URL(href, location.href);
  const scheme = u.protocol.replace(':', '');
  return `intent://${u.host}${u.pathname}${u.search}#Intent;scheme=${scheme};end`;
}
