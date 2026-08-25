import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/evaluation/cross_beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/evaluation_mapper.dart';

const _ackTagCapExceededMessage = 'Ack tag cap exceeded';

@Injectable(
  as: EvaluationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class EvaluationRepository implements EvaluationRepositoryPort {
  EvaluationRepository(this._db);

  final TenturaDb _db;

  @override
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  }) => _db
      .into(_db.beaconReviewWindows)
      .insert(
        BeaconReviewWindowsCompanion.insert(
          beaconId: beaconId,
          openedAt: PgDateTime(openedAt),
          closesAt: PgDateTime(closesAt),
          status: const Value(0),
        ),
      );

  @override
  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) async {
    final row = await _db.managers.beaconReviewWindows
        .filter((e) => e.beaconId.id(beaconId))
        .getSingleOrNull();
    return row == null ? null : beaconReviewWindowToRecord(row);
  }

  @override
  Future<void> insertParticipant({
    required String beaconId,
    required String userId,
    required int role,
    required String contributionSummary,
    required String causalHint,
  }) => _db
      .into(_db.beaconEvaluationParticipants)
      .insert(
        BeaconEvaluationParticipantsCompanion.insert(
          beaconId: beaconId,
          userId: userId,
          role: role,
          contributionSummary: contributionSummary,
          causalHint: causalHint,
        ),
      );

  @override
  Future<void> insertVisibility({
    required String beaconId,
    required String evaluatorId,
    required String participantId,
  }) => _db
      .into(_db.beaconEvaluationVisibility)
      .insert(
        BeaconEvaluationVisibilityCompanion.insert(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          participantId: participantId,
        ),
      );

  @override
  Future<void> insertReviewStatus({
    required String beaconId,
    required String userId,
    int status = 0,
  }) => _db
      .into(_db.beaconReviewStatuses)
      .insert(
        BeaconReviewStatusesCompanion.insert(
          beaconId: beaconId,
          userId: userId,
          status: Value(status),
        ),
      );

  @override
  Future<int?> getReviewUserStatus(String beaconId, String userId) async {
    final row = await _db.managers.beaconReviewStatuses
        .filter(
          (e) => e.beaconId.id(beaconId) & e.userId.id(userId),
        )
        .getSingleOrNull();
    return row?.status;
  }

  @override
  Future<void> setReviewUserStatus({
    required String beaconId,
    required String userId,
    required int status,
  }) => _db.managers.beaconReviewStatuses
      .filter(
        (e) => e.beaconId.id(beaconId) & e.userId.id(userId),
      )
      .update(
        (o) => o(
          status: Value(status),
          updatedAt: Value(PgDateTime(DateTime.timestamp())),
        ),
      );

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async {
    final rows = await _db.managers.beaconEvaluationParticipants
        .filter((e) => e.beaconId.id(beaconId))
        .get();
    return rows.map(beaconEvaluationParticipantToRecord).toList();
  }

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async {
    final rows = await _db.managers.beaconEvaluationVisibility
        .filter(
          (e) => e.beaconId.id(beaconId) & e.evaluatorId.id(evaluatorId),
        )
        .get();
    return rows.map(beaconEvaluationVisibilityToRecord).toList();
  }

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) async {
    final rows = await _db.managers.beaconEvaluationVisibility
        .filter((e) => e.beaconId.id(beaconId))
        .get();
    return rows.map(beaconEvaluationVisibilityToRecord).toList();
  }

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) => _getEvaluation(
    beaconId: beaconId,
    evaluatorId: evaluatorId,
    evaluatedUserId: evaluatedUserId,
  );

  Future<BeaconEvaluationRecord?> _getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {
    final rows = await _db
        .customSelect(
          r'''
      SELECT e.beacon_id, e.evaluator_id, e.evaluated_user_id, e.value,
             e.reason_tags, e.note, e.status, e.created_at, e.updated_at,
             COALESCE(
               (SELECT string_agg(a.tag_slug, ',' ORDER BY a.tag_slug)
                  FROM public.beacon_evaluation_ack_tag a
                 WHERE a.beacon_id = e.beacon_id
                   AND a.evaluator_id = e.evaluator_id
                   AND a.subject_id = e.evaluated_user_id),
               ''
             ) AS ack_tags_csv
        FROM public.beacon_evaluation e
       WHERE e.beacon_id = $1
         AND e.evaluator_id = $2
         AND e.evaluated_user_id = $3
      ''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(evaluatorId),
            Variable<String>(evaluatedUserId),
          ],
        )
        .get();
    return rows.isEmpty ? null : _evaluationFromQueryRow(rows.single);
  }

  /// All evaluation rows for one evaluator on a beacon (single query).
  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async {
    final rows = await _db
        .customSelect(
          r'''
      SELECT e.beacon_id, e.evaluator_id, e.evaluated_user_id, e.value,
             e.reason_tags, e.note, e.status, e.created_at, e.updated_at,
             COALESCE(
               (SELECT string_agg(a.tag_slug, ',' ORDER BY a.tag_slug)
                  FROM public.beacon_evaluation_ack_tag a
                 WHERE a.beacon_id = e.beacon_id
                   AND a.evaluator_id = e.evaluator_id
                   AND a.subject_id = e.evaluated_user_id),
               ''
             ) AS ack_tags_csv
        FROM public.beacon_evaluation e
       WHERE e.beacon_id = $1 AND e.evaluator_id = $2
      ''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(evaluatorId),
          ],
        )
        .get();
    return rows.map(_evaluationFromQueryRow).toList();
  }

  @override
  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = BeaconEvaluationRowStatus.submitted,
    EvaluationWriteResolver? resolve,
  }) async {
    await _db.transaction(() async {
      await _lockBeacon(beaconId);
      final existing = resolve == null
          ? null
          : await _getEvaluation(
              beaconId: beaconId,
              evaluatorId: evaluatorId,
              evaluatedUserId: evaluatedUserId,
            );
      final command = await resolve?.call(existing);
      await _upsertEvaluation(
        beaconId: beaconId,
        evaluatorId: evaluatorId,
        evaluatedUserId: evaluatedUserId,
        value: command?.value ?? value,
        reasonTagsCsv: command?.reasonTags.join(',') ?? reasonTagsCsv,
        note: command?.note ?? note,
        status: status,
      );
    });
  }

  Future<void> _upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    required int status,
  }) => _db
      .into(_db.beaconEvaluations)
      .insert(
        BeaconEvaluationsCompanion.insert(
          beaconId: beaconId,
          evaluatorId: evaluatorId,
          evaluatedUserId: evaluatedUserId,
          value: value,
          reasonTags: Value(reasonTagsCsv),
          note: Value(note),
          status: Value(status),
        ),
        onConflict: DoUpdate(
          (_) => BeaconEvaluationsCompanion(
            value: Value(value),
            reasonTags: Value(reasonTagsCsv),
            note: Value(note),
            status: Value(status),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        ),
      );

  @override
  Future<void> submitEvaluationAtomic({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required List<String> reasonTags,
    required String note,
    required List<String> ackTags,
    EvaluationWriteResolver? resolve,
  }) async {
    await _db.transaction(() async {
      await _lockBeacon(beaconId);

      final window = await _db.managers.beaconReviewWindows
          .filter((e) => e.beaconId.id(beaconId))
          .getSingleOrNull();
      if (window == null || window.status != 0) {
        throw StateError('Review window not open');
      }
      final now = DateTime.timestamp();
      if (window.closesAt.dateTime.isBefore(now)) {
        throw StateError('Review window expired');
      }

      final command =
          await resolve?.call(
            await _getEvaluation(
              beaconId: beaconId,
              evaluatorId: evaluatorId,
              evaluatedUserId: evaluatedUserId,
            ),
          ) ??
          EvaluationWriteCommand(
            value: value,
            reasonTags: reasonTags,
            note: note,
            ackTags: ackTags,
          );
      final reasonTagsCsv = command.reasonTags.join(',');

      if (command.ackTags.length > kCapMaxTagsPerSubjectBeacon) {
        throw StateError(_ackTagCapExceededMessage);
      }

      await _db
          .into(_db.beaconEvaluations)
          .insert(
            BeaconEvaluationsCompanion.insert(
              beaconId: beaconId,
              evaluatorId: evaluatorId,
              evaluatedUserId: evaluatedUserId,
              value: command.value,
              reasonTags: Value(reasonTagsCsv),
              note: Value(command.note),
              status: const Value(BeaconEvaluationRowStatus.draft),
            ),
            onConflict: DoUpdate(
              (_) => BeaconEvaluationsCompanion(
                value: Value(command.value),
                reasonTags: Value(reasonTagsCsv),
                note: Value(command.note),
                status: const Value(BeaconEvaluationRowStatus.draft),
                updatedAt: Value(PgDateTime(now)),
              ),
            ),
          );

      await _db.customStatement(
        r'''
        DELETE FROM public.beacon_evaluation_ack_tag
        WHERE beacon_id = $1
          AND evaluator_id = $2
          AND subject_id = $3
        ''',
        [beaconId, evaluatorId, evaluatedUserId],
      );

      for (final tagSlug in command.ackTags) {
        await _db.into(_db.beaconEvaluationAckTags).insert(
          BeaconEvaluationAckTagsCompanion.insert(
            beaconId: beaconId,
            evaluatorId: evaluatorId,
            subjectId: evaluatedUserId,
            tagSlug: tagSlug,
          ),
        );
      }

      // Demote sent package when the evaluator edits again.
      await _db.customStatement(
        r'''
        UPDATE public.beacon_review_status
           SET status = 1, updated_at = now()
         WHERE beacon_id = $1 AND user_id = $2 AND status = 2
        ''',
        [beaconId, evaluatorId],
      );
    });
  }

  /// Submitted or finalized evaluations written about [evaluatedUserId].
  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async {
    final rows = await _db
        .customSelect(
          r'''
      SELECT e.beacon_id, e.evaluator_id, e.evaluated_user_id, e.value,
             e.reason_tags, e.note, e.status, e.created_at, e.updated_at,
             COALESCE(
               (SELECT string_agg(a.tag_slug, ',' ORDER BY a.tag_slug)
                  FROM public.beacon_evaluation_ack_tag a
                 WHERE a.beacon_id = e.beacon_id
                   AND a.evaluator_id = e.evaluator_id
                   AND a.subject_id = e.evaluated_user_id),
               ''
             ) AS ack_tags_csv
        FROM public.beacon_evaluation e
       WHERE e.beacon_id = $1 AND e.evaluated_user_id = $2
         AND e.status IN ($3, $4)
      ''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(evaluatedUserId),
            const Variable<int>(BeaconEvaluationRowStatus.submitted),
            const Variable<int>(BeaconEvaluationRowStatus.final_),
          ],
        )
        .get();
    return rows.map(_evaluationFromQueryRow).toList();
  }

  /// Finalized evaluations one person wrote about another across closed requests.
  @override
  Future<List<CrossBeaconEvaluationRecord>> listFinalizedEvaluationsBetween({
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {
    final rows = await _db
        .customSelect(
          r'''
SELECT
  e.beacon_id,
  e.evaluator_id,
  e.evaluated_user_id,
  e.value,
  e.reason_tags,
  e.note,
  e.status,
  e.created_at,
  e.updated_at,
  b.title AS beacon_title,
  b.status_changed_at AS beacon_closed_at,
  COALESCE(
    (SELECT string_agg(a.tag_slug, ',' ORDER BY a.tag_slug)
       FROM public.beacon_evaluation_ack_tag a
      WHERE a.beacon_id = e.beacon_id
        AND a.evaluator_id = e.evaluator_id
        AND a.subject_id = e.evaluated_user_id),
    ''
  ) AS ack_tags_csv
FROM beacon_evaluation e
INNER JOIN beacon b ON b.id = e.beacon_id
WHERE e.evaluator_id = $1
  AND e.evaluated_user_id = $2
  AND e.status = $3
  AND b.status IN ($4, $5)
ORDER BY e.updated_at DESC
''',
          variables: [
            Variable<String>(evaluatorId),
            Variable<String>(evaluatedUserId),
            const Variable<int>(BeaconEvaluationRowStatus.final_),
            const Variable<int>(4),
            const Variable<int>(6),
          ],
        )
        .get();

    return [
      for (final row in rows)
        CrossBeaconEvaluationRecord(
          evaluatorId: row.read<String>('evaluator_id'),
          evaluatedUserId: row.read<String>('evaluated_user_id'),
          value: row.read<int>('value'),
          reasonTags: row.read<String>('reason_tags'),
          ackTags: _ackTagsFromCsv(row.read<String>('ack_tags_csv')),
          note: row.read<String>('note'),
          occurredAt: _readEvaluationTimestamp(row, 'updated_at'),
          beaconId: row.read<String>('beacon_id'),
          beaconTitle: row.read<String>('beacon_title'),
          beaconClosedAt: _readEvaluationTimestampNullable(
            row,
            'beacon_closed_at',
          ),
        ),
    ];
  }

  /// All draft rows for a beacon (any evaluator).
  @override
  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  ) async {
    final rows = await _db.managers.beaconEvaluations
        .filter(
          (e) =>
              e.beaconId.id(beaconId) &
              e.status.equals(BeaconEvaluationRowStatus.draft),
        )
        .get();
    return rows.map(beaconEvaluationToRecord).toList();
  }

  @override
  Future<void> deleteEvaluationRow({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) => _db.transaction(() async {
    await _db.customStatement(
      r'''
      DELETE FROM public.beacon_evaluation_ack_tag
      WHERE beacon_id = $1
        AND evaluator_id = $2
        AND subject_id = $3
      ''',
      [beaconId, evaluatorId, evaluatedUserId],
    );
    await _db.managers.beaconEvaluations
        .filter(
          (e) =>
              e.beaconId.id(beaconId) &
              e.evaluatorId.id(evaluatorId) &
              e.evaluatedUserId.id(evaluatedUserId),
        )
        .delete();
  });

  @override
  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId) => _db
      .managers
      .beaconEvaluations
      .filter(
        (e) =>
            e.beaconId.id(beaconId) &
            e.status.equals(BeaconEvaluationRowStatus.submitted),
      )
      .update(
        (o) => o(
          status: const Value(BeaconEvaluationRowStatus.final_),
          updatedAt: Value(PgDateTime(DateTime.timestamp())),
        ),
      );

  @override
  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) => _db
      .managers
      .beaconEvaluations
      .filter(
        (e) =>
            e.beaconId.id(beaconId) &
            e.status.equals(BeaconEvaluationRowStatus.draft),
      )
      .delete();

  @override
  Future<Map<String, int>> listReviewStatusesForBeacon(String beaconId) async {
    final rows = await _db.managers.beaconReviewStatuses
        .filter((e) => e.beaconId.id(beaconId))
        .get();
    return {for (final r in rows) r.userId: r.status};
  }

  @override
  Future<void> downgradeSubmittedReviewsToDraft(String beaconId) async {
    await _db.managers.beaconEvaluations
        .filter(
          (e) =>
              e.beaconId.id(beaconId) &
              e.status.equals(BeaconEvaluationRowStatus.submitted),
        )
        .update(
          (o) => o(
            status: const Value(BeaconEvaluationRowStatus.draft),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
  }

  @override
  Future<void> deleteReviewScaffoldingForBeacon(String beaconId) async {
    final window = await _db.managers.beaconReviewWindows
        .filter((e) => e.beaconId.id(beaconId))
        .getSingleOrNull();
    if (window != null && window.status == 1) {
      throw StateError('Review window already closed for $beaconId');
    }
    await _db.managers.beaconEvaluationVisibility
        .filter((e) => e.beaconId.id(beaconId))
        .delete();
    await _db.managers.beaconEvaluationParticipants
        .filter((e) => e.beaconId.id(beaconId))
        .delete();
    await _db.managers.beaconReviewStatuses
        .filter((e) => e.beaconId.id(beaconId))
        .delete();
    await _db.managers.beaconReviewWindows
        .filter((e) => e.beaconId.id(beaconId))
        .delete();
  }

  static const Duration _reviewExtensionDuration = Duration(days: 7);

  static const int _maxReviewExtensions = 2;

  @override
  Future<DateTime> extendReviewWindow(String beaconId) async {
    final row = await _db.managers.beaconReviewWindows
        .filter((e) => e.beaconId.id(beaconId))
        .getSingleOrNull();
    if (row == null || row.status != 0) {
      throw StateError('Review window not open');
    }
    if (row.extensionsUsed >= _maxReviewExtensions) {
      throw StateError('Review extension limit reached');
    }
    final newClosesAt = row.closesAt.dateTime.add(_reviewExtensionDuration);
    final now = DateTime.timestamp();
    await _db.managers.beaconReviewWindows
        .filter((e) => e.beaconId.id(beaconId))
        .update(
          (o) => o(
            closesAt: Value(PgDateTime(newClosesAt)),
            extensionsUsed: Value(row.extensionsUsed + 1),
            updatedAt: Value(PgDateTime(now)),
          ),
        );
    return newClosesAt;
  }

  @override
  Future<ReviewCloseSnapshot?> closeReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    final now = DateTime.timestamp();
    return _db.transaction(() async {
      await _db.customStatement(
        r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
        [beaconId],
      );

      final window = await _db.managers.beaconReviewWindows
          .filter((e) => e.beaconId.id(beaconId))
          .getSingleOrNull();
      if (window == null || window.status != 0) {
        return null;
      }

      final beaconRow = await _db.managers.beacons
          .filter((b) => b.id.equals(beaconId))
          .getSingleOrNull();
      if (beaconRow == null) {
        return null;
      }

      if (beaconRow.status != BeaconStatus.reviewOpen.smallintValue) {
        await downgradeSubmittedReviewsToDraft(beaconId);
        await deleteReviewScaffoldingForBeacon(beaconId);
        return null;
      }

      await _db.managers.beaconReviewWindows
          .filter((e) => e.beaconId.id(beaconId))
          .update(
            (o) => o(
              status: const Value(1),
              updatedAt: Value(PgDateTime(now)),
            ),
          );

      await _db.managers.beacons
          .filter((b) => b.id.equals(beaconId))
          .update((o) => o(status: const Value(6)));

      await _insertBeaconLifecycleEvent(
        db: _db,
        beaconId: beaconId,
        fromState: beaconRow.status,
        toState: 6,
        reason: reason,
        actorId: actorUserId,
        mutatingUserId: actorUserId ?? beaconRow.userId,
      );

      await _db.managers.beaconReviewStatuses
          .filter(
            (s) =>
                s.beaconId.id(beaconId) &
                (s.status.equals(0) | s.status.equals(1)),
          )
          .update(
            (o) => o(
              status: const Value(4),
              updatedAt: Value(PgDateTime(now)),
            ),
          );

      final transitioned = await _db
          .customSelect(
            r'''
WITH sent AS (
  SELECT user_id
    FROM public.beacon_review_status
   WHERE beacon_id = $2 AND status = 2
),
deleted AS (
  DELETE FROM public.beacon_evaluation e
   WHERE e.beacon_id = $2
     AND e.evaluator_id NOT IN (SELECT user_id FROM sent)
  RETURNING e.evaluator_id, e.evaluated_user_id
),
ack_cleanup AS (
  DELETE FROM public.beacon_evaluation_ack_tag a
   WHERE a.beacon_id = $2
     AND a.evaluator_id NOT IN (SELECT user_id FROM sent)
  RETURNING 1
),
finalized AS (
  UPDATE public.beacon_evaluation e
     SET status = $1, updated_at = now()
   WHERE e.beacon_id = $2
     AND e.status IN ($3, $4)
     AND e.evaluator_id IN (SELECT user_id FROM sent)
  RETURNING e.evaluator_id, e.evaluated_user_id, e.value
)
SELECT f.evaluator_id,
       f.evaluated_user_id,
       f.value,
       p.role,
       coalesce(
         array_agg(a.tag_slug ORDER BY a.tag_slug)
           FILTER (WHERE a.tag_slug IS NOT NULL),
         '{}'
       ) AS ack_tags
FROM finalized f
JOIN public.beacon_evaluation_participant p
  ON p.beacon_id = $2 AND p.user_id = f.evaluator_id
LEFT JOIN public.beacon_evaluation_ack_tag a
  ON a.beacon_id = $2
 AND a.evaluator_id = f.evaluator_id
 AND a.subject_id = f.evaluated_user_id
GROUP BY f.evaluator_id, f.evaluated_user_id, f.value, p.role
''',
            variables: [
              const Variable<int>(BeaconEvaluationRowStatus.final_),
              Variable<String>(beaconId),
              const Variable<int>(BeaconEvaluationRowStatus.draft),
              const Variable<int>(BeaconEvaluationRowStatus.submitted),
            ],
          )
          .get();

      final finalized = [
        for (final row in transitioned)
          FinalizedEvaluation(
            evaluatorId: row.read<String>('evaluator_id'),
            evaluatedUserId: row.read<String>('evaluated_user_id'),
            value: row.read<int>('value'),
            role: row.read<int>('role'),
            ackTags: row.read<List<dynamic>>('ack_tags').cast<String>(),
          ),
      ];

      return ReviewCloseSnapshot(
        beaconId: beaconId,
        beaconAuthorId: beaconRow.userId,
        beaconTitle: beaconRow.title,
        windowOpenedAt: window.openedAt.dateTime,
        finalizedEvaluations: finalized,
      );
    });
  }

  Future<void> _lockBeacon(String beaconId) => _db.customStatement(
    r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
    [beaconId],
  );
}

Future<void> _insertBeaconLifecycleEvent({
  required TenturaDb db,
  required String beaconId,
  required int fromState,
  required int toState,
  required String reason,
  required String? actorId,
  required String mutatingUserId,
}) {
  Future<void> insert() async {
    await db.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: beaconId,
        visibility: BeaconActivityEventVisibilityBits.public,
        type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
        actorId: actorId == null ? const Value(null) : Value(actorId),
        diff: Value(<String, Object?>{
          'fromState': fromState,
          'toState': toState,
          'reason': reason,
        }),
        createdAt: const Value.absent(),
      ),
    );
  }

  // Expiry runs in an actor-null UoW; preserve that system actor instead of
  // attempting to enter an author-scoped nested mutation.
  return actorId == null
      ? insert()
      : db.withMutatingUser(mutatingUserId, insert);
}

BeaconEvaluationRecord _evaluationFromQueryRow(QueryRow row) =>
    BeaconEvaluationRecord(
      beaconId: row.read<String>('beacon_id'),
      evaluatorId: row.read<String>('evaluator_id'),
      evaluatedUserId: row.read<String>('evaluated_user_id'),
      value: row.read<int>('value'),
      reasonTags: row.read<String>('reason_tags'),
      ackTags: _ackTagsFromCsv(row.read<String>('ack_tags_csv')),
      note: row.read<String>('note'),
      status: row.read<int>('status'),
      createdAt: _readEvaluationTimestamp(row, 'created_at'),
      updatedAt: _readEvaluationTimestamp(row, 'updated_at'),
    );

List<String> _ackTagsFromCsv(String csv) => csv.isEmpty
    ? const []
    : csv.split(',').where((tag) => tag.isNotEmpty).toList(growable: false);

DateTime _readEvaluationTimestamp(QueryRow row, String column) {
  final value = _readEvaluationTimestampNullable(row, column);
  if (value == null) {
    throw StateError('Expected non-null timestamp for $column');
  }
  return value;
}

DateTime? _readEvaluationTimestampNullable(QueryRow row, String column) {
  final value = row.data[column];
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is PgDateTime) {
    return value.dateTime;
  }
  return DateTime.parse(value.toString());
}
