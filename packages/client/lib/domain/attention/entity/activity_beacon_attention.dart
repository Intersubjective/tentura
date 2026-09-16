import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';

part 'activity_beacon_attention.freezed.dart';

@freezed
abstract class ActivityBeaconAttention with _$ActivityBeaconAttention {
  const factory ActivityBeaconAttention({
    required String beaconId,
    required int eventTotal,
    required int unseenCount,
    required DateTime latestAt,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> events,
    String? nextCursor,
  }) = _ActivityBeaconAttention;
}
