import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';

import '_use_case_base.dart';
import 'post_close_operation.dart';

/// Closes every open Post whose `expires_at` has passed (every 30 s).
///
/// Each row runs in its own system transaction that takes the Post lock first
/// and re-reads the Post, so one closed (budded, by its author) or shortened
/// between the select and the lock is handled by what it is then. A failing row
/// is logged and does not stop the batch.
@Singleton(order: 3)
final class PostExpirySweepCase extends UseCaseBase {
  PostExpirySweepCase({
    required MutatingUnitOfWorkPort unitOfWork,
    required BeaconRepositoryPort beaconRepository,
    required PostLockPort postLock,
    required PostCloseOperation postClose,
    required super.env,
    required super.logger,
  }) : _uow = unitOfWork,
       _beacons = beaconRepository,
       _lock = postLock,
       _close = postClose;

  final MutatingUnitOfWorkPort _uow;
  final BeaconRepositoryPort _beacons;
  final PostLockPort _lock;
  final PostCloseOperation _close;

  /// Test hook: runs between the candidate select and the per-row locks.
  Future<void> Function()? afterSelect;

  Future<void> runDue() async {
    final ids = await _beacons.postExpiryDueIds();
    await afterSelect?.call();
    for (final id in ids) {
      try {
        await _uow.run<void>(
          action: () async {
            await _lock.lockForPostMutation(id);
            if (!await _beacons.isPostExpiryDue(id)) return;
            await _close.expire(postId: id);
          },
        );
      } catch (e, s) {
        logger.severe('post expiry failed for $id', e, s);
      }
    }
  }
}
