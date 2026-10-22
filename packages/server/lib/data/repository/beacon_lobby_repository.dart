import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/questions_access.dart';
import 'package:tentura_server/domain/port/beacon_lobby_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

/// Request Questions (internally: the Request lobby, U088): the scope item
/// (`coordination_item` kind 7), `beacon_lobby_ban`, and the access policy
/// SQL functions of m0254, in plain SQL.
@LazySingleton(as: BeaconLobbyRepositoryPort)
class BeaconLobbyRepository implements BeaconLobbyRepositoryPort {
  const BeaconLobbyRepository(this._db);

  final TenturaDb _db;

  @override
  Future<String> ensureLobby({
    required String beaconId,
    required String authorId,
  }) async {
    final existing = await findLobby(beaconId);
    if (existing != null) return existing;
    await _db.customUpdate(
      'INSERT INTO public.coordination_item '
      '(id, beacon_id, kind, status, creator_id, published, published_at) '
      r'VALUES ($1, $2, $3, 0, $4, true, now()) '
      'ON CONFLICT DO NOTHING',
      variables: [
        Variable.withString(generateId('L')),
        Variable.withString(beaconId),
        const Variable<int>(coordinationItemKindLobby),
        Variable.withString(authorId),
      ],
    );
    return (await findLobby(beaconId))!;
  }

  @override
  Future<String?> findLobby(String beaconId) async {
    final row = await _db
        .customSelect(
          'SELECT id FROM public.coordination_item '
          r'WHERE beacon_id = $1 AND kind = $2',
          variables: [
            Variable.withString(beaconId),
            const Variable<int>(coordinationItemKindLobby),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('id');
  }

  @override
  Future<String?> lobbyBeaconId(String itemId) async {
    final row = await _db
        .customSelect(
          'SELECT beacon_id FROM public.coordination_item '
          r'WHERE id = $1 AND kind = $2',
          variables: [
            Variable.withString(itemId),
            const Variable<int>(coordinationItemKindLobby),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('beacon_id');
  }

  @override
  Future<Map<String, QuestionsAccess>> accessLevels({
    required String beaconId,
    required Iterable<String> userIds,
  }) async {
    final ids = {
      for (final id in userIds)
        if (id.isNotEmpty) id,
    }.toList();
    if (ids.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          'SELECT user_id, access::integer AS access '
          r'FROM public.questions_access_levels($1, $2::text[])',
          variables: [
            Variable.withString(beaconId),
            Variable<List<String>>(ids, PgTypes.textArray),
          ],
        )
        .get();
    final byId = {
      for (final r in rows)
        r.read<String>('user_id'): QuestionsAccess.fromLevel(
          r.read<int>('access'),
        ),
    };
    return {for (final id in ids) id: byId[id] ?? QuestionsAccess.none};
  }

  @override
  Future<List<QuestionsAudienceMember>> audience(String beaconId) async {
    final rows = await _db
        .customSelect(
          'SELECT a.user_id, a.access::integer AS access, '
          "COALESCE(u.display_name, '') AS display_name, "
          "COALESCE(u.handle, '') AS handle "
          r'FROM public.questions_audience($1) a '
          'JOIN public."user" u ON u.id = a.user_id '
          'ORDER BY a.user_id',
          variables: [Variable.withString(beaconId)],
        )
        .get();
    return [
      for (final r in rows)
        QuestionsAudienceMember(
          userId: r.read<String>('user_id'),
          displayName: r.read<String>('display_name'),
          handle: r.read<String>('handle'),
          access: QuestionsAccess.fromLevel(r.read<int>('access')),
        ),
    ];
  }

  @override
  Future<int> countVisibleMessages({
    required String lobbyId,
    required String viewerId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT count(*)::integer AS n FROM public.beacon_room_message m '
          r'WHERE m.thread_item_id = $1 '
          r'AND (m.author_id IS NULL OR NOT public.block_hides(m.author_id, $2))',
          variables: [
            Variable.withString(lobbyId),
            Variable.withString(viewerId),
          ],
        )
        .getSingle();
    return row.read<int>('n');
  }

  @override
  Future<bool> ban({
    required String beaconId,
    required String userId,
    required String bannedBy,
  }) async {
    final exists = await _db
        .customSelect(
          r'SELECT 1 AS one FROM public."user" WHERE id = $1',
          variables: [Variable.withString(userId)],
        )
        .getSingleOrNull();
    if (exists == null) return false;
    await _db.customUpdate(
      'INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by) '
      r'VALUES ($1, $2, $3) ON CONFLICT (beacon_id, user_id) DO NOTHING',
      variables: [
        Variable.withString(beaconId),
        Variable.withString(userId),
        Variable.withString(bannedBy),
      ],
    );
    return true;
  }

  @override
  Future<void> unban({required String beaconId, required String userId}) =>
      _db.customUpdate(
        'DELETE FROM public.beacon_lobby_ban '
        r'WHERE beacon_id = $1 AND user_id = $2',
        variables: [
          Variable.withString(beaconId),
          Variable.withString(userId),
        ],
      );

  @override
  Future<List<QuestionsBannedUser>> bannedUsers(String beaconId) async {
    final rows = await _db
        .customSelect(
          "SELECT ban.user_id, COALESCE(u.display_name, '') AS display_name "
          'FROM public.beacon_lobby_ban ban '
          'JOIN public."user" u ON u.id = ban.user_id '
          r'WHERE ban.beacon_id = $1 ORDER BY ban.banned_at, ban.user_id',
          variables: [Variable.withString(beaconId)],
        )
        .get();
    return [
      for (final r in rows)
        QuestionsBannedUser(
          userId: r.read<String>('user_id'),
          displayName: r.read<String>('display_name'),
        ),
    ];
  }
}
