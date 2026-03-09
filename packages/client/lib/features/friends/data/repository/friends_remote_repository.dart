import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/friends_fetch.req.gql.dart';

@lazySingleton
class FriendsRemoteRepository {
  FriendsRemoteRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<Iterable<Profile>> fetch() => _remoteApiService
      .request(GFriendsFetchReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).vote_user)
      .then((r) => r.map((e) => (e.user as UserModel).toEntity()));

  static const _label = 'Friends';
}
