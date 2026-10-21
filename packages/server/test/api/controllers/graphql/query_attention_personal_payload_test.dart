import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// #601 (from #381) — the policy writes `personal` as a bool, and the GraphQL
/// mapper kept only String values, so the flag never reached the client and
/// the For You card's «вам» zone (#189) never showed. The client reads it as
/// `decoded['personal'] == true` (`attentionReceiptIsPersonal`).
void main() {
  Map<String, Object?> wirePayload({
    required AttentionEventType eventType,
    required Set<AttentionRecipientReason> reasons,
    String excerpt = 'We found someone closer, thanks',
  }) {
    final projection = const AttentionPolicy().project(
      eventType: eventType,
      recipientId: 'helper',
      recipientReasons: reasons,
      role: AttentionRecipientRoleFacts(
        canReadBeaconContent: true,
        beaconId: 'beacon-1',
        targetEntityId: 'helper',
        actorUserId: 'author',
        excerpt: excerpt,
      ),
    );
    return _wire(projection.presentationPayload, projection);
  }

  test('a personal receipt keeps `personal: true` on the wire', () {
    final payload = wirePayload(
      eventType: AttentionEventType.offerRemoved,
      reasons: const {AttentionRecipientReason.affectedParticipant},
    );
    expect(payload['personal'], isTrue);
    expect(payload['eventType'], 'offerRemoved');
  });

  test('a general receipt says `personal: false`, not nothing', () {
    final payload = wirePayload(
      eventType: AttentionEventType.offerRemoved,
      reasons: const {AttentionRecipientReason.admittedRoomMember},
    );
    expect(payload['personal'], isFalse);
  });

  for (final eventType in [
    AttentionEventType.offerRemoved,
    AttentionEventType.commitmentReleased,
  ]) {
    test('${eventType.name} carries the author reason as excerpt', () {
      final payload = wirePayload(
        eventType: eventType,
        reasons: const {AttentionRecipientReason.affectedParticipant},
      );
      expect(payload['excerpt'], 'We found someone closer, thanks');
      expect(payload['personal'], isTrue);
    });
  }

  test('guard: a non-bool `personal` is still stripped', () {
    final payload = _wire({
      'eventType': 'offerRemoved',
      'beaconId': 'beacon-1',
      'personal': 'true',
    });
    expect(payload.containsKey('personal'), isFalse);
    expect(payload['eventType'], 'offerRemoved');
  });

  test('guard: unknown keys and non-String values are still stripped', () {
    final payload = _wire({
      'eventType': 'offerRemoved',
      'personal': true,
      'junk': 'must not leak',
      'beaconTitle': 42,
    });
    expect(payload.keys, unorderedEquals(['eventType', 'personal']));
  });

  test('the allow-list validator accepts the bool flag only', () {
    expect(
      () => QueryAttention.validateAttentionPresentationPayload({
        'eventType': 'offerRemoved',
        'personal': false,
      }),
      returnsNormally,
    );
    expect(
      () => QueryAttention.validateAttentionPresentationPayload({
        'eventType': 'offerRemoved',
        'personal': 'yes',
      }),
      throwsStateError,
    );
  });
}

Map<String, Object?> _wire(
  Map<String, Object?> presentationPayload, [
  AttentionReceiptProjection? projection,
]) {
  final mapped = QueryAttention.mapReceiptForTesting(
    AttentionReceipt(
      id: 'receipt-1',
      accountId: 'helper',
      category: NotificationCategory.coordination,
      kind: NotificationKind.commitmentRemoved,
      priority: NotificationPriority.normal,
      title: 'Removed from the discussion',
      body: 'Body',
      actionUrl: '/#/beacon/beacon-1',
      createdAt: DateTime.utc(2026, 10, 21),
      collapsedCount: 1,
      suppressionClass: AttentionSuppressionClass.standard,
      accessPolicy:
          projection?.accessPolicy ?? AttentionAccessPolicy.beaconContent,
      presentationKey: projection?.presentationKey,
      presentationPayload: presentationPayload,
      surface: AttentionSurface.activity,
    ),
  );
  return jsonDecode(mapped['presentationPayloadJson']! as String)
      as Map<String, Object?>;
}
