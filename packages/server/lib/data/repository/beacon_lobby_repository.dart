import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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

  /// `BeaconStatus.openFamilyValues` as an SQL list of integer constants, so
  /// a new open-family status cannot silently count as closed (#657).
  static final String _openFamilyStatusList =
      (BeaconStatus.openFamilyValues.toList()..sort()).join(', ');

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
  Future<QuestionsStandingFacts> standingFacts({
    required String beaconId,
    required String userId,
  }) async {
    final row = await _db
        .customSelect(
          // Open family (0 open, 7, 8) still takes offers; Final check (5)
          // and every closed state do not (#657).
          'SELECT b.status NOT IN ($_openFamilyStatusList) AS closed, '
          'EXISTS (SELECT 1 FROM public.beacon_lobby_ban ban '
          r'WHERE ban.beacon_id = b.id AND ban.user_id = $2) AS banned, '
          'EXISTS (SELECT 1 FROM public.beacon_forward_edge fe '
          r'WHERE fe.beacon_id = b.id AND fe.recipient_id = $2 '
          'AND fe.cancelled_at IS NULL AND fe.recipient_rejected) '
          'AS cant_help, '
          'COALESCE(ho.status <> 0, false) AS past_offer, '
          'COALESCE(ho.status <> 0 AND ho.withdraw_reason IS NOT NULL, false) '
          'AS withdrew, '
          r'(b.user_id <> $2 AND ( '
          'EXISTS (SELECT 1 FROM public.beacon_steward bs '
          r'WHERE bs.beacon_id = b.id AND bs.user_id = $2) '
          'OR EXISTS (SELECT 1 FROM public.beacon_participant bp '
          r'WHERE bp.beacon_id = b.id AND bp.user_id = $2 '
          'AND (bp.role = 1 OR bp.room_access = 3)) '
          'OR COALESCE(ho.status = 0, false))) AS helper '
          'FROM public.beacon b '
          'LEFT JOIN public.beacon_help_offer ho '
          r'ON ho.beacon_id = b.id AND ho.user_id = $2 '
          r'WHERE b.id = $1 AND b.kind = 0',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(userId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return const QuestionsStandingFacts();
    return QuestionsStandingFacts(
      closed: row.read<bool>('closed'),
      banned: row.read<bool>('banned'),
      answeredCantHelp: row.read<bool>('cant_help'),
      pastOffer: row.read<bool>('past_offer'),
      offerWithdrawnByHelper: row.read<bool>('withdrew'),
      helper: row.read<bool>('helper'),
    );
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
  Future<({int messageCount, int unreadCount})> countVisibleMessages({
    required String lobbyId,
    required String viewerId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT count(*)::integer AS message_count, '
          r'count(*) FILTER (WHERE m.author_id <> $2 '
          'AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at))'
          '::integer AS unread_count FROM public.beacon_room_message m '
          'LEFT JOIN public.beacon_room_seen s '
          r'ON s.thread_item_id = m.thread_item_id AND s.user_id = $2 '
          'AND s.beacon_id = m.beacon_id '
          r'WHERE m.thread_item_id = $1 '
          r'AND (m.author_id IS NULL OR NOT public.block_hides(m.author_id, $2))',
          variables: [
            Variable.withString(lobbyId),
            Variable.withString(viewerId),
          ],
        )
        .getSingle();
    return (
      messageCount: row.read<int>('message_count'),
      unreadCount: row.read<int>('unread_count'),
    );
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
