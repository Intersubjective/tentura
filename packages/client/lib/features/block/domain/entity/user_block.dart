import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/identifiable.dart';
import 'package:tentura/domain/entity/profile.dart';

part 'user_block.freezed.dart';

@freezed
abstract class BlockIntent with _$BlockIntent implements Identifiable {
  const factory BlockIntent({
    required Profile blocked,
    @Default(0) int cascadeMode,
    @Default(0) int inheritedCount,
    @Default(false) bool cascadeCapped,
    @Default(true) bool cascadePending,
  }) = _BlockIntent;

  const BlockIntent._();

  @override
  String get id => blocked.id;
}

@freezed
abstract class BlockPreview with _$BlockPreview {
  const factory BlockPreview({
    @Default(0) int cascadeCandidateCount,
    @Default(false) bool cascadeCapped,
    @Default(0) int openCommitmentCount,
    @Default(false) bool willWithdrawEdge,
  }) = _BlockPreview;
}
