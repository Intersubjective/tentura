import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';

/// Aggregates forward / commitment / inbox-rejection data for a beacon.
///
/// Used by the V2 `beaconInvolvement` query so the client does not rely on
/// Hasura `beacon_by_pk { rejected_user_ids, forward_edges, ... }`, which is
/// broken for empty `rejected_user_ids` (see `WORKAROUNDS.md`).
@Singleton(order: 2)
class BeaconInvolvementCase {
  const BeaconInvolvementCase(
    this._forwardEdgeRepository,
    this._commitmentRepository,
    this._inboxRepository,
  );

  final ForwardEdgeRepository _forwardEdgeRepository;
  final CommitmentRepository _commitmentRepository;
  final InboxRepository _inboxRepository;

  /// Returns a map matching `BeaconInvolvement` GraphQL field names.
  Future<Map<String, dynamic>> asMap({required String beaconId}) async {
    final results = await Future.wait([
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _commitmentRepository.fetchAllByBeaconId(beaconId),
      _inboxRepository.fetchRejectedUserIdsByBeacon(beaconId),
    ]);

    final edges = results[0] as List<ForwardEdgeEntity>;
    final commitments = results[1] as List<CommitmentEntity>;
    final rejectedIds = results[2] as List<String>;

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

    return {
      'forwardedToIds': forwardedToIds,
      'committedIds': committedIds,
      'withdrawnIds': withdrawnIds,
      'rejectedIds': rejectedIds,
    };
  }
}
