import 'package:injectable/injectable.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';
import 'graph_source_repository.dart';

/// Builds a directed graph from `beacon_forward_edge` rows for one beacon.
@Singleton(env: [Environment.dev, Environment.prod])
class ForwardsGraphRepository implements GraphSourceRepository {
  ForwardsGraphRepository(
    this._forwardRepository,
    this._beaconRepository,
  );

  final ForwardRepository _forwardRepository;
  final BeaconRepository _beaconRepository;

  static const _weight = 1.0;

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) async {
    final beaconId = focus;
    if (beaconId == null || beaconId.isEmpty) {
      return {};
    }

    final beacon = await _beaconRepository.fetchBeaconById(beaconId);
    final forwardEdges = await _forwardRepository.fetchEdges(beaconId: beaconId);

    final authorId = beacon.author.id;
    final result = <EdgeDirected>{};

    final viewerId = viewerUserId;
    if (viewerId != null &&
        viewerId.isNotEmpty &&
        viewerId != authorId) {
      result.add((
        src: viewerId,
        dst: authorId,
        weight: _weight,
        node: UserNode(user: beacon.author),
      ));
    }

    result.add((
      src: authorId,
      dst: beacon.id,
      weight: _weight,
      node: BeaconNode(beacon: beacon),
    ));

    for (final e in forwardEdges) {
      result.add((
        src: e.sender.id,
        dst: e.recipient.id,
        weight: _weight,
        node: UserNode(user: e.recipient),
      ));
    }

    return result;
  }
}
