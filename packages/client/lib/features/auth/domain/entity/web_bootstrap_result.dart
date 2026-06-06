/// Result of web-only auth bootstrap (handoff fragment + session cookie).
class WebBootstrapResult {
  const WebBootstrapResult({
    required this.currentAccountId,
    this.freshHandoffUserId,
    this.sessionUserId,
    this.invalidSessionCookieRejected = false,
    this.sessionCookieClearAcknowledged = false,
  });

  final String currentAccountId;

  /// Set when a `#th=` handoff was consumed this boot.
  final String? freshHandoffUserId;

  /// Set when an HttpOnly session cookie yielded a valid account.
  final String? sessionUserId;

  /// True when the server rejected the browser session cookie this boot.
  final bool invalidSessionCookieRejected;

  /// True when logout/clear returned 2xx after a rejection.
  final bool sessionCookieClearAcknowledged;
}
