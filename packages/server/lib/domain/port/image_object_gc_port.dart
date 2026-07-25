/// A leased outbox row claimed for object-storage cleanup.
final class ImageObjectGcLease {
  const ImageObjectGcLease({
    required this.imageId,
    required this.authorId,
    required this.attempts,
  });

  final String imageId;

  final String authorId;

  /// Attempt count including this claim; callers use it to compute
  /// exponential backoff for [ImageObjectGcPort.fail].
  final int attempts;
}

/// Durable outbox for remote object deletion after an image-row commit.
///
/// Remote object deletion never occurs inside a database transaction: a row
/// delete and [enqueue] commit together, and [removeObject] runs later, after
/// that commit, by the leased worker.
abstract interface class ImageObjectGcPort {
  /// Enqueues [imageId] for later object removal. Idempotent: a retry never
  /// resets attempts or steals a live lease.
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  });

  /// Removes the physical object at the path derived from [imageId] and
  /// [authorId]. A missing object is a successful, idempotent no-op.
  Future<void> removeObject({
    required String imageId,
    required String authorId,
  });

  /// Claims up to [limit] due rows under `FOR UPDATE SKIP LOCKED`, owned by
  /// [leaseOwner] until roughly two minutes after [now].
  Future<List<ImageObjectGcLease>> claim({
    required String leaseOwner,
    required DateTime now,
    int limit = 32,
  });

  /// Marks [imageId] done and removes its row, only under [leaseOwner].
  /// Returns whether a row matched (false when the lease already expired).
  Future<bool> complete({
    required String imageId,
    required String leaseOwner,
  });

  /// Records [error] and schedules a retry at [retryAt], clearing the lease,
  /// only under [leaseOwner]. Returns whether a row matched.
  Future<bool> fail({
    required String imageId,
    required String leaseOwner,
    required DateTime retryAt,
    required String error,
  });
}
