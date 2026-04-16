import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/friends_fetch.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class FriendsRemoteRepository extends RemoteRepository {
  FriendsRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<Iterable<Profile>> fetch() async {
    final data = await requestDataOnlineOrThrow(
      GFriendsFetchReq(),
      label: _label,
    );
    return data.vote_user.map((e) => (e.user as UserModel).toEntity());
  }

  static const _label = 'Friends';
}
