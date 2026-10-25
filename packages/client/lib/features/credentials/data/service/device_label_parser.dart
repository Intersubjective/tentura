/// A short "which device is this" label from a browser user agent, e.g.
/// "Chrome on Linux" (#467). Returns null when neither the browser nor the
/// OS can be told from [userAgent].
String? deviceLabelFromUserAgent(String userAgent) {
  final browser = _browserFrom(userAgent);
  final os = _osFrom(userAgent);
  return switch ((browser, os)) {
    (final String b, final String o) => '$b on $o',
    (final String b, null) => b,
    (null, final String o) => o,
    _ => null,
  };
}

String? _browserFrom(String ua) {
  if (ua.contains('Edg/') || ua.contains('EdgA/') || ua.contains('EdgiOS/')) {
    return 'Edge';
  }
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('SamsungBrowser/')) return 'Samsung Internet';
  if (ua.contains('YaBrowser/')) return 'Yandex Browser';
  if (ua.contains('Firefox/') || ua.contains('FxiOS/')) return 'Firefox';
  if (ua.contains('CriOS/') || ua.contains('Chrome/')) return 'Chrome';
  if (ua.contains('Chromium/')) return 'Chromium';
  if (ua.contains('Safari/') && ua.contains('Version/')) return 'Safari';
  return null;
}

String? _osFrom(String ua) {
  if (ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod')) {
    return 'iOS';
  }
  if (ua.contains('Android')) return 'Android';
  if (ua.contains('CrOS')) return 'ChromeOS';
  if (ua.contains('Windows')) return 'Windows';
  if (ua.contains('Macintosh') || ua.contains('Mac OS X')) return 'macOS';
  if (ua.contains('Linux')) return 'Linux';
  return null;
}
