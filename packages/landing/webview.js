// In-app-webview detection -> two-tier UX.
//   Tier 1 (system browser): full auth CTAs (wired in Phase 1).
//   Tier 2 (in-app webview): "open in your browser" primary CTA.
const ua = navigator.userAgent || '';

export function detectEnvironment() {
  const isIOS = /iPhone|iPad|iPod/i.test(ua);
  const isAndroid = /Android/i.test(ua);
  const inApp =
    /(FBAN|FBAV|Instagram|Line\/|Twitter|TikTok|musical_ly|WhatsApp|Telegram|Snapchat|GSA|MicroMessenger)/i.test(
      ua,
    ) ||
    // Generic Android System WebView marker.
    (isAndroid && /;\s*wv\)/i.test(ua));
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
