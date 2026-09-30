import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show TypedValue, Type;

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

import '../../data/database/tentura_db.dart';

@Singleton(as: TrustMaintenancePort, order: 2)
base class TrustMaintenanceCase extends UseCaseBase
    implements TrustMaintenancePort {
  TrustMaintenanceCase(
    this._db,
    // Kept for DI/call-site arity; m0202 (A1) removed the tombstone drain,
    // which was the last MeritRank call here. Publication now goes through
    // `trust_publish_queue`, drained by the A4/A5 publisher.
    // ignore: avoid_unused_constructor_parameters
    MeritrankRepositoryPort meritrank, {
    // Same arity keep as above: the witness-window epoch bump left with the
    // tombstone drain.
    // ignore: avoid_unused_constructor_parameters
    WitnessWindowPort? witnessWindow,
    required super.env,
    required super.logger,
  });

  final TenturaDb _db;

  DateTime? _lastSuccessAt;
  DateTime? _lastFailedAt;
  var _firstRun = true;

  @override
  Future<void> runDue({DateTime? now}) async {
    final clock = now ?? DateTime.timestamp();
    if (!_isDue(clock)) return;

    try {
      await _runProjectionSweep(env.trustSweepTimeBudget);
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
    await _runProjectionSweep(null);
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

  /// Re-projects every known pair via `trust_project_pair` (m0202): folds
  /// live evidence with time decay into `user_trust_edge` and enqueues
  /// publication when the target materially changed. Keyset-paginates the
  /// pair universe so a bounded sweep can stop between batches.
  Future<void> _runProjectionSweep(Duration? timeBudget) async {
    final started = DateTime.timestamp();
    var afterSubject = '';
    var afterObject = '';
    while (true) {
      if (timeBudget != null &&
          DateTime.timestamp().difference(started) >= timeBudget) {
        break;
      }
      final processed = await _db.transaction(() async {
        final pairs = await _db
            .customSelect(
              r'''
SELECT subject_user_id AS s, object_user_id AS o
FROM (
  SELECT subject AS subject_user_id, object AS object_user_id
  FROM public.user_trust_edge
) AS pairs
WHERE (subject_user_id, object_user_id) > ($1, $2)
ORDER BY subject_user_id, object_user_id
LIMIT $3
''',
              variables: [
                Variable<String>(afterSubject),
                Variable<String>(afterObject),
                Variable(TypedValue(Type.integer, env.trustSweepBatchSize)),
              ],
            )
            .get();
        for (final pair in pairs) {
          await _db.customSelect(
            r'SELECT public.trust_project_pair($1, $2)',
            variables: [
              Variable<String>(pair.read<String>('s')),
              Variable<String>(pair.read<String>('o')),
            ],
          ).getSingle();
        }
        return pairs;
      });
      if (processed.isEmpty) break;
      afterSubject = processed.last.read<String>('s');
      afterObject = processed.last.read<String>('o');
    }
    await _db.customStatement('SELECT public.mr_bump_publish_epoch()');
  }
}
