// #258 QA round 1: Updates «Read all» was enabled (and did nothing) when
// only unanswered forwards were left, because it was gated on
// `unreadTotal`, which counts the forwards Read all never clears. It is
// enabled only when Read all has something to do.
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_state.dart';

final _seen = DateTime.utc(2026, 10, 31, 12);

AttentionReceipt _forward(String id) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Alice',
  body: 'forwarded you a request',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 10, 30),
  collapsedCount: 1,
  presentationKey: 'relay_received',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  beaconId: 'B-$id',
  seenAt: _seen,
);

AttentionReceipt _sharedPost({bool read = false}) => AttentionReceipt(
  id: 'post',
  category: 'requestProgress',
  kind: 'postShared',
  priority: 'normal',
  title: 'Bob',
  body: 'shared a post',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 10, 30),
  collapsedCount: 1,
  presentationKey: 'post_shared',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  beaconId: 'P1',
  seenAt: read ? _seen : null,
  clearedAt: read ? _seen : null,
);

void main() {
  final forwards = [for (var i = 0; i < 6; i++) _forward('f$i')];

  test('only unanswered forwards left: Read all is disabled, even though '
      'unreadTotal still counts them', () {
    final state = UpdatesFeedState(
      summary: const AttentionSummary(unreadTotal: 6),
      items: forwards,
    );
    expect(state.canReadAll, isFalse);
  });

  test('a shared Post beside the forwards: enabled; after Read all '
      '(Post seen and cleared, sweep has nothing left): disabled', () {
    final before = UpdatesFeedState(
      summary: const AttentionSummary(unreadTotal: 7),
      sweepEligible: true,
      items: [_sharedPost(), ...forwards],
    );
    expect(before.canReadAll, isTrue);

    final after = before.copyWith(
      summary: const AttentionSummary(unreadTotal: 6),
      sweepEligible: false,
      items: [_sharedPost(read: true), ...forwards],
    );
    expect(after.canReadAll, isFalse);
  });

  test('the sweep alone (nothing loaded unseen) keeps it enabled', () {
    expect(
      UpdatesFeedState(sweepEligible: true, items: forwards).canReadAll,
      isTrue,
    );
  });

  test('an optional My Desk row Read all clears after the sweep keeps it '
      'enabled', () {
    final desk = _sharedPost(read: true).copyWith(
      id: 'desk',
      clearedAt: null,
      surface: AttentionSurface.myWork,
    );
    expect(UpdatesFeedState(items: [desk, ...forwards]).canReadAll, isTrue);
  });
}
