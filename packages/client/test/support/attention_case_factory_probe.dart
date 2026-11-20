import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';

import '../domain/attention/attention_case_test_support.dart';
import '../features/block/support/controllable_block_case.dart';
import 'attention_repository_fake_base.dart';
import 'test_realtime_sync.dart';

typedef AttentionCaseFactory =
    AttentionCase Function({
      AttentionRepositoryPort? repository,
      AttentionAccountPort? accounts,
      RealtimeSyncCase? realtimeSyncCase,
      BlockCase? blockCase,
      FeedSessionRegistry? feedSessions,
      Logger? logger,
      bool qaLatencyMeasurementEnabled,
    });

void registerAttentionCaseFactoryTests(AttentionCaseFactory buildCase) {
  test('default case has QA latency sampling disabled', () {
    // The launcher enables QA mode globally, so forwarding a null flag to
    // the constructor would accidentally enable sampling.
    final attention = buildCase();
    addTearDown(attention.dispose);
    expect(attention.qaHeadRefreshLatencies, isNull);
    expect(attention.lastQaHeadRefreshLatency, isNull);
  });

  test('omitted dependencies produce an inert independent case', () async {
    final first = buildCase();
    addTearDown(first.dispose);
    final second = buildCase();
    addTearDown(second.dispose);
    const destination = attentionCaseTestFeedDest;
    first.attachFeedSession(destination);
    second.attachFeedSession(destination);
    first.setSearch(destination, 'first session');

    expect(first.feedSession(destination).searchText, 'first session');
    expect(second.feedSession(destination).searchText, isEmpty);
    await first.refresh();
    expect(first.feedSession(destination).pages, isEmpty);
    expect(first.feedSession(destination).headRefreshError, isNull);
    expect(await first.liveObligationBeacons(), isEmpty);
  });

  test('a repository override alone serves Request history', () async {
    const beaconId = 'request-for-history';
    const cursor = 'older-history';
    final defaultCase = buildCase();
    addTearDown(defaultCase.dispose);
    // The existing fallback is an inert stub. Its history method fails if
    // called, making accidental dispatch to it visible during this load.
    await expectLater(
      () => defaultCase.requestHistory(beaconId: beaconId, cursor: cursor),
      throwsUnimplementedError,
    );

    final repository = _RecordingHistoryRepository();
    final attention = buildCase(repository: repository);
    addTearDown(attention.dispose);
    final page = await attention.requestHistory(
      beaconId: beaconId,
      cursor: cursor,
    );
    expect(repository.historyCalls, [(beaconId: beaconId, cursor: cursor)]);
    expect(page.items.single.id, 'history-from-supplied-repository');
  });

  test('supplied collaborators drive feed refreshes and QA reports', () async {
    final receiptIds = ['manual-refresh', 'reconnect', 'block-change'];
    final repository = AttentionCaseTestRepository();
    for (final id in receiptIds) {
      repository.pendingFetches.add(
        Completer<AttentionFeed>()..complete(
          attentionCaseTestFeed(
            items: [attentionCaseTestReceipt(id: id)],
          ),
        ),
      );
    }

    final accounts = AttentionCaseTestAccounts();
    final realtime = buildTestRealtimeSync();
    final block = ControllableBlockCase();
    final sessions = FeedSessionRegistry();
    final logger = Logger.detached('attention-factory-probe')
      ..level = Level.ALL;
    final logs = <LogRecord>[];
    final logSubscription = logger.onRecord.listen(logs.add);
    addTearDown(accounts.dispose);
    addTearDown(realtime.port.dispose);
    addTearDown(block.dispose);
    addTearDown(logSubscription.cancel);

    final attention = buildCase(
      repository: repository,
      accounts: accounts,
      realtimeSyncCase: realtime.case_,
      blockCase: block,
      feedSessions: sessions,
      logger: logger,
      qaLatencyMeasurementEnabled: true,
    );
    addTearDown(attention.dispose);
    final samples = <AttentionHeadRefreshLatency>[];
    final sampleStream = attention.qaHeadRefreshLatencies;
    expect(sampleStream, isNotNull);
    final sampleSubscription = sampleStream!.listen(samples.add);
    addTearDown(sampleSubscription.cancel);

    accounts.emit('account-a');
    await attentionCaseTestSettle();
    const destination = attentionCaseTestFeedDest;
    attention.attachFeedSession(destination);

    await attention.refresh();
    await attentionCaseTestSettle();
    expect(repository.fetchCalls, 1);
    expect(attention.feedSession(destination).headRefreshError, isNull);
    expect(
      sessions.session(destination).pages[AttentionView.all]!.items.single.id,
      receiptIds[0],
    );
    expect(samples, hasLength(1));
    expect(logs.single.message, contains('head_refresh_latency'));

    realtime.port.emitCatchUp();
    await attentionCaseTestSettle();
    expect(repository.fetchCalls, 2);
    expect(
      sessions.session(destination).pages[AttentionView.all]!.items.single.id,
      receiptIds[1],
    );

    block.emitBlock();
    await attentionCaseTestSettle();
    expect(repository.fetchCalls, 3);
    expect(
      sessions.session(destination).pages[AttentionView.all]!.items.single.id,
      receiptIds[2],
    );
  });
}

final class _RecordingHistoryRepository extends AttentionRepositoryFake {
  final historyCalls = <({String beaconId, String? cursor})>[];

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    historyCalls.add((beaconId: beaconId, cursor: cursor));
    return AttentionFeedPage(
      items: [attentionCaseTestReceipt(id: 'history-from-supplied-repository')],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
