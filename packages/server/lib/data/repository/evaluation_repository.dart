import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';

import '../database/tentura_db.dart';
import '../mapper/evaluation_mapper.dart';

@Injectable(
  as: EvaluationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class EvaluationRepository implements EvaluationRepositoryPort {
  EvaluationRepository(
    this._db,
    this._trustEdgeRepository,
  );

  final TenturaDb _db;
  final UserTrustEdgeRepositoryPort _trustEdgeRepository;

  @override
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  }) => _db.into(_db.beaconReviewWindows).insert(
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
  }) => _db.into(_db.beaconEvaluationParticipants).insert(
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
  }) => _db.into(_db.beaconEvaluationVisibility).insert(
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
  }) => _db.into(_db.beaconReviewStatuses).insert(
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
  }) async {
    final row = await _db.managers.beaconEvaluations
        .filter(
          (e) =>
              e.beaconId.id(beaconId) &
              e.evaluatorId.id(evaluatorId) &
              e.evaluatedUserId.id(evaluatedUserId),
        )
        .getSingleOrNull();
    return row == null ? null : beaconEvaluationToRecord(row);
  }

  /// All evaluation rows for one evaluator on a beacon (single query).
  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async {
    final rows = await _db.managers.beaconEvaluations
        .filter(
          (e) =>
              e.beaconId.id(beaconId) & e.evaluatorId.id(evaluatorId),
        )
        .get();
    return rows.map(beaconEvaluationToRecord).toList();
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
  }) => _db.into(_db.beaconEvaluations).insert(
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

  /// Non–NO_BASIS evaluations for aggregate summary.
  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async {
    final rows = await _db.managers.beaconEvaluations
        .filter(
          (e) =>
              e.beaconId.id(beaconId) & e.evaluatedUserId.id(evaluatedUserId),
        )
        .get();
    return rows
        .where(
          (r) =>
              r.value != BeaconEvaluationValue.noBasis &&
              BeaconEvaluationRowStatus.countsTowardSummary(r.status),
        )
        .map(beaconEvaluationToRecord)
        .toList();
  }

  @override
  Future<int> countDistinctEvaluatorsForEvaluated({
    required String beaconId,
    required String evaluatedUserId,
  }) async {
    final rows = await listEvaluationsForEvaluatedUser(
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
    );
    return rows.map((r) => r.evaluatorId).toSet().length;
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
  }) => _db.managers.beaconEvaluations
      .filter(
        (e) =>
            e.beaconId.id(beaconId) &
            e.evaluatorId.id(evaluatorId) &
            e.evaluatedUserId.id(evaluatedUserId),
      )
      .delete();

  @override
  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId) =>
      _db.managers.beaconEvaluations
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
  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) =>
      _db.managers.beaconEvaluations
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
  Future<void> deleteReviewScaffoldingForBeacon(String beaconId) async {
    await _db.managers.beaconEvaluations
        .filter((e) => e.beaconId.id(beaconId))
        .delete();
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
  Future<void> closeBeaconReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    final now = DateTime.timestamp();
    await _db.transaction(() async {
      final window = await _db.managers.beaconReviewWindows
          .filter((e) => e.beaconId.id(beaconId))
          .getSingleOrNull();
      if (window == null || window.status != 0) {
        return;
      }

      final beaconRow = await _db.managers.beacons
          .filter((b) => b.id.equals(beaconId))
          .getSingleOrNull();
      if (beaconRow == null) {
        return;
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
          .update((o) => o(state: const Value(6)));

      await _insertBeaconLifecycleEvent(
        db: _db,
        beaconId: beaconId,
        fromState: beaconRow.state,
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

      final batchesBySource = <String, List<TrustEvidence>>{};

      final transitioned = await _db.customSelect(
        r'''
UPDATE beacon_evaluation
SET status = $1, updated_at = now()
WHERE beacon_id = $2 AND status = $3
RETURNING evaluator_id, evaluated_user_id, value
''',
        variables: [
          const Variable<int>(BeaconEvaluationRowStatus.final_),
          Variable<String>(beaconId),
          const Variable<int>(BeaconEvaluationRowStatus.submitted),
        ],
      ).get();

      for (final row in transitioned) {
        final evaluatorId = row.read<String>('evaluator_id');
        final evaluatedUserId = row.read<String>('evaluated_user_id');
        final value = row.read<int>('value');
        final bin = reviewValueToBin(value);
        if (bin == null) continue;
        batchesBySource.putIfAbsent(evaluatorId, () => []).add(
          TrustEvidence(
            targetUserId: evaluatedUserId,
            bin: bin,
            count: kTrustReviewEvidenceCount,
          ),
        );
      }

      await deleteDraftEvaluationsForBeacon(beaconId);

      final sortedSources = batchesBySource.keys.toList()..sort();
      for (final source in sortedSources) {
        await _trustEdgeRepository.applyEvidenceInTransaction(
          TrustEvidenceBatch(
            sourceUserId: source,
            at: now,
            items: batchesBySource[source]!,
          ),
        );
      }
    });
  }

  @override
  Future<void> closeExpiredWindows() => _db.transaction(() async {
        final expiredBeaconIds = await _db.customSelect(
          '''
SELECT beacon_id
FROM beacon_review_window
WHERE status = 0 AND closes_at < now()
FOR UPDATE
''',
        ).map((r) => r.read<String>('beacon_id')).get();

        for (final beaconId in expiredBeaconIds) {
          await closeBeaconReviewWindow(
            beaconId,
            reason: BeaconLifecycleChangeReason.reviewExpired,
          );
        }
      });
}

Future<void> _insertBeaconLifecycleEvent({
  required TenturaDb db,
  required String beaconId,
  required int fromState,
  required int toState,
  required String reason,
  required String? actorId,
  required String mutatingUserId,
}) =>
    db.withMutatingUser(mutatingUserId, () async {
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
    });
