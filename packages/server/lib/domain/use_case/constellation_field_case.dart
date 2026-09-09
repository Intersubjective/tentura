import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ConstellationFieldCase extends UseCaseBase {
  ConstellationFieldCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationFieldRepositoryPort _repository;

  Future<ConstellationFieldSnapshot> load({
    required String viewerId,
    required String context,
  }) async {
    final loadedAt = DateTime.now().toUtc();
    if (viewerId.trim().isEmpty) {
      return ConstellationFieldSnapshot(
        loadedAt: loadedAt,
        context: context,
        peers: const [],
        edges: const [],
        requests: const [],
        peersCapped: false,
        requestsCapped: false,
      );
    }

    final graphPeers = await _repository.visibleGraphPeerIds(
      viewerId: viewerId,
      context: context,
      cap: kConstellationPeerCap,
    );

    final ownRequests = await _repository.ownRequests(viewerId: viewerId);

    final peerRequestsRaw = await _repository.discoverableRequests(
      viewerId: viewerId,
      context: context,
      cap: kConstellationRequestCap,
    );
    final requestsCapped = peerRequestsRaw.length > kConstellationRequestCap;
    final peerRequests = requestsCapped
        ? peerRequestsRaw.sublist(0, kConstellationRequestCap)
        : peerRequestsRaw;

    final requests = [...ownRequests, ...peerRequests];

    final edgeNodeIds = {...graphPeers.ids, viewerId};
    final edges = await _repository.trustEdges(
      viewerId: viewerId,
      context: context,
      nodeIds: edgeNodeIds,
    );

    final profileIds = {...graphPeers.ids};
    for (final request in requests) {
      profileIds.add(request.authorId);
    }

    final peers = await _repository.peerProfiles(ids: profileIds);

    return ConstellationFieldSnapshot(
      loadedAt: loadedAt,
      context: context,
      peers: peers,
      edges: edges,
      requests: requests,
      peersCapped: graphPeers.capped,
      requestsCapped: requestsCapped,
    );
  }
}
