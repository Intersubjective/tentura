import 'package:tentura/data/service/remote_api_service.dart';

import 'gql/_g/context_add.req.gql.dart';
import 'gql/_g/context_delete.req.gql.dart';
import 'gql/_g/context_fetch.req.gql.dart';

class ContextRepository {
  static const _label = 'Context';

  ContextRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  late final _fetchRequest = GContextFetchReq(
    (b) => b.fetchPolicy = FetchPolicy.CacheAndNetwork,
  );

  Stream<Iterable<String>> get stream =>
      _remoteApiService.gqlClient.request(_fetchRequest).map((r) =>
          r.dataOrThrow(label: _label).user_context.map((r) => r.context_name));

  Future<void> fetch() =>
      _remoteApiService.gqlClient.addRequestToRequestController(_fetchRequest);

  Future<String> add(String contextName) => _remoteApiService.gqlClient
      .request(GContextAddReq((b) => b.vars.context_name = contextName))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) =>
          r.dataOrThrow(label: _label).insert_user_context_one!.context_name);

  Future<String> delete(String contextName) => _remoteApiService.gqlClient
      .request(GContextDeleteReq((b) => b.vars
        ..user_id = _remoteApiService.userId
        ..context_name = contextName))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) =>
          r.dataOrThrow(label: _label).delete_user_context_by_pk!.context_name);
}
