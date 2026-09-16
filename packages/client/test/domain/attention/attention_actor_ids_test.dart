import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/attention_actor_ids.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';

AttentionReceipt _receipt({
  required String id,
  String? actorUserId,
  List<AttentionReceipt> eventsPreview = const [],
}) =>
    AttentionReceipt(
      id: id,
      category: 'requestProgress',
      kind: 'requestStatusChanged',
      priority: 'normal',
      title: 'Event $id',
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 1, 1),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
      actorUserId: actorUserId,
      eventsPreview: eventsPreview,
    );

void main() {
  test('collects actor ids from receipts and nested previews', () {
    final ids = attentionActorIds([
      _receipt(id: 'a', actorUserId: 'u1'),
      _receipt(
        id: 'b',
        actorUserId: '  ',
        eventsPreview: [
          _receipt(id: 'b1', actorUserId: 'u2'),
          _receipt(id: 'b2', actorUserId: 'u1'),
        ],
      ),
      _receipt(id: 'c'),
    ]);
    expect(ids, {'u1', 'u2'});
  });

  test('skips blank actor ids', () {
    expect(
      attentionActorIds([
        _receipt(id: 'a', actorUserId: ''),
        _receipt(id: 'b', actorUserId: null),
      ]),
      isEmpty,
    );
  });
}
