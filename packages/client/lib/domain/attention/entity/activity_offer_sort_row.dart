import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_receipt.dart';

part 'activity_offer_sort_row.freezed.dart';

@freezed
abstract class ActivityOfferSortRow with _$ActivityOfferSortRow {
  const factory ActivityOfferSortRow({
    required String beaconId,
    // U10c — the key the zone is ordered by. `effectiveActivityAt` below is
    // the latest-event key: rendered, never ordered by.
    required DateTime listPositionAt,
    required DateTime effectiveActivityAt,
    required DateTime latestForwardAt,
    required bool unseen,
    required int eventTotal,
    required int eventUnseenCount,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> eventsPreview,

    /// Plan C6: the viewer's pending author invite on this Request; a row
    /// with it renders the «Для вас» invite card.
    String? inviteId,

    /// #725: the viewer's latest author invitation to this Request was
    /// answered «Can't make it». The plain card (the row is back after a
    /// restore or a forward) then keeps the invitation's words for its
    /// «Can't help» route, as the Activity row will say "You said you can't
    /// make it".
    @Default(false) bool declinedInvite,
  }) = _ActivityOfferSortRow;
}

@freezed
abstract class ActivityOfferPage with _$ActivityOfferPage {
  const factory ActivityOfferPage({
    @Default(<ActivityOfferSortRow>[]) List<ActivityOfferSortRow> items,
    @Default(0) int totalCount,
    String? nextCursor,
  }) = _ActivityOfferPage;
}
