import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

import '_use_case_base.dart';

/// Builds the edge set powering the V2 `beaconForwardGraph` query.
///
/// The viewer only sees:
/// * forward edges where they are sender or recipient (their direct view), and
/// * the parent_edge_id ancestor closure of those edges, so the chain back to
///   the author is reconstructed even when the viewer never received an
///   intermediate forward, and
/// * for every active committer of the beacon, the chain that delivered the
///   beacon to them (so the graph shows who acted on it and via whom).
///
/// Authorization: viewer must be the beacon author OR have at least one
/// forward edge for the beacon (as sender or recipient) OR have an active
/// commitment on the beacon.
///
/// The committer ids are returned alongside so the client can highlight them.
@Singleton(order: 2)
final class BeaconForwardGraphCase extends UseCaseBase {
  BeaconForwardGraphCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._commitmentRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final CommitmentRepositoryPort _commitmentRepository;

  // TODO(contract): Phase-2 DTO migration — replace Map return with typed DTO at resolver boundary.
  // ignore: no_map_dynamic_in_use_case_api
  Future<Map<String, dynamic>> asMap({
    required String beaconId,
    required String currentUserId,
  }) async {
    final results = await Future.wait([
      _beaconRepository.getBeaconById(beaconId: beaconId),
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _commitmentRepository.fetchAllByBeaconId(beaconId),
    ]);

    final beacon = results[0] as BeaconEntity;
    final allEdges = results[1] as List<ForwardEdgeEntity>;
    final commitments = results[2] as List<CommitmentEntity>;

    final authorId = beacon.author.id;
    final committerIds = commitments
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet();

    final isAuthor = currentUserId == authorId;
    final isInvolved =
        isAuthor ||
        committerIds.contains(currentUserId) ||
        allEdges.any(
          (e) =>
              e.senderId == currentUserId || e.recipientId == currentUserId,
        );
    if (!isInvolved) {
      throw const UnauthorizedException(
        description: 'Viewer is not involved in this beacon',
      );
    }

    final edgeById = <String, ForwardEdgeEntity>{
      for (final e in allEdges) e.id: e,
    };

    // Seeds: edges directly visible to viewer + every edge that delivered the
    // beacon to a committer. Author has no inbound forward, so committers that
    // are also the author contribute no seed; their authorship link is rendered
    // via the synthetic author->beacon edge on the client.
    final seedIds = <String>{};
    for (final e in allEdges) {
      if (e.senderId == currentUserId || e.recipientId == currentUserId) {
        seedIds.add(e.id);
      }
      if (committerIds.contains(e.recipientId)) {
        seedIds.add(e.id);
      }
    }

    final visibleIds = <String>{};
    for (final id in seedIds) {
      var cursor = edgeById[id];
      while (cursor != null && visibleIds.add(cursor.id)) {
        final parentId = cursor.parentEdgeId;
        if (parentId == null) break;
        cursor = edgeById[parentId];
      }
    }

    final visibleEdges = visibleIds
        .map((id) => edgeById[id]!)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return {
      'beaconId': beaconId,
      'authorId': authorId,
      'committerIds': committerIds.toList(),
      'edges': [
        for (final e in visibleEdges)
          {
            'id': e.id,
            'beaconId': e.beaconId,
            'senderId': e.senderId,
            'recipientId': e.recipientId,
            'parentEdgeId': e.parentEdgeId,
            'batchId': e.batchId,
          },
      ],
    };
  }
}
