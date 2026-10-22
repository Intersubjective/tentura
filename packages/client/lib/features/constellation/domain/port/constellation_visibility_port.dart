import '../constellation_visibility.dart';

/// What the field shows, kept per viewer on this device (#645).
abstract interface class ConstellationVisibilityPort {
  /// The stored choice of [viewerId], or null when they never changed it.
  Future<ConstellationVisibility?> read({required String viewerId});

  Future<void> write({
    required String viewerId,
    required ConstellationVisibility visibility,
  });
}
