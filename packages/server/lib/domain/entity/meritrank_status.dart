/// MeritRank walks-cache and snapshot state, for the `/health` signal.
///
/// [snapshotBytes] is null when the MeritRank build in use does not report it.
class MeritrankStatus {
  const MeritrankStatus({
    required this.walksCacheSize,
    required this.activeReaders,
    required this.snapshotBudgetBytes,
    this.snapshotBytes,
  });

  /// Resident-frame bound of the walks cache; 0 means unlimited.
  final int walksCacheSize;

  /// Viewers whose reads need a resident frame.
  final int activeReaders;

  final int? snapshotBytes;

  final int snapshotBudgetBytes;

  /// More active readers than the bounded cache holds.
  bool get walksCacheOverCapacity =>
      walksCacheSize > 0 && activeReaders > walksCacheSize;

  /// Snapshots fill the process-wide budget, so new ones evict old ones.
  bool get snapshotPressure =>
      snapshotBytes != null &&
      snapshotBudgetBytes > 0 &&
      snapshotBytes! >= snapshotBudgetBytes;
}
