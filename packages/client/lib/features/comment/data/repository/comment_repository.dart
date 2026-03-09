import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/comment_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/comment.dart';

import '../../domain/exception.dart';
import '../gql/_g/comment_create.req.gql.dart';
import '../gql/_g/comment_fetch_by_beacon_id.req.gql.dart';
import '../gql/_g/comment_fetch_by_id.req.gql.dart';

@lazySingleton
class CommentRepository {
  CommentRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Iterable<Comment>> fetchCommentsByBeaconId(String beaconId) =>
      _remoteApiService
          .request(
            GCommentFetchByBeaconIdReq((b) => b.vars.beacon_id = beaconId),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then((r) => r.dataOrThrow(label: _label).comment)
          .then((v) => v.map<Comment>((e) => (e as CommentModel).asEntity));

  Future<Comment> fetchCommentById(String commentId) => _remoteApiService
      .request(GCommentFetchByIdReq((b) => b.vars.id = commentId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).comment_by_pk)
      .then(
        (v) => v == null
            ? throw const CommentFetchException()
            : (v as CommentModel).asEntity,
      );

  Future<Comment> addComment({
    required String beaconId,
    required String content,
  }) => _remoteApiService
      .request(
        GCommentCreateReq(
          (b) => b.vars
            ..beacon_id = beaconId
            ..content = content,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).insert_comment_one)
      .then(
        (v) => v == null
            ? throw const CommentCreateException()
            : Comment(
                id: v.id,
                content: content,
                beaconId: beaconId,
                createdAt: v.created_at,
              ),
      );

  static const _label = 'Comment';
}
