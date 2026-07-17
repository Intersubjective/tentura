import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

import '../../support/test_realtime_sync.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository implements AttentionRepositoryPort {
  Set<String> unread = const {};
  bool failMarkers = false;
  final markerQueries = <Set<String>>[];
  final pendingMarkers = <Completer<Set<String>>>[];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) {
    markerQueries.add(Set<String>.from(beaconIds));
    if (pendingMarkers.isNotEmpty) return pendingMarkers.removeAt(0).future;
    if (failMarkers) return Future.error(StateError('offline'));
    return Future.value(unread.intersection(beaconIds));
  }

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
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
    'projects unread ids with My Work precedence and hides active-tab dots',
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
      expect(home.state.hasInboxDot, isTrue);
      expect(home.state.hasMyWorkDot, isFalse);

      home.setActiveHomeTab(HomeTab.inbox);
      expect(home.state.hasInboxDot, isFalse);
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
