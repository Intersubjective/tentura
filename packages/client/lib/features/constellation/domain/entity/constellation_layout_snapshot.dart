import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

part 'constellation_layout_snapshot.freezed.dart';

/// Server `ConstellationLayoutSnapshotKind` code carried in
/// [ConstellationLayoutSnapshot.kind]: 0 is the viewer's single favourite,
/// 1 the rolling history.
enum ConstellationLayoutSnapshotKind {
  favourite(0),
  history(1);

  const ConstellationLayoutSnapshotKind(this.smallintValue);

  final int smallintValue;

  static ConstellationLayoutSnapshotKind? tryFromInt(int? value) {
    if (value == null) return null;
    return switch (value) {
      0 => favourite,
      1 => history,
      _ => null,
    };
  }
}

/// Saved coordinates have no live revision and can be previewed without writes.
@freezed
abstract class ConstellationLayoutSnapshot with _$ConstellationLayoutSnapshot {
  const factory ConstellationLayoutSnapshot({
    required String id,
    required int kind,
    required DateTime createdAt,
    required Map<ConstellationAnchorTarget, ConstellationAnchorPosition>
    anchors,
  }) = _ConstellationLayoutSnapshot;
}
