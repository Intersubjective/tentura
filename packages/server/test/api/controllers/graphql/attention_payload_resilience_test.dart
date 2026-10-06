import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';

import '../../../support/attention_payload_expectations.dart';

void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'account-1')};
  const sanitizedPayloads = <String, Map<String, String>>{
    'closure receipt with integer epoch': {
      'eventType': 'closureOpened',
      'beaconId': 'beacon-1',
    },
    'closure receipt with result codes': {
      'eventType': 'closureFinalized',
      'beaconId': 'beacon-1',
    },
    'receipt with non-string values and unknown fields': {
      'eventType': 'coordinationChanged',
      'beaconId': 'beacon-1',
      'actorUserId': 'actor-1',
    },
  };
  const coerciblePayloads = <String, Map<String, String>>{
    'closure receipt with integer epoch': {'epoch': '2'},
    'closure receipt with result codes': {
      'epoch': '2',
      'outcome': '1',
      'band': '3',
      'draftFlag': '0',
    },
    'receipt with non-string values and unknown fields': {
      'beaconTitle': '42',
      'excerpt': 'true',
    },
  };
  const healthyPayload = {
    'eventType': 'coordinationChanged',
    'beaconId': 'beacon-1',
    'beaconTitle': 'Garden cleanup',
  };
  const payloads = <String, Map<String, Object?>>{
    // ClosureReceiptsRepository writes epoch as an integer. Its SQL strips
    // null result fields for opened receipts, leaving this exact shape.
    'closure receipt with integer epoch': {
      'eventType': 'closureOpened',
      'beaconId': 'beacon-1',
      'epoch': 2,
    },
    // Finalized receipts also carry result codes outside the old allow-list.
    'closure receipt with result codes': {
      'eventType': 'closureFinalized',
      'beaconId': 'beacon-1',
      'epoch': 2,
      'outcome': 1,
      'band': 3,
      'draftFlag': 0,
    },
    'receipt with non-string values and unknown fields': {
      'eventType': 'coordinationChanged',
      'beaconId': 'beacon-1',
      'actorUserId': 'actor-1',
      'beaconTitle': 42,
      'excerpt': true,
      'toStatus': null,
      'extension': {'revision': 3},
    },
  };

  for (final entry in payloads.entries) {
    group(
      'Attention queries preserve receipts and sanitize their payloads',
      () {
        final receipt = _receipt('affected-receipt', entry.value);
        final healthy = _receipt('healthy-receipt', healthyPayload);
        final expectedPayload = sanitizedPayloads[entry.key]!;

        void expectAffected(Map<dynamic, dynamic> mapped) =>
            _expectUsableReceipt(
              mapped,
              receipt,
              expectedPayload,
              coerciblePayloads[entry.key]!,
            );

        void expectHealthy(Map<dynamic, dynamic> mapped) =>
            _expectUsableReceipt(mapped, healthy, healthyPayload);

        test('maps ${entry.key} with sanitized presentation fields', () {
          final mapped = QueryAttention.mapReceiptForTesting(receipt);

          expectAffected(mapped);
          expect(receipt.presentationPayload, entry.value);
        });

        test(
          'attentionFeed returns ${entry.key} alongside healthy items',
          () async {
            final query = _PayloadQuery(receipts: [receipt, healthy]);
            final field = QueryAttention(query: query).attentionFeed;

            final result =
                await field.resolve!(null, {...auth, 'view': 'unread'}) as Map;
            final page = result['page'] as Map;
            final items = page['items'] as List;

            expect(query.lastAccountId, 'account-1');
            expect((result['summary'] as Map)['unreadTotal'], 2);
            expect(items.map((item) => (item as Map)['id']), [
              'affected-receipt',
              'healthy-receipt',
            ]);
            expectAffected(items.first as Map);
            expectHealthy(items.last as Map);
          },
        );

        test(
          'myWorkAttention returns ${entry.key} as latest unseen',
          () async {
            final query = _PayloadQuery(
              receipts: [receipt, healthy],
              latestUnseen: receipt,
              liveObligations: [healthy],
            );
            final field = QueryAttention(query: query).myWorkAttention;

            final result =
                await field.resolve!(null, {
                      ...auth,
                      'beaconIds': ['beacon-1'],
                    })
                    as List;
            final projection = result.single as Map;

            expect(query.lastAccountId, 'account-1');
            expect(query.lastBeaconIds, {'beacon-1'});
            expect(projection['beaconId'], 'beacon-1');
            expect(projection['unseenCount'], 2);
            expectAffected(projection['latestUnseen'] as Map);
            expectHealthy(
              (projection['liveObligations'] as List).single as Map,
            );
          },
        );

        test(
          'myWorkAttention returns ${entry.key} alongside healthy obligations',
          () async {
            final query = _PayloadQuery(
              receipts: [receipt, healthy],
              latestUnseen: healthy,
              liveObligations: [receipt, healthy],
            );
            final field = QueryAttention(query: query).myWorkAttention;

            final result =
                await field.resolve!(null, {
                      ...auth,
                      'beaconIds': ['beacon-1'],
                    })
                    as List;
            final projection = result.single as Map;
            final obligations = projection['liveObligations'] as List;

            expect(obligations.map((item) => (item as Map)['id']), [
              'affected-receipt',
              'healthy-receipt',
            ]);
            expectHealthy(projection['latestUnseen'] as Map);
            expectAffected(obligations.first as Map);
            expectHealthy(obligations.last as Map);
          },
        );
      },
    );
  }
}

