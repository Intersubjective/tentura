import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_cursor.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import 'attention_case_test_support.dart';

String _cursor(int version) => base64Url
    .encode(utf8.encode(jsonEncode({'v': version, 'k': '2026-09-19'})))
    .replaceAll('=', '');

void main() {
  late _CursorRepository repository;
  late AttentionCaseTestAccounts accounts;
  late TestRealtimeSyncPort realtimePort;
  late FeedSessionRegistry sessions;
  late AttentionCase attention;

  Future<void> loadHead(String? nextCursor) async {
    repository.next = _feed(['r-1'], nextCursor: nextCursor);
    attention.attachFeedSession(attentionCaseTestFeedDest);
    accounts.emit('account-1');
    await attentionCaseTestSettle();
  }

  setUp(() {
    repository = _CursorRepository();
    accounts = AttentionCaseTestAccounts();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    sessions = FeedSessionRegistry();
    attention = AttentionCase(
      repository,
      accounts,
      realtime.case_,
      noopBlockCase(),
      sessions,
      Logger('attention-cursor-reset-test'),
      qaLatencyMeasurementEnabled: false,
    );
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.dispose();
    await realtimePort.dispose();
  });

  test('the cursor contract recognises an older generation', () {
    expect(AttentionCursorContract.versionOf(_cursor(1)), 1);
    expect(AttentionCursorContract.isCurrent(_cursor(1)), isFalse);
    expect(AttentionCursorContract.isCurrent(_cursor(2)), isTrue);
    expect(AttentionCursorContract.isKnownStale(_cursor(1)), isTrue);
    expect(AttentionCursorContract.isKnownStale(_cursor(2)), isFalse);
    expect(
      AttentionCursorContract.isKnownStale('opaque-not-json'),
      isFalse,
      reason: 'an unreadable cursor is not evidence of an older generation',
    );
  });

  test('a held v1 cursor is never sent, and never yields a page', () async {
    await loadHead(_cursor(1));
    final generationBefore = attention
        .feedSession(attentionCaseTestFeedDest)
        .requestGeneration;
    repository.cursors.clear();
    repository.next = _feed(['r-2']);

    await attention.fetchNextPage(destinationId: attentionCaseTestFeedDest);
    await attentionCaseTestSettle();

    expect(
      repository.cursors,
      isNot(contains(_cursor(1))),
      reason: 'the dead cursor is never sent',
    );
    expect(repository.cursors, [null], reason: 'head refetch, not a tail');
    final session = attention.feedSession(attentionCaseTestFeedDest);
    expect(session.requestGeneration, generationBefore + 1);
    expect(session.pages[AttentionView.all]?.nextCursor, isNull);
    expect(
      session.pages[AttentionView.all]?.items.map((item) => item.id),
      ['r-2'],
      reason: 'the head replaced the page rather than appending to it',
    );
  });

  test('a cursor the server refuses resets the session once', () async {
    await loadHead(_cursor(2));
    repository.cursors.clear();
    repository.failNextWith = ArgumentError('invalid attention cursor');
    repository.next = _feed(['r-2']);

    await attention.fetchNextPage(destinationId: attentionCaseTestFeedDest);
    await attentionCaseTestSettle();

    expect(
      repository.cursors,
      [_cursor(2), null],
      reason: 'the refused tail is not retried; a head refetch replaces it',
    );
    final session = attention.feedSession(attentionCaseTestFeedDest);
    expect(session.pages[AttentionView.all]?.nextCursor, isNull);
    expect(
      session.pages[AttentionView.all]?.items.map((item) => item.id),
      ['r-2'],
    );
  });

  test('a tail failure that is not a cursor refusal still surfaces', () async {
    await loadHead(_cursor(2));
    repository.failNextWith = StateError('offline');

    await expectLater(
      attention.fetchNextPage(destinationId: attentionCaseTestFeedDest),
      throwsA(isA<StateError>()),
    );
  });
}

AttentionFeed _feed(List<String> ids, {String? nextCursor}) => AttentionFeed(
  summary: AttentionSummary(unreadTotal: ids.length),
  page: AttentionFeedPage(
    nextCursor: nextCursor,
    items: [
      for (final id in ids) attentionCaseTestReceipt(id: id),
    ],
  ),
);

final class _CursorRepository extends AttentionRepositoryFake {
  final List<String?> cursors = [];
  AttentionFeed next = AttentionFeed(
    summary: const AttentionSummary(),
    page: const AttentionFeedPage(),
  );
  Object? failNextWith;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    cursors.add(cursor);
    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      throw failure;
    }
    return next;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => const {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeen(List<String> ids) async => ids.length;

  @override
  Future<int> markUnseen(List<String> ids) async => ids.length;

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

