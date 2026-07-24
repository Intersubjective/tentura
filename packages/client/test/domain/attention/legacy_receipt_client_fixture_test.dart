import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_state.dart';

/// Stage-0 / CR-13 client fixture: a legacy-shaped GraphQL receipt (null
/// new-shape fields) must still parse into [AttentionReceipt] and render via
/// the actionUrl fallback. Server resolver tests alone cannot prove this.
void main() {
  AttentionReceipt legacyReceipt() => AttentionReceipt(
    id: 'Nlegacy00000001',
    category: 'connections',
    kind: 'inviteAccepted',
    priority: 'normal',
    title: 'Invite accepted',
    body: 'Alex joined via your invite',
    actionUrl: '/profile/view/Uactor000000001',
    createdAt: DateTime.utc(2026, 7, 24, 12),
    collapsedCount: 1,
    presentationPayloadJson: '{}',
    actorUserId: 'Uactor000000001',
    // Legacy shape: new-shape identity columns absent.
    sourceEventKey: null,
    destinationKind: null,
    targetEntityId: null,
    presentationKey: null,
  );

  AttentionReceipt canonicalReceipt() => AttentionReceipt(
    id: 'Ncanon000000001',
    category: 'connections',
    kind: 'inviteAccepted',
    priority: 'normal',
    title: 'Invite accepted',
    body: 'Alex joined via your invite',
    actionUrl: '/profile/view/Uactor000000001',
    createdAt: DateTime.utc(2026, 7, 24, 12),
    collapsedCount: 1,
    presentationPayloadJson:
        '{"eventType":"inviteAccepted","actorUserId":"Uactor000000001"}',
    actorUserId: 'Uactor000000001',
    sourceEventKey: 'inviteAccepted:Uactor000000001:Urecipient00001',
    destinationKind: 'profile',
    targetEntityId: 'Uactor000000001',
    presentationKey: 'invite_accepted',
  );

  test('legacy receipt falls back to actionUrl for navigation', () {
    final uri = attentionDestination(legacyReceipt());
    expect(uri.toString(), '/profile/view/Uactor000000001');
  });

  test('canonical profile destination uses typed target', () {
    final uri = attentionDestination(canonicalReceipt());
    expect(uri.path, '/profile/view/Uactor000000001');
  });

  test('legacy and canonical share unread / Needs-you card axes', () {
    final legacy = legacyReceipt();
    final canonical = canonicalReceipt();

    expect(legacy.isSeen, isFalse);
    expect(canonical.isSeen, isFalse);
    expect(legacy.isLiveObligation, isFalse);
    expect(canonical.isLiveObligation, isFalse);
    expect(legacy.title, canonical.title);
    expect(legacy.body, canonical.body);
  });

  test('updates feed state can hold a legacy receipt without null crashes', () {
    final state = UpdatesFeedState(items: [legacyReceipt()]);
    expect(state.items, hasLength(1));
    expect(state.items.single.sourceEventKey, isNull);
    expect(state.items.single.destinationKind, isNull);
    expect(state.items.single.presentationKey, isNull);
    expect(attentionDestination(state.items.single).toString(), isNotEmpty);
  });
}
