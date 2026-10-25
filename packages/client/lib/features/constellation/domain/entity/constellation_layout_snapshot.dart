import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

part 'constellation_layout_snapshot.freezed.dart';

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
