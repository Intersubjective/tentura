import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/port/beacon_lobby_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

/// U088 — lobby scope item (`coordination_item` kind 7, m0253) and
/// `beacon_lobby_ban`, in plain SQL.
@LazySingleton(as: BeaconLobbyRepositoryPort)
class BeaconLobbyRepository implements BeaconLobbyRepositoryPort {
  const BeaconLobbyRepository(this._db);

  final TenturaDb _db;

  @override
  Future<String> ensureLobby({
    required String beaconId,
    required String authorId,
  }) async {
    final existing = await _findLobby(beaconId);
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
    return (await _findLobby(beaconId))!;
  }

  Future<String?> _findLobby(String beaconId) async {
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
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT 1 AS one FROM public.beacon_help_offer '
          r'WHERE beacon_id = $1 AND user_id = $2 AND status = 0',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(userId),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<bool> isBanned({
    required String beaconId,
    required String userId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT 1 AS one FROM public.beacon_lobby_ban '
          r'WHERE beacon_id = $1 AND user_id = $2',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(userId),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> ban({
    required String beaconId,
    required String userId,
    required String bannedBy,
  }) => _db.customUpdate(
    'INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by) '
    r'VALUES ($1, $2, $3) ON CONFLICT (beacon_id, user_id) DO NOTHING',
    variables: [
      Variable.withString(beaconId),
      Variable.withString(userId),
      Variable.withString(bannedBy),
    ],
  );

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
  Future<List<String>> bannedUserIds(String beaconId) async {
    final rows = await _db
        .customSelect(
          'SELECT user_id FROM public.beacon_lobby_ban '
          r'WHERE beacon_id = $1 ORDER BY banned_at, user_id',
          variables: [Variable.withString(beaconId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('user_id')];
  }
}
