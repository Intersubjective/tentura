import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_block_entity.freezed.dart';

@freezed
abstract class UserBlockEntity with _$UserBlockEntity {
  const factory UserBlockEntity({
    required String blockerId,
    required String blockedId,
    required String originId,
    required DateTime createdAt,
  }) = _UserBlockEntity;

  const UserBlockEntity._();

  bool get isDirect => blockedId == originId;
}

@freezed
abstract class UserBlockIntentEntity with _$UserBlockIntentEntity {
  const factory UserBlockIntentEntity({
    required String blockerId,
    required String blockedId,
    @Default(0) int cascadeMode,
    @Default(0) int cascadeStatus,
    @Default(0) int materializedCount,
    required DateTime createdAt,
  }) = _UserBlockIntentEntity;
}

@freezed
abstract class BlockPreviewEntity with _$BlockPreviewEntity {
  const factory BlockPreviewEntity({
    @Default(0) int cascadeCandidateCount,
    @Default(false) bool cascadeCapped,
    @Default(0) int openCommitmentCount,
    @Default(false) bool willWithdrawEdge,
  }) = _BlockPreviewEntity;
}
