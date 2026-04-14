import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import '../database/tentura_db.dart';
import 'user_presence_repository.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class MutualFriendsRepository {
  const MutualFriendsRepository(
    this._database,
    this._userPresenceRepository,
  );

  final TenturaDb _database;

  final UserPresenceRepository _userPresenceRepository;

  /// Returns GraphQL `user` maps (`gqlTypeUserPublic`) for mutual friends of
  /// [aliceId] and [bobId] in [context].
  Future<List<Map<String, dynamic>>> fetchMutualFriends({
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

    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row.data['id']! as String;
      final title = row.data['title']! as String;
      final description = row.data['description']! as String;
      final imageIdRaw = row.data['image_id'];

      Map<String, dynamic>? imageMap;
      if (imageIdRaw != null) {
        final imageUuid = imageIdRaw is UuidValue
            ? imageIdRaw
            : UuidValue.fromString(imageIdRaw.toString());
        final image = await _database.managers.images
            .filter((e) => e.id.equals(imageUuid))
            .getSingleOrNull();
        if (image != null) {
          imageMap = {
            'id': image.id.toString(),
            'hash': image.hash,
            'height': image.height,
            'width': image.width,
            'author_id': image.authorId,
            'created_at': image.createdAt.dateTime.toUtc(),
          };
        }
      }

      final presence = await _userPresenceRepository.get(id);
      out.add({
        'id': id,
        'title': title,
        'description': description,
        'my_vote': null,
        'image': imageMap,
        'scores': <Map<String, dynamic>>[],
        'user_presence': presence == null
            ? null
            : {
                'last_seen_at':
                    presence.lastSeenAt.toUtc().toIso8601String(),
                'status': presence.status.index,
              },
      });
    }
    return out;
  }
}
