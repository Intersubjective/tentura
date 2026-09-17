import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_feed.dart';

part 'attention_receipt.freezed.dart';

enum AttentionForwardOutcome {
  helping,
  watching,
  notInterested,
  closedBeforeResponse,
  deletedBeforeResponse;

  static AttentionForwardOutcome? fromWire(String? wire) {
    if (wire == null) return null;
    return switch (wire) {
      'helping' => AttentionForwardOutcome.helping,
      'watching' => AttentionForwardOutcome.watching,
      'notInterested' => AttentionForwardOutcome.notInterested,
      'closedBeforeResponse' => AttentionForwardOutcome.closedBeforeResponse,
      'deletedBeforeResponse' => AttentionForwardOutcome.deletedBeforeResponse,
      _ => null,
    };
  }

  String get wireName => switch (this) {
    AttentionForwardOutcome.helping => 'helping',
    AttentionForwardOutcome.watching => 'watching',
    AttentionForwardOutcome.notInterested => 'notInterested',
    AttentionForwardOutcome.closedBeforeResponse => 'closedBeforeResponse',
    AttentionForwardOutcome.deletedBeforeResponse => 'deletedBeforeResponse',
  };
}

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
    required AttentionSurface surface,
    @Default(AttentionItemKind.receipt) AttentionItemKind itemKind,
    AttentionForwardOutcome? forwardOutcome,
    int? forwardCount,
    int? digestCount,
    @Default(false) bool requiresAction,
    String? attentionThreadKey,
    String? settlementKind,
    DateTime? settledAt,
    int? eventTotal,
    int? eventUnseenCount,
    @Default([]) List<AttentionReceipt> eventsPreview,
  }) = _AttentionReceipt;

  const AttentionReceipt._();

  bool get isSeen => seenAt != null;
  bool get isLiveObligation => requiresAction && settlementKind == null;

  /// Live obligations the user may clear with Done / Mark done.
  /// Review reminders stay until the package is sent or the window ends.
  bool get isUserSettleable =>
      isLiveObligation && presentationKey != 'review_opened';
}
