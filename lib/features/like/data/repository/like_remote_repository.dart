import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import 'package:tentura/features/beacon/domain/entity/beacon.dart';
import 'package:tentura/features/comment/domain/entity/comment.dart';
import 'package:tentura/features/profile/domain/entity/profile.dart';

import '../../domain/exception.dart';
import '../gql/_g/like_beacon_by_id.req.gql.dart';
import '../gql/_g/like_comment_by_id.req.gql.dart';
import '../gql/_g/like_user_by_id.req.gql.dart';

@lazySingleton
class LikeRemoteRepository {
  LikeRemoteRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  final _controller = StreamController<RepositoryEvent<Likable>>.broadcast();

  Stream<RepositoryEvent<Likable>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  Future<T> setLike<T extends Likable>(
    T entity, {
    required int amount,
  }) async {
    switch (entity) {
      case final Beacon e:
        final result = e.copyWith(
          myVote: await _likeBeacon(beaconId: e.id, amount: amount),
        );
        _controller.add(RepositoryEventUpdate<Beacon>(result));
        return result as T;

      case final Comment e:
        final result = e.copyWith(
          myVote: await _likeComment(commentId: e.id, amount: amount),
        );
        _controller.add(RepositoryEventUpdate<Comment>(result));
        return result as T;

      case final Profile e:
        final result = e.copyWith(
          myVote: await _likeUser(userId: e.id, amount: amount),
        );
        _controller.add(RepositoryEventUpdate<Profile>(result));
        return result as T;

      default:
        throw LikeSetException(entity);
    }
  }

  Future<int> _likeBeacon({
    required String beaconId,
    required int amount,
  }) async {
    final response = await _remoteApiService
        .request(GLikeBeaconByIdReq(
          (b) => b
            ..vars.amount = amount
            ..vars.beacon_id = beaconId,
        ))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final result =
        response.dataOrThrow(label: _label).insert_vote_beacon_one?.amount;
    if (result == null) throw LikeSetException(beaconId);
    return result;
  }

  Future<int> _likeComment({
    required String commentId,
    required int amount,
  }) async {
    final response = await _remoteApiService
        .request(GLikeCommentByIdReq(
          (b) => b
            ..vars.amount = amount
            ..vars.comment_id = commentId,
        ))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final result =
        response.dataOrThrow(label: _label).insert_vote_comment_one?.amount;
    if (result == null) throw LikeSetException(commentId);
    return result;
  }

  Future<int> _likeUser({
    required String userId,
    required int amount,
  }) async {
    final response = await _remoteApiService
        .request(GLikeUserByIdReq(
          (b) => b.vars
            ..object = userId
            ..amount = amount,
        ))
        .firstWhere((e) => e.dataSource == DataSource.Link);
    final result =
        response.dataOrThrow(label: _label).insert_vote_user_one?.amount;
    if (result == null) throw LikeSetException(userId);
    return result;
  }

  static const _label = 'Like';
}
