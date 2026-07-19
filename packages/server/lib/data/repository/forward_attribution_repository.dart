import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_attribution_entity.dart';
import 'package:tentura_server/domain/entity/forward_attribution_method.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(
  as: ForwardAttributionRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class ForwardAttributionRepository implements ForwardAttributionRepositoryPort {
  ForwardAttributionRepository(this._db);

  final TenturaDb _db;

  static const _weightTolerance = 1e-9;

  @override
  Future<void> record({
    required String batchId,
    required Map<String, double> weightByParentEdgeId,
    required ForwardAttributionMethod method,
  }) async {
    if (weightByParentEdgeId.isEmpty) {
      throw ArgumentError('weightByParentEdgeId must not be empty');
    }

    final totalWeight = weightByParentEdgeId.values.fold<double>(
      0,
      (sum, weight) => sum + weight,
    );
    if ((totalWeight - 1).abs() > _weightTolerance) {
      throw ArgumentError('attribution weights must sum to 1');
    }

    for (final entry in weightByParentEdgeId.entries) {
      await _db.into(_db.forwardDecisionAttributions).insert(
        ForwardDecisionAttributionsCompanion.insert(
          childForwardBatchId: batchId,
          parentForwardEdgeId: entry.key,
          attributionWeight: entry.value,
          attributionMethod: method.key,
        ),
        onConflict: DoNothing(),
      );
    }
  }

  @override
  Future<List<ForwardAttributionEntity>> fetchByBatchIds(
    List<String> batchIds,
  ) async {
    if (batchIds.isEmpty) return const [];

    final rows = await _db.managers.forwardDecisionAttributions
        .filter((a) => a.childForwardBatchId.isIn(batchIds))
        .get();

    return rows
        .map(
          (row) => ForwardAttributionEntity(
            childForwardBatchId: row.childForwardBatchId,
            parentForwardEdgeId: row.parentForwardEdgeId,
            weight: row.attributionWeight,
            method: ForwardAttributionMethod.values.firstWhere(
              (m) => m.key == row.attributionMethod,
            ),
            createdAt: row.createdAt.dateTime,
          ),
        )
        .toList();
  }
}
