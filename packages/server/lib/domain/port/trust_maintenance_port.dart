/// Port for trust maintenance operations (sweep, forced republication).
abstract interface class TrustMaintenancePort {
  Future<void> forceRefreshAll();

  /// Periodic bounded sweep + tombstone drain.
  Future<void> runDue({DateTime? now});
}
