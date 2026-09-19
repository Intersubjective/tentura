import 'dart:convert';

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
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';
import 'package:tentura_server/domain/port/attention_sweep_port.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_clear_port.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/attention_settlement_port.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';
import 'package:tentura_server/domain/attention/attention_reconciliation_models.dart';
import 'package:tentura_server/domain/use_case/obligation_reconciliation_case.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';

class _FakeReconciliation implements ObligationReconciliationRunner {
  String? accountId;

  @override
  Future<AttentionReconciliationResult> reconcileAccount({
    required String accountId,
  }) async {
    this.accountId = accountId;
    return const AttentionReconciliationResult(
      createdObligationCount: 1,
      settledObligationCount: 2,
      unrepairableObligationCount: 3,
      summary: AttentionSurfaceSummary(
        activityUnreadTotal: 4,
        myWorkUnreadTotal: 5,
        needsYouTotal: 6,
      ),
    );
  }
}

class _FakeQuery implements AttentionQueryPort {
  String? accountId;
  AttentionFeedView? view;
  AttentionCursor? cursor;
  String? search;
  Set<String>? beaconIds;

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
    surface: AttentionSurface.myWork,
  );

  @override
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    String? search,
    AttentionSurface? surface,
    int limit = 50,
  }) async {
    this.accountId = accountId;
    this.view = view;
    this.cursor = cursor;
    this.search = search;
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

  @override
  Future<AttentionSurfaceSummary> surfaceSummary({
    required String accountId,
  }) async {
    this.accountId = accountId;
    return const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 1,
      needsYouTotal: 0,
      myDeskCount: 3,
      myDeskDot: true,
      forYouDot: false,
    );
  }

  @override
  Future<Set<String>> unreadForBeacons({
    required String accountId,
    required Set<String> beaconIds,
  }) async {
    this.accountId = accountId;
    this.beaconIds = beaconIds;
    return beaconIds.where((id) => id == 'B1').toSet();
  }

  Set<String> liveObligationBeaconIds = const {'B2', 'B1'};

  @override
  Future<Set<String>> liveObligationBeacons({
    required String accountId,
  }) async {
    this.accountId = accountId;
    return liveObligationBeaconIds;
  }

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention({
    required String accountId,
    required Set<String> beaconIds,
  }) async {
    this.accountId = accountId;
    this.beaconIds = beaconIds;
    return const [];
  }

  @override
  Future<ActivityOfferPage> activityOffers({
    required String accountId,
    AttentionCursor? cursor,
    int limit = 20,
  }) async {
    this.accountId = accountId;
    this.cursor = cursor;
    return const ActivityOfferPage(items: [], totalCount: 0);
  }

  String? historyBeaconId;
  int? historyLimit;

  @override
  Future<AttentionPage> attentionRequestHistory({
    required String accountId,
    required String beaconId,
    AttentionCursor? cursor,
    int limit = 50,
  }) async {
    this.accountId = accountId;
    this.cursor = cursor;
    historyBeaconId = beaconId;
    historyLimit = limit;
    return AttentionPage(
      items: [receipt],
      nextCursor: AttentionCursor(
        createdAt: DateTime.utc(2026, 7, 15),
        id: 'N0',
      ),
    );
  }

  @override
  Future<ActivityBeaconAttention> activityAttention({
    required String accountId,
    required String beaconId,
    AttentionCursor? cursor,
    int limit = 20,
  }) async {
    this.accountId = accountId;
    this.cursor = cursor;
    return ActivityBeaconAttention(
      beaconId: beaconId,
      eventTotal: 0,
      unseenCount: 0,
      latestAt: DateTime.utc(2026),
      events: const [],
    );
  }
}

class _FakeAck implements AttentionAckPort {
  String? accountId;
  List<String>? ids;
  String? beaconId;

  @override
  Future<int> markAllSeen(String accountId, {AttentionSurface? surface}) async {
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
  Future<int> markUnseen({
    required String accountId,
    required List<String> ids,
  }) async {
    this.accountId = accountId;
    this.ids = ids;
    return ids.length;
  }

  @override
  Future<int> markSeenForBeacon({
    required String accountId,
    required String beaconId,
  }) async {
    this.accountId = accountId;
    this.beaconId = beaconId;
    return 2;
  }

  @override
  Future<int> bridgeRoomWatermark({
    required String accountId,
    required String beaconId,
    required String? threadItemId,
    required DateTime lastSeenAt,
  }) async => 0;
}

class _FakeSweep implements AttentionSweepPort {
  String? sweptAccountId;
  String? sweptOperationId;
  int? sweptBatchSize;
  int? sweptMaxBatches;

