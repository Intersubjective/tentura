import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/use_case/attention_shadow_case.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16);

  NotificationOutboxItemEntity legacy({
    String id = 'N1',
    DateTime? readAt,
    String accessPolicy = 'legacy',
    String suppressionClass = 'standard',
    String? preferenceClass,
  }) => NotificationOutboxItemEntity(
    id: id,
    accountId: 'U1',
    category: NotificationCategory.coordination,
    kind: NotificationKind.coordinationChanged,
    priority: NotificationPriority.normal,
    title: 'Title',
    body: 'Body',
    actionUrl: '/#/beacon/B1',
    createdAt: now,
    collapsedCount: 1,
    readAt: readAt,
    suppressionClass: suppressionClass,
    accessPolicy: accessPolicy,
    inAppPreferenceClass: preferenceClass,
  );

  AttentionReceipt attention({
    String id = 'N1',
    DateTime? seenAt,
    String? sourceEventKey,
  }) => AttentionReceipt(
    id: id,
    accountId: 'U1',
    category: NotificationCategory.coordination,
    kind: NotificationKind.coordinationChanged,
    priority: NotificationPriority.normal,
    title: 'Title',
    body: 'Body',
    actionUrl: '/#/beacon/B1',
    createdAt: now,
    collapsedCount: 1,
    seenAt: seenAt,
    sourceEventKey: sourceEventKey,
    suppressionClass: AttentionSuppressionClass.standard,
    accessPolicy: AttentionAccessPolicy.legacy,
    presentationPayload: const {'eventType': 'coordinationChanged'},
  );

  test('reports zero for matching legacy and dual-write read axes', () {
    final result = AttentionShadowCase.compare([legacy()], [attention()]);

    expect(result.unexplained, 0);
    expect(result.expectedTotal, 0);
  });

  test('does not hide a dual-write read-axis mismatch', () {
    final result = AttentionShadowCase.compare(
      [legacy(readAt: now)],
      [attention()],
    );

    expect(result.readAxisMismatch, 1);
    expect(result.unexplained, 1);
  });

  test('separately labels known authorization, mute, and new-class deltas', () {
    final result = AttentionShadowCase.compare(
      [
        legacy(id: 'Nauthorization', accessPolicy: 'beacon_content'),
        legacy(
          id: 'Nmute',
          suppressionClass: 'noisy',
          preferenceClass: 'coordination_churn',
        ),
      ],
      [attention(id: 'Nnew', sourceEventKey: 'room_message:R1')],
    );

    expect(result.authorization, 1);
    expect(result.mute, 1);
    expect(result.newClass, 1);
    expect(result.unexplained, 0);
  });

  test('keeps unclassified page differences release-blocking', () {
    final result = AttentionShadowCase.compare(
      [legacy(id: 'Nlegacy')],
      [attention(id: 'Nattention')],
    );

    expect(result.unexplained, 2);
    expect(result.expectedTotal, 0);
  });
}
