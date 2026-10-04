import 'package:drift_postgres/drift_postgres.dart' show PgDateTime, PgTypes;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/port/room_baton_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(as: RoomBatonRepositoryPort)
class RoomBatonRepository implements RoomBatonRepositoryPort {
  const RoomBatonRepository(this._database);

  final TenturaDb _database;

  static DateTime? _readTimestamp(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  RoomBaton _batonFromRow(QueryRow row) {
    final selectionMode = row.readNullable<int>('selection_mode');
    return RoomBaton(
      id: row.read<String>('id'),
      messageId: row.read<String>('message_id'),
      beaconId: row.read<String>('beacon_id'),
      authorId: row.read<String>('author_id'),
      status: BatonStatus.fromSmallint(row.read<int>('status')),
      takerId: row.readNullable<String>('taker_id'),
      selectionMode: selectionMode == null
          ? null
          : BatonSelectionMode.fromSmallint(selectionMode),
      allAnsweredNotifiedAt: _readTimestamp(row, 'all_answered_notified_at'),
      createdAt: _readTimestamp(row, 'created_at')!,
      resolvedAt: _readTimestamp(row, 'resolved_at'),
    );
  }

  RoomBatonCandidate _candidateFromRow(QueryRow row) => RoomBatonCandidate(
    batonId: row.read<String>('baton_id'),
    userId: row.read<String>('user_id'),
    tier: row.read<int>('tier'),
    response: BatonResponse.fromSmallint(row.read<int>('response')),
    respondedAt: _readTimestamp(row, 'responded_at'),
  );

  @override
  Future<RoomBaton?> getLiveBatonForMessage(String messageId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT * FROM public.beacon_room_baton
 WHERE message_id = $1 AND status <> 2
''',
          variables: [Variable<String>(messageId)],
        )
        .getSingleOrNull();
    return row == null ? null : _batonFromRow(row);
  }

  @override
  Future<RoomBaton?> getById(String batonId) async {
    final row = await _database
        .customSelect(
          r'SELECT * FROM public.beacon_room_baton WHERE id = $1',
          variables: [Variable<String>(batonId)],
        )
        .getSingleOrNull();
    return row == null ? null : _batonFromRow(row);
  }

  @override
  Future<List<RoomBatonCandidate>> getCandidates(String batonId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT * FROM public.beacon_room_baton_candidate
 WHERE baton_id = $1
 ORDER BY user_id
''',
          variables: [Variable<String>(batonId)],
        )
        .get();
    return rows.map(_candidateFromRow).toList();
  }

  @override
  Future<RoomBaton> create({
    required String id,
    required String messageId,
    required String beaconId,
    required String authorId,
    required List<({String userId, int tier})> candidates,
  }) async {
    await _database.customStatement(
      r'''
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id)
VALUES ($1, $2, $3, $4)
''',
      [id, messageId, beaconId, authorId],
    );
    for (final candidate in candidates) {
      await _database.customStatement(
        r'''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier)
VALUES ($1, $2, $3)
''',
        [id, candidate.userId, candidate.tier],
      );
    }
    return (await getById(id))!;
  }

  @override
  Future<void> updateCandidateResponse({
    required String batonId,
    required String userId,
    required BatonResponse response,
    required DateTime respondedAt,
  }) => _database.customUpdate(
    r'''
UPDATE public.beacon_room_baton_candidate
   SET response = $3, responded_at = $4
 WHERE baton_id = $1 AND user_id = $2
''',
    variables: [
      Variable<String>(batonId),
      Variable<String>(userId),
      Variable<int>(response.smallintValue),
      Variable(PgDateTime(respondedAt), PgTypes.timestampWithTimezone),
    ],
  );

  @override
  Future<bool> hasWaitingCandidate(String batonId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT count(*)::int AS waiting FROM public.beacon_room_baton_candidate
 WHERE baton_id = $1 AND response = 0
''',
          variables: [Variable<String>(batonId)],
        )
        .getSingle();
    return row.read<int>('waiting') > 0;
  }

  @override
  Future<bool> markAllAnsweredNotifiedIfUnset({
    required String batonId,
    required DateTime at,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
UPDATE public.beacon_room_baton
   SET all_answered_notified_at = $2
 WHERE id = $1 AND all_answered_notified_at IS NULL
RETURNING id
''',
          variables: [
            Variable<String>(batonId),
            Variable(PgDateTime(at), PgTypes.timestampWithTimezone),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<void> select({
    required String batonId,
    required String takerId,
    required BatonSelectionMode mode,
    required DateTime resolvedAt,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_room_baton
   SET status = 1, taker_id = $2, selection_mode = $3, resolved_at = $4
 WHERE id = $1
''',
    [batonId, takerId, mode.smallintValue, resolvedAt],
  );

  @override
  Future<void> cancel({
    required String batonId,
    required DateTime resolvedAt,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_room_baton
   SET status = 2, resolved_at = $2
 WHERE id = $1
''',
    [batonId, resolvedAt],
  );
}
