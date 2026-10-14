// U087 — with "Recent", active Requests are ordered by their last activity
// (a message or system line, a next-step edit, a logged event such as a status
// change), not by when they entered the list. The busiest Request came last,
// below one untouched for 8 hours (round-2 QA). "Oldest" keeps entry order;
// the Needs-you zone and the attention tiers still lead.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

MyWorkCardViewModel _card(
  String id, {
  DateTime? roomLastActivityAt,
  DateTime? lastEventAt,
  MyWorkAttentionChip? chip,
}) => MyWorkCardViewModel(
  beaconId: id,
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  attentionChip: chip,
  beacon: Beacon.empty.copyWith(
    id: id,
    title: id,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  ),
  roomLastActivityAt: roomLastActivityAt,
  lastActivityEvent: lastEventAt == null
      ? null
      : MyWorkLastEvent(
          event: BeaconActivityEvent(
            id: 'e-$id',
            beaconId: id,
            visibility: 0,
            type: 16,
            createdAt: lastEventAt,
          ),
          actor: const Profile(id: 'u1'),
        ),
);

Map<String, MyWorkBeaconAttention> _entered(Map<String, DateTime> at) => {
  for (final e in at.entries)
    e.key: MyWorkBeaconAttention(
      beaconId: e.key,
      unseenCount: 0,
      firstEntryAt: e.value,
    ),
};

List<String> _order(
  List<MyWorkCardViewModel> cards,
  Map<String, MyWorkBeaconAttention> attention, {
  MyWorkSort sort = MyWorkSort.recent,
}) => visibleMyWorkCardsForDesk(
  filter: MyWorkFilter.all,
  sort: sort,
  nonArchivedCards: cards,
  archivedCards: const [],
  attentionByBeacon: attention,
).map((c) => c.beaconId).toList();

void main() {
  final entered = _entered({
    'quiet': DateTime.utc(2026, 10, 14, 4),
    'busy': DateTime.utc(2026, 10, 14, 1),
    'old': DateTime.utc(2026, 10, 13),
  });

  test('Recent: the Request with the latest discussion activity leads', () {
    final cards = [
      _card('quiet'),
      _card('busy', roomLastActivityAt: DateTime.utc(2026, 10, 14, 12)),
      _card('old'),
    ];
    expect(_order(cards, entered), ['busy', 'quiet', 'old']);
  });

  test('Recent: a logged event (status change) counts as activity', () {
    final cards = [
      _card('quiet'),
      _card('busy'),
      _card('old', lastEventAt: DateTime.utc(2026, 10, 14, 9)),
    ];
    expect(_order(cards, entered), ['old', 'quiet', 'busy']);
  });

  test('Recent: activity older than the entry does not push a card down', () {
    final cards = [
      _card('quiet', roomLastActivityAt: DateTime.utc(2026, 10, 1)),
      _card('busy'),
      _card('old'),
    ];
    expect(_order(cards, entered), ['quiet', 'busy', 'old']);
  });

  test('Oldest keeps the entry order', () {
    final cards = [
      _card('quiet'),
      _card('busy', roomLastActivityAt: DateTime.utc(2026, 10, 14, 12)),
      _card('old'),
    ];
    expect(_order(cards, entered, sort: MyWorkSort.oldest), [
      'old',
      'busy',
      'quiet',
    ]);
  });

  test('attention tiers still lead the activity order', () {
    final cards = [
      _card('quiet', chip: MyWorkAttentionChip.wrappingUp),
      _card('busy', roomLastActivityAt: DateTime.utc(2026, 10, 14, 12)),
      _card('old'),
    ];
    expect(_order(cards, entered), ['quiet', 'busy', 'old']);
  });
}
