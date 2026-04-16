import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

import '_use_case_base.dart';

/// Aggregates forward / commitment / inbox-rejection data for a beacon.
///
/// Used by the V2 `beaconInvolvement` query so the client does not rely on
/// Hasura `beacon_by_pk { rejected_user_ids, forward_edges, ... }`, which is
/// broken for empty `rejected_user_ids` (see `WORKAROUNDS.md`).
@Singleton(order: 2)
final class BeaconInvolvementCase extends UseCaseBase {
  BeaconInvolvementCase(
    this._forwardEdgeRepository,
    this._commitmentRepository,
    this._inboxRepository, {
    required super.env,
    required super.logger,
  });

  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final InboxRepositoryPort _inboxRepository;

  /// Returns a map matching `BeaconInvolvement` GraphQL field names.
  ///
  /// [currentUserId] identifies the requesting user so the response can
  /// distinguish "forwarded by me" from "forwarded by others".
  Future<Map<String, dynamic>> asMap({
    required String beaconId,
    required String currentUserId,
  }) async {
    final results = await Future.wait([
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _commitmentRepository.fetchAllByBeaconId(beaconId),
      _inboxRepository.fetchRejectedUserIdsByBeacon(beaconId),
      _inboxRepository.fetchWatchingUserIdsByBeacon(beaconId),
      _forwardEdgeRepository.fetchDistinctSenderIdsByBeaconId(beaconId),
    ]);

    final edges = results[0] as List<ForwardEdgeEntity>;
    final commitments = results[1] as List<CommitmentEntity>;
    final rejectedIds = results[2] as List<String>;
    final watchingIds = results[3] as List<String>;
    final onwardForwarderIds = results[4] as List<String>;

    final forwardedToIds = edges.map((e) => e.recipientId).toSet().toList();
    final committedIds = commitments
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet()
        .toList();
    final withdrawnIds = commitments
        .where((c) => c.status == 1)
        .map((c) => c.userId)
        .toSet()
        .toList();

    final myForwardedRecipients = <Map<String, String>>[];
    for (final edge in edges) {
      if (edge.senderId == currentUserId) {
        myForwardedRecipients.add({
          'recipientId': edge.recipientId,
          'note': edge.note,
        });
      }
    }

    return {
      'forwardedToIds': forwardedToIds,
      'committedIds': committedIds,
      'withdrawnIds': withdrawnIds,
      'rejectedIds': rejectedIds,
      'watchingIds': watchingIds,
      'onwardForwarderIds': onwardForwarderIds,
      'myForwardedRecipients': myForwardedRecipients,
    };
  }
}
