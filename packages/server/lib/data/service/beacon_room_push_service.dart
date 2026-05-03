import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

/// FCM helpers for beacon-related push events.
@lazySingleton
class BeaconRoomPushService {
  BeaconRoomPushService(
    this._fcmBatch,
    this._fcmTokens,
    this._users,
  );

  final FcmBatchQueuePort _fcmBatch;

  final FcmTokenRepositoryPort _fcmTokens;

  final UserRepositoryPort _users;

  Future<void> notifyForwardReceived({
    required String beaconId,
    required String senderId,
    required String beaconAuthorId,
    required List<String> recipientIds,
  }) async {
    if (recipientIds.isEmpty) return;
    final sender = await _users.getById(senderId);
    final title = sender.title.isEmpty ? 'Someone' : sender.title;
    for (final receiverId in recipientIds.toSet()) {
      if (receiverId.isEmpty || receiverId == senderId || receiverId == beaconAuthorId) continue;
      await _send(
        receiverId: receiverId,
        title: title,
        body: 'Forwarded a beacon to you',
        beaconId: beaconId,
      );
    }
  }

  Future<void> notifyCommitToAuthor({
    required String beaconId,
    required String committerId,
    required String authorId,
  }) async {
    if (authorId.isEmpty || authorId == committerId) return;
    final committer = await _users.getById(committerId);
    final title = committer.title.isEmpty ? 'Someone' : committer.title;
    await _send(
      receiverId: authorId,
      title: title,
      body: 'Committed to your beacon',
      beaconId: beaconId,
    );
  }

  Future<void> notifyRoomAdmitted({
    required String receiverId,
    required String beaconId,
  }) =>
      _send(
        receiverId: receiverId,
        title: 'Room access',
        body: 'You were admitted to the beacon room',
        beaconId: beaconId,
        dest: 'room',
      );

  Future<void> notifyNeedInfoRequested({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
  }) async {
    final actor = await _users.getById(actorUserId);
    await _send(
      receiverId: receiverId,
      title: actor.title,
      body: 'Information was requested in the beacon room',
      beaconId: beaconId,
      dest: 'room',
    );
  }

  Future<void> notifyHelpOfferedToModerators({
    required String beaconId,
    required String offererUserId,
    required List<String> moderatorUserIds,
  }) async {
    if (moderatorUserIds.isEmpty) {
      return;
    }
    final offerer = await _users.getById(offererUserId);
    final title = offerer.title.isEmpty ? 'Someone' : offerer.title;
    for (final receiverId in moderatorUserIds.toSet()) {
      if (receiverId.isEmpty || receiverId == offererUserId) {
        continue;
      }
      await _send(
        receiverId: receiverId,
        title: title,
        body: 'Offered help on your beacon',
        beaconId: beaconId,
        dest: 'room',
      );
    }
  }

  Future<void> notifyPlanUpdatedToRoom({
    required String beaconId,
    required String actorUserId,
    required List<String> admittedUserIds,
  }) async {
    final actor = await _users.getById(actorUserId);
    final title = actor.title.isEmpty ? 'Room' : actor.title;
    for (final receiverId in admittedUserIds.toSet()) {
      if (receiverId.isEmpty || receiverId == actorUserId) {
        continue;
      }
      await _send(
        receiverId: receiverId,
        title: title,
        body: 'Updated the coordinated plan',
        beaconId: beaconId,
        dest: 'room',
      );
    }
  }

  Future<void> notifyBlockerRoomEvent({
    required String beaconId,
    required String actorUserId,
    required Set<String> receiverIds,
    required String body,
  }) async {
    if (receiverIds.isEmpty) {
      return;
    }
    final actor = await _users.getById(actorUserId);
    final title = actor.title.isEmpty ? 'Beacon room' : actor.title;
    for (final receiverId in receiverIds) {
      if (receiverId.isEmpty || receiverId == actorUserId) {
        continue;
      }
      await _send(
        receiverId: receiverId,
        title: title,
        body: body,
        beaconId: beaconId,
        dest: 'room',
      );
    }
  }

  Future<void> notifyNextMoveUpdated({
    required String beaconId,
    required String targetUserId,
    required String actorUserId,
  }) async {
    if (targetUserId.isEmpty || targetUserId == actorUserId) {
      return;
    }
    final actor = await _users.getById(actorUserId);
    final title = actor.title.isEmpty ? 'Coordinator' : actor.title;
    await _send(
      receiverId: targetUserId,
      title: title,
      body: 'Your next step in the beacon room was updated',
      beaconId: beaconId,
      dest: 'room',
    );
  }

  Future<void> notifyFactPinned({
    required String beaconId,
    required String actorUserId,
    required bool isPublic,
    required List<String> recipientUserIds,
  }) async {
    if (recipientUserIds.isEmpty) {
      return;
    }
    final actor = await _users.getById(actorUserId);
    final title = actor.title.isEmpty ? 'Someone' : actor.title;
    final body = isPublic
        ? 'Pinned a public fact on the beacon'
        : 'Pinned a room fact';
    for (final receiverId in recipientUserIds.toSet()) {
      if (receiverId.isEmpty || receiverId == actorUserId) {
        continue;
      }
      await _send(
        receiverId: receiverId,
        title: title,
        body: body,
        beaconId: beaconId,
        dest: 'room',
      );
    }
  }

  Future<void> _send({
    required String receiverId,
    required String title,
    required String body,
    required String beaconId,
    String? dest,
  }) async {
    if (receiverId.isEmpty) return;
    final tokens = await _fcmTokens.getTokensByUserId(receiverId);
    if (tokens.isEmpty) return;
    final destParam = dest != null ? '&dest=$dest' : '';
    _fcmBatch.enqueue(
      receiverId: receiverId,
      fcmTokens: tokens.map((e) => e.token).toSet(),
      message: FcmNotificationEntity(
        title: title,
        body: body,
        actionUrl: '/#$kPathAppLinkView?id=$beaconId$destParam',
      ),
    );
  }
}
