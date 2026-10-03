import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';

/// The published Post and its root room message.
final class PostPublishResult {
  const PostPublishResult({
    required this.beaconId,
    required this.rootMessageId,
  });

  final String beaconId;

  final String rootMessageId;
}

/// Publishing a Post draft and attaching files to its root message.
abstract interface class PostPublishPort {
  /// Publishes the draft [beaconId], sends it to [recipientIds] and stores
  /// [body] as the root message; [attachment] rides inline with it.
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    RoomPendingUpload? attachment,
  });

  /// Uploads [upload] into the existing root message.
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  });
}
