/// The wall owner's trust preferences (m0216). Only the noisy-contact wall
/// switch for now.
abstract interface class TrustPreferencePort {
  /// Whether noisy-contact walls apply in [userId]'s frame: the user's own
  /// choice, else the server default (`TRUST_NOISY_WALL_ENABLED`).
  Future<bool> noisyWallEnabled(String userId);

  /// Stores [userId]'s explicit choice and re-projects their pairs in the
  /// same transaction. Returns the effective value.
  Future<bool> setNoisyWallEnabled({
    required String userId,
    required bool enabled,
  });
}
