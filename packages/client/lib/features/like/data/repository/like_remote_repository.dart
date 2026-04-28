import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/exception.dart';
import '../gql/_g/like_beacon_by_id.req.gql.dart';
import '../gql/_g/like_user_by_id.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class LikeRemoteRepository extends RemoteRepository {
  LikeRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  final _controller = StreamController<RepositoryEvent<Likable>>.broadcast();

  Stream<RepositoryEvent<Likable>> get changes => _controller.stream;

  @disposeMethod
  Future<void> dispose() => _controller.close();

  Future<T> setLike<T extends Likable>(T entity, {required int amount}) async {
    switch (entity) {
      case final Beacon e:
        final result = e.copyWith(
          myVote: await _likeBeacon(beaconId: e.id, amount: amount),
        );
        _controller.add(RepositoryEventUpdate<Beacon>(result));
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
    final data = await requestDataOnlineOrThrow(
      GLikeBeaconByIdReq(
        (b) =>
            b
              ..vars.amount = amount
              ..vars.beacon_id = beaconId,
      ),
      label: _label,
    );
    final result = data.insert_vote_beacon_one?.amount;
    if (result == null) throw LikeSetException(beaconId);
    return result;
  }

  Future<int> _likeUser({required String userId, required int amount}) async {
    final data = await requestDataOnlineOrThrow(
      GLikeUserByIdReq(
        (b) =>
            b.vars
              ..object = userId
              ..amount = amount,
      ),
      label: _label,
    );
    final result = data.insert_vote_user_one?.amount;
    if (result == null) throw LikeSetException(userId);
    return result;
  }

  static const _label = 'Like';
}
