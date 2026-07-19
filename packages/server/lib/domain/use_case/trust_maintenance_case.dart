import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show TypedValue, Type;

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

import '../../data/database/tentura_db.dart';

@Singleton(as: TrustMaintenancePort, order: 2)
base class TrustMaintenanceCase extends UseCaseBase
    implements TrustMaintenancePort {
  TrustMaintenanceCase(
    this._db,
    this._meritrank, {
    required super.env,
    required super.logger,
  });

  final TenturaDb _db;
  final MeritrankRepositoryPort _meritrank;

  DateTime? _lastSuccessAt;
  DateTime? _lastFailedAt;
  var _firstRun = true;

  @override
  Future<void> runDue({DateTime? now}) async {
    final clock = now ?? DateTime.timestamp();
    if (!_isDue(clock)) return;

    try {
      await _drainTombstones();
      await _runBoundedSweep(epsilonOverride: null, timeBudget: env.trustSweepTimeBudget);
      _lastSuccessAt = clock;
      _firstRun = false;
    } catch (e, st) {
      _lastFailedAt = clock;
      _firstRun = false;
      logger.warning('TrustMaintenanceCase.runDue failed: $e\n$st');
      rethrow;
    }
  }

  @override
  Future<void> forceRefreshAll() async {
    await _drainTombstones();
    await _runBoundedSweep(
      epsilonOverride: -1,
      timeBudget: null,
    );
  }

  bool _isDue(DateTime now) {
    if (_firstRun) return true;
    if (_lastFailedAt != null &&
        (_lastSuccessAt == null || _lastFailedAt!.isAfter(_lastSuccessAt!))) {
      return now.difference(_lastFailedAt!) >= env.trustSweepRetry;
    }
    final anchor = _lastSuccessAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return now.difference(anchor) >= env.trustSweepInterval;
  }

  Future<void> _drainTombstones() async {
    final rows = await _db
        .customSelect(
          r'''
SELECT subject, object
FROM meritrank_edge_tombstone
ORDER BY subject, object
''',
        )
        .get();
    for (final row in rows) {
      final subject = row.read<String>('subject');
      final object = row.read<String>('object');
      await _db.transaction(() async {
        final live = await _db
            .customSelect(
              r'''
SELECT prev_sent_weight
FROM user_trust_edge
WHERE subject = $1 AND object = $2
''',
              variables: [
                Variable<String>(subject),
                Variable<String>(object),
              ],
            )
            .getSingleOrNull();
        if (live != null && live.read<double>('prev_sent_weight') != 0) {
          await _db.customStatement(
            'DELETE FROM meritrank_edge_tombstone WHERE subject = \$1 AND object = \$2',
            [subject, object],
          );
          return;
        }
        try {
          await _meritrank.deleteEdge(nodeA: subject, nodeB: object);
          await _db.customStatement(
            'DELETE FROM meritrank_edge_tombstone WHERE subject = \$1 AND object = \$2',
            [subject, object],
          );
        } catch (e) {
          await _db.customStatement(
            r'''
UPDATE meritrank_edge_tombstone
SET last_error = left($3, 500)
WHERE subject = $1 AND object = $2
''',
            [subject, object, e.toString()],
          );
        }
      });
    }
  }

  Future<void> _runBoundedSweep({
    required double? epsilonOverride,
    required Duration? timeBudget,
  }) async {
    final started = DateTime.timestamp();
    var afterSubject = '';
    var afterObject = '';
    while (true) {
      if (timeBudget != null &&
          DateTime.timestamp().difference(started) >= timeBudget) {
        break;
      }
      final row = await _db.transaction(() async {
        final variables = [
          Variable<String>(afterSubject),
          Variable<String>(afterObject),
          Variable(TypedValue(Type.integer, env.trustSweepBatchSize)),
        ];
        if (epsilonOverride == null) {
          return _db
              .customSelect(
                r'SELECT * FROM trust_rebuild_effective_batch($1, $2, $3)',
                variables: variables,
              )
              .getSingleOrNull();
        }
        return _db
            .customSelect(
              r'SELECT * FROM trust_rebuild_effective_batch($1, $2, $3, $4)',
              variables: [
                ...variables,
                Variable<double>(epsilonOverride),
              ],
            )
            .getSingleOrNull();
      });
      if (row == null) break;
      final processed = row.read<int>('processed');
      if (processed == 0) break;
      final lastSubject = row.read<String?>('last_subject');
      final lastObject = row.read<String?>('last_object');
      if (lastSubject == null || lastObject == null) break;
      afterSubject = lastSubject;
      afterObject = lastObject;
    }
  }
}
