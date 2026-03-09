import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/enums.dart';

part 'complaint_entity.freezed.dart';

@freezed
abstract class ComplaintEntity with _$ComplaintEntity {
  const factory ComplaintEntity({
    required String id,
    required String userId,
    required String email,
    required String details,
    required ComplaintType type,
    required DateTime createdAt,
  }) = _ComplaintEntity;

  const ComplaintEntity._();
}
