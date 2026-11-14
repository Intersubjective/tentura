/// A user's saved fact pointers (`user_saved_fact`, plan §4.3).
abstract class SavedFactRepositoryPort {
  /// Saves [factCardId] for [userId] unless they already keep [cap] other
  /// saved facts. Answers false only when the cap refused a new row; saving
  /// a fact already saved answers true and changes nothing.
  Future<bool> save({
    required String userId,
    required String factCardId,
    required int cap,
  });

  /// Deletes the row of [userId] for [factCardId], if there is one.
  Future<void> unsave({required String userId, required String factCardId});

  /// The saved facts of [userId], newest saved first. A row the user may read
  /// now carries `available: true`, `beaconId`, `beaconKind`, `factText` and
  /// `attachmentsJson`; every other row (unreadable, removed, dangling id)
  /// carries `factCardId` and `available: false` only.
  Future<List<Map<String, Object?>>> list({required String userId});
}
