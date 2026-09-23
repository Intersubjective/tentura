import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  Set<String> unread = const {};
  int needsYouTotal = 0;
  AttentionSurfaceSummary surfaceSummaryValue = const AttentionSurfaceSummary(
  );
  bool failMarkers = false;
  final markerQueries = <Set<String>>[];
  final pendingMarkers = <Completer<Set<String>>>[];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: AttentionSummary(needsYouTotal: needsYouTotal),
    page: const AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) {
    markerQueries.add(Set<String>.from(beaconIds));
    if (pendingMarkers.isNotEmpty) return pendingMarkers.removeAt(0).future;
    if (failMarkers) return Future.error(StateError('offline'));
    return Future.value(unread.intersection(beaconIds));
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      surfaceSummaryValue;

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  late _Accounts accounts;
  late _Repository repository;
  late TestRealtimeSyncPort realtime;
  late AttentionCase attention;
  late HomeAttentionCubit home;

  setUp(() {
    accounts = _Accounts();
    repository = _Repository();
    final sync = buildTestRealtimeSync();
    realtime = sync.port;
    attention = AttentionCase(
      repository,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('home-attention-test'),
    );
    home = HomeAttentionCubit(
      attention,
      accounts,
      Logger('home-attention-test'),
    );
  });

  tearDown(() async {
    await home.close();
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  test(
    'projects unread ids with My Work precedence, on every tab',
    () async {
      repository.unread = {'inbox', 'work', 'shared'};
      accounts.emit('U1');
      await _settle();

      home.reportInboxSnapshot(
        accountId: 'U1',
        beaconIds: {'inbox', 'shared'},
        loaded: true,
      );
      home.reportMyWorkSnapshot(
        accountId: 'U1',
        beaconIds: {'work', 'shared'},
        loaded: true,
      );
      await _settle();

      expect(home.state.inboxMarkerIds, {'inbox'});
      expect(home.state.myWorkMarkerIds, {'work', 'shared'});
      // U14c / §6: a dot reports marked Requests on its surface. Opening the
      // tab is not clearing them, so neither dot depends on the active tab.
      expect(home.state.hasInboxDot, isTrue);
      expect(home.state.hasMyWorkDot, isTrue);

      home.setActiveHomeTab(HomeTab.inbox);
      expect(home.state.hasInboxDot, isTrue);
      expect(home.state.hasMyWorkDot, isTrue);
    },
  );

  test(
    'losing surface membership suppresses a stale marker immediately',
    () async {
      repository.unread = {'B1'};
      accounts.emit('U1');
      await _settle();
      home.reportInboxSnapshot(
        accountId: 'U1',
        beaconIds: {'B1'},
        loaded: true,
      );
      home.reportMyWorkSnapshot(
        accountId: 'U1',
        beaconIds: const {},
        loaded: true,
      );
      await _settle();
      expect(home.state.isInboxBeaconMarked('B1'), isTrue);

      final pending = Completer<Set<String>>();
      repository.pendingMarkers.add(pending);
      home.reportInboxSnapshot(
        accountId: 'U1',
        beaconIds: const {},
        loaded: true,
      );

      expect(home.state.isInboxBeaconMarked('B1'), isFalse);
      expect(home.state.hasInboxDot, isFalse);
      pending.complete(const {});
      await _settle();
      expect(home.state.inboxMarkerIds, isEmpty);
    },
  );

  test(
    'unknown or failed projections conservatively suppress markers',
    () async {
      repository
        ..unread = {'B1'}
        ..failMarkers = true;
      accounts.emit('U1');
      await _settle();

      home.reportInboxSnapshot(
        accountId: 'U1',
        beaconIds: {'B1'},
        loaded: true,
      );
      await _settle();
      expect(home.state.projectionReady, isFalse);
      expect(repository.markerQueries, isEmpty);

      home.reportMyWorkSnapshot(
        accountId: 'U1',
        beaconIds: const {},
        loaded: true,
      );
      await _settle();
      expect(home.state.projectionReady, isFalse);
      expect(home.state.inboxMarkerIds, isEmpty);
    },
  );

  test('maps the §6 count into nav state', () async {
    // CHANGES IN U15R-e: the badge follows §6 `my desk.count`
    // (`surfaceMyDeskCount`), not the legacy unscoped `needsYouTotal`.
    // CHANGES IN U18c: that legacy total, and the `surfaceNeedsYouTotal`
    // state field mirroring it, are retired — the badge cannot read them.
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      myDeskCount: 2,
    );
    accounts.emit('U1');
    await _settle(20);

    expect(home.state.surfaceSummaryLoaded, isTrue);
    expect(home.state.surfaceMyDeskCount, 2);
    expect(home.state.showRedesignMyWorkObligationBadge, isTrue);
  });

  // CHANGES IN U18c: this was 'a legacy needsYouTotal alone does not raise
  // the badge'. The legacy total is retired, so the case it guarded against
  // is unexpressible; what remains is the live half — a zero §6 count shows
  // no number even with a loaded summary. A ported assertion, not a deletion.
  test('a zero my desk.count does not raise the badge', () async {
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      myDeskDot: true,
    );
    accounts.emit('U1');
    await _settle(20);

    expect(home.state.surfaceSummaryLoaded, isTrue);
    expect(home.state.surfaceMyDeskCount, 0);
    expect(home.state.showRedesignMyWorkObligationBadge, isFalse);
  });

  test('chunks the candidate union at the server request bound', () async {
    accounts.emit('U1');
    await _settle();
    final ids = {for (var i = 0; i < 501; i++) 'B$i'};

    home.reportInboxSnapshot(
      accountId: 'U1',
      beaconIds: ids,
      loaded: true,
    );
    home.reportMyWorkSnapshot(
      accountId: 'U1',
      beaconIds: const {},
      loaded: true,
    );
    await _settle();

    expect(repository.markerQueries.map((query) => query.length), [500, 1]);
    expect(home.state.projectionReady, isTrue);
  });
}
