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
      coTakerId: row.readNullable<String>('co_taker_id'),
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
    partnerUserId: row.readNullable<String>('partner_user_id'),
    partnerResponse: switch (row.readNullable<int>('partner_response')) {
      final int v => BatonPartnerResponse.fromSmallint(v),
      null => null,
    },
    partnerRespondedAt: _readTimestamp(row, 'partner_responded_at'),
    partnerInvites: row.read<int>('partner_invites'),
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
  Future<void> updateCandidates({
    required String batonId,
    required List<({String userId, int tier})> add,
    required List<String> remove,
    required List<({String userId, int tier})> retier,
  }) async {
    for (final userId in remove) {
      await _database.customStatement(
        r'''
DELETE FROM public.beacon_room_baton_candidate
 WHERE baton_id = $1 AND user_id = $2
''',
        [batonId, userId],
      );
    }
    for (final candidate in retier) {
      await _database.customStatement(
        r'''
UPDATE public.beacon_room_baton_candidate
   SET tier = $3
 WHERE baton_id = $1 AND user_id = $2
''',
        [batonId, candidate.userId, candidate.tier],
      );
    }
    for (final candidate in add) {
      await _database.customStatement(
        r'''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier)
VALUES ($1, $2, $3)
''',
        [batonId, candidate.userId, candidate.tier],
      );
    }
    if (add.isNotEmpty) {
      await _database.customStatement(
        r'''
UPDATE public.beacon_room_baton
   SET all_answered_notified_at = NULL
 WHERE id = $1
''',
        [batonId],
      );
    }
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
  Future<void> saveCandidate(RoomBatonCandidate candidate) =>
      _database.customUpdate(
        r'''
UPDATE public.beacon_room_baton_candidate
   SET response = $3,
       responded_at = $4::timestamptz,
       partner_user_id = $5,
       partner_response = $6::smallint,
       partner_invites = $7,
       partner_responded_at = CASE
         WHEN $6::smallint IS NULL OR $6::smallint = 0 THEN NULL
         WHEN partner_response IS DISTINCT FROM $6::smallint THEN now()
         ELSE partner_responded_at
       END
 WHERE baton_id = $1 AND user_id = $2
''',
        variables: [
          Variable<String>(candidate.batonId),
          Variable<String>(candidate.userId),
          Variable<int>(candidate.response.smallintValue),
          Variable<String>(candidate.respondedAt?.toUtc().toIso8601String()),
          Variable<String>(candidate.partnerUserId),
          Variable<int>(candidate.partnerResponse?.smallintValue),
          Variable<int>(candidate.partnerInvites),
        ],
      );

  @override
  Future<Set<String>> namedPartnerIds({
    required String batonId,
    required String userId,
  }) async {
    final prefix = 'baton_partner_asked:$batonId:$userId:';
    // Bound the existing source_event_key btree lookup by the final delimiter.
    final prefixEnd = 'baton_partner_asked:$batonId:$userId;';
    final rows = await _database
        .customSelect(
          r'''
SELECT substr(source_event_key, length($1) + 1) AS partner_id
  FROM public.attention_occurrence
 WHERE event_type = 'batonPartnerAsked'
   AND source_event_key >= $1 AND source_event_key < $2
   AND starts_with(source_event_key, $1)
''',
          variables: [Variable<String>(prefix), Variable<String>(prefixEnd)],
        )
        .get();
    return {for (final r in rows) r.read<String>('partner_id')};
  }

  @override
  Future<bool> isPairBlocked({required String a, required String b}) async {
    final row = await _database
        .customSelect(
          r'SELECT public.block_hides($1, $2) AS hidden',
          variables: [Variable<String>(a), Variable<String>(b)],
        )
        .getSingle();
    return row.read<bool>('hidden');
  }

  @override
  Future<void> clearAllAnsweredNotified(String batonId) =>
      _database.customUpdate(
        r'''
UPDATE public.beacon_room_baton
   SET all_answered_notified_at = NULL
 WHERE id = $1 AND all_answered_notified_at IS NOT NULL
''',
        variables: [Variable<String>(batonId)],
      );

  @override
  Future<bool> hasUnansweredCandidate(String batonId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT count(*)::int AS waiting FROM public.beacon_room_baton_candidate
 WHERE baton_id = $1
   AND (response = 0 OR partner_response IS NOT DISTINCT FROM 0
        OR (partner_response = 1 AND partner_user_id IS NULL))
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
    String? coTakerId,
  }) => _database.customUpdate(
    r'''
UPDATE public.beacon_room_baton
   SET status = 1, taker_id = $2, selection_mode = $3, resolved_at = $4,
       co_taker_id = $5
 WHERE id = $1
''',
    variables: [
      Variable<String>(batonId),
      Variable<String>(takerId),
      Variable<int>(mode.smallintValue),
      Variable(PgDateTime(resolvedAt), PgTypes.timestampWithTimezone),
      Variable<String>(coTakerId),
    ],
  );

  @override
  Future<void> cancel({
    required String batonId,
    required DateTime resolvedAt,
  }) => _database.customUpdate(
    r'''
WITH cancelled AS (
  UPDATE public.beacon_room_baton
     SET status = 2, resolved_at = $2
   WHERE id = $1
  RETURNING message_id
)
-- No-op touch of the baton message: its row trigger fans `room_message` out to
-- the whole room, so members outside the baton (who get no `room_baton`
-- event) refetch and see the bubble switch to «cancelled». Skipped while the
-- room is read-only: the lifecycle write guard rejects message updates then.
UPDATE public.beacon_room_message m
   SET body = m.body
  FROM cancelled, public.beacon b
 WHERE m.id = cancelled.message_id
   AND b.id = m.beacon_id
   AND b.status NOT IN (1, 2, 6)
''',
    variables: [
      Variable<String>(batonId),
      Variable(PgDateTime(resolvedAt), PgTypes.timestampWithTimezone),
    ],
  );
}
