import 'package:freezed_annotation/freezed_annotation.dart';

part 'quoted_fact_entity.freezed.dart';

/// A room message's snapshot of a pinned fact at the moment it was quoted,
/// together with the fact's current head [currentSeq] (plan §14.2).
@freezed
abstract class QuotedFactEntity with _$QuotedFactEntity {
  const factory QuotedFactEntity({
    required String factCardId,
    required int seq,
    required String factText,
    required String pinnedByTitle,
    required int visibility,
    required int status,
    required int currentSeq,
    required String attachmentsJson,
    String? pinnedById,
  }) = _QuotedFactEntity;
}
