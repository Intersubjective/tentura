import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/merit_score_lookup_port.dart';
import 'package:tentura_server/domain/port/mutual_friends_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';

import '../database/tentura_db.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

@Injectable(
  as: MutualFriendsRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class MutualFriendsRepository implements MutualFriendsRepositoryPort {
  MutualFriendsRepository(
    this._database,
    this._userPresenceRepository,
    this._voteUserFriendshipLookup,
    this._meritScoreLookup,
  );

  final TenturaDb _database;

  final UserPresenceRepositoryPort _userPresenceRepository;

  final VoteUserFriendshipLookupPort _voteUserFriendshipLookup;

  final MeritScoreLookupPort _meritScoreLookup;

  /// Mutual friends of [aliceId] and [bobId] in [context], as domain records
  /// (same fields as `gqlTypeUserPublic`).
  @override
  Future<List<UserPublicRecord>> fetchMutualFriends({
    required String aliceId,
    required String bobId,
    required String context,
  }) async {
    final rows = await _database
        .customSelect(
          r'SELECT * FROM mutual_friends($1, $2, $3)',
          variables: [
            Variable<String>(aliceId),
            Variable<String>(bobId),
            Variable<String>(context),
          ],
        )
        .get();

    final reciprocal = await _voteUserFriendshipLookup
        .reciprocalPositivePeerIds(
          viewerId: aliceId,
          peerIds: rows.map((r) => r.data['id']! as String),
        );

    final peerScores = await _meritScoreLookup.reciprocalScoresForViewer(
      viewerId: aliceId,
      context: context,
    );

    final out = <UserPublicRecord>[];
    for (final row in rows) {
      final id = row.data['id']! as String;
      final displayName = row.data['display_name']! as String;
      final description = row.data['description']! as String;
      final handleRaw = row.data['handle'];
      final handle = handleRaw is String && handleRaw.trim().isNotEmpty
          ? handleRaw.trim()
          : null;
      final imageIdRaw = row.data['image_id'];

      ImagePublicRecord? imageRecord;
      if (imageIdRaw != null) {
        final imageUuid = imageIdRaw is UuidValue
            ? imageIdRaw
            : UuidValue.fromString(imageIdRaw.toString());
        final image = await _database.managers.images
            .filter((e) => e.id.equals(imageUuid))
            .getSingleOrNull();
        if (image != null) {
          imageRecord = ImagePublicRecord(
            id: image.id.toString(),
            hash: image.hash,
            height: image.height,
            width: image.width,
            authorId: image.authorId,
            createdAt: image.createdAt.dateTime.toUtc(),
          );
        }
      }

      final presence = await _userPresenceRepository.get(id);
      final peerScore = peerScores[id];
      final scores = peerScore == null
          ? const <MutualScoreRecord>[]
          : [peerScore];
      final userPresence = presence == null
          ? null
          : UserPresenceRecord(
              lastSeenAt: presence.lastSeenAt,
              status: presence.status.index,
            );
      out.add(
        UserPublicRecord(
          id: id,
          displayName: displayName,
          description: description,
          handle: handle,
          isMutualFriend: reciprocal.contains(id),
          image: imageRecord,
          scores: scores,
          userPresence: userPresence,
        ),
      );
    }
    return out;
  }
}
