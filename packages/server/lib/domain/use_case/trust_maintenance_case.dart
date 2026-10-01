import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_sweep_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';

@Singleton(as: TrustMaintenancePort, order: 2)
base class TrustMaintenanceCase extends UseCaseBase
    implements TrustMaintenancePort {
  TrustMaintenanceCase(
    this._sweep,
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

  final TrustMaintenanceSweepPort _sweep;

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
      final processed = await _sweep.projectNextBatch(
        afterSubject: afterSubject,
        afterObject: afterObject,
        batchSize: env.trustSweepBatchSize,
      );
      if (processed.isEmpty) break;
      final last = processed.last;
      afterSubject = last.$1;
      afterObject = last.$2;
    }
    await _sweep.bumpMrPublishEpoch();
  }
}
