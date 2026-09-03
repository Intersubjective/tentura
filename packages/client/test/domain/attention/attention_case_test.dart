import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/attention_ack_store.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import '../../support/test_realtime_sync.dart';
import '../../features/block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> dispose() => _changes.close();
}

final class _Repository implements AttentionRepositoryPort {
  final List<Completer<AttentionFeed>> pendingFetches = [];
  final List<Completer<int>> pendingMarkSeen = [];
  final List<Completer<int>> pendingMarkUnseen = [];
  final List<Completer<int>> pendingMarkAllSeen = [];
  final List<List<String>> markSeenCalls = [];
  final List<List<String>> markUnseenCalls = [];
  int markAllSeenCalls = 0;
  final List<Completer<int>> pendingSettles = [];
  final List<({String receiptId, String kind})> settles = [];
  final List<({AttentionView view, String? cursor, String? search})> fetches =
      [];
  final List<Set<String>> markerQueries = [];
  Set<String> unreadBeaconIds = const {};
  int fetchCalls = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) {
    fetchCalls++;
    fetches.add((view: view, cursor: cursor, search: search));
    return pendingFetches.removeAt(0).future;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async {
    markerQueries.add(Set<String>.from(beaconIds));
    return unreadBeaconIds.intersection(beaconIds);
  }

  @override
  Future<int> markAllSeen() {
    markAllSeenCalls++;
    return pendingMarkAllSeen.removeAt(0).future;
  }

  @override
  Future<int> markSeen(List<String> ids) {
    markSeenCalls.add(List<String>.from(ids));
    return pendingMarkSeen.removeAt(0).future;
  }

  @override
  Future<int> markUnseen(List<String> ids) {
    markUnseenCalls.add(List<String>.from(ids));
    return pendingMarkUnseen.removeAt(0).future;
  }

  @override
  Future<int> settle({required String receiptId, required String kind}) {
    settles.add((receiptId: receiptId, kind: kind));
    return pendingSettles.removeAt(0).future;
  }
}

AttentionFeed _feed({int unread = 1, List<AttentionReceipt>? items}) =>
    AttentionFeed(
      summary: AttentionSummary(unreadTotal: unread),
      page: AttentionFeedPage(items: items ?? [_receipt()]),
    );

AttentionReceipt _receipt({String id = 'receipt-1'}) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Title',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
);

