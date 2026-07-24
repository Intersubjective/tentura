import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// Stage-0 / CR-13 semantic compatibility fixture.
///
/// Asserts behavioural equality of legacy vs canonical receipt *presentation*
/// for feed readers — not serialization byte-equality. Legacy rows omit the
/// new-shape identity columns; canonical rows carry them. Both must still
/// expose the live fallback fields the client contract requires.
void main() {
  final createdAt = DateTime.utc(2026, 7, 24, 12);

  AttentionReceipt legacyReceipt() => AttentionReceipt(
    id: 'Nlegacy00000001',
    accountId: 'Urecipient00001',
    category: NotificationCategory.connections,
    kind: NotificationKind.inviteAccepted,
    priority: NotificationPriority.normal,
    title: 'Invite accepted',
    body: 'Alex joined via your invite',
    actionUrl: '/profile/view/Uactor000000001',
    createdAt: createdAt,
    collapsedCount: 1,
    suppressionClass: AttentionSuppressionClass.standard,
    accessPolicy: AttentionAccessPolicy.legacy,
    presentationPayload: const {},
    actorUserId: 'Uactor000000001',
  );

  AttentionReceipt canonicalReceipt() => AttentionReceipt(
    id: 'Ncanon000000001',
    accountId: 'Urecipient00001',
    category: NotificationCategory.connections,
    kind: NotificationKind.inviteAccepted,
    priority: NotificationPriority.normal,
    title: 'Invite accepted',
    body: 'Alex joined via your invite',
    actionUrl: '/profile/view/Uactor000000001',
    createdAt: createdAt,
    collapsedCount: 1,
    suppressionClass: AttentionSuppressionClass.standard,
    accessPolicy: AttentionAccessPolicy.profile,
    presentationPayload: const {
      'eventType': 'inviteAccepted',
      'actorUserId': 'Uactor000000001',
    },
    actorUserId: 'Uactor000000001',
    sourceEventKey: 'inviteAccepted:Uactor000000001:Urecipient00001',
    destinationKind: AttentionDestinationKind.profile,
    targetEntityId: 'Uactor000000001',
    presentationKey: 'invite_accepted',
  );

  test('legacy and canonical share feed fallback presentation fields', () {
    final legacy = legacyReceipt();
    final canonical = canonicalReceipt();

    expect(legacy.title, canonical.title);
    expect(legacy.body, canonical.body);
    expect(legacy.actionUrl, canonical.actionUrl);
    expect(legacy.category, canonical.category);
    expect(legacy.kind, canonical.kind);
    expect(legacy.priority, canonical.priority);
    expect(legacy.collapsedCount, canonical.collapsedCount);
    expect(legacy.seenAt, isNull);
    expect(canonical.seenAt, isNull);
  });

  test('legacy omits new-shape identity; canonical supplies it', () {
    final legacy = legacyReceipt();
    final canonical = canonicalReceipt();

    expect(legacy.sourceEventKey, isNull);
    expect(legacy.destinationKind, isNull);
    expect(legacy.presentationKey, isNull);
    expect(legacy.accessPolicy, AttentionAccessPolicy.legacy);

    expect(canonical.sourceEventKey, isNotNull);
    expect(canonical.destinationKind, AttentionDestinationKind.profile);
    expect(canonical.presentationKey, 'invite_accepted');
    expect(canonical.accessPolicy, isNot(AttentionAccessPolicy.legacy));
  });

  test('unread Needs-you summary axes agree when both are unresolved', () {
    final legacy = legacyReceipt();
    final canonical = canonicalReceipt();

    expect(legacy.seenAt, isNull);
    expect(canonical.seenAt, isNull);
    expect(legacy.requiresAction, isFalse);
    expect(canonical.requiresAction, isFalse);
    expect(legacy.settlementKind, isNull);
    expect(canonical.settlementKind, isNull);
  });

  test('cursor ordering key is createdAt then id for both shapes', () {
    final older = legacyReceipt();
    final newer = canonicalReceipt().copyWith(
      createdAt: createdAt.add(const Duration(seconds: 1)),
    );

    expect(older.createdAt.isBefore(newer.createdAt), isTrue);
    // Same timestamp → id is the secondary key (lexicographic).
    final sameTs = canonicalReceipt().copyWith(createdAt: older.createdAt);
    final ordered = [older, sameTs]..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    expect(ordered.map((r) => r.id).toList(), [
      sameTs.id.compareTo(older.id) < 0 ? sameTs.id : older.id,
      sameTs.id.compareTo(older.id) < 0 ? older.id : sameTs.id,
    ]);
  });
}
