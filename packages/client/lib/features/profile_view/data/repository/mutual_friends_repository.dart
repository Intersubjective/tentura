import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/mutual_friends_fetch.req.gql.dart';

@lazySingleton
class MutualFriendsRepository {
  MutualFriendsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'MutualFriends';

  Future<List<Profile>> fetchMutualFriends(String userId) => _remoteApiService
      .request(
        GMutualFriendsFetchReq((b) => b.vars.id = userId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) {
        final rows = r.dataOrThrow(label: _label).mutualFriends;
        return rows
            .map(
              (e) => Profile(
                id: e.id,
                title: e.title,
                image: e.image == null
                    ? null
                    : ImageEntity(
                        id: e.image!.id,
                        authorId: e.image!.author_id,
                        blurHash: e.image!.hash,
                        height: e.image!.height,
                        width: e.image!.width,
                      ),
              ),
            )
            .toList();
      });
}
