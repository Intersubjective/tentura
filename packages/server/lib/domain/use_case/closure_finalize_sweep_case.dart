import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

import '_use_case_base.dart';

/// A14: finalizes evaluating epochs whose window has elapsed (every 60 s).
///
/// Each row runs in its own transaction that takes the per-request lock
/// first; finalize re-reads the live epoch, so an epoch extended, cancelled or
/// replaced between the select and the lock is left alone.
@Singleton(order: 3)
final class ClosureFinalizeSweepCase extends UseCaseBase {
  ClosureFinalizeSweepCase({
    required MutatingUnitOfWorkPort unitOfWork,
    required ClosureRepositoryPort closureRepository,
    required ClosureFinalizerPort finalizer,
    required super.env,
    required super.logger,
  }) : _uow = unitOfWork,
       _repo = closureRepository,
       _finalizer = finalizer;

  final MutatingUnitOfWorkPort _uow;
  final ClosureRepositoryPort _repo;
  final ClosureFinalizerPort _finalizer;

  /// Test hook: runs between the candidate select and the per-row locks.
  Future<void> Function()? afterSelect;

  Future<void> run() async {
    final due = await _repo.dueEpochs();
    await afterSelect?.call();
    for (final row in due) {
      try {
        await _uow.run<void>(
          action: () async {
            await _repo.lockRequest(row.beaconId);
            await _finalizer.finalize(
              beaconId: row.beaconId,
              epoch: row.epoch,
              reason: FinalizeReason.expired,
            );
          },
        );
      } catch (e, s) {
        logger.severe(
          'closure finalize failed for ${row.beaconId}#${row.epoch}',
          e,
          s,
        );
      }
    }
  }
}
