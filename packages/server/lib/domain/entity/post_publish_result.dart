/// Outcome of publishing a Post: the Post id and its root room message id.
final class PostPublishResult {
  const PostPublishResult({
    required this.beaconId,
    required this.rootMessageId,
    this.expiresAt,
  });

  final String beaconId;
  final String rootMessageId;

  /// Server `expires_at` after publish (UTC), when known — aligns client clocks
  /// with the lifetime shown after send (#1081).
  final DateTime? expiresAt;
}