void _expectUsableReceipt(
  Map<dynamic, dynamic> mapped,
  AttentionReceipt receipt,
  Map<String, String> expectedPayload, [
  Map<String, String> coerciblePayload = const {},
]) {
  expect(mapped['id'], receipt.id);
  expect(mapped['beaconId'], receipt.beaconId);
  expect(mapped['title'], receipt.title);
  expect(mapped['body'], receipt.body);
  expect(mapped['actionUrl'], receipt.actionUrl);
  expectSanitizedAttentionPayload(
    mapped['presentationPayloadJson'],
    requiredFields: expectedPayload,
    coercibleFields: coerciblePayload,
  );
}

AttentionReceipt _receipt(String id, Map<String, Object?> payload) =>
    AttentionReceipt(
      id: id,
      accountId: 'account-1',
      category: NotificationCategory.unblocksMe,
      kind: NotificationKind.reviewReady,
      priority: NotificationPriority.normal,
      title: 'Evaluation ready',
      body: 'The closing results are ready.',
      actionUrl: '/#/beacon/beacon-1',
      createdAt: DateTime.utc(2026, 10, 5),
      collapsedCount: 1,
      suppressionClass: AttentionSuppressionClass.standard,
      accessPolicy: AttentionAccessPolicy.beaconContent,
      presentationPayload: payload,
      surface: AttentionSurface.myWork,
      beaconId: 'beacon-1',
    );

class _PayloadQuery implements AttentionQueryPort {
  _PayloadQuery({
    required this.receipts,
    this.latestUnseen,
    this.liveObligations = const [],
  });

  final List<AttentionReceipt> receipts;
  final AttentionReceipt? latestUnseen;
  final List<AttentionReceipt> liveObligations;
  String? lastAccountId;
  Set<String>? lastBeaconIds;

  @override
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    String? search,
    AttentionSurface? surface,
    int limit = 50,
  }) async {
    lastAccountId = accountId;
    return AttentionFeed(
      summary: AttentionSummary(unreadTotal: receipts.length),
      page: AttentionPage(items: receipts),
    );
  }

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention({
    required String accountId,
    required Set<String> beaconIds,
  }) async {
    lastAccountId = accountId;
    lastBeaconIds = beaconIds;
    return [
      MyWorkBeaconAttention(
        beaconId: 'beacon-1',
        unseenCount: receipts.length,
        latestUnseen: latestUnseen,
        liveObligations: liveObligations,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
