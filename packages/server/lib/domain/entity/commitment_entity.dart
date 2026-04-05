import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_entity.dart';

part 'commitment_entity.freezed.dart';

@freezed
abstract class CommitmentEntity with _$CommitmentEntity {
  const factory CommitmentEntity({
    required String beaconId,
    required String userId,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('') String message,
    @Default(0) int status,
    String? helpType,
    String? uncommitReason,
    UserEntity? user,
  }) = _CommitmentEntity;

  const CommitmentEntity._();

  bool get isActive => status == 0;
  bool get isWithdrawn => status == 1;
}
