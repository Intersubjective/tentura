import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/model/opinion_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/opinion.dart';

import '../../domain/exception.dart';
import '../gql/_g/opinion_create.req.gql.dart';
import '../gql/_g/opinion_fetch_by_id.req.gql.dart';
import '../gql/_g/opinion_remove_by_id.req.gql.dart';
import '../gql/_g/opinions_fetch_by_user_id.req.gql.dart';

@lazySingleton
class OpinionRepository {
  OpinionRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Opinion> fetchById(String id) async {
    final result = await _remoteApiService
        .request(GOpinionFetchByIdReq((b) => b.vars.id = id))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).opinion_by_pk);
    if (result == null) {
      throw OpinionFetchException('Opinion with id [$id] not found');
    } else {
      return (result as OpinionModel).asEntity;
    }
  }

  Future<List<Opinion>> fetchByUserId({
    required String userId,
    required int offset,
    int limit = kFetchWindowSize,
  }) => _remoteApiService
      .request(
        GOpinionsFetchByUserIdReq(
          (b) => b.vars
            ..objectId = userId
            ..offset = offset
            ..limit = limit,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).opinions)
      .then(
        (v) => v
            .where((e) => e.opinion != null)
            .map((e) => (e.opinion! as OpinionModel).asEntity)
            .toList(),
      );

  Future<Opinion> createOpinion({
    required String content,
    required String userId,
    required int amount,
  }) => _remoteApiService
      .request(
        GOpinionCreateReq(
          (b) => b.vars
            ..amount = amount
            ..content = content
            ..objectId = userId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).insert_opinion_one)
      .then(
        (v) =>
            (v as OpinionModel?)?.asEntity ??
            (throw const OpinionCreateException()),
      );

  Future<void> removeOpinionById(String id) => _remoteApiService
      .request(GOpinionRemoveByIdReq((b) => b.vars.id = id))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  static const _label = 'Opinion';
}
