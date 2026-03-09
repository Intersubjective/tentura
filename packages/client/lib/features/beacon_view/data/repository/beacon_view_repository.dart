import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/comment_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/exception.dart';
import '../../domain/typedef.dart';
import '../gql/_g/beacon_fetch_by_comment_id.req.gql.dart';
import '../gql/_g/beacon_fetch_by_id_with_comments.req.gql.dart';

@lazySingleton
class BeaconViewRepository {
  BeaconViewRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<BeaconViewResult> fetchBeaconByCommentId(String commentId) =>
      _remoteApiService
          .request(GBeaconFetchByCommentIdReq((b) => b.vars.id = commentId))
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).comment_by_pk)
          .then(
            (v) => v == null
                ? throw BeaconViewFetchException(commentId)
                : (
                    beacon: (v.beacon as BeaconModel).toEntity(),
                    comment: (v as CommentModel).asEntity,
                  ),
          );

  Future<BeaconViewResults> fetchBeaconByIdWithComments({
    required String beaconId,
    int limit = 3,
  }) => _remoteApiService
      .request(
        GBeaconFetchByIdWithCommentsReq(
          (b) => b.vars
            ..id = beaconId
            ..limit = limit,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).beacon_by_pk)
      .then(
        (v) => v == null
            ? throw BeaconViewFetchException(beaconId)
            : (
                beacon: (v as BeaconModel).toEntity(),
                comments: v.comments.map((e) => (e as CommentModel).asEntity),
              ),
      );

  static const _label = 'BeaconView';
}
