import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

// import 'package:tentura/consts.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';

import '../gql/_g/graph_fetch.data.gql.dart';
import '../gql/_g/graph_fetch.req.gql.dart';
import '../gql/_g/graph_fetch_with_exclude.data.gql.dart';
import '../gql/_g/graph_fetch_with_exclude.req.gql.dart';
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
    Set<String> excludeNeighborIds = const {},
  }) async {
    final focusVal = focus ?? '';
    final useExclude =
        focusVal.isNotEmpty && excludeNeighborIds.isNotEmpty;
    if (useExclude) {
      final data = await requestDataOnlineOrThrow(
        GGraphFetchWithExcludeReq(
          (b) => b
            ..vars.focus = focusVal
            ..vars.exclude_ids.replace(excludeNeighborIds.toList())
            ..vars.limit = limit
            ..vars.offset = offset
            ..vars.context = context
            ..vars.positive_only = positiveOnly,
        ),
        label: _label,
      );
      return _edgesFromGraphFetchWithExclude(data);
    }
    final data = await requestDataOnlineOrThrow(
      GGraphFetchReq(
        (b) => b
          // ..context = const Context().withEntry(
          //   HttpLinkHeaders(headers: {kHeaderQueryContext: context}),
          // )
          ..vars.focus = focusVal
          ..vars.limit = limit
          ..vars.offset = offset
          ..vars.context = context
          ..vars.positive_only = positiveOnly,
      ),
      label: _label,
    );
    return _edgesFromGraphFetch(data);
  }

  Set<EdgeDirected> _edgesFromGraphFetch(GGraphFetchData data) {
    final beacon = data.beacon_by_pk;
    final result = <EdgeDirected>{};
    for (final e in data.graph) {
      _addGraphEdgeRow(
        result: result,
        src: e.src,
        dst: e.dst,
        dstScore: e.dst_score,
        user: e.user,
        beaconId: beacon?.id,
        beaconModel: beacon,
        srcTotalNeighborCount: e.src_total_neighbor_count,
        dstTotalNeighborCount: e.dst_total_neighbor_count,
      );
    }
    return result;
  }

  Set<EdgeDirected> _edgesFromGraphFetchWithExclude(
    GGraphFetchWithExcludeData data,
  ) {
    final beacon = data.beacon_by_pk;
    final result = <EdgeDirected>{};
    for (final e in data.graph) {
      _addGraphEdgeRow(
        result: result,
        src: e.src,
        dst: e.dst,
        dstScore: e.dst_score,
        user: e.user,
        beaconId: beacon?.id,
        beaconModel: beacon,
        srcTotalNeighborCount: e.src_total_neighbor_count,
        dstTotalNeighborCount: e.dst_total_neighbor_count,
      );
    }
    return result;
  }

  void _addGraphEdgeRow({
    required Set<EdgeDirected> result,
    required String? src,
    required String? dst,
    required double? dstScore,
    required dynamic user,
    required String? beaconId,
    required dynamic beaconModel,
    required int? srcTotalNeighborCount,
    required int? dstTotalNeighborCount,
  }) {
    final weight = dstScore;
    if (src == null || dst == null || weight == null) {
      return;
    }
    if (user == null) {
      if (beaconModel != null && dst == beaconId) {
        result.add((
          src: src,
          dst: dst,
          weight: weight,
          node: BeaconNode(beacon: (beaconModel as BeaconModel).toEntity()),
          branch: null,
          srcTotalNeighborCount: srcTotalNeighborCount,
          dstTotalNeighborCount: dstTotalNeighborCount,
        ));
      }
      return;
    }
    result.add((
      src: src,
      dst: dst,
      weight: weight,
      node: UserNode(user: (user as UserModel).toEntity()),
      branch: null,
      srcTotalNeighborCount: srcTotalNeighborCount,
      dstTotalNeighborCount: dstTotalNeighborCount,
    ));
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
          // Hasura exposes Postgres `text[]` as scalar `_text`; pass a PG array
          // literal string. A GraphQL `[String!]` list is rejected at parse time.
          ..vars.node_ids = pgTextArrayLiteral(nodeIds)
          ..vars.positive_only = positiveOnly,
      ),
      label: _label,
    );

    return {
      for (final e in data.graph_edges_between)
        if (e.src != null && e.dst != null && e.dst_score != null)
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

  /// Encodes ids as a Postgres `text[]` literal for Hasura's `_text` scalar.
  @visibleForTesting
  static String pgTextArrayLiteral(Iterable<String> ids) {
    final parts = ids.map((id) {
      final escaped = id.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '"$escaped"';
    });
    return '{${parts.join(',')}}';
  }

  static const _label = 'Graph';
}
