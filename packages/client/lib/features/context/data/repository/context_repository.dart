import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import '../../domain/entity/context_entity.dart';
import '../../domain/exception.dart';
import '../gql/_g/context_add.req.gql.dart';
import '../gql/_g/context_delete.req.gql.dart';
import '../gql/_g/context_fetch.req.gql.dart';

@lazySingleton
class ContextRepository {
  ContextRepository(
    this._remoteApiService,
  );

  final RemoteApiService _remoteApiService;

  final _cache = <String>{};

  final _controller =
      StreamController<RepositoryEvent<ContextEntity>>.broadcast();

  Stream<RepositoryEvent<ContextEntity>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  Future<Iterable<String>> fetch({bool fromCache = true}) async {
    if (!fromCache) {
      final response = await _remoteApiService
          .request(GContextFetchReq())
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).user_context);
      _cache
        ..clear()
        ..addAll(response.map((r) => r.context_name));
    }
    return Set.from(_cache);
  }

  Future<void> add(String contextName) async {
    final response = await _remoteApiService
        .request(GContextAddReq((b) => b.vars.context_name = contextName))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).insert_user_context_one);
    if (response == null) {
      throw ContextCreateException(contextName);
    }
    _cache.add(contextName);
    _controller.add(
      RepositoryEventCreate(ContextEntity(name: response.context_name)),
    );
  }

  Future<void> delete({
    required String userId,
    required String contextName,
  }) async {
    final response = await _remoteApiService
        .request(
          GContextDeleteReq(
            (b) => b.vars
              ..user_id = userId
              ..context_name = contextName,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).delete_user_context_by_pk);
    if (response == null) {
      throw ContextDeleteException(contextName);
    }
    _cache.remove(contextName);
    _controller.add(
      RepositoryEventDelete(
        ContextEntity(
          name: response.context_name,
        ),
      ),
    );
  }

  static const _label = 'Context';
}
