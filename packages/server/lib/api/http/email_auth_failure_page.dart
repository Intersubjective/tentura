/// Accessible HTML pages for email magic-link confirmation and errors.
library;

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeHtmlAttr(String value) => _escapeHtml(value);

String _requestNewLinkHref({required String landingUrl, String? inviteCode}) {
  if (inviteCode != null && inviteCode.isNotEmpty) {
    return _escapeHtmlAttr('/invite/${Uri.encodeComponent(inviteCode)}');
  }
  return _escapeHtmlAttr(landingUrl);
}

String _emailAuthPageShell({
  required String title,
  required String headingId,
  required String heading,
  required String bodyHtml,
  String? actionsHtml,
  String alertRole = '',
}) {
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>$title</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f5f6f8;
      --card: #ffffff;
      --fg: #111318;
      --muted: #4b5563;
      --accent: #2563eb;
      --accent-fg: #ffffff;
      --border: #d1d5db;
      --danger: #b91c1c;
      --radius: 14px;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0f1115;
        --card: #181b22;
        --fg: #f5f6f8;
        --muted: #9aa3b2;
        --accent: #5b8cff;
        --border: #2a2f3a;
        --danger: #f87171;
      }
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; }
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
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.12);
    }
    h1 { font-size: 20px; margin: 0 0 12px; line-height: 1.3; }
    p { color: var(--muted); margin: 0 0 12px; }
    p:last-of-type { margin-bottom: 0; }
    .actions { margin-top: 20px; display: flex; flex-direction: column; gap: 8px; }
    .btn {
      display: block;
      width: 100%;
      min-height: 44px;
      padding: 12px 16px;
      border: 0;
      border-radius: 10px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      text-align: center;
      line-height: 1.25;
    }
    .btn-primary { background: var(--accent); color: var(--accent-fg); }
    .btn-secondary {
      background: transparent;
      color: var(--fg);
      border: 1px solid var(--border);
    }
    .btn:hover { filter: brightness(1.06); }
    .btn:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: 2px;
    }
    form { margin: 0; }
    input[type="hidden"] { display: none; }
    .trace { font-family: ui-monospace, monospace; font-size: 13px; word-break: break-all; }
    details { margin-top: 16px; color: var(--muted); font-size: 14px; }
    details pre {
      white-space: pre-wrap;
      word-break: break-word;
      font-size: 12px;
      overflow-x: auto;
    }
    @media (prefers-reduced-motion: reduce) {
      .btn:hover { filter: none; }
    }
  </style>
</head>
<body>
  <main>
    <section class="card" aria-labelledby="$headingId"$alertRole>
      <h1 id="$headingId">$heading</h1>
      $bodyHtml
      ${actionsHtml == null ? '' : '<div class="actions">$actionsHtml</div>'}
    </section>
  </main>
</body>
</html>
''';
}

/// Confirmation page (GET, valid token). User must POST to sign in.
String renderEmailAuthConfirmPage({
  required String token,
  required bool isLink,
}) {
  final safeToken = _escapeHtmlAttr(token);
  final heading = isLink
      ? 'Confirm adding this email'
      : 'Confirm sign-in to Tentura';
  final body = isLink
      ? '<p>Tap below to add this email as a sign-in method for your account.</p>'
      : '<p>Tap below to finish signing in. Your email security scanner may have opened this page already — that is fine; the link is only used when you continue.</p>';

  return _emailAuthPageShell(
    title: isLink ? 'Confirm email link' : 'Confirm sign-in',
    headingId: 'email-auth-confirm-title',
    heading: heading,
    bodyHtml: body,
    actionsHtml: '''
<form method="post" action="/auth/email/verify">
  <input type="hidden" name="t" value="$safeToken">
  <button type="submit" class="btn btn-primary">${isLink ? 'Link this email' : 'Continue to Tentura'}</button>
</form>''',
  );
}

String renderEmailAuthExpiredPage({
  required String landingUrl,
  required int ttlMinutes,
  String? inviteCode,
}) {
  final newLink = _requestNewLinkHref(inviteCode: inviteCode, landingUrl: landingUrl);
  return _emailAuthPageShell(
    title: 'Link expired',
    headingId: 'email-auth-expired-title',
    heading: 'This sign-in link expired',
    bodyHtml:
        '<p>Email links expire after about $ttlMinutes minutes for security.</p>\n'
        '<p>Request a fresh link and open it once in your browser.</p>',
    actionsHtml:
        '<a class="btn btn-primary" href="$newLink">Request a new link</a>',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthAlreadyUsedPage({
  required String landingUrl,
  String? inviteCode,
}) {
  final newLink = _requestNewLinkHref(inviteCode: inviteCode, landingUrl: landingUrl);
  final openApp = _escapeHtmlAttr(landingUrl);
  return _emailAuthPageShell(
    title: 'Link already used',
    headingId: 'email-auth-used-title',
    heading: 'This sign-in link was already used',
    bodyHtml:
        '<p>Each email link works once. If you already signed in, you can open Tentura.</p>\n'
        '<p>Otherwise request a new link.</p>',
    actionsHtml: '''
