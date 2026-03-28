import 'package:freezed_annotation/freezed_annotation.dart';

import 'beacon_entity.dart';

part 'inbox_item_entity.freezed.dart';

@freezed
abstract class InboxItemEntity with _$InboxItemEntity {
  const factory InboxItemEntity({
    required String userId,
    required String beaconId,
    required DateTime latestForwardAt,
    @Default(0) int forwardCount,
    @Default('') String latestNotePreview,
    @Default(false) bool isHidden,
    @Default(false) bool isWatching,
    String? context,
    BeaconEntity? beacon,
  }) = _InboxItemEntity;

  const InboxItemEntity._();
}
