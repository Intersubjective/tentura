import 'package:tentura_server/domain/entity/constellation_tag_magnet.dart';

/// A viewer's tag magnets (m0267). Every write is one transaction and
/// idempotent by `(viewerId, clientOpId)`: a repeat with the same payload
/// returns the stored result, a different one throws opIdReused. A tag that is
/// not the viewer's own throws tagNotFound.
abstract interface class ConstellationTagMagnetRepositoryPort {
  Future<List<ConstellationTagMagnet>> list(String viewerId);

  /// Creates or moves the magnet of [tagId]; a move raises its revision.
  Future<ConstellationTagMagnet> upsert({
    required String viewerId,
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  });

  /// Removing a tag's missing magnet is a no-op.
  Future<void> remove({
    required String viewerId,
    required String tagId,
    required String clientOpId,
  });
}
