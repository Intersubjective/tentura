import 'package:freezed_annotation/freezed_annotation.dart';

part 'attention_receipt.freezed.dart';

@freezed
abstract class AttentionReceipt with _$AttentionReceipt {
  const factory AttentionReceipt({
    required String id,
    required String category,
    required String kind,
    required String priority,
    required String title,
    required String body,
    required String actionUrl,
    required DateTime createdAt,
    required int collapsedCount,
    required String presentationPayloadJson,
    DateTime? seenAt,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
    String? sourceEventKey,
    String? destinationKind,
    String? targetEntityId,
    String? presentationKey,
    String? inAppPreferenceClass,
    @Default(false) bool requiresAction,
    String? attentionThreadKey,
    String? settlementKind,
    DateTime? settledAt,
  }) = _AttentionReceipt;

  const AttentionReceipt._();

  bool get isSeen => seenAt != null;
  bool get isLiveObligation => requiresAction && settlementKind == null;
}
