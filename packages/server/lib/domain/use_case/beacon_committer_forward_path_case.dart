import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

import '_use_case_base.dart';

/// Builds the edge set for the V2 `beaconCommitterForwardPath` query.
///
/// The graph is centered on a single active committer of `beaconId` and
/// returns the **union** of:
/// * every forward edge whose ancestor closure delivered the beacon to the
///   committer (`recipient_id == committerId`), plus
/// * every forward edge in which the viewer is sender or recipient and
///   their ancestor closure (so case 2 — viewer is "an involved person" —
///   sees how they fit between the author and the committer).
///
/// When the viewer is the beacon author the second seed matches nothing
/// extra and the result reduces to the committer's chain. When the viewer
/// is the committer themselves the second seed coincides with the first.
///
/// Authorization mirrors `BeaconForwardGraphCase`: viewer must be the
/// beacon author OR have at least one forward edge for the beacon (as
/// sender or recipient) OR have an active commitment on the beacon. In
/// addition, `committerId` must currently be an active committer of
/// `beaconId`; otherwise an `IdNotFoundException` is thrown to avoid
/// leaking arbitrary user→beacon relationships.
@Singleton(order: 2)
final class BeaconCommitterForwardPathCase extends UseCaseBase {
  BeaconCommitterForwardPathCase(
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
    required String committerId,
    required String currentUserId,
  }) async {
    final results = await Future.wait([
      _beaconRepository.getBeaconById(beaconId: beaconId),
      _commitmentRepository.fetchAllByBeaconId(beaconId),
    ]);

    final beacon = results[0] as BeaconEntity;
    final commitments = results[1] as List<CommitmentEntity>;

    final authorId = beacon.author.id;
    final activeCommitterIds = commitments
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet();

    if (!activeCommitterIds.contains(committerId)) {
      throw IdNotFoundException(
        id: committerId,
        description:
            'Committer is not an active committer of the beacon',
      );
    }

    // Reuse the existing involvement check: edges-by-beacon + viewer match.
    // Calling the chain CTE first would leak existence to non-involved
    // viewers, so we fan out a `fetchByBeaconId` only for the auth gate.
    final allEdges = await _forwardEdgeRepository.fetchByBeaconId(beaconId);
    final isAuthor = currentUserId == authorId;
    final isInvolved =
        isAuthor ||
        activeCommitterIds.contains(currentUserId) ||
        allEdges.any(
          (e) =>
              e.senderId == currentUserId || e.recipientId == currentUserId,
        );
    if (!isInvolved) {
      throw const UnauthorizedException(
        description: 'Viewer is not involved in this beacon',
      );
    }

    final chainEdges = await _forwardEdgeRepository.fetchCommitterPathChain(
      beaconId: beaconId,
      committerId: committerId,
      viewerId: currentUserId,
    );

    return {
      'beaconId': beaconId,
      'authorId': authorId,
      'viewerId': currentUserId,
      'committerIds': <String>[committerId],
      'edges': [
        for (final e in chainEdges)
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
