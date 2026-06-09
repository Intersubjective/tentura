/// Signed-out landing URL on the public host.
String publicLandingUrl(String publicOrigin) {
  return publicOrigin.endsWith('/') ? publicOrigin : '$publicOrigin/';
}

/// Invite page URL when the OAuth/email flow preserved an invite [returnTo].
String? invitePageUrlFromReturnTo({
  required String returnTo,
  required String publicOrigin,
}) {
  if (returnTo.isEmpty) return null;
  final uri = returnTo.startsWith('/')
      ? Uri.parse(publicOrigin).replace(
          path: returnTo.split('?').first,
        )
      : Uri.tryParse(returnTo.split('?').first);
  if (uri == null) return null;
  final segments = uri.pathSegments;
  if (segments.length >= 2 &&
      segments[0] == 'invite' &&
      segments[1].isNotEmpty) {
    return Uri.parse(publicOrigin)
        .replace(path: '/invite/${segments[1]}')
        .toString();
  }
  return null;
}

String _escapeHtmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');

/// Shown when a sign-in method succeeds at the provider but Tentura has no
/// matching account and the server is invite-only (no invite in this flow).
String renderAuthInviteRequiredPage({
  required String landingUrl,
  String? inviteUrl,
}) {
  final safeLanding = _escapeHtmlAttr(landingUrl);
  final safeInvite = inviteUrl == null ? '' : _escapeHtmlAttr(inviteUrl);
  final inviteCta = inviteUrl == null
      ? ''
      : '''
      <a class="btn btn-secondary" href="$safeInvite">Return to your invite</a>''';

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>No account yet — Tentura</title>
  <style>
    :root {
      --bg: #0f1115;
      --card: #181b22;
      --fg: #f5f6f8;
      --muted: #9aa3b2;
      --accent: #5b8cff;
      --accent-fg: #fff;
      --radius: 14px;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; height: 100%; }
    body {
      background: var(--bg);
      color: var(--fg);
      font: 16px/1.5 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    main {
      min-height: 100%;
      display: grid;
      place-items: center;
      padding: 24px;
    }
    .card {
      width: 100%;
      max-width: 420px;
      background: var(--card);
      border-radius: var(--radius);
      padding: 28px 24px 24px;
      text-align: center;
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.35);
    }
    .eyebrow {
      font-size: 13px;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      color: var(--accent);
      margin: 0 0 8px;
    }
    h1 { font-size: 20px; margin: 8px 0 6px; }
    p { color: var(--muted); margin: 6px 0 16px; }
    .hint { font-size: 13px; margin-top: 12px; }
    .btn {
      display: block;
      width: 100%;
      padding: 14px 16px;
      margin: 8px 0 0;
      border: 0;
      border-radius: 10px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      text-align: center;
    }
    .btn-primary { background: var(--accent); color: var(--accent-fg); }
    .btn-secondary {
      background: transparent;
      color: var(--fg);
      border: 1px solid #2a2f3a;
    }
    .btn:hover { filter: brightness(1.08); }
    .btn:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: 2px;
    }
    @media (prefers-reduced-motion: reduce) {
      .btn:hover { filter: none; }
    }
  </style>
</head>
<body>
  <main>
    <section class="card" aria-labelledby="auth-invite-required-title">
      <p class="eyebrow">Invite only</p>
      <h1 id="auth-invite-required-title">No account found for this sign-in</h1>
      <p>
        Tentura is a private network. This sign-in is not linked to a profile
        yet, so we could not log you in.
      </p>
      <p>
        New here? Ask someone who uses Tentura for a personal invite link.
        Already have an account? Try another sign-in method on the landing page.
      </p>
      <a class="btn btn-primary" href="$safeLanding">Back to sign in</a>
      $inviteCta
      <p class="hint">
        On the landing page you can paste an invite link or code, use email, or
        try a different sign-in option.
      </p>
    </section>
  </main>
</body>
</html>
''';
}
