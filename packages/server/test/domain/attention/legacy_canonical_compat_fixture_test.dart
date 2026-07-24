import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';

/// CR-13 compatibility coverage through the production resolver path:
/// query-port receipt -> [QueryAttention] -> GraphQL-shaped map. It verifies
/// optional identity fields are emitted as nullable legacy values while the
/// always-present presentation fallback fields remain available to old clients.
void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'Urecipient00001')};

  test(
    'resolver preserves legacy fallback fields and emits null new identity',
    () async {
      final result = await _resolve(_legacyReceipt(), auth);
      final item = _singleItem(result);

      expect(item['title'], 'Invite accepted');
      expect(item['body'], 'Alex joined via your invite');
      expect(item['actionUrl'], '/profile/view/Uactor000000001');
      expect(item['sourceEventKey'], isNull);
      expect(item['destinationKind'], isNull);
      expect(item['targetEntityId'], isNull);
      expect(item['presentationKey'], isNull);
      expect(item['presentationPayloadJson'], jsonEncode({}));
    },
  );

  test(
    'resolver exposes canonical identity alongside the same fallback fields',
    () async {
      final result = await _resolve(_canonicalReceipt(), auth);
      final item = _singleItem(result);

      expect(item['title'], 'Invite accepted');
      expect(item['body'], 'Alex joined via your invite');
      expect(item['actionUrl'], '/profile/view/Uactor000000001');
      expect(
        item['sourceEventKey'],
        'inviteAccepted:Uactor000000001:Urecipient00001',
      );
      expect(item['destinationKind'], 'profile');
      expect(item['targetEntityId'], 'Uactor000000001');
      expect(item['presentationKey'], 'invite_accepted');
      expect(
        item['presentationPayloadJson'],
        jsonEncode({
          'eventType': 'inviteAccepted',
          'actorUserId': 'Uactor000000001',
        }),
      );
    },
  );
}

Future<Map<dynamic, dynamic>> _resolve(
  AttentionReceipt receipt,
  Map<String, Object> auth,
) async {
  final query = QueryAttention(query: _FixtureQuery(receipt));
  final field = query.all.singleWhere((field) => field.name == 'attentionFeed');
  return await field.resolve!(null, {...auth, 'view': 'all'})
      as Map<dynamic, dynamic>;
}

Map<dynamic, dynamic> _singleItem(Map<dynamic, dynamic> result) =>
    ((result['page'] as Map<dynamic, dynamic>)['items'] as List).single
        as Map<dynamic, dynamic>;

AttentionReceipt _legacyReceipt() => _receipt(
  accessPolicy: AttentionAccessPolicy.legacy,
  presentationPayload: const {},
);

AttentionReceipt _canonicalReceipt() => _receipt(
  accessPolicy: AttentionAccessPolicy.profile,
  presentationPayload: const {
    'eventType': 'inviteAccepted',
    'actorUserId': 'Uactor000000001',
  },
  sourceEventKey: 'inviteAccepted:Uactor000000001:Urecipient00001',
  destinationKind: AttentionDestinationKind.profile,
  targetEntityId: 'Uactor000000001',
  presentationKey: 'invite_accepted',
);

AttentionReceipt _receipt({
  required AttentionAccessPolicy accessPolicy,
  required Map<String, String> presentationPayload,
  String? sourceEventKey,
  AttentionDestinationKind? destinationKind,
  String? targetEntityId,
  String? presentationKey,
}) => AttentionReceipt(
  id: 'Nlegacy00000001',
  accountId: 'Urecipient00001',
  category: NotificationCategory.connections,
  kind: NotificationKind.inviteAccepted,
  priority: NotificationPriority.normal,
  title: 'Invite accepted',
  body: 'Alex joined via your invite',
  actionUrl: '/profile/view/Uactor000000001',
  createdAt: DateTime.utc(2026, 7, 24, 12),
  collapsedCount: 1,
  suppressionClass: AttentionSuppressionClass.standard,
  accessPolicy: accessPolicy,
  presentationPayload: presentationPayload,
  actorUserId: 'Uactor000000001',
  sourceEventKey: sourceEventKey,
  destinationKind: destinationKind,
  targetEntityId: targetEntityId,
  presentationKey: presentationKey,
);

final class _FixtureQuery implements AttentionQueryPort {
  _FixtureQuery(this.receipt);

  final AttentionReceipt receipt;

  @override
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    String? search,
    int limit = 50,
  }) async => AttentionFeed(
    summary: const AttentionSummary(unreadTotal: 1),
    page: AttentionPage(items: [receipt]),
  );

  @override
  Future<Set<String>> unreadForBeacons({
    required String accountId,
    required Set<String> beaconIds,
  }) async => const {};
}
