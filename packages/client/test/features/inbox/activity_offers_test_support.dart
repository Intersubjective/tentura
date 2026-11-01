import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';

import '../../support/attention_repository_fake_base.dart';
import 'inbox_case_test.dart';

ActivityOfferSortRow activityOfferSortRow(
  InboxItem item, {
  int eventTotal = 0,
  int eventUnseenCount = 0,
  List<AttentionReceipt> eventsPreview = const [],
  bool unseen = false,
  DateTime? listPositionAt,
}) => ActivityOfferSortRow(
  beaconId: item.beaconId,
  listPositionAt: listPositionAt ?? item.latestForwardAt,
  effectiveActivityAt: item.latestForwardAt,
  latestForwardAt: item.latestForwardAt,
  unseen: unseen,
  eventTotal: eventTotal,
  eventUnseenCount: eventUnseenCount,
  eventsPreview: eventsPreview,
);

abstract class ConfigurableActivityOffersAttentionRepo
    extends AttentionRepositoryFake {
  List<ActivityOfferSortRow> offerRows = const [];
  List<ActivityOfferSortRow> secondOfferRows = const [];
  String? offersNextCursor;
  String? secondOffersNextCursor;
  int offerTotalCount = 0;
  int activityOffersCalls = 0;
  String? lastActivityOffersCursor;
  bool failActivityOffers = false;

  /// #725: the one-Request lookups a live arrival makes; kept apart from
  /// [activityOffersCalls], which counts page loads.
  final beaconOfferLookups = <String>[];

  /// Beacons the v2 single-row lookup treats as absent (#928 Post parent).
  Set<String> v2AbsentBeaconIds = const {};

  @override
  Future<ActivityOfferPage> activityOffers({
    String? cursor,
    int limit = 20,
    String? beaconId,
  }) async {
    if (beaconId != null) {
      beaconOfferLookups.add(beaconId);
      if (failActivityOffers) {
        throw StateError('activity offers offline');
      }
      if (v2AbsentBeaconIds.contains(beaconId)) {
        return const ActivityOfferPage(items: [], totalCount: 0);
      }
      return ActivityOfferPage(
        items: [
          for (final row in [...offerRows, ...secondOfferRows])
            if (row.beaconId == beaconId) row,
        ].take(1).toList(),
        totalCount: offerTotalCount,
      );
    }
    activityOffersCalls++;
    lastActivityOffersCursor = cursor;
    if (failActivityOffers) {
      throw StateError('activity offers offline');
    }
    if (cursor != null && cursor.isNotEmpty) {
      final start = 0;
      final end = (start + limit).clamp(0, secondOfferRows.length);
      return ActivityOfferPage(
        items: secondOfferRows.sublist(start, end),
        totalCount: offerTotalCount == 0
            ? offerRows.length + secondOfferRows.length
            : offerTotalCount,
        nextCursor: secondOffersNextCursor,
      );
    }
    final end = limit.clamp(0, offerRows.length);
    return ActivityOfferPage(
      items: offerRows.sublist(0, end),
      totalCount: offerTotalCount == 0 ? offerRows.length : offerTotalCount,
      nextCursor: offersNextCursor,
    );
  }
}

void wireActivityOffersV2({
  required FakeInboxRepository inbox,
  required ConfigurableActivityOffersAttentionRepo attention,
  required List<InboxItem> items,
  String? nextCursor,
  int? totalCount,
}) {
  inbox.inboxItemsByBeacon = {for (final item in items) item.beaconId: item};
  inbox.openForwardsCount = totalCount ?? items.length;
  attention.offerRows = [
    for (final item in items) activityOfferSortRow(item),
  ];
  attention.offersNextCursor = nextCursor;
  attention.offerTotalCount = totalCount ?? items.length;
}