  String? undoneAccountId;
  String? undoneOperationId;
  String? undoneToken;

  @override
  Future<AttentionUndoResult> undo({
    required String accountId,
    required String operationId,
    required String undoToken,
  }) async {
    undoneAccountId = accountId;
    undoneOperationId = operationId;
    undoneToken = undoToken;
    return AttentionUndoResult(
      operationId: operationId,
      restoredReceiptIds: const ['N1'],
      restoredOutcomeBeaconIds: const ['B1'],
      skipped: const [
        AttentionUndoMember(
          kind: 'outcome',
          id: 'B2',
          reason: AttentionUndoSkipReason.decisionChanged,
        ),
      ],
      failed: const [],
      status: AttentionUndoStatus.partial,
    );
  }

  @override
  Future<AttentionSweepResult> dismissAll({
    required String accountId,
    required String operationId,
    int batchSize = AttentionSweepLimits.batchSize,
    int? maxBatches,
  }) async {
    sweptAccountId = accountId;
    sweptOperationId = operationId;
    sweptBatchSize = batchSize;
    sweptMaxBatches = maxBatches;
    return AttentionSweepResult(
      operationId: operationId,
      appliedReceiptIds: const ['N1'],
      appliedOutcomeBeaconIds: const ['B1'],
      skipped: const [
        AttentionSweepMember(
          kind: AttentionSweepMemberKind.outcome,
          id: 'B2',
          reason: AttentionSweepSkipReason.awaitingDecision,
        ),
      ],
      failed: const [],
      pending: const [],
      status: AttentionClearStatus.partial,
      undoDeadline: deadline,
      undoToken: token,
    );
  }

  static final deadline = DateTime.utc(2026, 9, 19, 12);
  static const token = 'fake-undo-token';
}

class _FakeClear implements AttentionClearPort {
  String? capturedAccountId;
  String? capturedBeaconId;
  String? capturedReceiptId;

  String? appliedAccountId;
  String? appliedOperationId;
  String? appliedBeaconId;
  AttentionClearCaptureKind? appliedKind;
  int? appliedDecisionRevision;
  List<String>? appliedReceiptIds;

  @override
  Future<AttentionClearCapture> captureEligible({
    required String accountId,
    String? beaconId,
    String? receiptId,
    int limit = AttentionClearSnapshotToken.maxMembers,
  }) async {
    capturedAccountId = accountId;
    capturedBeaconId = beaconId;
    capturedReceiptId = receiptId;
    return const AttentionClearCapture(
      receiptIds: ['N1', 'N2'],
      outcomeGeneration: 0,
      decisionRevision: 0,
    );
  }

  @override
  Future<AttentionClearResult> apply({
    required String accountId,
    required String operationId,
    required String? beaconId,
    required AttentionClearCaptureKind kind,
    required int outcomeGeneration,
    required int decisionRevision,
    required List<String> receiptIds,
  }) async {
    appliedAccountId = accountId;
    appliedOperationId = operationId;
    appliedBeaconId = beaconId;
    appliedKind = kind;
    appliedDecisionRevision = decisionRevision;
    appliedReceiptIds = receiptIds;
    return AttentionClearResult(
      operationId: operationId,
      appliedReceiptIds: const ['N1'],
      skippedReceiptIds: const ['N2'],
      deniedReceiptIds: const [],
      status: AttentionClearStatus.partial,
      undoDeadline: DateTime.utc(2026, 9, 19, 12, 0, 30),
      undoToken: 'UNDO-TOKEN',
    );
  }
}

class _FakeSettlement implements AttentionSettlementPort {
  String? accountId;
  String? receiptId;
  AttentionSettlementKind? kind;
  String? liveEventType;
  int settleCalls = 0;

  @override
  Future<String?> liveObligationEventType({
    required String accountId,
    required String receiptId,
  }) async => liveEventType;

