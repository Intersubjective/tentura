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
    /// 0 = needs_me, 1 = watching, 2 = rejected
    @Default(0) int status,
    @Default('') String rejectionMessage,
    String? context,
    BeaconEntity? beacon,
  }) = _InboxItemEntity;

  const InboxItemEntity._();
}
