import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/port/person_shared_context_port.dart';
import '../gql/_g/person_shared_contexts.req.gql.dart';

@Singleton(
  as: PersonSharedContextPort,
  env: [Environment.dev, Environment.prod],
)
final class PersonSharedContextRepository implements PersonSharedContextPort {
  PersonSharedContextRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'PersonSharedContexts';

  @override
  Future<List<PersonSharedContext>> fetchSharedContexts(String userId) =>
      _remoteApiService
          .request(GPersonSharedContextsReq((b) => b.vars.userId = userId))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => [
              for (final row
                  in r.dataOrThrow(label: _label).personSharedContexts)
                (beaconId: row.beaconId, title: row.title),
            ],
          );
}
