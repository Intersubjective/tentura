import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

MyWorkCardViewModel _card(String id, {DateTime? updatedAt}) =>
    MyWorkCardViewModel(
      beaconId: id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: id,
        title: id,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
      ),
    );

AttentionReceipt _optional(String id) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'roomMessagePosted',
  priority: 'normal',
  title: 'Boris',
  body: 'posted',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 1),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: id,
);

List<String> _order(
  List<MyWorkCardViewModel> cards,
  Map<String, MyWorkBeaconAttention> attention,
) => visibleMyWorkCardsForDesk(
  filter: MyWorkFilter.all,
  sort: MyWorkSort.recent,
  nonArchivedCards: cards,
  archivedCards: const [],
  attentionByBeacon: attention,
).map((c) => c.beaconId).toList();

void main() {
  test('a new obligation promotes its Request to the top', () {
    final cards = [_card('a'), _card('b'), _card('c')];
    const none = <String, MyWorkBeaconAttention>{};
    final before = _order(cards, none);

    final after = _order(cards, {
      'c': MyWorkBeaconAttention(
        beaconId: 'c',
        unseenCount: 0,
        needsYouAt: DateTime.utc(2026, 9, 18),
        firstEntryAt: DateTime.utc(2026, 1, 1),
      ),
    });

    expect(before.first, isNot('c'));
    expect(after.first, 'c');
  });

  test('the newest obligation leads inside Needs you', () {
    final cards = [_card('a'), _card('b')];
    final order = _order(cards, {
      'a': MyWorkBeaconAttention(
        beaconId: 'a',
        unseenCount: 0,
        needsYouAt: DateTime.utc(2026, 9, 10),
      ),
      'b': MyWorkBeaconAttention(
        beaconId: 'b',
        unseenCount: 0,
        needsYouAt: DateTime.utc(2026, 9, 18),
      ),
    });
    expect(order, ['b', 'a']);
  });

  test('an optional update never changes a position', () {
    final cards = [_card('a'), _card('b'), _card('c')];
    final quiet = {
      for (final id in ['a', 'b', 'c'])
        id: MyWorkBeaconAttention(
          beaconId: id,
          unseenCount: 0,
          firstEntryAt: DateTime.utc(2026, 1, id == 'a' ? 3 : (id == 'b' ? 2 : 1)),
        ),
    };
    final before = _order(cards, quiet);

    // The one thing an optional event may not do. `c` gets a dot, a preview
    // and an event; `firstEntryAt` — its place — is untouched, because entry
    // is what established the place and nothing has re-entered.
    final noisy = {
      ...quiet,
      'c': quiet['c']!.copyWith(
        unseenCount: 9,
        latestUnseen: _optional('c'),
      ),
    };

    expect(_order(cards, noisy), before);
  });

  test('the optional-update rule can fail', () {
    // Proof the previous assertion is load-bearing: order the same three by
    // the mutable Beacon.updatedAt the desk used before U15 and the noisy
    // Request jumps, because that is exactly what an optional event moves.
    final quietCards = [
      _card('a', updatedAt: DateTime.utc(2026, 1, 3)),
      _card('b', updatedAt: DateTime.utc(2026, 1, 2)),
      _card('c', updatedAt: DateTime.utc(2026, 1, 1)),
    ];
    final noisyCards = [
      quietCards[0],
      quietCards[1],
      _card('c', updatedAt: DateTime.utc(2026, 9, 18)),
    ];

    List<String> byUpdatedAt(List<MyWorkCardViewModel> cards) =>
        (List<MyWorkCardViewModel>.from(cards)..sort(
              (x, y) => y.beacon.updatedAt.compareTo(x.beacon.updatedAt),
            ))
            .map((c) => c.beaconId)
            .toList();

    expect(byUpdatedAt(quietCards), ['a', 'b', 'c']);
    expect(byUpdatedAt(noisyCards), ['c', 'a', 'b']);

    // The same event under the ordering U15 installs moves nothing.
    final keys = {
      for (final id in ['a', 'b', 'c'])
        id: MyWorkBeaconAttention(
          beaconId: id,
          unseenCount: id == 'c' ? 9 : 0,
          latestUnseen: id == 'c' ? _optional('c') : null,
          firstEntryAt: DateTime.utc(
            2026,
            1,
            id == 'a' ? 3 : (id == 'b' ? 2 : 1),
          ),
        ),
    };
    expect(_order(noisyCards, keys), ['a', 'b', 'c']);
  });

  test('a Request entering the surface establishes its place then', () {
    final cards = [_card('a'), _card('b')];
    final keys = {
      'a': MyWorkBeaconAttention(
        beaconId: 'a',
        unseenCount: 0,
        firstEntryAt: DateTime.utc(2026, 1, 1),
      ),
      'b': MyWorkBeaconAttention(
        beaconId: 'b',
        unseenCount: 0,
        firstEntryAt: DateTime.utc(2026, 9, 18),
      ),
    };
    expect(_order(cards, keys), ['b', 'a']);
  });

  test('resolving the obligation demotes the Request naturally', () {
    final cards = [_card('a'), _card('b')];
    final withObligation = {
      'a': MyWorkBeaconAttention(
        beaconId: 'a',
        unseenCount: 0,
        firstEntryAt: DateTime.utc(2026, 9, 18),
      ),
      'b': MyWorkBeaconAttention(
        beaconId: 'b',
        unseenCount: 0,
        needsYouAt: DateTime.utc(2026, 9, 1),
        firstEntryAt: DateTime.utc(2026, 1, 1),
      ),
    };
    expect(_order(cards, withObligation), ['b', 'a']);

    final resolved = {
      ...withObligation,
      'b': withObligation['b']!.copyWith(needsYouAt: null),
    };
    expect(_order(cards, resolved), ['a', 'b']);
  });

  test('the desk no longer reads Beacon.updatedAt for Recent', () {
    final cards = [
      _card('a', updatedAt: DateTime.utc(2026, 1, 1)),
      _card('b', updatedAt: DateTime.utc(2026, 12, 31)),
    ];
    final keys = {
      'a': MyWorkBeaconAttention(
        beaconId: 'a',
        unseenCount: 0,
        firstEntryAt: DateTime.utc(2026, 9, 18),
      ),
      'b': MyWorkBeaconAttention(
        beaconId: 'b',
        unseenCount: 0,
        firstEntryAt: DateTime.utc(2026, 1, 1),
      ),
    };
    expect(_order(cards, keys), ['a', 'b']);
  });
}
