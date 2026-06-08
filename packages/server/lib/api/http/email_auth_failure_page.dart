/// Generic failure page for invalid/expired/reused email magic links.
String renderEmailAuthFailurePage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Link not valid</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; color: #333; max-width: 28rem; }
    h1 { font-size: 1.25rem; }
    p { color: #555; line-height: 1.5; }
  </style>
</head>
<body>
  <h1>This sign-in link is not valid</h1>
  <p>It may have expired or already been used. Request a new link from the invite page.</p>
</body>
</html>
''';

/// Static confirmation shown after a magic link links an email to an account
/// from Settings. Deliberately mints NO session (the originating browser keeps
/// its own session); the user returns to the app to see the new method.
String renderEmailLinkedSuccessPage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Email linked</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; color: #333; max-width: 28rem; }
    h1 { font-size: 1.25rem; }
    p { color: #555; line-height: 1.5; }
  </style>
</head>
<body>
  <h1>Email linked</h1>
  <p>This email is now a sign-in method for your account. You can close this tab and return to the app.</p>
</body>
</html>
''';

/// Shown when the email a user tried to link is already owned by a different
/// account (no merge — see the strict-link conflict policy).
String renderEmailLinkConflictPage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Email already in use</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; color: #333; max-width: 28rem; }
    h1 { font-size: 1.25rem; }
    p { color: #555; line-height: 1.5; }
  </style>
</head>
<body>
  <h1>This email is already in use</h1>
  <p>It is linked to a different account and can't be added here. You can close this tab.</p>
</body>
</html>
''';
