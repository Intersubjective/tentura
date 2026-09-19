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
