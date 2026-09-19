import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_card_attention.dart';

AttentionReceipt _receipt({required String id, required bool obligation}) =>
    AttentionReceipt(
      id: id,
      category: 'coordination',
      kind: 'helpOfferSubmitted',
      priority: 'normal',
      title: 'Anna',
      body: 'body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 9, 1),
      collapsedCount: 1,
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      surface: AttentionSurface.myWork,
      beaconId: 'b1',
      requiresAction: obligation,
    );

void main() {
  test('the count is obligations, not the rows the card groups them into', () {
    // Two offers from one person coalesce into one sub-card; the contract
    // counts obligations, never visual groups.
    final view = myWorkCardAttentionView(
      beaconId: 'b1',
      attention: MyWorkBeaconAttention(
        beaconId: 'b1',
        unseenCount: 0,
        liveObligations: [
          _receipt(id: 'o1', obligation: true),
          _receipt(id: 'o2', obligation: true),
        ],
      ),
      viewerArchived: false,
    );

    expect(requestCount(view.facts), 2);
  });

  test('a lit card always has a row behind the light', () {
    // The enumeration the card can actually be in: a server total with and
    // without a renderable optional row, crossed with obligations.
    for (final unseenCount in const [0, 1, 4]) {
      for (final hasLatest in const [false, true]) {
        for (final obligations in const [0, 1, 3]) {
          final view = myWorkCardAttentionView(
            beaconId: 'b1',
            attention: MyWorkBeaconAttention(
              beaconId: 'b1',
              unseenCount: unseenCount,
              latestUnseen: hasLatest
                  ? _receipt(id: 'opt', obligation: false)
                  : null,
              liveObligations: [
                for (var i = 0; i < obligations; i++)
                  _receipt(id: 'o$i', obligation: true),
              ],
            ),
            viewerArchived: false,
          );
          final rows = [...view.obligations, ...view.optionalEvents];
          final reason = 'unseen=$unseenCount latest=$hasLatest ob=$obligations';

          // The equality, not the implication: a dark card with rows is the
          // same defect seen from the other side.
          expect(
            requestHasDot(view.facts) || requestCount(view.facts) > 0,
            rows.isNotEmpty,
            reason: reason,
          );
          // The dot specifically derives from the optional row the card
          // renders — a server total with nothing to show lights nothing.
          expect(
            requestHasDot(view.facts),
            view.optionalEvents.isNotEmpty,
            reason: reason,
          );
        }
      }
    }
  });

  test('a missing attention row is dark and empty', () {
    final view = myWorkCardAttentionView(
      beaconId: 'b1',
      attention: null,
      viewerArchived: false,
    );
    expect(view.obligations, isEmpty);
    expect(view.optionalEvents, isEmpty);
    expect(requestHasDot(view.facts), isFalse);
    expect(requestCount(view.facts), 0);
  });

  test('an archived Request is exposed by the Archive filter', () {
    final view = myWorkCardAttentionView(
      beaconId: 'b1',
      attention: MyWorkBeaconAttention(
        beaconId: 'b1',
        unseenCount: 1,
        latestUnseen: _receipt(id: 'opt', obligation: false),
      ),
      viewerArchived: true,
    );
    expect(myDeskFilterExposing(view.facts), MyDeskAttentionFilter.archive);
  });
}
