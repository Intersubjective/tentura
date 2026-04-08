import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/enums.dart';

import '../gql/_g/user_model.data.gql.dart';
import 'image_model.dart';

extension type const UserModel(GUserModel i) implements GUserModel {
  Profile toEntity({ImageModel? image}) {
    final p = i.user_presence;
    UserPresenceStatus? presenceStatus;
    DateTime? presenceLastSeenAt;
    if (p != null) {
      presenceStatus = _userPresenceStatusFromSmallint(p.status);
      presenceLastSeenAt = p.last_seen_at;
    }
    return Profile(
      id: i.id,
      title: i.title,
      description: i.description,
      myVote: i.my_vote ?? 0,
      image: (i.image as ImageModel?)?.asEntity ?? image?.asEntity,
      score: i.scores?.firstOrNull?.dst_score ?? 0,
      rScore: i.scores?.firstOrNull?.src_score ?? 0,
      presenceStatus: presenceStatus,
      presenceLastSeenAt: presenceLastSeenAt,
    );
  }
}

UserPresenceStatus _userPresenceStatusFromSmallint(int value) =>
    switch (value) {
      0 => UserPresenceStatus.unknown,
      1 => UserPresenceStatus.online,
      2 => UserPresenceStatus.offline,
      3 => UserPresenceStatus.inactive,
      _ => UserPresenceStatus.unknown,
    };
