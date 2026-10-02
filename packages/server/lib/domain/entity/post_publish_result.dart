/// Outcome of publishing a Post: the Post id and its root room message id.
final class PostPublishResult {
  const PostPublishResult({
    required this.beaconId,
    required this.rootMessageId,
  });

  final String beaconId;
  final String rootMessageId;
}
