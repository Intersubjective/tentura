import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../entity/leased_job_retry.dart';
import '../entity/phantom_pending_forward.dart';
import '../exception.dart';
import '../port/owner_graph_transaction_port.dart';
import '../port/phantom_merge_repository_port.dart';
import '../port/phantom_pending_forward_repository_port.dart';
import '../port/phantom_repository_port.dart';
import '../port/user_block_repository_port.dart';
import 'phantom_forward_delivery_case.dart';

sealed class PhantomMergeResult {}

final class PhantomMerged implements PhantomMergeResult {
  const PhantomMerged(this.mergeId, [this._claimedForwards = const []]);

  final String mergeId;
  final List<PhantomForwardClaim> _claimedForwards;
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
    this._pendingForwards,
    this._forwardDelivery,
    this._logger,
  );

  final OwnerGraphTransactionPort _ownerGraph;
  final PhantomRepositoryPort _phantoms;
  final PhantomMergeRepositoryPort _merges;
  final UserBlockRepositoryPort _blocks;
  final PhantomPendingForwardRepositoryPort _pendingForwards;
  final PhantomForwardDeliveryCase _forwardDelivery;
  final Logger _logger;

  Future<bool> link({
    required String ownerId,
    required String phantomId,
    required String userId,
  }) async {
    final result = await merge(
      ownerId: ownerId,
      phantomId: phantomId,
      userId: userId,
    );
    return switch (result) {
      PhantomMerged() => true,
      PhantomMergeGuardFailure() => throw IdNotFoundException(id: phantomId),
    };
  }

  Future<bool> unmerge({
    required String ownerId,
    required String phantomId,
    String? mergeId,
  }) => _ownerGraph.run({ownerId}, ownerId, (scope) async {
    final currentMergeId = await _merges.lockCurrentMerge(
      scope,
      ownerId: ownerId,
      phantomId: phantomId,
    );
    if (currentMergeId == null ||
        (mergeId != null && mergeId != currentMergeId)) {
      throw IdNotFoundException(id: phantomId);
    }
    await _phantoms.requireActiveCapacity(scope, ownerId);
    await _merges.unmerge(scope, ownerId: ownerId, mergeId: currentMergeId);
    return true;
  });

  /// An owner selecting a person from their Field omits [origin]. An explicit
  /// origin runs the merge engine for an already authorized target.
  Future<PhantomMergeResult> merge({
    required String ownerId,
    required String phantomId,
    required String userId,
    int? origin,
  }) async {
    final authorizedOrigin = origin == null
        ? null
        : PhantomMergeOrigin.fromCode(origin);
    final target = (ownerId: ownerId, phantomId: phantomId, userId: userId);
    final result = await _ownerGraph.run({ownerId}, ownerId, (scope) async {
      final result = await _mergeInScope(scope, target, authorizedOrigin);
      return result == PhantomMergeGuardFailure.deleted
          ? PhantomMergeGuardFailure.inactive
          : result;
    });
    await _deliverMergedForwards(result);
    return result;
  }

  Future<PhantomMergeResult> _mergeInScope(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
    PhantomMergeOrigin? authorizedOrigin,
  ) async {
    final (:ownerId, :phantomId, :userId) = target;
    final origin = authorizedOrigin ?? PhantomMergeOrigin.manualLink;
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
    if (authorizedOrigin == null &&
        !await _merges.isInFieldPopulation(scope, target)) {
      throw IdNotFoundException(id: userId);
    }

    final mergeId = await _merges.merge(
      scope,
      target,
      origin: origin,
      displayName: entry.displayName,
    );
    final claimedForwards = origin == PhantomMergeOrigin.manualLink
        ? const <PhantomForwardClaim>[]
        : await _pendingForwards.claimForMerge(
            scope,
            phantomId: phantomId,
            senderId: ownerId,
            mergeId: mergeId,
            recipientId: userId,
          );
    return PhantomMerged(mergeId, claimedForwards);
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
      final PhantomMergeResult? result;
      try {
        result = await _runJob(job);
      } on Object catch (error, stackTrace) {
        await _recordError(job, error, stackTrace, clock);
        continue;
      }
      await _deliverMergedForwards(result);
    }
  }

  Future<void> _deliverMergedForwards(PhantomMergeResult? result) async {
    if (result is PhantomMerged) {
      await _forwardDelivery.deliver(result._claimedForwards);
    }
  }

  Future<PhantomMergeResult?> _runJob(PhantomMergeJobLease job) {
    final owner = job.target.ownerId;
    return _ownerGraph.run({owner}, owner, (scope) async {
      if (!await _merges.lockClaim(scope, job)) return null;
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
      return result;
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
