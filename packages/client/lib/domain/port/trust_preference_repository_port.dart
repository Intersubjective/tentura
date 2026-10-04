/// The signed-in user's trust preferences, stored on the server.
abstract class TrustPreferenceRepositoryPort {
  /// Whether noisy-contact walls apply in the user's own frame: their choice,
  /// else the server default.
  Future<bool> fetchNoisyWallEnabled();

  /// Stores the user's choice; returns the effective value.
  Future<bool> setNoisyWallEnabled({required bool enabled});
}
