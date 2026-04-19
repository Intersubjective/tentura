import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_graph.dart';

import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';
import 'graph_source_repository.dart';

/// Result payload for [ForwardsGraphRepository.fetchForwardsGraph].
typedef ForwardsGraphPayload = ({
  Set<EdgeDirected> edges,
  Set<String> committerIds,
});

/// Builds a directed graph from the V2 `beaconForwardGraph` query for one
/// beacon. The query returns the viewer's directly-visible edges, their
/// parent_edge_id ancestor closure, and the chains that delivered the beacon
/// to each active committer. See
/// `packages/server/lib/domain/use_case/beacon_forward_graph_case.dart`.
@Singleton(env: [Environment.dev, Environment.prod])
class ForwardsGraphRepository implements GraphSourceRepository {
  ForwardsGraphRepository(
    this._forwardRepository,
    this._beaconRepository,
  );

  final ForwardRepository _forwardRepository;
  final BeaconRepository _beaconRepository;

  static const _weight = 1.0;

  /// Forwards-graph specific fetch that also surfaces the committer ids so the
  /// renderer can highlight committed users. Source/destination user nodes are
  /// not pre-populated on the returned edges; the cubit lazy-fetches them.
  Future<ForwardsGraphPayload> fetchForwardsGraph({
    required String beaconId,
  }) async {
    final results = await Future.wait<Object>([
      _beaconRepository.fetchBeaconById(beaconId),
      _forwardRepository.fetchForwardGraph(beaconId: beaconId),
    ]);
    final beacon = results[0] as Beacon;
    final graph = results[1] as ForwardGraph;

    final edges = <EdgeDirected>{
      (
        src: graph.authorId,
        dst: beacon.id,
        weight: _weight,
        node: BeaconNode(beacon: beacon),
      ),
      for (final e in graph.edges)
        (
          src: e.senderId,
          dst: e.recipientId,
          weight: _weight,
          node: null,
        ),
    };

    return (
      edges: edges,
      committerIds: graph.committerIds,
    );
  }

  /// [GraphSourceRepository] adapter used by the shared `GraphCubit` code path.
  /// Drops the committer ids; callers that need them call
  /// [fetchForwardsGraph] directly.
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
    final payload = await fetchForwardsGraph(beaconId: beaconId);
    return payload.edges;
  }
}
