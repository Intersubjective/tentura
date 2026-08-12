import 'package:freezed_annotation/freezed_annotation.dart';

import 'projection_tier.dart';

part 'tag_projection.freezed.dart';

@freezed
abstract class TagProjection with _$TagProjection {
  const factory TagProjection({
    required String subjectUserId,
    required String tagSlug,
    required ProjectionTier tier,
  }) = _TagProjection;

  const TagProjection._();
}
