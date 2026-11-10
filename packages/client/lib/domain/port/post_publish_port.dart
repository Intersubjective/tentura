import 'package:tentura/domain/entity/beacon_kind.dart';

/// The published Post and its root room message.
final class PostPublishResult {
  const PostPublishResult({
    required this.beaconId,
    required this.rootMessageId,
    this.expiresAt,
  });

  final String beaconId;

  final String rootMessageId;

  /// Server `expires_at` after publish (UTC), when returned.
  final DateTime? expiresAt;
}

/// Publishing a Post draft.
abstract interface class PostPublishPort {
  /// Publishes the draft [beaconId], sends it to [recipientIds] and stores
  /// [body] as the root message; the server moves the attachments saved on
  /// the draft onto it, so nothing is uploaded here.
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    Duration? lifetime,
  });
}
