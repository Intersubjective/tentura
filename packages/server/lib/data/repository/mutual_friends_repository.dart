import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/mutual_friends_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: MutualFriendsRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class MutualFriendsRepository implements MutualFriendsRepositoryPort {
  const MutualFriendsRepository(
    this._database,
    this._userPresenceRepository,
  );

  final TenturaDb _database;

  final UserPresenceRepositoryPort _userPresenceRepository;

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

    final peerScores = await _fetchPeerScoresForViewer(
      viewerId: aliceId,
      context: context,
    );

    final out = <UserPublicRecord>[];
    for (final row in rows) {
      final id = row.data['id']! as String;
      final title = row.data['title']! as String;
      final description = row.data['description']! as String;
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
      // Align with Hasura `UserModel` / `gqlTypeMutualScore`: `dst_score` →
      // Profile.score (viewer→peer), `src_score` → Profile.rScore (peer→viewer).
      final scores = peerScore == null
          ? const <MutualScoreRecord>[]
          : [
              MutualScoreRecord(
                srcScore: peerScore.rev,
                dstScore: peerScore.fwd,
              ),
            ];
      final userPresence = presence == null
          ? null
          : UserPresenceRecord(
              lastSeenAt: presence.lastSeenAt,
              status: presence.status.index,
            );
      out.add(
        UserPublicRecord(
          id: id,
          title: title,
          description: description,
          image: imageRecord,
          scores: scores,
          userPresence: userPresence,
        ),
      );
    }
    return out;
  }

  /// Alice→peer (fwd) and peer→Alice (rev) from `mr_mutual_scores`, same
  /// semantics as `mutual_friends` SQL (`alice_peers` CTE).
  Future<Map<String, _PeerMrScores>> _fetchPeerScoresForViewer({
    required String viewerId,
    required String context,
  }) async {
    final scoreRows = await _database
        .customSelect(
          r'''
SELECT
  CASE WHEN ms.src = $1 THEN ms.dst::text ELSE ms.src::text END AS peer_id,
  CASE WHEN ms.src = $1 THEN ms.score_value_of_dst
       ELSE ms.score_value_of_src END AS fwd_alice,
  CASE WHEN ms.src = $1 THEN ms.score_value_of_src
       ELSE ms.score_value_of_dst END AS rev_alice
FROM mr_mutual_scores($1, $2) ms
WHERE (ms.src = $1 OR ms.dst = $1)
  AND ms.score_value_of_src > 0::double precision
  AND ms.score_value_of_dst > 0::double precision
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(context),
          ],
        )
        .get();

    final out = <String, _PeerMrScores>{};
    for (final row in scoreRows) {
      final peerId = row.data['peer_id']! as String;
      out[peerId] = _PeerMrScores(
        fwd: _asDouble(row.data['fwd_alice']),
        rev: _asDouble(row.data['rev_alice']),
      );
    }
    return out;
  }

  static double _asDouble(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    throw StateError('Expected num, got ${value.runtimeType}');
  }
}

/// Forward (viewer→peer) and reverse (peer→viewer) MeritRank scores for one
/// peer of `viewerId`.
class _PeerMrScores {
  const _PeerMrScores({
    required this.fwd,
    required this.rev,
  });

  final double fwd;
  final double rev;
}
