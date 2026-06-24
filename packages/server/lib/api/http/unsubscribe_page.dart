// Deps-light static HTML for the email unsubscribe flow (no JS framework).

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _scopeLabel(String scope) =>
    scope == 'all' ? 'all Tentura emails' : 'these "$scope" emails';

String _page(String title, String body) => '''
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex"/>
<title>$title</title>
<style>
  body { font-family: sans-serif; max-width: 520px; margin: 48px auto; padding: 0 16px; color: #222; }
  .btn { display: inline-block; padding: 10px 18px; border: 0; border-radius: 8px;
         background: #2b6; color: #fff; font-size: 16px; cursor: pointer; }
  a { color: #2563eb; }
</style>
</head><body>
$body
</body></html>
''';

/// Scanner-safe GET page: requires an explicit POST to actually unsubscribe.
String renderUnsubscribeConfirmPage({
  required String token,
  required String scope,
  required String postUrl,
}) =>
    _page('Unsubscribe', '''
<h2>Unsubscribe?</h2>
<p>This will stop ${_escape(_scopeLabel(scope))}. You'll still see everything
in the app's Notification Center.</p>
<form method="post" action="${_escape(postUrl)}">
  <input type="hidden" name="token" value="${_escape(token)}"/>
  <button class="btn" type="submit">Unsubscribe</button>
</form>
''');

String renderUnsubscribeDonePage({
  required String scope,
  required String manageUrl,
}) =>
    _page('Unsubscribed', '''
<h2>You're unsubscribed</h2>
<p>You will no longer receive ${_escape(_scopeLabel(scope))}.</p>
<p><a href="${_escape(manageUrl)}">Manage notification settings</a></p>
''');

String renderUnsubscribeInvalidPage() => _page('Link expired', '''
<h2>This link isn't valid</h2>
<p>The unsubscribe link is malformed or has expired. You can manage email
notifications from your Tentura notification settings.</p>
''');
