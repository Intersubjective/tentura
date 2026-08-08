import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/enums.dart';

import '../gql/_g/user_public_model.data.gql.dart';
import 'image_model_v2.dart';

extension type const UserPublicModel(GUserPublicModel i)
    implements GUserPublicModel {
  Profile toEntity({ImageModelV2? image}) {
    final p = i.user_presence;
    UserPresenceStatus? presenceStatus;
    DateTime? presenceLastSeenAt;
    if (p != null) {
      presenceStatus = _userPresenceStatusFromSmallint(p.status);
      presenceLastSeenAt = DateTime.tryParse(p.last_seen_at);
    }
    return Profile(
      id: i.id,
      displayName: i.displayName,
      contactName: contactNameOf(i.id),
      handle: i.handle ?? '',
      description: i.description,
      myVote: i.my_vote ?? 0,
      subjectExplicitlyTrustsViewer: i.trusts_viewer,
      isMutualFriend: i.is_mutual_friend,
      image: (i.image as ImageModelV2?)?.asEntity ?? image?.asEntity,
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
