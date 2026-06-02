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