  @override
  Future<int> settle({
    required String accountId,
    required String receiptId,
    required AttentionSettlementKind kind,
  }) async {
    settleCalls++;
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
    final field = QueryAttention(
      query: query,
    ).all.singleWhere((field) => field.name == 'attentionFeed');
    final result = await field.resolve!(null, {...auth, 'view': 'unread'});

    expect(query.accountId, 'U1');
    expect(query.view, AttentionFeedView.unread);
    expect((result as Map)['summary'], {
      'unreadTotal': 1,
      'needsYouTotal': 0,
    });
    expect(((result['page'] as Map)['nextCursor'] as String), isNotEmpty);
  });

  test('attentionFeed trims bounded structured-payload search input', () async {
    final query = _FakeQuery();
    final field = QueryAttention(
      query: query,
    ).all.singleWhere((field) => field.name == 'attentionFeed');
    await field.resolve!(null, {...auth, 'view': 'all', 'search': '  B1  '});
    expect(query.search, 'B1');
    await expectLater(
      field.resolve!(null, {
        ...auth,
        'view': 'all',
        'search': 'x' * 121,
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a cursor minted under the previous sort keys is refused', () async {
    // U10c versioned the cursor because the pinned zone and the grouped feed
    // stopped ordering by `GREATEST(latest_forward_at, max child created_at)`.
    // A cursor from before that names a point on a line that no longer
    // exists; resuming from it silently skips or repeats rows, so it is
    // refused and the reader refetches the head.
    final stale = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'createdAt': '2026-08-10T09:00:00.000Z',
              'id': 'N0',
            }),
          ),
        )
        .replaceAll('=', '');
    final field = QueryAttention(
      query: _FakeQuery(),
    ).all.singleWhere((field) => field.name == 'attentionFeed');
    await expectLater(
      field.resolve!(null, {...auth, 'view': 'all', 'cursor': stale}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a cursor of an unknown future generation is refused too', () async {
    final future = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'v': kAttentionCursorVersion + 1,
              'createdAt': '2026-08-10T09:00:00.000Z',
              'id': 'N0',
            }),
          ),
        )
        .replaceAll('=', '');
    final field = QueryAttention(
      query: _FakeQuery(),
    ).all.singleWhere((field) => field.name == 'attentionFeed');
    await expectLater(
      field.resolve!(null, {...auth, 'view': 'all', 'cursor': future}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a cursor the server minted itself round-trips', () async {
    final query = _FakeQuery();
    final all = QueryAttention(query: query).all;
    final history = all.singleWhere(
      (field) => field.name == 'attentionRequestHistory',
    );
    final result =
        await history.resolve!(null, {...auth, 'beaconId': 'B1'}) as Map;
    final cursor = result['nextCursor'] as String;

    final feed = all.singleWhere((field) => field.name == 'attentionFeed');
    await feed.resolve!(null, {...auth, 'view': 'all', 'cursor': cursor});
    expect(query.cursor?.id, 'N0');
    expect(query.cursor?.version, kAttentionCursorVersion);
  });

  test('attentionFeed rejects malformed cursors and unknown views', () async {
    final field = QueryAttention(
      query: _FakeQuery(),
    ).all.singleWhere((field) => field.name == 'attentionFeed');
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
      final field = QueryAttention(
        query: query,
      ).all.singleWhere((field) => field.name == 'attentionFeed');
      await expectLater(
        field.resolve!(null, {...auth, 'view': 'all'}),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'attentionRequestHistory scopes to the account and returns an opaque '
    'cursor the feed can also decode',
    () async {
      final query = _FakeQuery();
      final all = QueryAttention(query: query).all;
      final field = all.singleWhere(
        (field) => field.name == 'attentionRequestHistory',
      );

      final result =
          await field.resolve!(null, {...auth, 'beaconId': 'B1'}) as Map;

      expect(query.accountId, 'U1');
      expect(query.historyBeaconId, 'B1');
      expect(query.historyLimit, 50);
      expect((result['items'] as List).single, isA<Map>());
      final cursor = result['nextCursor'] as String;
      expect(cursor, isNotEmpty);

      // Cursor parity with the feed is a contract: the same opaque string must
      // round-trip through the feed field.
      final feed = all.singleWhere((field) => field.name == 'attentionFeed');
      await feed.resolve!(null, {...auth, 'view': 'all', 'cursor': cursor});
      expect(query.cursor?.id, 'N0');
    },
  );

  test('attentionRequestHistory rejects bad beacon ids and cursors', () async {
    final field = QueryAttention(
      query: _FakeQuery(),
    ).all.singleWhere((field) => field.name == 'attentionRequestHistory');

    await expectLater(
      field.resolve!(null, {...auth, 'beaconId': ''}),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      field.resolve!(null, {...auth, 'beaconId': 'x' * 65}),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      field.resolve!(null, {...auth, 'beaconId': 'B1', 'cursor': 'bad'}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('attentionSurfaceSummary exposes the §6 indicators beside the legacy '
      'totals',
      () async {
    final query = _FakeQuery();
    final field = QueryAttention(
      query: query,
    ).all.singleWhere((field) => field.name == 'attentionSurfaceSummary');

    expect(await field.resolve!(null, auth), {
      'activityUnreadTotal': 0,
      'myWorkUnreadTotal': 1,
      'needsYouTotal': 0,
      // §6 `my desk.dot`, `for you.dot` and — CHANGES IN U15R-e — the fourth
      // rule, `my desk.count`. There is no `forYouCount` key: §6 says
      // `for you.count = never`, so the wire has nowhere to put one.
      'myDeskDot': true,
      'forYouDot': false,
      'myDeskCount': 3,
    });
    expect(query.accountId, 'U1');
  });

  test('liveObligationBeacons scopes to the authenticated account', () async {
    final query = _FakeQuery();
    final field = QueryAttention(
      query: query,
    ).all.singleWhere((field) => field.name == 'liveObligationBeacons');

    expect(await field.resolve!(null, auth), ['B1', 'B2']);
    expect(query.accountId, 'U1');
  });

  test('attentionMarkers scopes and bounds candidate Beacon ids', () async {
    final query = _FakeQuery();
    final field = QueryAttention(
      query: query,
    ).all.singleWhere((field) => field.name == 'attentionMarkers');

    expect(
      await field.resolve!(null, {
        ...auth,
        'beaconIds': ['B2', 'B1', 'B1'],
      }),
      {
        'unreadBeaconIds': ['B1'],
      },
    );
    expect(query.accountId, 'U1');
    expect(query.beaconIds, {'B1', 'B2'});
    expect(
      () => field.resolve!(null, {
        ...auth,
        'beaconIds': List.generate(501, (index) => 'B$index'),
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('myWorkAttention scopes and bounds candidate Beacon ids', () async {
    final query = _FakeQuery();
    final field = QueryAttention(
      query: query,
    ).all.singleWhere((field) => field.name == 'myWorkAttention');

    expect(
      await field.resolve!(null, {
        ...auth,
        'beaconIds': ['B1', 'B2'],
      }),
      isEmpty,
    );
    expect(query.accountId, 'U1');
    expect(query.beaconIds, {'B1', 'B2'});
    expect(
      () => field.resolve!(null, {
        ...auth,
        'beaconIds': List.generate(501, (index) => 'B$index'),
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('attentionMarkSeenForBeacon scopes beaconId to the account', () async {
    final ack = _FakeAck();
    final field = MutationAttention(ack: ack).all.singleWhere(
      (mutation) => mutation.name == 'attentionMarkSeenForBeacon',
    );
    expect(
      await field.resolve!(null, {
        ...auth,
        'beaconId': 'B1',
      }),
      2,
    );
    expect(ack.accountId, 'U1');
    expect(ack.beaconId, 'B1');
  });

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

  test('attentionMarkUnseen scopes ids and caps the request at 200', () async {
    final ack = _FakeAck();
    final field = MutationAttention(
      ack: ack,
    ).all.singleWhere((field) => field.name == 'attentionMarkUnseen');
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
    expect(
      () => field.resolve!(null, {
        'ids': ['N1'],
      }),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test(
    'attentionReconcile runs as the caller and cannot name an account',
    () async {
      final reconciliation = _FakeReconciliation();
      final field = MutationAttention(
        ack: _FakeAck(),
        reconciliation: reconciliation,
      ).all.singleWhere((field) => field.name == 'attentionReconcile');

      // Authorization is structural: there is no argument to put another
      // account id in, so a foreign id is inexpressible rather than refused.
      expect(field.inputs, isEmpty);

      expect(await field.resolve!(null, auth), {
        'createdObligationCount': 1,
        'settledObligationCount': 2,
        'unrepairableObligationCount': 3,
        // CHANGES IN U15R-d/U15R-e: §6 gives `attentionSurfaceSummary` three
        // more indicator fields (`my desk.dot`, `for you.dot`,
        // `my desk.count`), and the reconcile result carries the same object,
        // so its wire shape gains them too.
        // The three legacy totals keep their values: this unit adds, it does
        // not resemanticize.
        'summary': {
          'activityUnreadTotal': 4,
          'myWorkUnreadTotal': 5,
          'needsYouTotal': 6,
          'myDeskDot': false,
          'forYouDot': false,
          'myDeskCount': 0,
        },
      });
      expect(reconciliation.accountId, 'U1');

      // A foreign id smuggled into the argument map is ignored, not honoured.
      await field.resolve!(null, {...auth, 'accountId': 'U2'});
      expect(reconciliation.accountId, 'U1');

      expect(
        () => field.resolve!(null, const <String, dynamic>{}),
        throwsA(isA<UnauthorizedException>()),
      );
    },
  );

  test('attentionSettle scopes a user-resolvable live obligation', () async {
    final settlement = _FakeSettlement();
    final field = MutationAttention(
      ack: _FakeAck(),
      settlement: _settlementCase(settlement),
    ).all.singleWhere((field) => field.name == 'attentionSettle');

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

  test('attentionSettle rejects reviewOpened live obligations', () async {
    final settlement = _FakeSettlement()..liveEventType = 'reviewOpened';
    final field = MutationAttention(
      ack: _FakeAck(),
      settlement: _settlementCase(settlement),
    ).all.singleWhere((field) => field.name == 'attentionSettle');

    expect(
      () => field.resolve!(null, {
        ...auth,
        'receiptId': 'N1',
        'kind': 'resolved',
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(settlement.settleCalls, 0);
  });

  test('attentionSettle rejects helpOfferSubmitted live obligations', () async {
    final settlement = _FakeSettlement()..liveEventType = 'helpOfferSubmitted';
    final field = MutationAttention(
      ack: _FakeAck(),
      settlement: _settlementCase(settlement),
    ).all.singleWhere((field) => field.name == 'attentionSettle');

    expect(
      () => field.resolve!(null, {
        ...auth,
        'receiptId': 'N1',
        'kind': 'resolved',
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(settlement.settleCalls, 0);
  });

  test('attentionSettle rejects non-user settlement kinds', () async {
    final field = MutationAttention(
      ack: _FakeAck(),
      settlement: _settlementCase(_FakeSettlement()),
    ).all.singleWhere((field) => field.name == 'attentionSettle');

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

  test(
    'attentionClearSnapshot issues a token bound to the caller and Request',
    () async {
      final port = _FakeClear();
      final field = QueryAttention(
        query: _FakeQuery(),
        clear: AttentionClearCase(port),
      ).all.singleWhere((field) => field.name == 'attentionClearSnapshot');

      final result =
          await field.resolve!(null, {
                ...auth,
                'beaconId': 'B1',
                'kind': 'request_open',
              })
              as Map;

      expect(port.capturedAccountId, 'U1');
      expect(port.capturedBeaconId, 'B1');
      expect(result['receiptIds'], ['N1', 'N2']);
      expect(result['outcomeGeneration'], 0);
      expect(result['decisionRevision'], 0);

      // The token is opaque on the wire but must carry the caller, the scope
      // and the exact membership — apply re-checks all three.
      final token = AttentionClearSnapshotToken.decode(
        result['snapshotToken']! as String,
      );
      expect(token.accountId, 'U1');
      expect(token.beaconId, 'B1');
      expect(token.kind, AttentionClearCaptureKind.requestOpen);
      expect(token.receiptIds, ['N1', 'N2']);
    },
  );

  test('attentionClearSnapshot rejects an unscoped or unknown capture', () {
    final field = QueryAttention(
      query: _FakeQuery(),
      clear: AttentionClearCase(_FakeClear()),
    ).all.singleWhere((field) => field.name == 'attentionClearSnapshot');

    expect(
      () => field.resolve!(null, {...auth, 'kind': 'explicit'}),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => field.resolve!(null, {...auth, 'beaconId': 'B1', 'kind': 'sweep'}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('attentionClear applies the token under the caller account', () async {
    final port = _FakeClear();
    final field = MutationAttention(
      ack: _FakeAck(),
      clear: AttentionClearCase(port),
    ).all.singleWhere((field) => field.name == 'attentionClear');

    final token = const AttentionClearSnapshotToken(
      accountId: 'U1',
      beaconId: 'B1',
      kind: AttentionClearCaptureKind.explicit,
      outcomeGeneration: 0,
      decisionRevision: 7,
      receiptIds: ['N1', 'N2'],
    ).encode();

    final result =
        await field.resolve!(null, {
              ...auth,
              'snapshotToken': token,
              'operationId': 'OP1',
            })
            as Map;

    expect(port.appliedAccountId, 'U1');
    expect(port.appliedOperationId, 'OP1');
    expect(port.appliedBeaconId, 'B1');
    expect(port.appliedKind, AttentionClearCaptureKind.explicit);
    expect(port.appliedReceiptIds, ['N1', 'N2']);
    expect(result['appliedReceiptIds'], ['N1']);
    expect(result['skippedReceiptIds'], ['N2']);
    expect(result['deniedReceiptIds'], isEmpty);
    expect(result['status'], 'partial');
    // U15R-a / R3: the token's revision reaches storage, and the operation's
    // undo affordance reaches the wire. Without both, a snackbar in U16 has
    // nothing to offer and nothing to call.
    expect(port.appliedDecisionRevision, 7);
    expect(result['undoToken'], 'UNDO-TOKEN');
    expect(result['undoDeadline'], '2026-09-19T12:00:30.000Z');
  });

  test(
    'attentionClear refuses another account token without reaching storage',
    () async {
      final port = _FakeClear();
      final field = MutationAttention(
        ack: _FakeAck(),
        clear: AttentionClearCase(port),
      ).all.singleWhere((field) => field.name == 'attentionClear');

      final token = const AttentionClearSnapshotToken(
        accountId: 'U2',
        beaconId: 'B1',
        kind: AttentionClearCaptureKind.explicit,
        outcomeGeneration: 0,
        decisionRevision: 0,
        receiptIds: ['N9'],
      ).encode();

      final result =
          await field.resolve!(null, {
                ...auth,
                'snapshotToken': token,
                'operationId': 'OP2',
              })
              as Map;

      expect(result['status'], 'denied');
      expect(result['appliedReceiptIds'], isEmpty);
      expect(result['deniedReceiptIds'], ['N9']);
      expect(
        port.appliedOperationId,
        isNull,
        reason: 'a denied token must not reach storage at all',
      );
    },
  );

  test('attentionClear rejects a malformed token', () {
    final field = MutationAttention(
      ack: _FakeAck(),
      clear: AttentionClearCase(_FakeClear()),
    ).all.singleWhere((field) => field.name == 'attentionClear');

    expect(
      () => field.resolve!(null, {
        ...auth,
        'snapshotToken': 'not-a-token',
        'operationId': 'OP3',
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('attentionDismissAll sweeps under the caller account', () async {
    final port = _FakeSweep();
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(port),
    ).all.singleWhere((field) => field.name == 'attentionDismissAll');

    final result =
        await field.resolve!(null, {...auth, 'operationId': 'OPSWEEP'}) as Map;

    expect(port.sweptAccountId, 'U1');
    expect(port.sweptOperationId, 'OPSWEEP');
    expect(
      port.sweptMaxBatches,
      isNull,
      reason: 'an unbounded call runs the operation to the end',
    );
    expect(result['appliedReceiptIds'], ['N1']);
    expect(result['appliedOutcomeBeaconIds'], ['B1']);
    expect(result['appliedCount'], 2);
    expect(result['status'], 'partial');
    // A skip without a reason is not a report.
    final skipped = (result['skipped']! as List).single as Map;
    expect(skipped['kind'], 'outcome');
    expect(skipped['id'], 'B2');
    expect(skipped['reason'], 'awaiting_decision');
    expect(result['failed'], isEmpty);
    expect(result['pendingCount'], 0);
  });

  test('attentionDismissAll takes no membership from the caller', () async {
    // The whole point of a server-captured sweep: there is no argument that
    // could narrow it to the pages a client happens to have loaded.
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(_FakeSweep()),
    ).all.singleWhere((field) => field.name == 'attentionDismissAll');

    expect(
      field.inputs.map((input) => input.name).toSet(),
      {'operationId', 'maxBatches'},
    );
  });

  test('attentionDismissAll rejects an unusable operation id', () {
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(_FakeSweep()),
    ).all.singleWhere((field) => field.name == 'attentionDismissAll');

    expect(
      () => field.resolve!(null, {...auth, 'operationId': ''}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('attentionDismissAll requires authentication', () {
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(_FakeSweep()),
    ).all.singleWhere((field) => field.name == 'attentionDismissAll');

    expect(
      () => field.resolve!(null, {'operationId': 'OPSWEEP'}),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('attentionDismissAll hands back the undo window it opened', () async {
    final port = _FakeSweep();
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(port),
    ).all.singleWhere((field) => field.name == 'attentionDismissAll');

    final result =
        await field.resolve!(null, {...auth, 'operationId': 'OPSWEEP'}) as Map;

    expect(result['undoToken'], _FakeSweep.token);
    expect(result['undoDeadline'], _FakeSweep.deadline.toIso8601String());
  });

  test('attentionUndo reverses under the caller account', () async {
    final port = _FakeSweep();
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(port),
    ).all.singleWhere((field) => field.name == 'attentionUndo');

    final result =
        await field.resolve!(null, {
              ...auth,
              'operationId': 'OPSWEEP',
              'undoToken': const AttentionUndoToken(
                accountId: 'U1',
                operationId: 'OPSWEEP',
              ).encode(),
            })
            as Map;

    expect(port.undoneAccountId, 'U1');
    expect(port.undoneOperationId, 'OPSWEEP');
    expect(result['restoredReceiptIds'], ['N1']);
    expect(result['restoredOutcomeBeaconIds'], ['B1']);
    expect(result['restoredCount'], 2);
    expect(result['status'], 'partial');
    expect(result['refusal'], isNull);
    final skipped = (result['skipped']! as List).single as Map;
    expect(skipped['kind'], 'outcome');
    expect(skipped['id'], 'B2');
    expect(skipped['reason'], 'decision_changed');
  });

  test('attentionUndo names the refusal instead of failing', () async {
    // "Expired" is the one refusal a person actually sees. It must arrive as
    // a value, not as an error the client has to guess at.
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(_FakeSweep()),
    ).all.singleWhere((field) => field.name == 'attentionUndo');

    final result =
        await field.resolve!(null, {
              ...auth,
              'operationId': 'OPSWEEP',
              // A token bound to another operation never reaches the port.
              'undoToken': const AttentionUndoToken(
                accountId: 'U1',
                operationId: 'OPELSEWHERE',
              ).encode(),
            })
            as Map;

    expect(result['refusal'], 'not_found');
    expect(result['status'], 'denied');
    expect(result['restoredCount'], 0);
  });

  test('attentionUndo takes the operation and its token, nothing else', () {
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(_FakeSweep()),
    ).all.singleWhere((field) => field.name == 'attentionUndo');

    expect(
      field.inputs.map((input) => input.name).toSet(),
      {'operationId', 'undoToken'},
      reason:
          'a caller cannot name which members come back — undo reverses what '
          'the operation did, or it refuses',
    );
  });

  test('attentionUndo requires authentication', () {
    final field = MutationAttention(
      ack: _FakeAck(),
      sweep: AttentionSweepCase(_FakeSweep()),
    ).all.singleWhere((field) => field.name == 'attentionUndo');

    expect(
      () => field.resolve!(null, {
        'operationId': 'OPSWEEP',
        'undoToken': 'whatever',
      }),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('attention operations require authentication', () {
    final field = MutationAttention(
      ack: _FakeAck(),
    ).all.singleWhere((field) => field.name == 'attentionSettle');
    expect(
      () => field.resolve!(null, {}),
      throwsA(isA<UnauthorizedException>()),
    );
  });
}
