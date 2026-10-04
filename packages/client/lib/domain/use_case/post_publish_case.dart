import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/features/beacon_threads/domain/entity/committed_mention.dart';

/// Owns the wire shape of publishing a Post: mentions as parallel lists and
/// the first attachment inline; the rest is uploaded by the caller afterwards.
@singleton
class PostPublishCase {
  PostPublishCase(this._port);

  final PostPublishPort _port;

  Future<PostPublishResult> publish({
    required String beaconId,
    required String body,
    required List<CommittedMention> mentions,
    required Set<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    RoomPendingUpload? firstAttachment,
  }) => _port.postPublish(
    beaconId: beaconId,
    body: body,
    mentionUserIds: [for (final m in mentions) m.userId],
    mentionOffsets: [for (final m in mentions) m.start],
    mentionLengths: [for (final m in mentions) m.end - m.start],
    recipientIds: recipientIds.toList(growable: false),
    notes: notes,
    forwardPolicy: forwardPolicy,
    attachment: firstAttachment,
  );

  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) => _port.addRootAttachment(
    beaconId: beaconId,
    messageId: messageId,
    upload: upload,
  );
}
