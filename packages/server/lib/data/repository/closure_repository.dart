import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';

import '../database/tentura_db.dart';

/// A11: raw-SQL persistence for the nine `beacon_closure*` tables (m0203,
/// no Drift table classes — same pattern as the m0202 trust ledger).
/// One SQL statement per method; no business rules (those live in A12).
@Injectable(
  as: ClosureRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class ClosureRepository implements ClosureRepositoryPort {
  const ClosureRepository(this._database);

  final TenturaDb _database;

  static const _epochColumns = '''
beacon_id,
epoch,
status,
opened_at::text AS opened_at,
closes_at::text AS closes_at,
extensions_used,
finalized_at::text AS finalized_at,
finalize_reason,
settlement_version,
settlement_params::text AS settlement_params
''';

  @override
  Future<void> lockRequest(String beaconId) => _database.customStatement(
    r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
    [beaconId],
  );

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) => _database
      .customSelect(
        '''
SELECT $_epochColumns
FROM public.beacon_closure
WHERE beacon_id = \$1 AND status = 0
''',
        variables: [Variable<String>(beaconId)],
      )
      .map(_mapEpoch)
      .getSingleOrNull();

  @override
  Future<int> maxEpoch(String beaconId) => _database
      .customSelect(
        r'''
SELECT COALESCE(MAX(epoch), 0) AS n
FROM public.beacon_closure
WHERE beacon_id = $1
''',
        variables: [Variable<String>(beaconId)],
      )
      .map((row) => row.read<int>('n'))
      .getSingle();

  @override
  Future<int> cancelledEpochCount(String beaconId) => _database
      .customSelect(
        r'''
SELECT count(*)::int AS n
FROM public.beacon_closure
WHERE beacon_id = $1 AND status = 2
''',
        variables: [Variable<String>(beaconId)],
      )
      .map((row) => row.read<int>('n'))
      .getSingle();

  @override
  Future<void> extendEpoch({
    required String beaconId,
    required int epoch,
  }) => _database.customUpdate(
    r'''
UPDATE public.beacon_closure
SET closes_at = closes_at + interval '7 days',
    extensions_used = extensions_used + 1
WHERE beacon_id = $1 AND epoch = $2
''',
    variables: [Variable<String>(beaconId), Variable<int>(epoch)],
  );

  @override
  Future<ClosureEpoch> createEpoch({
    required String beaconId,
    required int epoch,
    required DateTime openedAt,
    required DateTime closesAt,
    int extensionsUsed = 0,
  }) => _database
      .customSelect(
        '''
INSERT INTO public.beacon_closure (
  beacon_id,
  epoch,
  status,
  opened_at,
  closes_at,
  extensions_used
) VALUES (\$1, \$2, 0, \$3, \$4, \$5)
RETURNING $_epochColumns
''',
        variables: [
          Variable<String>(beaconId),
          Variable<int>(epoch),
          Variable(PgDateTime(openedAt.toUtc()), PgTypes.timestampWithTimezone),
          Variable(PgDateTime(closesAt.toUtc()), PgTypes.timestampWithTimezone),
          Variable<int>(extensionsUsed),
        ],
      )
      .map(_mapEpoch)
      .getSingle();

  @override
  Future<void> setEpochStatus({
    required String beaconId,
    required int epoch,
    required ClosureEpochStatus status,
    DateTime? finalizedAt,
    int? finalizeReason,
    int? settlementVersion,
    Map<String, Object?>? settlementParams,
  }) => _database.customUpdate(
    r'''
UPDATE public.beacon_closure
SET
  status = $3,
  finalized_at = $4::timestamptz,
  finalize_reason = $5,
  settlement_version = $6,
  settlement_params = $7::jsonb
WHERE beacon_id = $1 AND epoch = $2
''',
    variables: [
      Variable<String>(beaconId),
      Variable<int>(epoch),
      Variable<int>(status.dbValue),
      Variable<String>(finalizedAt?.toUtc().toIso8601String()),
      Variable<int>(finalizeReason),
      Variable<int>(settlementVersion),
      Variable<String>(
        settlementParams == null ? null : jsonEncode(settlementParams),
      ),
    ],
  );

  @override
  Future<void> insertMembers({
    required String beaconId,
    required int epoch,
    required List<ClosureMemberInsert> members,
  }) async {
    if (members.isEmpty) return;
    final variables = <Variable>[
      Variable<String>(beaconId),
      Variable<int>(epoch),
    ];
    final values = <String>[];
    for (final member in members) {
      final base = variables.length + 1;
      values.add(
        '(\$1, \$2, \$$base, \$${base + 1}, \$${base + 2}, \$${base + 3})',
      );
      variables.addAll([
        Variable<String>(member.userId),
        Variable<String>(member.arrivalEdgeId),
        Variable<int>(member.departure?.dbValue),
        Variable<bool>(member.activeAtOpen),
      ]);
    }
    await _database.customInsert(
      '''
INSERT INTO public.beacon_closure_member (
  beacon_id,
  epoch,
  user_id,
  arrival_edge_id,
  departure,
  active_at_open
) VALUES ${values.join(', ')}
''',
      variables: variables,
    );
  }

  @override
  Future<void> setDeparture({
    required String beaconId,
    required int epoch,
    required String userId,
    Departure? departure,
  }) => _database.customUpdate(
    r'''
UPDATE public.beacon_closure_member
SET departure = $4
WHERE beacon_id = $1 AND epoch = $2 AND user_id = $3
''',
    variables: [
      Variable<String>(beaconId),
      Variable<int>(epoch),
      Variable<String>(userId),
      Variable<int>(departure?.dbValue),
    ],
  );

  @override
  Future<List<ClosureMemberRow>> members({
    required String beaconId,
    required int epoch,
  }) => _database
      .customSelect(
        r'''
SELECT user_id, active_at_open, arrival_edge_id, departure
FROM public.beacon_closure_member
WHERE beacon_id = $1 AND epoch = $2
ORDER BY user_id
''',
        variables: [Variable<String>(beaconId), Variable<int>(epoch)],
      )
      .map(
        (row) => ClosureMemberRow(
          userId: row.read<String>('user_id'),
          activeAtOpen: row.read<bool>('active_at_open'),
          arrivalEdgeId: row.readNullable<String>('arrival_edge_id'),
          departure: _departureFromInt(row.readNullable<int>('departure')),
        ),
      )
      .get();

  @override
  Future<List<ClosureOutcomeRow>> outcomes(String beaconId) => _database
      .customSelect(
        r'''
SELECT helper_id, outcome, updated_at::text AS updated_at
FROM public.beacon_closure_outcome
WHERE beacon_id = $1
ORDER BY helper_id
''',
        variables: [Variable<String>(beaconId)],
      )
      .map(
        (row) => ClosureOutcomeRow(
          helperId: row.read<String>('helper_id'),
          outcome: ClosureOutcome.tryFromInt(row.readNullable<int>('outcome')),
          updatedAt: DateTime.parse(row.read<String>('updated_at')).toUtc(),
        ),
      )
      .get();

  @override
  Future<void> saveOutcome({
    required String beaconId,
    required String helperId,
    ClosureOutcome? outcome,
  }) => _database.customInsert(
    r'''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES ($1, $2, $3)
ON CONFLICT (beacon_id, helper_id)
DO UPDATE SET outcome = EXCLUDED.outcome, updated_at = now()
''',
    variables: [
      Variable<String>(beaconId),
      Variable<String>(helperId),
      Variable<int>(outcome?.smallintValue),
    ],
  );

  @override
  Future<Map<String, int>> split(String beaconId) => _database
      .customSelect(
        r'''
SELECT helper_id, pct
FROM public.beacon_closure_author_split
WHERE beacon_id = $1
''',
        variables: [Variable<String>(beaconId)],
      )
      .map((row) => (row.read<String>('helper_id'), row.read<int>('pct')))
      .get()
      .then((rows) => {for (final row in rows) row.$1: row.$2});

  @override
  Future<void> replaceSplit(String beaconId, Map<String, int>? helperPct) {
    if (helperPct == null || helperPct.isEmpty) {
      return _database.customUpdate(
        r'DELETE FROM public.beacon_closure_author_split WHERE beacon_id = $1',
        variables: [Variable<String>(beaconId)],
      );
    }
    final variables = <Variable>[Variable<String>(beaconId)];
    final values = <String>[];
    for (final entry in helperPct.entries) {
      final base = variables.length + 1;
      values.add('(\$1, \$$base, \$${base + 1})');
      variables.addAll([
        Variable<String>(entry.key),
        Variable<int>(entry.value),
      ]);
    }
    return _database.customInsert(
      '''
WITH d AS (
  DELETE FROM public.beacon_closure_author_split
  WHERE beacon_id = \$1
  RETURNING beacon_id
)
INSERT INTO public.beacon_closure_author_split (beacon_id, helper_id, pct)
VALUES ${values.join(', ')}
''',
      variables: variables,
    );
  }

  @override
  Future<List<ClosureSupportRow>> supports({
    required String beaconId,
    required ClosureSupportVersion version,
  }) => _database
      .customSelect(
        r'''
SELECT voter_id, target_id, version, pressed_at::text AS pressed_at
FROM public.beacon_closure_support
WHERE beacon_id = $1 AND version = $2
ORDER BY voter_id, target_id
''',
        variables: [
          Variable<String>(beaconId),
          Variable<int>(version.dbValue),
        ],
      )
      .map(
        (row) => ClosureSupportRow(
          voterId: row.read<String>('voter_id'),
          targetId: row.read<String>('target_id'),
          version: ClosureSupportVersion.tryFromInt(row.read<int>('version'))!,
          pressedAt: DateTime.parse(row.read<String>('pressed_at')).toUtc(),
        ),
      )
      .get();

  @override
  Future<void> toggleSupport({
    required String beaconId,
    required String voterId,
    required String targetId,
    required bool on,
  }) {
    final variables = [
      Variable<String>(beaconId),
      Variable<String>(voterId),
      Variable<String>(targetId),
    ];
    return on
        ? _database.customInsert(
            r'''
INSERT INTO public.beacon_closure_support (
  beacon_id,
  voter_id,
  target_id,
  version
) VALUES ($1, $2, $3, 0)
ON CONFLICT DO NOTHING
''',
            variables: variables,
          )
        : _database.customUpdate(
            r'''
DELETE FROM public.beacon_closure_support
WHERE beacon_id = $1 AND voter_id = $2 AND target_id = $3 AND version = 0
''',
            variables: variables,
          );
  }

  @override
  Future<void> commitSupport({
    required String beaconId,
    required String voterId,
  }) => _database.customInsert(
    r'''
WITH moved AS (
  UPDATE public.beacon_closure_support
  SET version = 1
  WHERE beacon_id = $1 AND voter_id = $2 AND version = 0
  RETURNING voter_id
)
INSERT INTO public.beacon_closure_commit (beacon_id, voter_id, committed_at)
VALUES ($1, $2, now())
ON CONFLICT (beacon_id, voter_id) DO NOTHING
''',
    variables: [Variable<String>(beaconId), Variable<String>(voterId)],
  );

  @override
  Future<void> skip({
    required String beaconId,
    required String voterId,
  }) => _database.customInsert(
    r'''
INSERT INTO public.beacon_closure_commit (beacon_id, voter_id, committed_at)
VALUES ($1, $2, now())
ON CONFLICT (beacon_id, voter_id) DO NOTHING
''',
    variables: [Variable<String>(beaconId), Variable<String>(voterId)],
  );

  @override
  Future<void> clearCommitted(String beaconId) => _database.customUpdate(
    r'''
WITH s AS (
  DELETE FROM public.beacon_closure_support
  WHERE beacon_id = $1 AND version = 1
  RETURNING beacon_id
)
DELETE FROM public.beacon_closure_commit
WHERE beacon_id = $1
''',
    variables: [Variable<String>(beaconId)],
  );

  @override
  Future<List<ClosureCommitRow>> commits(String beaconId) => _database
      .customSelect(
        r'''
SELECT voter_id, committed_at::text AS committed_at
FROM public.beacon_closure_commit
WHERE beacon_id = $1
ORDER BY voter_id
''',
        variables: [Variable<String>(beaconId)],
      )
      .map(
        (row) => ClosureCommitRow(
          voterId: row.read<String>('voter_id'),
          committedAt: DateTime.parse(
            row.read<String>('committed_at'),
          ).toUtc(),
        ),
      )
      .get();

  @override
  Future<void> setMark({
    required String beaconId,
    required String markerId,
    required String targetId,
    required bool on,
  }) {
    final variables = [
      Variable<String>(beaconId),
      Variable<String>(markerId),
      Variable<String>(targetId),
    ];
    return on
        ? _database.customInsert(
            r'''
INSERT INTO public.beacon_closure_mark (beacon_id, marker_id, target_id)
VALUES ($1, $2, $3)
ON CONFLICT (beacon_id, marker_id, target_id)
DO UPDATE SET updated_at = now()
''',
            variables: variables,
          )
        : _database.customUpdate(
            r'''
DELETE FROM public.beacon_closure_mark
WHERE beacon_id = $1 AND marker_id = $2 AND target_id = $3
''',
            variables: variables,
          );
  }

  @override
  Future<List<ClosureMarkRow>> marks(String beaconId) => _database
      .customSelect(
        r'''
SELECT marker_id, target_id, updated_at::text AS updated_at
FROM public.beacon_closure_mark
WHERE beacon_id = $1
ORDER BY marker_id, target_id
''',
        variables: [Variable<String>(beaconId)],
      )
      .map(
        (row) => ClosureMarkRow(
          markerId: row.read<String>('marker_id'),
          targetId: row.read<String>('target_id'),
          updatedAt: DateTime.parse(row.read<String>('updated_at')).toUtc(),
        ),
      )
      .get();

  @override
  Future<void> saveStory({
    required String beaconId,
    required String body,
  }) => _database.customInsert(
    r'''
INSERT INTO public.beacon_closure_story (beacon_id, body)
VALUES ($1, $2)
ON CONFLICT (beacon_id)
DO UPDATE SET body = EXCLUDED.body, updated_at = now()
''',
    variables: [Variable<String>(beaconId), Variable<String>(body)],
  );

  @override
  Future<String?> story(String beaconId) => _database
      .customSelect(
        r'''
SELECT body
FROM public.beacon_closure_story
WHERE beacon_id = $1
''',
        variables: [Variable<String>(beaconId)],
      )
      .map((row) => row.read<String>('body'))
      .getSingleOrNull();

  @override
  Future<void> insertResults({
    required String beaconId,
    required int epoch,
    required List<ClosureResultInsert> rows,
  }) async {
    if (rows.isEmpty) return;
    final variables = <Variable>[
      Variable<String>(beaconId),
      Variable<int>(epoch),
    ];
    final values = <String>[];
    for (final result in rows) {
      final base = variables.length + 1;
      values.add(
        '(\$1, \$2, \$$base, \$${base + 1}, \$${base + 2}, '
        '\$${base + 3}, \$${base + 4})',
      );
      variables.addAll([
        Variable<String>(result.userId),
        Variable<int>(result.outcome.smallintValue),
        Variable<int>(result.band.smallintValue),
        Variable<int>(result.draftFlag.dbValue),
        Variable<double>(result.helped),
      ]);
    }
    await _database.customInsert(
      '''
INSERT INTO public.beacon_closure_result (
  beacon_id,
  epoch,
  user_id,
  outcome,
  band,
  draft_flag,
  helped
) VALUES ${values.join(', ')}
''',
      variables: variables,
    );
  }

  @override
  Future<ClosureResultRow?> resultFor({
    required String beaconId,
    required String userId,
  }) => _database
      .customSelect(
        r'''
SELECT beacon_id, epoch, user_id, outcome, band, draft_flag, helped
FROM public.beacon_closure_result
WHERE beacon_id = $1 AND user_id = $2
ORDER BY epoch DESC
LIMIT 1
''',
        variables: [Variable<String>(beaconId), Variable<String>(userId)],
      )
      .map(
        (row) => ClosureResultRow(
          beaconId: row.read<String>('beacon_id'),
          epoch: row.read<int>('epoch'),
          userId: row.read<String>('user_id'),
          outcome: ClosureOutcome.tryFromInt(row.read<int>('outcome'))!,
          band: ClosureBand.tryFromInt(row.read<int>('band'))!,
          draftFlag: ClosureResultDraftFlag.tryFromInt(
            row.read<int>('draft_flag'),
          )!,
          helped: row.read<double>('helped'),
        ),
      )
      .getSingleOrNull();

  @override
  Future<ForwardEdgeEntity?> selectArrivalEdge({
    required String beaconId,
    required String helperId,
    required DateTime offerCreatedAt,
  }) => _database
      .customSelect(
        r'''
SELECT
  id,
  beacon_id,
  sender_id,
  recipient_id,
  note,
  context,
  parent_edge_id,
  batch_id,
  recipient_rejected,
  recipient_rejection_message,
  created_at::text AS created_at,
  cancelled_at::text AS cancelled_at,
  recipient_read_at::text AS recipient_read_at
FROM public.beacon_forward_edge
WHERE beacon_id = $1
  AND recipient_id = $2
  AND created_at < $3
  AND (cancelled_at IS NULL OR cancelled_at > $3)
ORDER BY created_at DESC, id DESC
LIMIT 1
''',
        variables: [
          Variable<String>(beaconId),
          Variable<String>(helperId),
          Variable(
            PgDateTime(offerCreatedAt.toUtc()),
            PgTypes.timestampWithTimezone,
          ),
        ],
        readsFrom: {_database.beaconForwardEdges},
      )
      .map(_mapEdge)
      .getSingleOrNull();

  static ClosureEpoch _mapEpoch(QueryRow row) => ClosureEpoch(
    beaconId: row.read<String>('beacon_id'),
    epoch: row.read<int>('epoch'),
    status: ClosureEpochStatus.tryFromInt(row.read<int>('status'))!,
    openedAt: DateTime.parse(row.read<String>('opened_at')).toUtc(),
    closesAt: DateTime.parse(row.read<String>('closes_at')).toUtc(),
    extensionsUsed: row.read<int>('extensions_used'),
    finalizedAt: _parseTs(row.readNullable<String>('finalized_at')),
    finalizeReason: row.readNullable<int>('finalize_reason'),
    settlementVersion: row.readNullable<int>('settlement_version'),
    settlementParams: switch (row.readNullable<String>('settlement_params')) {
      final String raw => jsonDecode(raw) as Map<String, Object?>,
      null => null,
    },
  );

  static ForwardEdgeEntity _mapEdge(QueryRow row) => ForwardEdgeEntity(
    id: row.read<String>('id'),
    beaconId: row.read<String>('beacon_id'),
    senderId: row.read<String>('sender_id'),
    recipientId: row.read<String>('recipient_id'),
    note: row.read<String>('note'),
    context: row.readNullable<String>('context'),
    parentEdgeId: row.readNullable<String>('parent_edge_id'),
    batchId: row.readNullable<String>('batch_id'),
    recipientRejected: row.read<bool>('recipient_rejected'),
    recipientRejectionMessage: row.read<String>(
      'recipient_rejection_message',
    ),
    createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
    cancelledAt: _parseTs(row.readNullable<String>('cancelled_at')),
    recipientReadAt: _parseTs(row.readNullable<String>('recipient_read_at')),
  );

  static DateTime? _parseTs(String? raw) =>
      raw == null ? null : DateTime.parse(raw).toUtc();

  static Departure? _departureFromInt(int? v) => switch (v) {
    1 => Departure.voluntary,
    2 => Departure.removed,
    _ => null,
  };
}
