import '../entity/constellation_tag_magnet.dart';

abstract interface class ConstellationTagMagnetRepositoryPort {
  /// The viewer's magnets.
  Future<List<ConstellationTagMagnet>> list();

  /// Places or moves the magnet of own tag [tagId].
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  });

  /// Removes the magnet of own tag [tagId]; the tag itself stays.
  Future<void> remove({required String tagId, required String clientOpId});
}