<a class="btn btn-primary" href="$newLink">Request a new link</a>
<a class="btn btn-secondary" href="$openApp">Open Tentura</a>''',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthMissingPage({required String landingUrl}) {
  final safeLanding = _escapeHtmlAttr(landingUrl);
  return _emailAuthPageShell(
    title: 'Link incomplete',
    headingId: 'email-auth-missing-title',
    heading: 'This email link is incomplete',
    bodyHtml:
        '<p>The link in your email may be broken or truncated. Copy the full URL from the message, or request a new link.</p>',
    actionsHtml:
        '<a class="btn btn-primary" href="$safeLanding">Back to sign in</a>',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthInviteInvalidPage({
  required String landingUrl,
  String? inviteCode,
}) {
  final newLink = _requestNewLinkHref(inviteCode: inviteCode, landingUrl: landingUrl);
  return _emailAuthPageShell(
    title: 'Invite not found',
    headingId: 'email-auth-invite-invalid-title',
    heading: 'This invite is not valid',
    bodyHtml:
        '<p>We could not find the invite associated with this sign-up attempt.</p>\n'
        '<p>Ask your contact for a fresh invite link, then try again.</p>',
    actionsHtml:
        '<a class="btn btn-primary" href="$newLink">Back to sign in</a>',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthInviteExpiredPage({
  required String landingUrl,
  String? inviteCode,
}) {
  final newLink = _requestNewLinkHref(inviteCode: inviteCode, landingUrl: landingUrl);
  return _emailAuthPageShell(
    title: 'Invite expired',
    headingId: 'email-auth-invite-expired-title',
    heading: 'This invite has expired',
    bodyHtml:
        '<p>The invite used for this sign-up is no longer active.</p>\n'
        '<p>Ask for a new invite, then sign in or create your account again.</p>',
    actionsHtml:
        '<a class="btn btn-primary" href="$newLink">Back to sign in</a>',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthInviteUsedPage({
  required String landingUrl,
  String? inviteCode,
}) {
  final newLink = _requestNewLinkHref(inviteCode: inviteCode, landingUrl: landingUrl);
  final openApp = _escapeHtmlAttr(landingUrl);
  return _emailAuthPageShell(
    title: 'Invite already used',
    headingId: 'email-auth-invite-used-title',
    heading: 'This invite was already used',
    bodyHtml:
        '<p>That invite code has already been consumed. If you already have an account, sign in with Google or email.</p>',
    actionsHtml: '''
<a class="btn btn-primary" href="$openApp">Open Tentura</a>
<a class="btn btn-secondary" href="$newLink">Request a new link</a>''',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthAmbiguousIdentityPage({required String landingUrl}) {
  final safeLanding = _escapeHtmlAttr(landingUrl);
  return _emailAuthPageShell(
    title: 'Account conflict',
    headingId: 'email-auth-ambiguous-title',
    heading: 'We could not sign you in automatically',
    bodyHtml:
        '<p>Multiple accounts match this email address. Contact support with the reference below if you need help merging access.</p>',
    actionsHtml:
        '<a class="btn btn-primary" href="$safeLanding">Back to sign in</a>',
    alertRole: ' role="alert"',
  );
}

String renderEmailAuthInternalPage({
  required String traceId,
  String? debugDetails,
  String? retryToken,
}) {
  final safeTrace = _escapeHtml(traceId);
  final debugBlock = debugDetails == null || debugDetails.isEmpty
      ? ''
      : '<details><summary>Technical details (debug)</summary><pre>${_escapeHtml(debugDetails)}</pre></details>';
  final hiddenToken = retryToken == null || retryToken.isEmpty
      ? ''
      : '<input type="hidden" name="t" value="${_escapeHtmlAttr(retryToken)}">';

  return _emailAuthPageShell(
    title: 'Sign-in error',
    headingId: 'email-auth-internal-title',
    heading: 'Something went wrong while signing you in',
    bodyHtml:
        '<p>Your link may still work — try again with the button below. If it keeps failing, request a new link.</p>\n'
        '<p>Reference: <span class="trace">$safeTrace</span></p>'
        '$debugBlock',
    actionsHtml: '''
<form method="post" action="/auth/email/verify">
  $hiddenToken
  <button type="submit" class="btn btn-primary">Try again</button>
</form>''',
    alertRole: ' role="alert"',
  );
}

/// Static confirmation shown after a magic link links an email to an account
/// from Settings. Deliberately mints NO session (the originating browser keeps
/// its own session); the user returns to the app to see the new method.
String renderEmailLinkedSuccessPage() => _emailAuthPageShell(
  title: 'Email linked',
  headingId: 'email-linked-title',
  heading: 'Email linked',
  bodyHtml:
      '<p>This email is now a sign-in method for your account. You can close this tab and return to the app.</p>',
);

/// Shown when the email a user tried to link is already owned by a different
/// account (no merge — see the strict-link conflict policy).
String renderEmailLinkConflictPage() => _emailAuthPageShell(
  title: 'Email already in use',
  headingId: 'email-link-conflict-title',
  heading: 'This email is already in use',
  bodyHtml:
      '<p>It is linked to a different account and cannot be added here. You can close this tab.</p>',
  alertRole: ' role="alert"',
);
