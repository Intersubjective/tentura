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
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import '../../support/test_realtime_sync.dart';

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
  final List<Completer<int>> pendingMarkAllSeen = [];
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
  Future<int> markAllSeen() => pendingMarkAllSeen.removeAt(0).future;

  @override
  Future<int> markSeen(List<String> ids) => pendingMarkSeen.removeAt(0).future;

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
    late AttentionCase attention;

    setUp(() {
      repository = _Repository();
      accounts = _Accounts();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      attention = AttentionCase(
        repository,
        accounts,
        realtime.case_,
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
