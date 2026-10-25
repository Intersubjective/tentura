import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';

/// A viewer's saved Field layouts. Every write is one transaction and
/// idempotent by `(viewerId, clientOpId)`.
abstract interface class ConstellationLayoutSnapshotRepositoryPort {
  /// Favourite first, then history newest first.
  Future<List<ConstellationLayoutSnapshot>> list(String viewerId);

  /// Captures the viewer's current anchors. History keeps the newest 20; a
  /// favourite replaces the previous one.
  Future<ConstellationLayoutSnapshot> save({
    required String viewerId,
    required ConstellationLayoutSnapshotKind kind,
    required ConstellationLayoutSnapshotReason reason,
    required String clientOpId,
  });

  /// Writes a `restore` history snapshot of the current layout, then makes the
  /// anchors equal the snapshot for targets that still exist. Throws
  /// snapshotNotFound for an id that is not the viewer's.
  Future<ConstellationLayoutSnapshot> restore({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  });

  /// Favourite-only write: leaves live anchors untouched.
  Future<void> restoreFavourite({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  });
}