AttentionReceipt _seenReceipt({String id = 'receipt-1'}) =>
    _receipt(id: id).copyWith(seenAt: DateTime.utc(2026, 1, 2));

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('ack store overlays unseen until that generation confirms', () {
    final store = AttentionAckStore()..resetForAccount('account-a');
    final seen = _seenReceipt();
    final token = store.markUnseen([seen.id]);
    expect(store.apply(seen).isSeen, isFalse);
    store.markCommitted([seen.id], token);
    expect(store.apply(_receipt()).isSeen, isFalse);
    expect(store.apply(_seenReceipt()).isSeen, isTrue);
  });

  test('ack store stale unseen fetch does not confirm an uncommitted overlay', () {
    final store = AttentionAckStore()
      ..resetForAccount('account-a')
      ..markUnseen(['receipt-1']);
    expect(store.apply(_receipt()).isSeen, isFalse);
    expect(store.isOptimisticallyUnseen('receipt-1'), isTrue);
  });

  test('ack store resets optimistic state on account changes', () {
    final store = AttentionAckStore()
      ..resetForAccount('account-a')
      ..markSeen(['receipt-1']);
    expect(store.apply(_receipt()).isSeen, isTrue);

    store.resetForAccount('account-b');
    expect(store.apply(_receipt()).isSeen, isFalse);
  });

  group('AttentionCase', () {
    late _Repository repository;
    late _Accounts accounts;
    late TestRealtimeSyncPort realtimePort;
    late RealtimeSyncCase realtimeCase;
    late AttentionCase attention;

    setUp(() {
      repository = _Repository();
      accounts = _Accounts();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      realtimeCase = realtime.case_;
      attention = AttentionCase(
        repository,
        accounts,
        realtimeCase,
        noopBlockCase(),
        Logger('attention-case-test'),
      );
    });

    tearDown(() async {
      await attention.dispose();
      await accounts.dispose();
      await realtimePort.dispose();
    });

    test(
      'forwards semantic unread Beacon queries without surface labels',
      () async {
        repository.unreadBeaconIds = {'B1', 'B3'};

        expect(await attention.unreadForBeacons({'B1', 'B2'}), {'B1'});
        expect(repository.markerQueries, [
          {'B1', 'B2'},
        ]);
      },
    );

    test(
      'coalesces notification hints to one in-flight refresh and one rerun',
      () async {
        final first = Completer<AttentionFeed>();
        final second = Completer<AttentionFeed>();
        repository.pendingFetches.addAll([first, second]);
        accounts.emit('account-a');
        await _settle();
        expect(repository.fetchCalls, 1);

        for (var index = 0; index < 20; index++) {
          realtimePort.emitChange(
            const RealtimeEntityChange(
              kind: RealtimeEntityKind.notification,
              aggregateId: 'account-a',
              operation: RealtimeOperation.insert,
              source: RealtimeChangeSource.serverInvalidation,
            ),
          );
        }
        await _settle();
        expect(repository.fetchCalls, 1);

        first.complete(_feed());
        await _settle();
        expect(repository.fetchCalls, 2);

        second.complete(_feed());
        await _settle();
        expect(repository.fetchCalls, 2);
      },
    );

    test('catch-up refreshes the feed head', () async {
      final first = Completer<AttentionFeed>();
      final second = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([first, second]);
      accounts.emit('account-a');
      await _settle();
      first.complete(_feed());
      await _settle();

      realtimePort.emitCatchUp();
      await _settle();
      expect(repository.fetchCalls, 2);
      second.complete(_feed(unread: 2));
      await _settle();
      expect(attention.snapshot.summary.unreadTotal, 2);
    });

    test('catch-up keeps one UI receipt for each stable receipt id', () async {
      final initial = Completer<AttentionFeed>();
      final reconnect = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([initial, reconnect]);
      accounts.emit('account-a');
      await _settle();
      initial.complete(_feed(items: [_receipt(id: 'existing')]));
      await _settle();

      realtimePort.emitCatchUp();
      await _settle();
      reconnect.complete(
        _feed(
          unread: 2,
          items: [
            _receipt(id: 'new-after-reconnect'),
            _receipt(id: 'existing'),
            _receipt(id: 'existing'),
          ],
        ),
      );
      await _settle();

      expect(
        attention.snapshot.pages[AttentionView.all]!.items.map(
          (item) => item.id,
        ),
        ['new-after-reconnect', 'existing'],
      );
    });

    test('records QA head refresh latency for the newest receipt', () async {
      final qaRepository = _Repository();
      final qaAccounts = _Accounts();
      final first = Completer<AttentionFeed>();
      final second = Completer<AttentionFeed>();
      qaRepository.pendingFetches.addAll([first, second]);
      final qaAttention = AttentionCase(
        qaRepository,
        qaAccounts,
        realtimeCase,
        noopBlockCase(),
        Logger('attention-case-qa-latency-test'),
        qaLatencyMeasurementEnabled: true,
      );
      addTearDown(qaAttention.dispose);
      addTearDown(qaAccounts.dispose);
      final samples = <AttentionHeadRefreshLatency>[];
      final sub = qaAttention.qaHeadRefreshLatencies!.listen(samples.add);

      qaAccounts.emit('account-a');
      await _settle();
      expect(qaRepository.fetchCalls, 1);
      first.complete(
        _feed(
          items: [
            _receipt(id: 'older').copyWith(
              createdAt: DateTime.now().toUtc().subtract(
                const Duration(seconds: 30),
              ),
            ),
            _receipt(id: 'newer').copyWith(
              createdAt: DateTime.now().toUtc().subtract(
                const Duration(seconds: 5),
              ),
            ),
          ],
        ),
      );
      await _settle();

      expect(samples, hasLength(1));
      expect(samples.single.latency, greaterThanOrEqualTo(const Duration(seconds: 4)));
      expect(samples.single.latency, lessThan(const Duration(seconds: 10)));
      expect(qaAttention.lastQaHeadRefreshLatency, samples.single);

      await sub.cancel();
    });

    test('block change refreshes the feed head', () async {
      final blockRepository = _Repository();
      final blockAccounts = _Accounts();
      final blockCase = ControllableBlockCase();
      final blockAttention = AttentionCase(
        blockRepository,
        blockAccounts,
        realtimeCase,
        blockCase,
        Logger('attention-case-block-test'),
      );
      addTearDown(blockAttention.dispose);
      addTearDown(blockAccounts.dispose);
      addTearDown(blockCase.dispose);

      final first = Completer<AttentionFeed>();
      final second = Completer<AttentionFeed>();
      blockRepository.pendingFetches.addAll([first, second]);
      blockAccounts.emit('account-a');
      await _settle();
      expect(blockRepository.fetchCalls, 1);

      blockCase.emitBlock();
      await _settle();
      expect(blockRepository.fetchCalls, 1);

      first.complete(_feed());
      await _settle();
      expect(blockRepository.fetchCalls, 2);

      second.complete(_feed());
      await _settle();
      expect(blockRepository.fetchCalls, 2);
    });

    test('account changes reset state and drop stale responses', () async {
      final stale = Completer<AttentionFeed>();
      final fresh = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([stale, fresh]);
      accounts.emit('account-a');
      await _settle();
      accounts.emit('account-b');
      await _settle();
      expect(attention.snapshot.pages, isEmpty);

      stale.complete(_feed(items: [_receipt(id: 'from-a')]));
      await _settle();
      expect(repository.fetchCalls, 2);
      fresh.complete(_feed(items: [_receipt(id: 'from-b')]));
      await _settle();
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.id,
        'from-b',
      );
    });

    test(
      'optimistic acknowledgements survive stale feed reconciliation',
      () async {
        final initial = Completer<AttentionFeed>();
        final refresh = Completer<AttentionFeed>();
        final mark = Completer<int>();
        repository.pendingFetches.addAll([initial, refresh]);
        repository.pendingMarkSeen.add(mark);
        accounts.emit('account-a');
        await _settle();
        initial.complete(_feed());
        await _settle();

        final command = attention.markSeen(['receipt-1']);
        await _settle();
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
          isTrue,
        );
        expect(attention.snapshot.summary.unreadTotal, 0);

        mark.complete(1);
        await command;
        await _settle();
        refresh.complete(_feed());
        await _settle();
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
          isTrue,
        );
      },
    );

    test(
      'optimistic mark-seen decrements server unread not cached length',
      () async {
        final initial = Completer<AttentionFeed>();
        final unreadPage = Completer<AttentionFeed>();
        repository.pendingFetches.addAll([initial, unreadPage]);
        accounts.emit('account-a');
        await _settle();
        final cached = [
          for (var i = 0; i < 50; i++) _receipt(id: 'r$i'),
        ];
        initial.complete(_feed(unread: 100, items: cached));
        await _settle();

        attention.setActiveView(AttentionView.unread);
        await _settle();
        unreadPage.complete(_feed(unread: 100, items: cached));
        await _settle();

        repository.pendingMarkSeen.add(Completer<int>());
        unawaited(attention.markSeen(['r0']));
        await _settle();

        expect(attention.snapshot.summary.unreadTotal, 99);
        expect(
          attention.snapshot.pages[AttentionView.unread]!.items.map(
            (receipt) => receipt.id,
          ),
          isNot(contains('r0')),
        );
      },
    );

    test(
      'mark-all is optimistic and restores unread rows after failure',
      () async {
        final initial = Completer<AttentionFeed>();
        final rejected = Completer<int>();
        repository.pendingFetches.add(initial);
        repository.pendingMarkAllSeen.add(rejected);
        accounts.emit('account-a');
        await _settle();
        initial.complete(
          _feed(
            unread: 2,
            items: [
              _receipt(id: 'one'),
              _receipt(id: 'two'),
            ],
          ),
        );
        await _settle();

        final command = attention.markAllSeen();
        await _settle();
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.every(
            (receipt) => receipt.isSeen,
          ),
          isTrue,
        );
        expect(attention.snapshot.summary.unreadTotal, 0);

        rejected.completeError(StateError('offline'));
        await expectLater(command, throwsStateError);
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.every(
            (receipt) => !receipt.isSeen,
          ),
          isTrue,
        );
        expect(attention.snapshot.summary.unreadTotal, 2);
      },
    );

    test('optimistic unsee restores unread and rolls back on failure', () async {
      final initial = Completer<AttentionFeed>();
      final rejected = Completer<int>();
      repository.pendingFetches.add(initial);
      repository.pendingMarkUnseen.add(rejected);
      accounts.emit('account-a');
      await _settle();
      initial.complete(_feed(unread: 0, items: [_seenReceipt()]));
      await _settle();

      final command = attention.markUnseen(['receipt-1']);
      await _settle();
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isFalse,
      );
      expect(attention.snapshot.summary.unreadTotal, 1);

      rejected.completeError(StateError('offline'));
      await expectLater(command, throwsStateError);
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isTrue,
      );
      expect(attention.snapshot.summary.unreadTotal, 0);
    });

    test('queued unsee runs after in-flight markSeen', () async {
      final initial = Completer<AttentionFeed>();
      final seenRefresh = Completer<AttentionFeed>();
      final unseenRefresh = Completer<AttentionFeed>();
      final mark = Completer<int>();
      final unsee = Completer<int>();
      repository.pendingFetches.addAll([initial, seenRefresh, unseenRefresh]);
      repository.pendingMarkSeen.add(mark);
      repository.pendingMarkUnseen.add(unsee);
      accounts.emit('account-a');
      await _settle();
      initial.complete(_feed());
      await _settle();

      final seenCommand = attention.markSeen(['receipt-1']);
      await _settle();
      final unseenCommand = attention.markUnseen(['receipt-1']);
      await _settle();
      expect(repository.markUnseenCalls, isEmpty);

      mark.complete(1);
      await seenCommand;
      await _settle();
      expect(repository.markUnseenCalls, [
        ['receipt-1'],
      ]);
      unsee.complete(1);
      seenRefresh.complete(_feed(unread: 0, items: [_seenReceipt()]));
      unseenRefresh.complete(_feed());
      await unseenCommand;
      await _settle();
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isFalse,
      );
    });

    test('zero-row unsee drops overlay instead of pinning unread', () async {
      final initial = Completer<AttentionFeed>();
      final refresh = Completer<AttentionFeed>();
      final unsee = Completer<int>();
      repository.pendingFetches.addAll([initial, refresh]);
      repository.pendingMarkUnseen.add(unsee);
      accounts.emit('account-a');
      await _settle();
      initial.complete(_feed(unread: 0, items: [_seenReceipt()]));
      await _settle();

      final command = attention.markUnseen(['receipt-1']);
      await _settle();
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isFalse,
      );

      unsee.complete(0);
      refresh.complete(_feed(unread: 0, items: [_seenReceipt()]));
      await command;
      await _settle();
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isTrue,
      );
      expect(attention.snapshot.summary.unreadTotal, 0);
    });

    test(
      'refresh during queued unsee keeps overlay unread total',
      () async {
        final initial = Completer<AttentionFeed>();
        final midRefresh = Completer<AttentionFeed>();
        final afterSeen = Completer<AttentionFeed>();
        final afterUnsee = Completer<AttentionFeed>();
        final mark = Completer<int>();
        final unsee = Completer<int>();
        repository.pendingFetches.addAll([
          initial,
          midRefresh,
          afterSeen,
          afterUnsee,
        ]);
        repository.pendingMarkSeen.add(mark);
        repository.pendingMarkUnseen.add(unsee);
        accounts.emit('account-a');
        await _settle();
        initial.complete(_feed());
        await _settle();

        unawaited(attention.markSeen(['receipt-1']));
        await _settle();
        unawaited(attention.markUnseen(['receipt-1']));
        await _settle();
        expect(attention.snapshot.summary.unreadTotal, 1);
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
          isFalse,
        );

        realtimePort.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.notification,
            aggregateId: 'account-a',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await _settle();
        midRefresh.complete(_feed(unread: 0, items: [_seenReceipt()]));
        await _settle();
        expect(attention.snapshot.summary.unreadTotal, 1);
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
          isFalse,
        );

        mark.complete(1);
        await _settle();
        afterSeen.complete(_feed(unread: 0, items: [_seenReceipt()]));
        unsee.complete(1);
        afterUnsee.complete(_feed());
        await _settle();
        expect(attention.snapshot.summary.unreadTotal, 1);
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
          isFalse,
        );
      },
    );

    test('markAllSeen waits so a later unsee still wins', () async {
      final initial = Completer<AttentionFeed>();
      final allSeen = Completer<int>();
      final unsee = Completer<int>();
      final afterAllSeen = Completer<AttentionFeed>();
      final afterUnsee = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([initial, afterAllSeen, afterUnsee]);
      repository.pendingMarkAllSeen.add(allSeen);
      repository.pendingMarkUnseen.add(unsee);
      accounts.emit('account-a');
      await _settle();
      initial.complete(
        _feed(
          unread: 1,
          items: [_receipt()],
        ),
      );
      await _settle();

      unawaited(attention.markAllSeen());
      await _settle();
      final unseenCommand = attention.markUnseen(['receipt-1']);
      await _settle();
      expect(repository.markUnseenCalls, isEmpty);
      expect(repository.markAllSeenCalls, 1);

      allSeen.complete(1);
      await _settle();
      expect(repository.markUnseenCalls, [
        ['receipt-1'],
      ]);
      unsee.complete(1);
      afterAllSeen.complete(_feed(unread: 0, items: [_seenReceipt()]));
      afterUnsee.complete(_feed());
      await unseenCommand;
    });

    test('in-flight unsee delays markAllSeen', () async {
      final initial = Completer<AttentionFeed>();
      final unsee = Completer<int>();
      final allSeen = Completer<int>();
      final afterUnsee = Completer<AttentionFeed>();
      final afterAllSeen = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([initial, afterUnsee, afterAllSeen]);
      repository.pendingMarkUnseen.add(unsee);
      repository.pendingMarkAllSeen.add(allSeen);
      accounts.emit('account-a');
      await _settle();
      initial.complete(_feed(unread: 0, items: [_seenReceipt()]));
      await _settle();

      unawaited(attention.markUnseen(['receipt-1']));
      await _settle();
      unawaited(attention.markAllSeen());
      await _settle();
      expect(repository.markUnseenCalls, [
        ['receipt-1'],
      ]);
      expect(repository.markAllSeenCalls, 0);
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isTrue,
      );
      expect(attention.snapshot.summary.unreadTotal, 0);

      unsee.complete(1);
      afterUnsee.complete(_feed());
      await _settle();
      expect(repository.markAllSeenCalls, 1);
      allSeen.complete(1);
      afterAllSeen.complete(_feed(unread: 0, items: [_seenReceipt()]));
      await _settle();
      expect(
        attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
        isTrue,
      );
      expect(attention.snapshot.summary.unreadTotal, 0);
    });

    test(
      'account switch drops queued markAllSeen before it can hit the next account',
      () async {
        final first = Completer<AttentionFeed>();
        final second = Completer<AttentionFeed>();
        final allSeen = Completer<int>();
        repository.pendingFetches.addAll([first, second]);
        repository.pendingMarkAllSeen.add(allSeen);
        accounts.emit('account-a');
        await _settle();
        first.complete(_feed());
        await _settle();

        unawaited(attention.markAllSeen());
        await _settle();
        accounts.emit('account-b');
        await _settle();
        allSeen.complete(1);
        await _settle();
        second.complete(_feed(items: [_receipt(id: 'from-b')]));
        await _settle();
        expect(repository.markAllSeenCalls, 1);
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.id,
          'from-b',
        );
        expect(
          attention.snapshot.pages[AttentionView.all]!.items.single.isSeen,
          isFalse,
        );
      },
    );

    test(
      'settling a live obligation refreshes without changing unread state',
      () async {
        final initial = Completer<AttentionFeed>();
        final refresh = Completer<AttentionFeed>();
        final settle = Completer<int>();
        repository.pendingFetches.addAll([initial, refresh]);
        repository.pendingSettles.add(settle);
        accounts.emit('account-a');
        await _settle();
        initial.complete(
          _feed(
            items: [_receipt().copyWith(requiresAction: true)],
          ),
        );
        await _settle();

        final command = attention.settle('receipt-1');
        await _settle();
        expect(repository.settles, [
          (receiptId: 'receipt-1', kind: 'resolved'),
        ]);
        expect(attention.snapshot.summary.unreadTotal, 1);

        settle.complete(1);
        await _settle();
        expect(repository.fetchCalls, 2);
        refresh.complete(_feed(items: const []));
        await command;
        expect(attention.snapshot.summary.unreadTotal, 1);
      },
    );

    test('search normalizes and survives pagination', () async {
      final initial = Completer<AttentionFeed>();
      final searched = Completer<AttentionFeed>();
      final next = Completer<AttentionFeed>();
      repository.pendingFetches.addAll([initial, searched, next]);
      accounts.emit('account-a');
      await _settle();
      initial.complete(
        AttentionFeed(
          summary: const AttentionSummary(unreadTotal: 2),
          page: AttentionFeedPage(
            items: [_receipt(id: 'one')],
            nextCursor: 'page-two',
          ),
        ),
      );
      await _settle();

      attention.setSearch('  needle  ');
      await _settle();
      searched.complete(
        AttentionFeed(
          summary: const AttentionSummary(unreadTotal: 2),
          page: AttentionFeedPage(
            items: [_receipt(id: 'one')],
            nextCursor: 'page-two',
          ),
        ),
      );
      await _settle();
      final loadNext = attention.fetchNextPage();
      await _settle();
      next.complete(_feed(items: [_receipt(id: 'two')]));
      await loadNext;

      expect(repository.fetches, [
        (view: AttentionView.all, cursor: null, search: null),
        (view: AttentionView.all, cursor: null, search: 'needle'),
        (view: AttentionView.all, cursor: 'page-two', search: 'needle'),
      ]);
    });

    test(
      'room-bridge notification fan-out reconciles another client after an ack',
      () async {
        final secondRepository = _Repository();
        final secondAccounts = _Accounts();
        final secondRealtime = buildTestRealtimeSync();
        final secondAttention = AttentionCase(
          secondRepository,
          secondAccounts,
          secondRealtime.case_,
          noopBlockCase(),
          Logger('attention-case-second-client-test'),
        );
        addTearDown(secondAttention.dispose);
        addTearDown(secondAccounts.dispose);
        addTearDown(secondRealtime.port.dispose);

        final first = Completer<AttentionFeed>();
        final second = Completer<AttentionFeed>();
        repository.pendingFetches.add(first);
        secondRepository.pendingFetches.add(second);
        accounts.emit('account-a');
        secondAccounts.emit('account-a');
        await _settle();
        first.complete(_feed());
        second.complete(_feed());
        await _settle();

        final remoteRefresh = Completer<AttentionFeed>();
        secondRepository.pendingFetches.add(remoteRefresh);
        // The server room bridge publishes the same account-scoped notification
        // hint as explicit acknowledgement writes.
        secondRealtime.port.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.notification,
            aggregateId: 'account-a',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await _settle();
        remoteRefresh.complete(_feed(unread: 0, items: [_seenReceipt()]));
        await _settle();

        expect(secondAttention.snapshot.summary.unreadTotal, 0);
        expect(
          secondAttention
              .snapshot
              .pages[AttentionView.all]!
              .items
              .single
              .isSeen,
          isTrue,
        );
      },
    );
  });
}
