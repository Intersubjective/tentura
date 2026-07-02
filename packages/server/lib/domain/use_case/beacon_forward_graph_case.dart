import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/forward_graph_result.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';

import '_use_case_base.dart';

ForwardGraphEdgeResult _edgeToResult(ForwardEdgeEntity e) => ForwardGraphEdgeResult(
      id: e.id,
      beaconId: e.beaconId,
      senderId: e.senderId,
      recipientId: e.recipientId,
      parentEdgeId: e.parentEdgeId,
      batchId: e.batchId,
    );

/// Builds the edge set powering the V2 `beaconForwardGraph` query.
@Singleton(order: 2)
final class BeaconForwardGraphCase extends UseCaseBase {
  BeaconForwardGraphCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._helpOfferRepository,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final BeaconAccessGuard _guard;

  Future<ForwardGraphResult> asMap({
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

    final results = await Future.wait([
      _beaconRepository.getBeaconById(beaconId: beaconId),
      _forwardEdgeRepository.fetchByBeaconId(beaconId),
      _helpOfferRepository.fetchAllByBeaconId(beaconId),
    ]);

    final beacon = results[0] as BeaconEntity;
    final allEdges = results[1] as List<ForwardEdgeEntity>;
    final helpOffers = results[2] as List<HelpOfferEntity>;

    final authorId = beacon.author.id;
    final helpOffererIds = helpOffers
        .where((c) => c.status == 0)
        .map((c) => c.userId)
        .toSet();

    final edgeById = <String, ForwardEdgeEntity>{
      for (final e in allEdges) e.id: e,
    };

    final seedIds = <String>{};
    for (final e in allEdges) {
      if (e.senderId == currentUserId || e.recipientId == currentUserId) {
        seedIds.add(e.id);
      }
      if (helpOffererIds.contains(e.recipientId)) {
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

    return ForwardGraphResult(
      beaconId: beaconId,
      authorId: authorId,
      helpOffererIds: helpOffererIds.toList(),
      edges: visibleEdges.map(_edgeToResult).toList(),
    );
  }
}
