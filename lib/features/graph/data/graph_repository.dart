import 'package:tentura/data/service/remote_api_service.dart';

import '../domain/entity/edge_directed.dart';
import '../domain/entity/node_details.dart';

import 'gql/_g/graph_fetch.req.gql.dart';

class GraphRepository {
  static const _label = 'Graph';

  GraphRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String? context,
    String? focus,
    int offset = 0,
    int limit = 5,
  }) =>
      _remoteApiService.gqlClient
          .request(GGraphFetchReq(
            (b) => b.vars
              ..focus = focus
              ..limit = limit
              ..offset = offset
              ..context = context
              ..positive_only = positiveOnly,
          ))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) {
        final data = r.dataOrThrow(label: _label);
        final beacon = data.beacon_by_pk;
        final result = <EdgeDirected>{};
        for (final e in data.graph) {
          final weight = double.parse(e.score!.value);
          if (e.user == null) {
            if (beacon != null && e.dst == beacon.id) {
              result.add((
                src: e.src!,
                dst: e.dst!,
                weight: weight,
                node: BeaconNode(
                  id: beacon.id,
                  label: beacon.title,
                  userId: beacon.author.id,
                  hasImage: beacon.has_picture,
                  score: double.parse(beacon.score!.value),
                )
              ));
            }
          } else {
            result.add((
              src: e.src!,
              dst: e.dst!,
              weight: weight,
              node: UserNode(
                id: e.user!.id,
                label: e.user!.title,
                hasImage: e.user!.has_picture,
                score: double.parse(e.user!.score!.value),
              ),
            ));
          }
        }
        return result;
      });
}
