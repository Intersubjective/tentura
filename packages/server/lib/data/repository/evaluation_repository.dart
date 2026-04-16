import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/evaluation_mapper.dart';

@Injectable(
  as: EvaluationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class EvaluationRepository implements EvaluationRepositoryPort {
  const EvaluationRepository(this._db);

  final TenturaDb _db;

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

  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) async {
    final row = await _db.managers.beaconReviewWindows
        .filter((e) => e.beaconId.id(beaconId))
        .getSingleOrNull();
    return row == null ? null : beaconReviewWindowToRecord(row);
  }

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

  Future<int?> getReviewUserStatus(String beaconId, String userId) async {
    final row = await _db.managers.beaconReviewStatuses
        .filter(
          (e) => e.beaconId.id(beaconId) & e.userId.id(userId),
        )
        .getSingleOrNull();
    return row?.status;
  }

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

  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async {
    final rows = await _db.managers.beaconEvaluationParticipants
        .filter((e) => e.beaconId.id(beaconId))
        .get();
    return rows.map(beaconEvaluationParticipantToRecord).toList();
  }

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

  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) async {
    final rows = await _db.managers.beaconEvaluationVisibility
        .filter((e) => e.beaconId.id(beaconId))
        .get();
    return rows.map(beaconEvaluationVisibilityToRecord).toList();
  }

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

  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) =>
      _db.managers.beaconEvaluations
          .filter(
            (e) =>
                e.beaconId.id(beaconId) &
                e.status.equals(BeaconEvaluationRowStatus.draft),
          )
          .delete();

  Future<void> closeExpiredWindows() => _db.transaction(() async {
        final now = DateTime.timestamp();
        final open = await _db.managers.beaconReviewWindows
            .filter((w) => w.status.equals(0))
            .get();
        final expired = open.where(
          (w) => w.closesAt.dateTime.isBefore(now),
        );

        for (final w in expired) {
          await _db.managers.beaconReviewWindows
              .filter((e) => e.beaconId.id(w.beaconId))
              .update(
                (o) => o(
                  status: const Value(1),
                  updatedAt: Value(PgDateTime(DateTime.timestamp())),
                ),
              );

          await _db.managers.beacons
              .filter((b) => b.id.equals(w.beaconId))
              .update((o) => o(state: const Value(6)));

          await _db.managers.beaconReviewStatuses
              .filter(
                (s) =>
                    s.beaconId.id(w.beaconId) &
                    (s.status.equals(0) | s.status.equals(1)),
              )
              .update(
                (o) => o(
                  status: const Value(4),
                  updatedAt: Value(PgDateTime(DateTime.timestamp())),
                ),
              );

          await finalizeSubmittedEvaluationsForBeacon(w.beaconId);
          await deleteDraftEvaluationsForBeacon(w.beaconId);
        }
      });
}
