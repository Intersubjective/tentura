/// Outcome of a best-effort browser session cookie clear (logout POST).
class SessionCookieClearResult {
  const SessionCookieClearResult({required this.acknowledged});

  /// True when the logout endpoint returned 2xx (browser should apply Set-Cookie).
  final bool acknowledged;

  static const succeeded = SessionCookieClearResult(acknowledged: true);
  static const failed = SessionCookieClearResult(acknowledged: false);
}
