import 'package:freezed_annotation/freezed_annotation.dart';

import 'projection_tier.dart';
import 'tag_projection.dart';

part 'forward_band_row.freezed.dart';

@freezed
abstract class ForwardBandRow with _$ForwardBandRow {
  const factory ForwardBandRow({
    required String userId,
    ProjectionTier? rowTier,
    @Default([]) List<TagProjection> labels,
    @Default(0) int rank,
    @Default(false) bool isExploration,
  }) = _ForwardBandRow;

  const ForwardBandRow._();
}
