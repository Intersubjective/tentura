import 'package:tentura_server/domain/entity/gql_public/commitment_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

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

List<Map<String, dynamic>> mutualScoresToGqlList(List<MutualScoreRecord> s) =>
    s
        .map(
          (e) => <String, dynamic>{
            'src_score': e.srcScore,
            'dst_score': e.dstScore,
          },
        )
        .toList();

Map<String, dynamic> userPublicToGqlMap(UserPublicRecord u) => {
  'id': u.id,
  'title': u.title,
  'description': u.description,
  'my_vote': u.myVote,
  'is_mutual_friend': u.isMutualFriend,
  'image': u.image == null ? null : imagePublicToGqlMap(u.image!),
  'scores': mutualScoresToGqlList(u.scores),
  'user_presence': userPresenceToGqlMap(u.userPresence),
};

Map<String, dynamic> commitmentWithCoordinationToGqlMap(
  CommitmentWithCoordinationRow row,
) => {
  'beaconId': row.beaconId,
  'userId': row.userId,
  'message': row.message,
  'helpType': row.helpType,
  'status': row.status,
  'uncommitReason': row.uncommitReason,
  'createdAt': row.createdAt.toUtc().toIso8601String(),
  'updatedAt': row.updatedAt.toUtc().toIso8601String(),
  'responseType': row.responseType,
  'responseUpdatedAt': row.responseUpdatedAt?.toUtc().toIso8601String(),
  'responseAuthorUserId': row.responseAuthorUserId,
  'user': userPublicToGqlMap(row.user),
};
