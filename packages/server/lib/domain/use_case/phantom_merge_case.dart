import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../entity/leased_job_retry.dart';
import '../exception.dart';
import '../port/owner_graph_transaction_port.dart';
import '../port/phantom_merge_repository_port.dart';
import '../port/phantom_repository_port.dart';
import '../port/user_block_repository_port.dart';

sealed class PhantomMergeResult {}

final class PhantomMerged implements PhantomMergeResult {
  const PhantomMerged(this.mergeId);

  final String mergeId;
}

enum PhantomMergeGuardFailure implements PhantomMergeResult {
  deleted,
  inactive,
  self,
  blocked;

  String get reason => name;
}

@lazySingleton
final class PhantomMergeCase {
  const PhantomMergeCase(
    this._ownerGraph,
    this._phantoms,
    this._merges,
    this._blocks,
    this._logger,
  );

  final OwnerGraphTransactionPort _ownerGraph;
  final PhantomRepositoryPort _phantoms;
  final PhantomMergeRepositoryPort _merges;
  final UserBlockRepositoryPort _blocks;
  final Logger _logger;

  Future<PhantomMergeResult> merge({
    required String ownerId,
    required String phantomId,
    required String userId,
    required int origin,
  }) {
    final mergeOrigin = PhantomMergeOrigin.fromCode(origin);
    final target = (ownerId: ownerId, phantomId: phantomId, userId: userId);
    return _ownerGraph.run({ownerId}, ownerId, (scope) async {
      final result = await _mergeInScope(scope, target, mergeOrigin);
      return result == PhantomMergeGuardFailure.deleted
          ? PhantomMergeGuardFailure.inactive
          : result;
    });
  }

  Future<PhantomMergeResult> _mergeInScope(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
    PhantomMergeOrigin origin,
  ) async {
    final (:ownerId, :phantomId, :userId) = target;
    if (origin == PhantomMergeOrigin.manualLink) {
      final joiningName = await _phantoms.lockInvitesAndFindJoiningName(
        scope,
        ownerId: ownerId,
        id: phantomId,
      );
      if (joiningName != null) throw PhantomJoiningException(joiningName);
    }

    final entry = await _merges.lockEntry(scope, target);
    if (entry == null) return PhantomMergeGuardFailure.deleted;
    if (!entry.active) return PhantomMergeGuardFailure.inactive;
    if (userId == ownerId) return PhantomMergeGuardFailure.self;
    if (await _blocks.isBlockedPair(a: ownerId, b: userId)) {
      return PhantomMergeGuardFailure.blocked;
    }

    final mergeId = await _merges.merge(
      scope,
      target,
      origin: origin,
      displayName: entry.displayName,
    );
    return PhantomMerged(mergeId);
  }

  Future<void> runDue({
    required String leaseOwner,
    required DateTime Function() clock,
  }) async {
    final jobs = await _merges.claimJobs(leaseOwner: leaseOwner, now: clock());
    for (final job in jobs) {
      if (job.exhausted) {
        // The final claimant died before recording an outcome.
        await _recordError(job, 'Final attempt lease expired', null, clock);
        continue;
      }
      try {
        await _runJob(job);
      } on Object catch (error, stackTrace) {
        await _recordError(job, error, stackTrace, clock);
      }
    }
  }

  Future<void> _runJob(PhantomMergeJobLease job) {
    final owner = job.target.ownerId;
    return _ownerGraph.run({owner}, owner, (scope) async {
      if (!await _merges.lockClaim(scope, job)) return;
      final result = await _mergeInScope(scope, job.target, job.origin);
      final finished = await _merges.finishJob(
        scope,
        job,
        skipReason: switch (result) {
          PhantomMerged() => null,
          PhantomMergeGuardFailure() => result.reason,
        },
      );
      if (!finished) {
        throw StateError('Could not complete phantom merge job ${job.id}');
      }
      if (result == PhantomMergeGuardFailure.self ||
          result == PhantomMergeGuardFailure.blocked) {
        await _merges.recordLinkCard(scope, job);
      }
    });
  }

  Future<void> _recordError(
    PhantomMergeJobLease job,
    Object error,
    StackTrace? stackTrace,
    DateTime Function() clock,
  ) async {
    final owner = job.target.ownerId;
    final terminal = job.attempts >= kLeasedJobMaxAttempts;
    final retryAt = terminal
        ? null
        : clock().add(leasedJobRetryBackoff(job.attempts));
    final recorded = await _ownerGraph.run({owner}, owner, (scope) async {
      final updated = await _merges.recordJobError(
        scope,
        job,
        error: error.toString(),
        retryAt: retryAt,
      );
      if (updated && terminal) await _merges.recordLinkCard(scope, job);
      return updated;
    });
    if (recorded && terminal) {
      _logger.severe(
        'Phantom merge job ${job.id} exhausted its attempts',
        error,
        stackTrace,
      );
    }
  }
}
