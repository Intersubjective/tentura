import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/trust/forward/forward_causal_graph_builder.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import 'beacon_hierarchy_repository.dart';
import 'capability_evidence_repository.dart';
import 'commitment_repository.dart' show insertCommitmentEvent;
import 'trust_ledger_repository.dart';

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

  TrustLedgerRepository get _ledger => TrustLedgerRepository(_database);

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
  Future<void> lockHierarchyScope() =>
      BeaconHierarchyRepository(_database).lockMutationScope();

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
  Future<ClosureEpoch?> latestEpoch(String beaconId) => _database
      .customSelect(
        '''
SELECT $_epochColumns
FROM public.beacon_closure
WHERE beacon_id = \$1
ORDER BY epoch DESC
LIMIT 1
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
  Future<void> expireLiveEpoch(String beaconId) => _database.customUpdate(
    r'''
UPDATE public.beacon_closure
SET closes_at = now() - interval '1 second'
WHERE beacon_id = $1 AND status = 0
''',
    variables: [Variable<String>(beaconId)],
  );

  @override
  Future<String> seedQaRequestWithHelpers({
    required String authorId,
    required List<String> helperIds,
    required String title,
  }) => _database.withTransaction(() async {
    final beaconId =
        (await _database
                .customSelect(
                  r'''
INSERT INTO public.beacon (user_id, title, description, status, published_at)
VALUES ($1, $2, '', 0, now())
RETURNING id
''',
                  variables: [
                    Variable<String>(authorId),
                    Variable<String>(title),
                  ],
                )
                .getSingle())
            .read<String>('id');
    for (final helperId in helperIds) {
      await _database.customInsert(
        r'''
INSERT INTO public.beacon_help_offer (beacon_id, user_id)
VALUES ($1, $2)
''',
        variables: [Variable<String>(beaconId), Variable<String>(helperId)],
      );
      await insertCommitmentEvent(
        _database,
        beaconId: beaconId,
        userId: helperId,
        actorUserId: helperId,
        kind: CommitmentEventKind.offered,
      );
      await insertCommitmentEvent(
        _database,
        beaconId: beaconId,
        userId: helperId,
        actorUserId: authorId,
        kind: CommitmentEventKind.acknowledged,
      );
    }
    return beaconId;
  }, actorUserId: authorId);

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
    // Two statements: a data-modifying CTE would check the primary key
    // against the rows it is deleting.
    return _database
        .customUpdate(
          r'DELETE FROM public.beacon_closure_author_split WHERE beacon_id = $1',
          variables: [Variable<String>(beaconId)],
        )
        .then(
          (_) => _database.customInsert(
            '''
INSERT INTO public.beacon_closure_author_split (beacon_id, helper_id, pct)
VALUES ${values.join(', ')}
''',
            variables: variables,
          ),
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
  Future<void> commitDraft({
    required String beaconId,
    required String voterId,
  }) async {
    final variables = [Variable<String>(beaconId), Variable<String>(voterId)];
    await _database.customUpdate(
      r'''
DELETE FROM public.beacon_closure_support
WHERE beacon_id = $1 AND voter_id = $2 AND version = 1
''',
      variables: variables,
    );
    await _database.customInsert(
      r'''
INSERT INTO public.beacon_closure_support (
  beacon_id, voter_id, target_id, version, pressed_at
)
SELECT beacon_id, voter_id, target_id, 1, pressed_at
FROM public.beacon_closure_support
WHERE beacon_id = $1 AND voter_id = $2 AND version = 0
''',
      variables: variables,
    );
    await _database.customInsert(
      r'''
INSERT INTO public.beacon_closure_commit (beacon_id, voter_id, committed_at)
VALUES ($1, $2, now())
ON CONFLICT (beacon_id, voter_id) DO UPDATE SET committed_at = now()
''',
      variables: variables,
    );
  }

  @override
  Future<void> skip({
    required String beaconId,
    required String voterId,
  }) => _database.customInsert(
    r'''
WITH dropped AS (
  DELETE FROM public.beacon_closure_support
  WHERE beacon_id = $1 AND voter_id = $2 AND version = 1
  RETURNING 1
)
INSERT INTO public.beacon_closure_commit (beacon_id, voter_id, committed_at)
VALUES ($1, $2, now())
ON CONFLICT (beacon_id, voter_id) DO UPDATE SET committed_at = now()
''',
    variables: [Variable<String>(beaconId), Variable<String>(voterId)],
  );

  @override
  Future<void> upsertMarkEvidence({
    required String beaconId,
    required int epoch,
    required String markerId,
    required String targetId,
    required DateTime occurredAt,
  }) => _database.customInsert(
    r'''
INSERT INTO public.trust_evidence (
  id, subject_user_id, object_user_id, kind, count, source_key,
  beacon_id, closure_epoch, occurred_at
) VALUES (
  gen_random_uuid()::text, $1, $2, 3, 1, $3, $4, $5, $6
)
ON CONFLICT (source_key) DO UPDATE SET retracted_at = NULL
''',
    variables: [
      Variable<String>(markerId),
      Variable<String>(targetId),
      Variable<String>(_markSourceKey(beaconId, epoch, markerId, targetId)),
      Variable<String>(beaconId),
      Variable<int>(epoch),
      Variable(PgDateTime(occurredAt), PgTypes.timestampWithTimezone),
    ],
  );

  @override
  Future<void> retractMarkEvidence({
    required String beaconId,
    required int epoch,
    required String markerId,
    required String targetId,
  }) => _database.customUpdate(
    r'''
UPDATE public.trust_evidence SET retracted_at = now()
WHERE source_key = $1 AND retracted_at IS NULL
''',
    variables: [
      Variable<String>(_markSourceKey(beaconId, epoch, markerId, targetId)),
    ],
  );

  static String _markSourceKey(
    String beaconId,
    int epoch,
    String markerId,
    String targetId,
  ) => 'closure:$beaconId:$epoch:mark:$markerId:$targetId';

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
  }) => body.isEmpty
      ? _database.customUpdate(
          r'DELETE FROM public.beacon_closure_story WHERE beacon_id = $1',
          variables: [Variable<String>(beaconId)],
        )
      : _database.customInsert(
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

  @override
  Future<ForwardEdgeEntity?> selectEdgeById(String edgeId) => _database
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
WHERE id = $1
''',
        variables: [Variable<String>(edgeId)],
        readsFrom: {_database.beaconForwardEdges},
      )
      .map(_mapEdge)
      .getSingleOrNull();

  @override
  Future<void> recordApprovalEdge({
    required String beaconId,
    required String helperId,
    required String senderId,
    required String arrivalEdgeId,
  }) async {
    await _ledger.lockPair(helperId, senderId);
    final key = 'approval:$beaconId:$helperId';
    if (await _ledger.exists(key)) {
      await _ledger.unretract(key);
      return;
    }
    final since = DateTime.timestamp().subtract(const Duration(days: 30));
    if (await _ledger.hasLiveUsefulForwardSince(helperId, senderId, since)) {
      return;
    }
    await _ledger.record([
      LedgerEvidence(
        subjectId: helperId,
        objectId: senderId,
        kind: TrustEvidenceKind.usefulForward,
        count: 1,
        sourceKey: key,
        beaconId: beaconId,
        relatedUserId: senderId,
        metadata: {'arrival_edge_id': arrivalEdgeId},
      ),
    ]);
  }

  @override
  Future<void> retractApprovalEdge({
    required String beaconId,
    required String helperId,
  }) => _ledger.retract('approval:$beaconId:$helperId');

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

  @override
  Future<List<ClosureDueEpoch>> dueEpochs({int limit = 50}) => _database
      .customSelect(
        r'''
SELECT beacon_id, epoch
FROM public.beacon_closure
WHERE status = 0 AND closes_at <= now()
ORDER BY closes_at
LIMIT $1
''',
        variables: [Variable<int>(limit)],
      )
      .map(
        (row) => ClosureDueEpoch(
          beaconId: row.read<String>('beacon_id'),
          epoch: row.read<int>('epoch'),
        ),
      )
      .get();

  @override
  Future<ClosureRoutingSource> routingSource(String beaconId) async {
    final edges = await _database
        .customSelect(
          r'''
SELECT id, sender_id, recipient_id, parent_edge_id, batch_id,
  created_at::text AS created_at, cancelled_at::text AS cancelled_at
FROM public.beacon_forward_edge
WHERE beacon_id = $1
ORDER BY created_at, id
''',
          variables: [Variable<String>(beaconId)],
        )
        .map(
          (row) => ForwardProvenanceEdge(
            id: row.read<String>('id'),
            senderId: row.read<String>('sender_id'),
            recipientId: row.read<String>('recipient_id'),
            parentEdgeId: row.readNullable<String>('parent_edge_id'),
            batchId: row.readNullable<String>('batch_id'),
            createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
            cancelledAt: _parseTs(row.readNullable<String>('cancelled_at')),
          ),
        )
        .get();
    final attributions = await _database
        .customSelect(
          r'''
SELECT a.child_forward_batch_id, a.parent_forward_edge_id, a.attribution_weight
FROM public.forward_decision_attribution a
WHERE a.child_forward_batch_id IN (
  SELECT batch_id FROM public.beacon_forward_edge
  WHERE beacon_id = $1 AND batch_id IS NOT NULL
)
ORDER BY a.child_forward_batch_id, a.parent_forward_edge_id
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    final byBatch = <String, List<ForwardAttributionInput>>{};
    for (final row in attributions) {
      final batchId = row.read<String>('child_forward_batch_id');
      byBatch
          .putIfAbsent(batchId, () => [])
          .add(
            ForwardAttributionInput(
              batchId: batchId,
              parentForwardEdgeId: row.read<String>('parent_forward_edge_id'),
              weight: row.read<double>('attribution_weight'),
            ),
          );
    }
    final offers = await _database
        .customSelect(
          r'''
SELECT user_id, created_at::text AS created_at
FROM public.beacon_help_offer
WHERE beacon_id = $1
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    final bud = await _budRouting(beaconId);
    return ClosureRoutingSource(
      edges: edges,
      attributionByBatch: byBatch,
      offerAt: {
        for (final row in offers)
          row.read<String>('user_id'): DateTime.parse(
            row.read<String>('created_at'),
          ).toUtc(),
      },
      budSegments: bud.segments,
      budDeliveryEdgeIds: bud.deliveryEdgeIds,
    );
  }

  /// Budding C7 (Arch §7): for each accepted invite with a source Post, the
  /// Post chain walked up `parent_edge_id` from its `arrival_post_edge_id`
  /// (one invite per invitee, the latest accepted), rooted at the Post author
  /// and cut at the child's `published_at`; plus the invites' delivery edges.
  Future<
    ({
      Map<String, List<ForwardRoutingSegment>> segments,
      Set<String> deliveryEdgeIds,
    })
  >
  _budRouting(String beaconId) async {
    final invites = await _database
        .customSelect(
          r'''
SELECT forward_edge_id
FROM public.beacon_author_invite
WHERE beacon_id = $1 AND status = 1 AND source_post_id IS NOT NULL
  AND forward_edge_id IS NOT NULL
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    final deliveryEdgeIds = {
      for (final row in invites) row.read<String>('forward_edge_id'),
    };
    final rows = await _database
        .customSelect(
          r'''
WITH RECURSIVE inv AS (
  SELECT DISTINCT ON (i.invitee_id)
    i.invitee_id, i.source_post_id, i.arrival_post_edge_id,
    post.user_id AS root_sender_id, child.published_at AS cutoff_at
  FROM public.beacon_author_invite i
  JOIN public.beacon child ON child.id = i.beacon_id
  JOIN public.beacon post ON post.id = i.source_post_id
  WHERE i.beacon_id = $1 AND i.status = 1
    AND i.arrival_post_edge_id IS NOT NULL
    AND child.published_at IS NOT NULL
  ORDER BY i.invitee_id, i.resolved_at DESC NULLS LAST, i.id DESC
), chain AS (
  SELECT inv.invitee_id, e.id, e.beacon_id, e.sender_id, e.recipient_id,
    e.parent_edge_id, e.batch_id, e.created_at, e.cancelled_at
  FROM inv
  JOIN public.beacon_forward_edge e
    ON e.id = inv.arrival_post_edge_id AND e.beacon_id = inv.source_post_id
  UNION
  SELECT chain.invitee_id, e.id, e.beacon_id, e.sender_id, e.recipient_id,
    e.parent_edge_id, e.batch_id, e.created_at, e.cancelled_at
  FROM chain
  JOIN public.beacon_forward_edge e
    ON e.id = chain.parent_edge_id AND e.beacon_id = chain.beacon_id
)
SELECT inv.invitee_id, inv.root_sender_id,
  inv.cutoff_at::text AS cutoff_at,
  chain.id, chain.sender_id, chain.recipient_id, chain.parent_edge_id,
  chain.batch_id, chain.created_at::text AS created_at,
  chain.cancelled_at::text AS cancelled_at
FROM chain
JOIN inv USING (invitee_id)
ORDER BY inv.invitee_id, chain.created_at, chain.id
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    if (rows.isEmpty) {
      return (
        segments: const <String, List<ForwardRoutingSegment>>{},
        deliveryEdgeIds: deliveryEdgeIds,
      );
    }
    final edgesByInvitee = <String, List<ForwardProvenanceEdge>>{};
    final rootByInvitee = <String, String>{};
    final cutoffByInvitee = <String, DateTime>{};
    final batchIds = <String>{};
    for (final row in rows) {
      final invitee = row.read<String>('invitee_id');
      rootByInvitee[invitee] = row.read<String>('root_sender_id');
      cutoffByInvitee[invitee] = DateTime.parse(
        row.read<String>('cutoff_at'),
      ).toUtc();
      final batchId = row.readNullable<String>('batch_id');
      if (batchId != null) batchIds.add(batchId);
      edgesByInvitee
          .putIfAbsent(invitee, () => [])
          .add(
            ForwardProvenanceEdge(
              id: row.read<String>('id'),
              senderId: row.read<String>('sender_id'),
              recipientId: row.read<String>('recipient_id'),
              parentEdgeId: row.readNullable<String>('parent_edge_id'),
              batchId: batchId,
              createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
              cancelledAt: _parseTs(row.readNullable<String>('cancelled_at')),
            ),
          );
    }
    final byBatch = await _attributionsForBatches(batchIds);
    return (
      segments: {
        for (final MapEntry(key: invitee, value: edges)
            in edgesByInvitee.entries)
          invitee: [
            ForwardRoutingSegment(
              edges: edges,
              attributionByBatch: {
                for (final e in edges)
                  if (e.batchId != null && byBatch[e.batchId] != null)
                    e.batchId!: byBatch[e.batchId]!,
              },
              rootSenderId: rootByInvitee[invitee]!,
              cutoffAt: cutoffByInvitee[invitee]!,
            ),
          ],
      },
      deliveryEdgeIds: deliveryEdgeIds,
    );
  }

  Future<Map<String, List<ForwardAttributionInput>>> _attributionsForBatches(
    Set<String> batchIds,
  ) async {
    if (batchIds.isEmpty) return const {};
    final rows = await _database
        .customSelect(
          r'''
SELECT child_forward_batch_id, parent_forward_edge_id, attribution_weight
FROM public.forward_decision_attribution
WHERE child_forward_batch_id = ANY($1::text[])
ORDER BY child_forward_batch_id, parent_forward_edge_id
''',
          variables: [
            Variable<List<String>>(batchIds.toList(), PgTypes.textArray),
          ],
        )
        .get();
    final byBatch = <String, List<ForwardAttributionInput>>{};
    for (final row in rows) {
      final batchId = row.read<String>('child_forward_batch_id');
      byBatch
          .putIfAbsent(batchId, () => [])
          .add(
            ForwardAttributionInput(
              batchId: batchId,
              parentForwardEdgeId: row.read<String>('parent_forward_edge_id'),
              weight: row.read<double>('attribution_weight'),
            ),
          );
    }
    return byBatch;
  }

  @override
  Future<void> postStoryMessage({
    required String beaconId,
    required String body,
  }) => _database.customInsert(
    r'''
INSERT INTO public.beacon_room_message (beacon_id, body, system_message_kind)
VALUES ($1, $2, $3)
''',
    variables: [
      Variable<String>(beaconId),
      Variable<String>(body),
      Variable<int>(BeaconRoomSystemMessageKind.closureStory),
    ],
  );

  @override
  Future<void> insertCloseAcknowledgements({
    required String beaconId,
    required String authorId,
    required Set<String> helperIds,
  }) async {
    if (helperIds.isEmpty) return;
    final offers = await _database
        .customSelect(
          r'''
SELECT user_id, help_type
FROM public.beacon_help_offer
WHERE beacon_id = $1 AND help_type IS NOT NULL AND help_type <> ''
ORDER BY user_id
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    final emissions = [
      for (final row in offers)
        if (helperIds.contains(row.read<String>('user_id')))
          OutcomeEmission(
            observerUserId: authorId,
            subjectUserId: row.read<String>('user_id'),
            tagSlug: row.read<String>('help_type'),
          ),
    ];
    await CapabilityEvidenceRepository(
      _database,
    ).emitOutcomeEvidenceBatch(beaconId: beaconId, emissions: emissions);
  }

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
