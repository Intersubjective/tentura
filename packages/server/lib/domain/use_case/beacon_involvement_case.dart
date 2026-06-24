import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_involvement_result.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/exception.dart';

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
    this._inboxRepository,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final InboxRepositoryPort _inboxRepository;
  final BeaconAccessGuard _guard;

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
        description: 'Viewer cannot read beacon involvement',
      );
    }

    final results = await Future.wait([
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _helpOfferRepository.fetchAllByBeaconId(beaconId),
      _inboxRepository.fetchRejectedUserIdsByBeacon(beaconId),
      _inboxRepository.fetchWatchingUserIdsByBeacon(beaconId),
      _forwardEdgeRepository.fetchDistinctSenderIdsByBeaconId(beaconId),
    ]);

    final edges = results[0] as List<ForwardEdgeEntity>;
    final helpOffers = results[1] as List<HelpOfferEntity>;
    final rejectedIds = results[2] as List<String>;
    final watchingIds = results[3] as List<String>;
    final onwardForwarderIds = results[4] as List<String>;

    final forwardedToIds = edges.map((e) => e.recipientId).toSet().toList();
    final helpOfferedIds = helpOffers
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet()
        .toList();
    final withdrawnIds = helpOffers
        .where((c) => c.status == 1)
        .map((c) => c.userId)
        .toSet()
        .toList();

    final myForwardedRecipients = <MyForwardRecipientResult>[];
    final edgesToMarkRead = <ForwardEdgeEntity>[];
    for (final edge in edges) {
      if (edge.senderId == currentUserId) {
        myForwardedRecipients.add(
          MyForwardRecipientResult(
            edgeId: edge.id,
            recipientId: edge.recipientId,
            note: edge.note,
            readAt: edge.recipientReadAt,
          ),
        );
      }
      if (edge.recipientId == currentUserId && edge.recipientReadAt == null) {
        edgesToMarkRead.add(edge);
      }
    }
    for (final edge in edgesToMarkRead) {
      unawaited(
        _forwardEdgeRepository.markAsRead(edge.id, currentUserId),
      );
    }

    return BeaconInvolvementResult(
      forwardedToIds: forwardedToIds,
      helpOfferedIds: helpOfferedIds,
      withdrawnIds: withdrawnIds,
      rejectedIds: rejectedIds,
      watchingIds: watchingIds,
      onwardForwarderIds: onwardForwarderIds,
      myForwardedRecipients: myForwardedRecipients,
    );
  }
}
