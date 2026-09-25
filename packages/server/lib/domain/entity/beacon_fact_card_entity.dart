import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/utils/id.dart';

part 'beacon_fact_card_entity.freezed.dart';

@freezed
abstract class BeaconFactCardEntity with _$BeaconFactCardEntity {
  static String get newId => generateId('F');

  const factory BeaconFactCardEntity({
    required String id,
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    required DateTime createdAt,
    String? sourceMessageId,
    @Default(0) int status,
    DateTime? updatedAt,
    @Default(1) int revisionSeq,
    String? lastEditedBy,
    String? lastEditedByTitle,
    DateTime? lastEditedAt,
    @Default(0) int otherEditorCount,
    @Default(false) bool historyTruncated,

    /// Denormalized display metadata (not a DB column).
    @Default('') String pinnedByTitle,
  }) = _BeaconFactCardEntity;
}
