import 'package:injectable/injectable.dart';

import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../domain/entity/edge_directed.dart';
import 'graph_source_repository.dart';

/// Result payload for `ForwardsGraphRepository.fetchForwardsGraph` and
/// `ForwardsGraphRepository.fetchHelpOffererForwardsGraph`. `authorId` is
/// surfaced explicitly so the cubit can pick the focus node without
/// re-reading the beacon header.
typedef ForwardsGraphPayload = ({
  Set<EdgeDirected> edges,
  Set<String> helpOffererIds,
  String authorId,
  String? viewerId,
});

/// Builds a directed graph from the V2 `beaconForwardGraph` query for one
/// beacon. The query returns the viewer's directly-visible edges, their
/// parent_edge_id ancestor closure, and the chains that delivered the beacon
/// to each active help offerer. See
/// `packages/server/lib/domain/use_case/beacon_forward_graph_case.dart`.
@Singleton(env: [Environment.dev, Environment.prod])
class ForwardsGraphRepository implements GraphSourceRepository {
  ForwardsGraphRepository(this._forwardRepository);

  final ForwardRepository _forwardRepository;

  static const _weight = 1.0;

  /// Forwards-graph specific fetch that also surfaces the help offerer ids so the
  /// renderer can highlight help-offered users. Source/destination user nodes are
  /// not pre-populated on the returned edges; the cubit lazy-fetches them.
  Future<ForwardsGraphPayload> fetchForwardsGraph({
    required String beaconId,
  }) async {
    final graph = await _forwardRepository.fetchForwardGraph(
      beaconId: beaconId,
    );

    final edges = <EdgeDirected>{
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
      helpOffererIds: graph.helpOffererIds,
      authorId: graph.authorId,
      viewerId: graph.viewerId,
    );
  }

  /// Per-help-offerer forward-path graph (V2 `beaconHelpOffererForwardPath`).
  ///
  /// Returns the union of the focused [helpOffererId]'s ancestor closure and
  /// the viewer's own forward edges plus their ancestor closure (so when
  /// the viewer is an "involved other" the screen still shows author +
  /// viewer + help offerer simultaneously).
  Future<ForwardsGraphPayload> fetchHelpOffererForwardsGraph({
    required String beaconId,
    required String helpOffererId,
  }) async {
    final graph = await _forwardRepository.fetchHelpOffererForwardPath(
      beaconId: beaconId,
      helpOffererId: helpOffererId,
    );

    final edges = <EdgeDirected>{
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
      helpOffererIds: graph.helpOffererIds,
      authorId: graph.authorId,
      viewerId: graph.viewerId,
    );
  }

  /// [GraphSourceRepository] adapter used by the shared `GraphCubit` code path.
  /// Drops the help offerer ids; callers that need them call
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
