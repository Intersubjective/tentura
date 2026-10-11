import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_card_zones.dart';

AttentionReceipt _event(
  String id, {
  String eventType = 'roomMessagePosted',
  bool? personal = true,
  String? actor = 'olga',
  int minute = 0,
  bool requiresAction = false,
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: eventType,
  priority: 'normal',
  title: '',
  body: '',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 10, 11, 12, minute),
  collapsedCount: 1,
  presentationPayloadJson: personal == null
      ? '{"eventType":"$eventType"}'
      : '{"eventType":"$eventType","personal":$personal}',
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  actorUserId: actor,
  requiresAction: requiresAction,
);

void main() {
  test('personal is the server flag, not the event type', () {
    expect(attentionReceiptIsPersonal(_event('a')), isTrue);
    expect(attentionReceiptIsPersonal(_event('b', personal: false)), isFalse);
    // Written before the flag existed: not personal.
    expect(attentionReceiptIsPersonal(_event('c', personal: null)), isFalse);
  });

  test('one row per sender, newest sender first, newest item on top', () {
    final zones = RequestCardZones.fromPreview([
      _event('o1', minute: 1),
      _event('i1', actor: 'ivan', minute: 2),
      _event('o2', minute: 3),
    ]);
    expect(zones.personalRows.map((r) => r.senderId), ['olga', 'ivan']);
    expect(zones.personalRows.first.newest.id, 'o2');
    expect(zones.personalRows.first.receipts.map((r) => r.id), ['o2', 'o1']);
    expect(zones.changeLine, isNull);
  });

  test('exactly one change line: the newest general event', () {
    final zones = RequestCardZones.fromPreview([
      _event('s1', eventType: 'requestStatusChanged', personal: false),
      _event(
        's2',
        eventType: 'blockerOpened',
        personal: false,
        minute: 5,
      ),
      _event('m1', minute: 9),
    ]);
    expect(zones.changeLine?.id, 's2');
    expect(zones.personalRows, hasLength(1));
    // Personal and general items are never merged into one row.
    expect(zones.personalRows.single.receipts.map((r) => r.id), ['m1']);
    expect(zones.shownEventCount, 2);
  });

  test('a deadline change never makes the change line', () {
    final zones = RequestCardZones.fromPreview([
      _event('d1', eventType: 'deadlineChanged', personal: false, minute: 9),
    ]);
    expect(zones.changeLine, isNull);
  });

  test('an obligation never reaches either zone (For You is skippable only)',
      () {
    final zones = RequestCardZones.fromPreview([
      _event('ob', requiresAction: true, minute: 9),
      _event(
        'og',
        eventType: 'helpOfferSubmitted',
        personal: false,
        requiresAction: true,
      ),
    ]);
    expect(zones.personalRows, isEmpty);
    expect(zones.changeLine, isNull);
  });
}
