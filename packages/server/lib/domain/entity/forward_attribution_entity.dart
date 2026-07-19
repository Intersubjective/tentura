import 'package:freezed_annotation/freezed_annotation.dart';

import 'forward_attribution_method.dart';

part 'forward_attribution_entity.freezed.dart';

@freezed
abstract class ForwardAttributionEntity with _$ForwardAttributionEntity {
  const factory ForwardAttributionEntity({
    required String childForwardBatchId,
    required String parentForwardEdgeId,
    required double weight,
    required ForwardAttributionMethod method,
    required DateTime createdAt,
  }) = _ForwardAttributionEntity;
}
