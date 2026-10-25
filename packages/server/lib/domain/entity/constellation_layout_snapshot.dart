import 'package:meta/meta.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// Stored as the column value: 0 is the viewer's single favourite, 1 the
/// rolling history.
enum ConstellationLayoutSnapshotKind { favourite, history }

/// Why a snapshot was written; stored as the enum index.
enum ConstellationLayoutSnapshotReason { manual, restore, reset, rebuild }

/// A saved Field layout of one viewer, including its stored anchors.
@immutable
final class ConstellationLayoutSnapshot {
  const ConstellationLayoutSnapshot({
    required this.id,
    required this.kind,
    required this.reason,
    required this.anchorCount,
    required this.createdAt,
    this.anchors = const [],
  });

  final List<ConstellationLayoutSnapshotAnchor> anchors;
  final String id;
  final ConstellationLayoutSnapshotKind kind;
  final ConstellationLayoutSnapshotReason reason;
  final int anchorCount;
  final DateTime createdAt;
}

/// A snapshot coordinate, independent of the live anchor revision.
@immutable
final class ConstellationLayoutSnapshotAnchor {
  const ConstellationLayoutSnapshotAnchor({
    required this.targetKind,
    required this.targetId,
    required this.x,
    required this.y,
    required this.coordinateSpaceVersion,
  });

  final ConstellationAnchorTargetKind targetKind;
  final String targetId;
  final double x;
  final double y;
  final int coordinateSpaceVersion;
}
