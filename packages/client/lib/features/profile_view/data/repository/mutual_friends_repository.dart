import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/enums.dart';

import '../gql/_g/mutual_friends_fetch.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
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
        return rows.map(
          (e) {
            final image = e.image;
            final scoresList = e.scores;
            final firstScore = scoresList != null && scoresList.isNotEmpty
                ? scoresList.first
                : null;
            final p = e.user_presence;
            UserPresenceStatus? presenceStatus;
            DateTime? presenceLastSeenAt;
            if (p != null) {
              presenceStatus = _userPresenceStatusFromSmallint(p.status);
              presenceLastSeenAt = p.last_seen_at;
            }
            return Profile(
              id: e.id,
              title: e.title,
              image: image == null
                  ? null
                  : ImageEntity(
                      id: image.id,
                      authorId: image.author_id,
                      blurHash: image.hash,
                      height: image.height,
                      width: image.width,
                    ),
              score: firstScore?.dst_score ?? 0,
              rScore: firstScore?.src_score ?? 0,
              presenceStatus: presenceStatus,
              presenceLastSeenAt: presenceLastSeenAt,
            );
          },
        ).toList();
      });
}

UserPresenceStatus _userPresenceStatusFromSmallint(int value) =>
    switch (value) {
      0 => UserPresenceStatus.unknown,
      1 => UserPresenceStatus.online,
      2 => UserPresenceStatus.offline,
      3 => UserPresenceStatus.inactive,
      _ => UserPresenceStatus.unknown,
    };
