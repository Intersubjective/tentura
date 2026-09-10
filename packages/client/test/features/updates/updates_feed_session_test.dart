import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository implements AttentionRepositoryPort {
  final List<Completer<AttentionFeed>> pendingFetches = [];
  final List<({AttentionView view, String? cursor, String? search})> fetches =
      [];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) {
    fetches.add((view: view, cursor: cursor, search: search));
    return pendingFetches.removeAt(0).future;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

AttentionReceipt _receipt(String id) => AttentionReceipt(
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

AttentionFeed _feed({required String receiptId, int unread = 1}) =>
    AttentionFeed(
      summary: AttentionSummary(unreadTotal: unread),
      page: AttentionFeedPage(items: [_receipt(receiptId)]),
    );

Future<void> _pump([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Accounts accounts;
  late _Repository repository;
  late FeedSessionRegistry feedSessions;
  late AttentionCase attention;

  setUp(() {
    accounts = _Accounts();
    repository = _Repository();
    feedSessions = FeedSessionRegistry();
    final sync = buildTestRealtimeSync();
    attention = AttentionCase(
      repository,
      accounts,
      sync.case_,
      noopBlockCase(),
      feedSessions,
      Logger('updates-feed-session-test'),
    );
  });

  tearDown(() async {
    await attention.dispose();
    await accounts.close();
  });

  test('destinations keep independent view and search but share unread total',
      () async {
    const destA = AttentionFeedDestinationId.activity;
    const destB = AttentionFeedDestinationId.myWorkObligations;

    accounts.emit('account-a');
    await _pump();
    final bootA = Completer<AttentionFeed>();
    final bootB = Completer<AttentionFeed>();
    final unreadA = Completer<AttentionFeed>();
    final searchB = Completer<AttentionFeed>();
    repository.pendingFetches.addAll([bootA, bootB, unreadA, searchB]);

    final cubitA = UpdatesFeedCubit(
      destinationId: destA,
      attention: attention,
      logger: Logger('session-a'),
    );
    final cubitB = UpdatesFeedCubit(
      destinationId: destB,
      attention: attention,
      logger: Logger('session-b'),
    );

    await _pump();
    bootA.complete(_feed(receiptId: 'shared-a'));
    bootB.complete(_feed(receiptId: 'shared-b'));
    await _pump();

    expect(cubitA.state.summary.unreadTotal, 1);
    expect(cubitB.state.summary.unreadTotal, 1);
    expect(cubitA.state.items.single.id, 'shared-a');
    expect(cubitB.state.items.single.id, 'shared-b');

    cubitA.setView(AttentionView.unread);
    await _pump();
    unreadA.complete(_feed(receiptId: 'unread-a'));
    await _pump();
    expect(cubitA.state.view, AttentionView.unread);
    expect(cubitB.state.view, AttentionView.all);

    cubitB.setSearch('needle');
    await _pump();
    searchB.complete(_feed(receiptId: 'needle-b'));
    await _pump();
    expect(cubitB.state.searchText, 'needle');
    expect(cubitA.state.searchText, isEmpty);

    await cubitA.close();
    await cubitB.close();
  });

  test('dispose and remount restores prior view and search for a destination',
      () async {
    const dest = AttentionFeedDestinationId.activity;

    accounts.emit('account-a');
    await _pump();
    final initial = Completer<AttentionFeed>();
    final needsYou = Completer<AttentionFeed>();
    final searched = Completer<AttentionFeed>();
    final remounted = Completer<AttentionFeed>();
    repository.pendingFetches.addAll([initial, needsYou, searched, remounted]);

    var cubit = UpdatesFeedCubit(
      destinationId: dest,
      attention: attention,
      logger: Logger('session-remount'),
    );
    await _pump();
    initial.complete(_feed(receiptId: 'initial'));
    await _pump();

    await cubit.setView(AttentionView.needsYou);
    await _pump();
    needsYou.complete(_feed(receiptId: 'needs'));
    await _pump();
    cubit.setSearch('keep-me');
    await _pump();
    searched.complete(_feed(receiptId: 'searched'));
    await _pump();

    await cubit.close();

    cubit = UpdatesFeedCubit(
      destinationId: dest,
      attention: attention,
      logger: Logger('session-remount-2'),
    );
    await _pump();
    remounted.complete(_feed(receiptId: 'remounted'));
    await _pump();

    expect(cubit.state.view, AttentionView.needsYou);
    expect(cubit.state.searchText, 'keep-me');

    await cubit.close();
  });

  test('stale fetch does not apply after view changes bump generation', () async {
    const dest = AttentionFeedDestinationId.activity;

    final initial = Completer<AttentionFeed>();
    final staleUnread = Completer<AttentionFeed>();
    final freshAll = Completer<AttentionFeed>();
    repository.pendingFetches.addAll([initial, staleUnread, freshAll]);

    final cubit = UpdatesFeedCubit(
      destinationId: dest,
      attention: attention,
      logger: Logger('session-stale'),
    );
    accounts.emit('account-a');
    await _pump();
    initial.complete(_feed(receiptId: 'first'));
    await _pump();

    await cubit.setView(AttentionView.unread);
    await _pump();
    await cubit.setView(AttentionView.all);
    await _pump();
    freshAll.complete(_feed(receiptId: 'fresh-all'));
    await _pump();

    staleUnread.complete(_feed(receiptId: 'stale-unread'));
    await _pump();

    expect(cubit.state.view, AttentionView.all);
    expect(cubit.state.items.single.id, 'fresh-all');

    await cubit.close();
  });
}
