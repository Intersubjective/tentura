import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon.dart';

import '../enum.dart';

part 'inbox_item.freezed.dart';

@freezed
abstract class InboxItem with _$InboxItem {
  const factory InboxItem({
    required String beaconId,
    required DateTime latestForwardAt,
    @Default(0) int forwardCount,
    @Default('') String latestNotePreview,
    @Default(InboxItemStatus.needsMe) InboxItemStatus status,
    @Default('') String rejectionMessage,
    @Default('') String context,
    Beacon? beacon,
  }) = _InboxItem;

  const InboxItem._();
}
