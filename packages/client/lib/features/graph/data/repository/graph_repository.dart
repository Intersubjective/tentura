import 'package:injectable/injectable.dart';

// import 'package:tentura/consts.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';

import '../gql/_g/graph_fetch.req.gql.dart';
import '../gql/_g/graph_edges_between.req.gql.dart';
import 'graph_source_repository.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class GraphRepository extends RemoteRepository
    implements GraphSourceRepository {
  GraphRepository({
    required super.remoteApiService,
    required super.log,
  });

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) async {
    final data = await requestDataOnlineOrThrow(
      GGraphFetchReq(
        (b) => b
          // ..context = const Context().withEntry(
          //   HttpLinkHeaders(headers: {kHeaderQueryContext: context}),
          // )
          ..vars.focus = focus ?? ''
          ..vars.limit = limit
          ..vars.offset = offset
          ..vars.context = context
          ..vars.positive_only = positiveOnly,
      ),
      label: _label,
    );
    final beacon = data.beacon_by_pk;
    final result = <EdgeDirected>{};
    for (final e in data.graph) {
      final weight = e.dst_score!;
      final user = e.user;
      if (user == null) {
        if (beacon != null && e.dst == beacon.id) {
          result.add((
            src: e.src!,
            dst: e.dst!,
            weight: weight,
            node: BeaconNode(beacon: (beacon as BeaconModel).toEntity()),
            branch: null,
            srcTotalNeighborCount: e.src_total_neighbor_count,
            dstTotalNeighborCount: e.dst_total_neighbor_count,
          ));
        }
      } else {
        result.add((
          src: e.src!,
          dst: e.dst!,
          weight: weight,
          node: UserNode(user: (user as UserModel).toEntity()),
          branch: null,
          srcTotalNeighborCount: e.src_total_neighbor_count,
          dstTotalNeighborCount: e.dst_total_neighbor_count,
        ));
      }
    }
    return result;
  }

  /// Structural closure: every trust edge whose **both** endpoints are in [nodeIds].
  /// Complements [fetch], which only ever returns the neighbourhood of one focus.
  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async {
    if (nodeIds.length < 2) {
      return const {};
    }

    final data = await requestDataOnlineOrThrow(
      GGraphEdgesBetweenReq(
        (b) => b
          ..vars.node_ids.replace(nodeIds.toList(growable: false))
          ..vars.positive_only = positiveOnly,
      ),
      label: _label,
    );

    return {
      for (final e in data.graph_edges_between)
        (
          src: e.src!,
          dst: e.dst!,
          weight: e.dst_score!,
          node: null,
          branch: null,
          srcTotalNeighborCount: e.src_total_neighbor_count,
          dstTotalNeighborCount: e.dst_total_neighbor_count,
        ),
    };
  }

  static const _label = 'Graph';
}
