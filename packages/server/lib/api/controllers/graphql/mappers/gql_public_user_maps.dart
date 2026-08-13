import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_availability_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_availability_entity.dart';

import 'package:tentura_server/data/mapper/user_availability_mapper.dart';

Map<String, dynamic> imagePublicToGqlMap(ImagePublicRecord image) => {
  'id': image.id,
  'hash': image.hash,
  'height': image.height,
  'width': image.width,
  'author_id': image.authorId,
  'created_at': image.createdAt.toUtc(),
};

Map<String, dynamic>? userPresenceToGqlMap(UserPresenceRecord? p) {
  if (p == null) {
    return null;
  }
  return {
    'last_seen_at': p.lastSeenAt.toUtc().toIso8601String(),
    'status': p.status,
  };
}

List<Map<String, dynamic>> mutualScoresToGqlList(List<MutualScoreRecord> s) => s
    .map(
      (e) => <String, dynamic>{
        'src_score': e.srcScore,
        'dst_score': e.dstScore,
      },
    )
    .toList();

Map<String, dynamic>? userAvailabilityToGqlMap(UserAvailabilityRecord? availability) {
  if (availability == null) {
    return null;
  }
  return {
    'is_limited': availability.isLimited,
    'resume_on': availability.resumeOn == null
        ? null
        : utcCalendarDateToWireString(availability.resumeOn!),
  };
}

Map<String, dynamic>? userAvailabilityEntityToGqlMap({
  required UserAvailabilityEntity? entity,
  required DateTime todayUtc,
}) =>
    userAvailabilityToGqlMap(
      userAvailabilityEntityToPublicRecord(
        entity: entity,
        todayUtc: todayUtc,
      ),
    );

Map<String, dynamic> userPublicToGqlMap(UserPublicRecord u) => {
  'id': u.id,
  'displayName': u.displayName,
  'handle': u.handle,
  'description': u.description,
  'my_vote': u.myVote,
  'is_mutual_friend': u.isMutualFriend,
  'trusts_viewer': u.subjectExplicitlyTrustsViewer,
  'image': u.image == null ? null : imagePublicToGqlMap(u.image!),
  'scores': mutualScoresToGqlList(u.scores),
  'user_presence': userPresenceToGqlMap(u.userPresence),
  'user_availability': userAvailabilityToGqlMap(u.userAvailability),
};

Map<String, dynamic> helpOfferWithCoordinationToGqlMap(
  HelpOfferWithCoordinationRow row,
) => {
  'beaconId': row.beaconId,
  'userId': row.userId,
  'message': row.message,
  'helpType': row.helpType,
  'status': row.status,
  'withdrawReason': row.withdrawReason,
  'createdAt': row.createdAt.toUtc().toIso8601String(),
  'updatedAt': row.updatedAt.toUtc().toIso8601String(),
  'responseType': row.responseType,
  'responseUpdatedAt': row.responseUpdatedAt?.toUtc().toIso8601String(),
  'responseAuthorUserId': row.responseAuthorUserId,
  'roomAccess': row.roomAccess,
  'admissionAction': row.admissionAction,
  'lastDeclineReason': row.lastDeclineReason,
  'lastRemoveReason': row.lastRemoveReason,
  'stakeState': row.stakeState,
  'offerKind': row.offerKind,
  'isDirectAuthorForward': row.isDirectAuthorForward,
  'user': userPublicToGqlMap(row.user),
};
