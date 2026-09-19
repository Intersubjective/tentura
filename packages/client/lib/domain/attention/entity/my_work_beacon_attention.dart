import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';

part 'my_work_beacon_attention.freezed.dart';

@freezed
abstract class MyWorkBeaconAttention with _$MyWorkBeaconAttention {
  const factory MyWorkBeaconAttention({
    required String beaconId,
    required int unseenCount,
    // U10c — the `Needs you` sort keys, so the desk orders by the contract's
    // key instead of `Beacon.updatedAt`.
    DateTime? needsYouAt,
    DateTime? firstEntryAt,
    AttentionReceipt? latestUnseen,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> liveObligations,
  }) = _MyWorkBeaconAttention;
}
