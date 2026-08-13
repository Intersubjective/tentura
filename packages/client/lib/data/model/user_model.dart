import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/enums.dart';

import '../gql/_g/user_model.data.gql.dart';
import '../gql/calendar_date_serializer.dart';
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
      displayName: i.display_name,
      contactName: contactNameOf(i.id),
      handle: i.handle ?? '',
      description: i.description,
      myVote: i.my_vote ?? 0,
      subjectExplicitlyTrustsViewer: i.trusts_viewer ?? false,
      isMutualFriend: i.is_mutual_friend ?? false,
      image: (i.image as ImageModel?)?.asEntity ?? image?.asEntity,
      score: i.scores?.firstOrNull?.dst_score ?? 0,
      rScore: i.scores?.firstOrNull?.src_score ?? 0,
      presenceStatus: presenceStatus,
      presenceLastSeenAt: presenceLastSeenAt,
      availability: availabilityFromHasuraRelationship(i.user_availability),
    );
  }
}

Availability availabilityFromHasuraRelationship(
  GUserModel_user_availability? relationship,
) {
  if (relationship == null) {
    return Availability.open();
  }
  return Availability(
    isLimited: relationship.is_limited,
    resumeOn: relationship.resume_on,
  );
}

Availability availabilityFromV2Wire({
  required bool? isLimited,
  String? resumeOn,
}) {
  if (isLimited == null) {
    return Availability.open();
  }
  return Availability(
    isLimited: isLimited,
    resumeOn: resumeOn == null ? null : parseStrictUtcCalendarDateString(resumeOn),
  );
}

UserPresenceStatus _userPresenceStatusFromSmallint(int value) =>
    switch (value) {
      0 => UserPresenceStatus.unknown,
      1 => UserPresenceStatus.online,
      2 => UserPresenceStatus.offline,
      3 => UserPresenceStatus.inactive,
      _ => UserPresenceStatus.unknown,
    };
