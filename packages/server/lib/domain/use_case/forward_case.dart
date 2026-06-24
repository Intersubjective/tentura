import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';

import 'capability_case.dart';
import '_use_case_base.dart';

@Singleton(order: 2)
final class ForwardCase extends UseCaseBase {
  ForwardCase(
    this._forwardEdgeRepository,
    this._helpOfferRepository,
    this._inboxRepository,
    this._capabilityCase,
    this._beaconRepository,
    this._roomPush,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final InboxRepositoryPort _inboxRepository;
  final CapabilityCase _capabilityCase;
  final BeaconRepositoryPort _beaconRepository;
  final BeaconRoomNotificationPort _roomPush;
  final BeaconAccessGuard _guard;

  /// Cancel a forward edge (soft-delete).
  ///
  /// Returns false if the edge does not exist, does not belong to [senderId],
  /// has already been cancelled, has been read by the recipient, has been
  /// forwarded onward, or if the recipient has an active help offer.
  Future<bool> cancelForward({
    required String edgeId,
    required String senderId,
  }) async {
    final edge = await _forwardEdgeRepository.fetchById(edgeId);
    if (edge == null || edge.senderId != senderId) return false;
    if (edge.cancelledAt != null) return false;
    if (edge.recipientReadAt != null) return false;

    final hasChain = await _forwardEdgeRepository.existsWithParent(edgeId);
    if (hasChain) return false;

    final hasOffer = await _helpOfferRepository.hasActiveHelpOffer(
      beaconId: edge.beaconId,
      userId: edge.recipientId,
    );
    if (hasOffer) return false;

    await _forwardEdgeRepository.cancel(edgeId, senderId);
    await _inboxRepository.markForwardCancelledForRecipient(
      beaconId: edge.beaconId,
      recipientId: edge.recipientId,
    );
    return true;
  }

  /// Update the note on an existing forward edge.
  ///
  /// If [reasonSlugs] is non-empty the forward-reason capability events are
  /// re-recorded (appended — capability events are immutable log entries).
  /// Returns false when the edge is not found, not owned by [senderId], or
  /// has already been cancelled.
  Future<bool> updateForward({
    required String edgeId,
    required String senderId,
    required String note,
    List<String>? reasonSlugs,
  }) async {
    final edge = await _forwardEdgeRepository.fetchById(edgeId);
    if (edge == null || edge.senderId != senderId) return false;
    if (edge.cancelledAt != null) return false;

    await _forwardEdgeRepository.updateNote(edgeId, senderId, note);

    if (reasonSlugs != null && reasonSlugs.isNotEmpty) {
      try {
        await _capabilityCase.recordForwardReasons(
          observerId: senderId,
          subjectId: edge.recipientId,
          beaconId: edge.beaconId,
          slugs: reasonSlugs,
        );
      } catch (e) {
        logger.warning(
          'ForwardCase.updateForward: failed to record reasons for ${edge.recipientId}: $e',
        );
      }
    }
    return true;
  }

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

    if (!await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: senderId,
    )) {
      throw const UnauthorizedException(
        description: 'Sender cannot read beacon content',
      );
    }

    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsForward) {
      throw const UnauthorizedException(
        description: 'Beacon does not allow forwarding',
      );
    }

    final inbound = await _forwardEdgeRepository.fetchActiveInboundEdges(
      beaconId: beaconId,
      recipientId: senderId,
    );
    final resolvedParentEdgeId = resolveForwardParentEdgeId(
      clientParentEdgeId: parentEdgeId,
      activeInboundEdges: inbound,
      senderId: senderId,
      authorId: beacon.author.id,
    );

    final batchId = generateId('X');

    final insertedRecipientIds = await _forwardEdgeRepository.createBatch(
      beaconId: beaconId,
      senderId: senderId,
      recipientIds: recipientIds,
      batchId: batchId,
      noteForRecipient: (id) => perRecipientNotes?[id] ?? sharedNote,
      context: context,
      parentEdgeId: resolvedParentEdgeId,
      onAfterEdgesInserted: () async {
        final hasOffer = await _helpOfferRepository.hasActiveHelpOffer(
          beaconId: beaconId,
          userId: senderId,
        );
        if (hasOffer) return;
        await _inboxRepository.upsertWatchingForSender(
          senderId: senderId,
          beaconId: beaconId,
          context: context,
        );
      },
    );

    // Record forward-reason capability events after edges are committed.
    for (final recipientId in insertedRecipientIds) {
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

    if (insertedRecipientIds.isNotEmpty) {
      try {
        unawaited(
          _roomPush.notifyForwardReceived(
            beaconId: beaconId,
            senderId: senderId,
            beaconAuthorId: beacon.author.id,
            recipientIds: insertedRecipientIds,
          ),
        );
      } catch (e) {
        logger.warning('ForwardCase: failed to enqueue forward notification: $e');
      }
    }

    return batchId;
  }
}
