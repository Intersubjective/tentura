/// Result of web-only auth bootstrap (handoff fragment + session cookie).
class WebBootstrapResult {
  const WebBootstrapResult({
    required this.currentAccountId,
    this.freshHandoffUserId,
    this.sessionUserId,
  });

  final String currentAccountId;

  /// Set when a `#th=` handoff was consumed this boot.
  final String? freshHandoffUserId;

  /// Set when an HttpOnly session cookie yielded a valid account.
  final String? sessionUserId;
}
