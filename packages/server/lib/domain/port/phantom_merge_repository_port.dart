import 'owner_graph_transaction_port.dart';

enum PhantomMergeOrigin {
  inviteNew(1),
  inviteExisting(2),
  manualLink(3);

  const PhantomMergeOrigin(this.code);

  final int code;

  static PhantomMergeOrigin fromCode(int code) => values.firstWhere(
    (origin) => origin.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'origin', 'Unknown merge origin'),
  );
}

typedef PhantomMergeTarget = ({
  String ownerId,
  String phantomId,
  String userId,
});

typedef PhantomMergeJobLease = ({
  String id,
  PhantomMergeTarget target,
  PhantomMergeOrigin origin,
  String leaseOwner,
  int attempts,
  bool exhausted,
});

abstract interface class PhantomMergeRepositoryPort {
  /// Locks the owner's entry and distinguishes an inactive entry from one
  /// that no longer exists.
  Future<({String displayName, bool active})?> lockEntry(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
  );

  Future<bool> isInFieldPopulation(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
  );

  /// Persists the guarded merge, its undo record and owner attention event.
  Future<String> merge(
    OwnerGraphScope scope,
    PhantomMergeTarget target, {
    required PhantomMergeOrigin origin,
    required String displayName,
  });

  Future<List<PhantomMergeJobLease>> claimJobs({
    required String leaseOwner,
    required DateTime now,
  });

  Future<bool> lockClaim(OwnerGraphScope scope, PhantomMergeJobLease job);

  /// A null reason completes the merge. A guard reason skips the job.
  Future<bool> finishJob(
    OwnerGraphScope scope,
    PhantomMergeJobLease job, {
    String? skipReason,
  });

  /// A null retry time records a terminal failure.
  Future<bool> recordJobError(
    OwnerGraphScope scope,
    PhantomMergeJobLease job, {
    required String error,
    required DateTime? retryAt,
  });

  Future<void> recordLinkCard(OwnerGraphScope scope, PhantomMergeJobLease job);
}
