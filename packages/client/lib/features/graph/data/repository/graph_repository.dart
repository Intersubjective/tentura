import 'package:injectable/injectable.dart';

// import 'package:tentura/consts.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';

import '../gql/_g/graph_fetch.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class GraphRepository extends RemoteRepository {
  GraphRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
  }) async {
    final data = await requestDataOnlineOrThrow(
      GGraphFetchReq(
        (b) => b
          // ..context = const Context().withEntry(
          //   HttpLinkHeaders(headers: {kHeaderQueryContext: context}),
          // )
          ..vars.focus = focus
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
          ));
        }
      } else {
        result.add((
          src: e.src!,
          dst: e.dst!,
          weight: weight,
          node: UserNode(user: (user as UserModel).toEntity()),
        ));
      }
    }
    return result;
  }

  static const _label = 'Graph';
}
