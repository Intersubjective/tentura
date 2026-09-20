import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/domain/my_desk_caught_up.dart';

/// U17d / D18 — "My Desk can be attention-clear while authored / active-help
/// Requests remain."
///
/// That sentence is the whole rule: the desk being caught up says nothing
/// about the desk being empty, and it is never said while the attention that
/// would contradict it has not arrived.
void main() {
  MyWorkBeaconAttention attention(
    String beaconId, {
    int unseenCount = 0,
    int obligations = 0,
  }) => MyWorkBeaconAttention(
    beaconId: beaconId,
    unseenCount: unseenCount,
    liveObligations: [
      for (var i = 0; i < obligations; i++)
        AttentionReceipt(
          id: '$beaconId-o$i',
          category: 'asksOfMe',
          kind: 'needsMe',
          priority: 'normal',
          title: 'Obligation',
          body: 'Body',
          actionUrl: '/#/',
          createdAt: DateTime.utc(2026, 9, 19),
          collapsedCount: 1,
          presentationPayloadJson: '{}',
          surface: AttentionSurface.myWork,
          beaconId: beaconId,
          requiresAction: true,
        ),
    ],
  );

  MyWorkCardViewModel card(String id) => MyWorkCardViewModel(
    beaconId: id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: Beacon.empty.copyWith(
      id: id,
      updatedAt: DateTime.utc(2026, 9, 18),
      status: BeaconStatus.open,
    ),
  );

  final cards = [card('b-1'), card('b-2')];

  test('work on the desk with no attention on it is caught up', () {
    expect(
      myDeskIsCaughtUp(
        filter: MyWorkFilter.active,
        cards: cards,
        attentionByBeacon: {'b-1': attention('b-1'), 'b-2': attention('b-2')},
        attentionLoaded: true,
        hasError: false,
      ),
      isTrue,
    );
  });

  test('one live obligation is not caught up', () {
    expect(
      myDeskIsCaughtUp(
        filter: MyWorkFilter.active,
        cards: cards,
        attentionByBeacon: {'b-2': attention('b-2', obligations: 1)},
        attentionLoaded: true,
        hasError: false,
      ),
      isFalse,
    );
  });

  test('an uncleared update is not caught up either', () {
    expect(
      myDeskIsCaughtUp(
        filter: MyWorkFilter.active,
        cards: cards,
        attentionByBeacon: {'b-1': attention('b-1', unseenCount: 2)},
        attentionLoaded: true,
        hasError: false,
      ),
      isFalse,
    );
  });

  test('attention that has not arrived yet never reads as clear', () {
    // The empty map is the same shape as "no attention anywhere", which is
    // exactly why the loaded flag is an input and not an inference.
    expect(
      myDeskIsCaughtUp(
        filter: MyWorkFilter.active,
        cards: cards,
        attentionByBeacon: const {},
        attentionLoaded: false,
        hasError: false,
      ),
      isFalse,
    );
  });

  test('a desk that failed to load says nothing reassuring', () {
    expect(
      myDeskIsCaughtUp(
        filter: MyWorkFilter.active,
        cards: cards,
        attentionByBeacon: const {},
        attentionLoaded: true,
        hasError: true,
      ),
      isFalse,
    );
  });

  test('an empty desk is not caught up — it has nothing to be caught up on', () {
    expect(
      myDeskIsCaughtUp(
        filter: MyWorkFilter.active,
        cards: const [],
        attentionByBeacon: const {},
        attentionLoaded: true,
        hasError: false,
      ),
      isFalse,
    );
  });

  test('only the filters that show the desk\'s responsibilities say it', () {
    final clear = {'b-1': attention('b-1'), 'b-2': attention('b-2')};
    final said = <MyWorkFilter>[
      for (final filter in MyWorkFilter.values)
        if (myDeskIsCaughtUp(
          filter: filter,
          cards: cards,
          attentionByBeacon: clear,
          attentionLoaded: true,
          hasError: false,
        ))
          filter,
    ];
    expect(said, [
      MyWorkFilter.active,
      MyWorkFilter.authored,
      MyWorkFilter.helpOffered,
      MyWorkFilter.all,
    ], reason: 'drafts ask nothing and the archive is over');
  });
}
