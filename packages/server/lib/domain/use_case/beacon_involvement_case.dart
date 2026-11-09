import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_involvement_result.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_involvement_read_port.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/utils/typed_wait.dart';

import '_use_case_base.dart';

/// Aggregates forward / help-offer / inbox-rejection data for a beacon.
///
/// Used by the V2 `beaconInvolvement` query so the client does not rely on
/// Hasura `beacon_by_pk { rejected_user_ids, forward_edges, ... }`, which is
/// broken for empty `rejected_user_ids` (see `WORKAROUNDS.md`).
@Singleton(order: 2)
final class BeaconInvolvementCase extends UseCaseBase {
  BeaconInvolvementCase(
    this._forwardEdgeRepository,
    this._helpOfferRepository,
    this._helpOfferAdmissionRepository,
    this._inboxRepository,
    this._guard, {
    required super.env,
    required super.logger,
    this.batchReads,
  });

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final HelpOfferAdmissionRepositoryPort _helpOfferAdmissionRepository;
  final InboxRepositoryPort _inboxRepository;
  final BeaconAccessGuard _guard;
  final BeaconInvolvementReadPort? batchReads;

  /// [currentUserId] identifies the requesting user so the response can
  /// distinguish "forwarded by me" from "forwarded by others".
  Future<BeaconInvolvementResult> asMap({
    required String beaconId,
    required String currentUserId,
  }) async {
    if (!await _guard.canReadInvolvement(
      beaconId: beaconId,
      viewerId: currentUserId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request involvement',
      );
    }

    final (
      edges,
      helpOffers,
      latestAdmissions,
      rejectedIds,
      watchingIds,
      onwardForwarderIds,
    ) = await (
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _helpOfferRepository.fetchAllByBeaconId(beaconId),
      _helpOfferAdmissionRepository.latestForBeacon(beaconId),
      _inboxRepository.fetchRejectedUserIdsByBeacon(beaconId),
      _inboxRepository.fetchWatchingUserIdsByBeacon(beaconId),
      _forwardEdgeRepository.fetchDistinctSenderIdsByBeaconId(beaconId),
    ).waitAll;

    for (final edge in edges) {
      if (edge.recipientId == currentUserId && edge.recipientReadAt == null) {
        unawaited(_forwardEdgeRepository.markAsRead(edge.id, currentUserId));
      }
    }
    return _project(
      currentUserId: currentUserId,
      records: (
        edges: edges,
        helpOffers: helpOffers,
        latestAdmissions: latestAdmissions,
        rejectedIds: rejectedIds,
        watchingIds: watchingIds,
        onwardForwarderIds: onwardForwarderIds,
      ),
    );
  }

  /// Listing candidates does not mark a Request as read. Inaccessible ids are
  /// omitted so callers can distinguish unknown involvement from unseen.
  Future<Map<String, BeaconInvolvementResult>> asBatch({
    required List<String> beaconIds,
    required String currentUserId,
  }) async {
    final reads = batchReads;
    if (reads == null) {
      throw StateError('Batch involvement reader is not configured');
    }
    if (beaconIds.length > reads.maxBatchSize) {
      throw const PayloadTooLargeException(
        description: 'At most 50 involvement ids are allowed',
      );
    }
    if (beaconIds.isEmpty) return {};
    final records = await reads.fetchReadableBatch(
      beaconIds: beaconIds.toSet().toList(),
      viewerId: currentUserId,
    );
    return {
      for (final entry in records.entries)
        entry.key: _project(currentUserId: currentUserId, records: entry.value),
    };
  }

  static BeaconInvolvementResult _project({
    required String currentUserId,
    required BeaconInvolvementRecords records,
  }) {
    final (
      :edges,
      :helpOffers,
      :latestAdmissions,
      :rejectedIds,
      :watchingIds,
      :onwardForwarderIds,
    ) = records;
    final forwardedToIds = edges.map((e) => e.recipientId).toSet().toList();
    final helpOfferedIds = helpOffers
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet()
        .toList();
    final declinedOfferIds = <String>{};
    final withdrawnIds = <String>{};
    for (final offer in helpOffers.where((c) => c.status == 1)) {
      final admission = latestAdmissions[offer.userId];
      if (admission?.action == HelpOfferAdmissionAction.decline) {
        declinedOfferIds.add(offer.userId);
      } else {
        withdrawnIds.add(offer.userId);
      }
    }

    final childParentIds = {
      for (final e in edges)
        if (e.parentEdgeId != null) e.parentEdgeId!,
    };

    final myForwardedRecipients = <MyForwardRecipientResult>[];
    for (final edge in edges) {
      if (edge.senderId == currentUserId) {
        myForwardedRecipients.add(
          MyForwardRecipientResult(
            edgeId: edge.id,
            recipientId: edge.recipientId,
            note: edge.note,
            hasOnwardChild: childParentIds.contains(edge.id),
            recipientRejected: edge.recipientRejected,
            readAt: edge.recipientReadAt,
          ),
        );
      }
    }

    return BeaconInvolvementResult(
      forwardedToIds: forwardedToIds,
      helpOfferedIds: helpOfferedIds,
      withdrawnIds: withdrawnIds.toList(),
      declinedOfferIds: declinedOfferIds.toList(),
      rejectedIds: rejectedIds,
      watchingIds: watchingIds,
      onwardForwarderIds: onwardForwarderIds,
      myForwardedRecipients: myForwardedRecipients,
    );
  }
}
