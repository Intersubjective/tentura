import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_attention.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/attention_settlement_port.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';

class _FakeQuery implements AttentionQueryPort {
  String? accountId;
  AttentionFeedView? view;
  AttentionCursor? cursor;

  AttentionReceipt receipt = AttentionReceipt(
    id: 'N1',
    accountId: 'U1',
    category: NotificationCategory.coordination,
    kind: NotificationKind.coordinationChanged,
    priority: NotificationPriority.normal,
    title: 'Title',
    body: 'Body',
    actionUrl: '/#/beacon/B1',
    createdAt: DateTime.utc(2026, 7, 16),
    collapsedCount: 1,
    suppressionClass: AttentionSuppressionClass.standard,
    accessPolicy: AttentionAccessPolicy.beaconContent,
    presentationPayload: const {'eventType': 'coordinationChanged'},
  );

  @override
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    int limit = 50,
  }) async {
    this.accountId = accountId;
    this.view = view;
    this.cursor = cursor;
    return AttentionFeed(
      summary: const AttentionSummary(unreadTotal: 1),
      page: AttentionPage(
        items: [receipt],
        nextCursor: AttentionCursor(
          createdAt: DateTime.utc(2026, 7, 15),
          id: 'N0',
        ),
      ),
    );
  }
}

class _FakeAck implements AttentionAckPort {
  String? accountId;
  List<String>? ids;

  @override
  Future<int> markAllSeen(String accountId) async {
    this.accountId = accountId;
    return 3;
  }

  @override
  Future<int> markSeen({
    required String accountId,
    required List<String> ids,
  }) async {
    this.accountId = accountId;
    this.ids = ids;
    return ids.length;
  }

  @override
  Future<int> bridgeRoomWatermark({
    required String accountId,
    required String beaconId,
    required String? threadItemId,
    required DateTime lastSeenAt,
  }) async => 0;
}

class _FakeSettlement implements AttentionSettlementPort {
  String? accountId;
  String? receiptId;
  AttentionSettlementKind? kind;

  @override
  Future<int> settle({
    required String accountId,
    required String receiptId,
    required AttentionSettlementKind kind,
  }) async {
    this.accountId = accountId;
    this.receiptId = receiptId;
    this.kind = kind;
    return 1;
  }
}

AttentionSettlementCase _settlementCase(AttentionSettlementPort port) =>
    AttentionSettlementCase(
      port,
      env: Env.test(),
      logger: Logger('attention-graphql-test'),
    );

void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'U1')};

  test('attentionFeed scopes the query and returns an opaque cursor', () async {
    final query = _FakeQuery();
    final field = QueryAttention(query: query).all.single;
    final result = await field.resolve!(null, {...auth, 'view': 'unread'});

    expect(query.accountId, 'U1');
    expect(query.view, AttentionFeedView.unread);
    expect((result as Map)['summary'], {
      'unreadTotal': 1,
      'needsYouTotal': 0,
    });
    expect(((result['page'] as Map)['nextCursor'] as String), isNotEmpty);
  });

  test('attentionFeed rejects malformed cursors and unknown views', () async {
    final field = QueryAttention(query: _FakeQuery()).all.single;
    await expectLater(
      field.resolve!(null, {...auth, 'view': 'unread', 'cursor': 'bad'}),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      field.resolve!(null, {...auth, 'view': 'everything'}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'attentionFeed rejects unexpected presentation payload fields',
    () async {
      final query = _FakeQuery()
        ..receipt = _FakeQuery().receipt.copyWith(
          presentationPayload: const {'freeFormBody': 'must not leak'},
        );
      final field = QueryAttention(query: query).all.single;
      await expectLater(
        field.resolve!(null, {...auth, 'view': 'all'}),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('attentionMarkSeen scopes ids and caps the request at 200', () async {
    final ack = _FakeAck();
    final field = MutationAttention(ack: ack).all.first;
    expect(
      await field.resolve!(null, {
        ...auth,
        'ids': ['N1'],
      }),
      1,
    );
    expect(ack.accountId, 'U1');
    expect(ack.ids, ['N1']);
    expect(
      () => field.resolve!(null, {...auth, 'ids': List.filled(201, 'N')}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('attentionSettle scopes a user-resolvable live obligation', () async {
    final settlement = _FakeSettlement();
    final field = MutationAttention(
      ack: _FakeAck(),
      settlement: _settlementCase(settlement),
    ).all.last;

    expect(
      await field.resolve!(null, {
        ...auth,
        'receiptId': 'N1',
        'kind': 'resolved',
      }),
      1,
    );
    expect(settlement.accountId, 'U1');
    expect(settlement.receiptId, 'N1');
    expect(settlement.kind, AttentionSettlementKind.resolved);
  });

  test('attentionSettle rejects non-user settlement kinds', () async {
    final field = MutationAttention(
      ack: _FakeAck(),
      settlement: _settlementCase(_FakeSettlement()),
    ).all.last;

    expect(
      () => field.resolve!(null, {
        ...auth,
        'receiptId': 'N1',
        'kind': 'legacy_archived',
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => field.resolve!(null, {
        ...auth,
        'receiptId': 'N1',
        'kind': 'unknown',
      }),
      throwsA(isA<StateError>()),
    );
  });

  test('attention operations require authentication', () {
    final field = MutationAttention(ack: _FakeAck()).all.last;
    expect(
      () => field.resolve!(null, {}),
      throwsA(isA<UnauthorizedException>()),
    );
  });
}
