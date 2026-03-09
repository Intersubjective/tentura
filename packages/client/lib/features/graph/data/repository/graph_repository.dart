import 'package:injectable/injectable.dart';

// import 'package:tentura/consts.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/edge_directed.dart';
import '../../domain/entity/node_details.dart';

import '../gql/_g/graph_fetch.req.gql.dart';

@injectable
class GraphRepository {
  GraphRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
  }) => _remoteApiService
      .request(
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
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final data = r.dataOrThrow(label: _label);
        final beacon = data.beacon_by_pk;
        final result = <EdgeDirected>{};
        for (final e in data.graph) {
          final weight = double.parse(e.dst_score!.value);
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
      });

  static const _label = 'Graph';
}
