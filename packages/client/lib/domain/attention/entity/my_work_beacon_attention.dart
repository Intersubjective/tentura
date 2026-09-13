import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';

part 'my_work_beacon_attention.freezed.dart';

@freezed
abstract class MyWorkBeaconAttention with _$MyWorkBeaconAttention {
  const factory MyWorkBeaconAttention({
    required String beaconId,
    required int unseenCount,
    AttentionReceipt? latestUnseen,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> liveObligations,
  }) = _MyWorkBeaconAttention;
}
