// Plan D0: an Activity offer row carries the viewer's pending author invite
// id (plan C6), mapped through the real `AttentionRepository` and Ferry chain.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';

import '../../support/remote_wire_harness.dart';

Map<String, dynamic> _row(
  String beaconId,
  String? inviteId, {
  bool declinedInvite = false,
}) => {
  '__typename': 'ActivityOfferSortRow',
  'beaconId': beaconId,
  'listPositionAt': '2026-10-11T08:00:00.000Z',
  'effectiveActivityAt': '2026-10-11T08:00:00.000Z',
  'latestForwardAt': '2026-10-11T07:00:00.000Z',
  'unseen': true,
  'eventTotal': 1,
  'eventUnseenCount': 1,
  'inviteId': inviteId,
  'declinedInvite': declinedInvite,
  'eventsPreview': <Object?>[],
};

void main() {
  test('activityOffers maps inviteId when present, null otherwise', () async {
    late ActivityOfferPage page;
    await withRemoteWire(
      {
        'ActivityOffersV2': {
          '__typename': 'query_root',
          'activityOffers': {
            '__typename': 'ActivityOfferPage',
            'totalCount': 2,
            'nextCursor': null,
            'items': [
              _row('Bchild0000001', 'Ainvite000001'),
              _row('Bother0000001', null),
            ],
          },
        },
      },
      <WireSent>[],
      (remote) async {
        page = await AttentionRepository(remote).activityOffers();
      },
    );
    expect(page.items.first.inviteId, 'Ainvite000001');
    expect(page.items.last.inviteId, isNull);
  });

  // #725: a Request whose author invitation the viewer declined says so, and
  // a live arrival asks for its one row by `beaconId`.
  test('activityOffers maps declinedInvite and sends beaconId', () async {
    late ActivityOfferPage page;
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'ActivityOffersV2': {
          '__typename': 'query_root',
          'activityOffers': {
            '__typename': 'ActivityOfferPage',
            'totalCount': 1,
            'nextCursor': null,
            'items': [
              _row('Bchild0000001', null, declinedInvite: true),
            ],
          },
        },
      },
      sent,
      (remote) async {
        page = await AttentionRepository(
          remote,
        ).activityOffers(limit: 1, beaconId: 'Bchild0000001');
      },
    );
    expect(page.items.single.declinedInvite, isTrue);
    expect(page.items.single.inviteId, isNull);
    expect(sent.single.variables['beaconId'], 'Bchild0000001');
  });
}
