import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

import 'capability_case.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class ForwardCase extends UseCaseBase {
  ForwardCase(
    this._forwardEdgeRepository,
    this._commitmentRepository,
    this._inboxRepository,
    this._capabilityCase,
    this._beaconRepository,
    this._roomPush, {
    required super.env,
    required super.logger,
  });

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
  final BeaconRepositoryPort _beaconRepository;
  final BeaconRoomPushService _roomPush;

  /// Forward a beacon to one or more recipients atomically.
  ///
  /// [sharedReasonSlugs] applies the same reason slugs to every recipient.
  /// [perRecipientReasonSlugs] overrides reasons for specific recipients
  /// (keyed by recipientId). Reason recording never throws — errors are logged.
  ///
  /// Returns the batch_id used for this forward action.
  Future<String> forward({
    required String senderId,
    required String beaconId,
    required List<String> recipientIds,
    String? context,
    String? parentEdgeId,
    String sharedNote = '',
    Map<String, String>? perRecipientNotes,
    List<String>? sharedReasonSlugs,
    Map<String, List<String>>? perRecipientReasonSlugs,
  }) async {
    if (recipientIds.isEmpty) {
      throw ArgumentError('recipientIds must not be empty');
    }

    final batchId = generateId('X');

    await _forwardEdgeRepository.createBatch(
      beaconId: beaconId,
      senderId: senderId,
      recipientIds: recipientIds,
      batchId: batchId,
      noteForRecipient: (id) => perRecipientNotes?[id] ?? sharedNote,
      context: context,
      parentEdgeId: parentEdgeId,
      onAfterEdgesInserted: () async {
        final hasCommit = await _commitmentRepository.hasActiveCommitment(
          beaconId: beaconId,
          userId: senderId,
        );
        if (hasCommit) return;
        await _inboxRepository.upsertWatchingForSender(
          senderId: senderId,
          beaconId: beaconId,
          context: context,
        );
      },
    );

    // Record forward-reason capability events after edges are committed.
    for (final recipientId in recipientIds) {
      final slugs =
          perRecipientReasonSlugs?[recipientId] ?? sharedReasonSlugs ?? [];
      if (slugs.isEmpty) continue;
      try {
        await _capabilityCase.recordForwardReasons(
          observerId: senderId,
          subjectId: recipientId,
          beaconId: beaconId,
          slugs: slugs,
        );
      } catch (e) {
        logger.warning(
          'ForwardCase: failed to record forward reasons for $recipientId: $e',
        );
      }
    }

    try {
      final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
      unawaited(
        _roomPush.notifyForwardReceived(
          beaconId: beaconId,
          senderId: senderId,
          beaconAuthorId: beacon.author.id,
          recipientIds: recipientIds,
        ),
      );
    } catch (e) {
      logger.warning('ForwardCase: failed to enqueue forward notification: $e');
    }

    return batchId;
  }
}
