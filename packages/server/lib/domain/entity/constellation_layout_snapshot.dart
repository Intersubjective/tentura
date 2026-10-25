import 'package:meta/meta.dart';

/// Stored as the column value: 0 is the viewer's single favourite, 1 the
/// rolling history.
enum ConstellationLayoutSnapshotKind { favourite, history }

/// Why a snapshot was written; stored as the enum index.
enum ConstellationLayoutSnapshotReason { manual, restore, reset }

/// A saved Field layout of one viewer, without its anchors.
@immutable
final class ConstellationLayoutSnapshot {
  const ConstellationLayoutSnapshot({
    required this.id,
    required this.kind,
    required this.reason,
    required this.anchorCount,
    required this.createdAt,
  });

  final String id;
  final ConstellationLayoutSnapshotKind kind;
  final ConstellationLayoutSnapshotReason reason;
  final int anchorCount;
  final DateTime createdAt;
}
