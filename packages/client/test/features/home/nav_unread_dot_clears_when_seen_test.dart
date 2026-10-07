// The My Work and Activity navigation dots must follow what the viewer has
// seen: opening an item clears the dot without a reload, and a marker for a
// Request the viewer can no longer open cannot hold it on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/widget/inbox_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/my_work_navbar_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

/// A server whose unread state moves when something is marked seen, and which
/// stops reporting Requests the viewer lost access to.
final class _Server extends AttentionRepositoryFake {
  /// Unread Request ids, as `unreadForBeacons` reports them.
  Set<String> unreadBeacons = {};

  /// Request ids the viewer can still open.
  Set<String> readable = {};

  /// Receipt id -> Request id.
  Map<String, String> receiptBeacon = {};

  bool myDeskDot = false;
  bool forYouDot = false;

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      AttentionSurfaceSummary(myDeskDot: myDeskDot, forYouDot: forYouDot);

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unreadBeacons.intersection(beaconIds).intersection(readable);

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeenForBeacon(String beaconId) async {
    unreadBeacons.remove(beaconId);
    if (!unreadBeacons.any(readable.contains)) {
      myDeskDot = false;
      forYouDot = false;
    }
    return 1;
  }

  @override
  Future<int> markSeen(List<String> ids) async {
    for (final id in ids) {
      final beaconId = receiptBeacon[id];
      if (beaconId != null) unreadBeacons.remove(beaconId);
    }
    if (unreadBeacons.isEmpty) {
      myDeskDot = false;
      forYouDot = false;
    }
    return ids.length;
  }

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

/// The server's real dot rule: `seen_at` is not an input to `my desk.dot` /
/// `for you.dot`, only the clear axis is. Marking items seen leaves the
/// server's booleans where they were.
final class _ClearAxisServer extends _Server {
  @override
  Future<int> markSeenForBeacon(String beaconId) async {
    unreadBeacons.remove(beaconId);
    return 1;
  }

  @override
  Future<int> markSeen(List<String> ids) async {
    for (final id in ids) {
      final beaconId = receiptBeacon[id];
      if (beaconId != null) unreadBeacons.remove(beaconId);
    }
    return ids.length;
  }
}

Future<void> _settle([int turns = 24]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

RealtimeEntityChange _beaconChange(String id) => RealtimeEntityChange(
  kind: RealtimeEntityKind.beacon,
  aggregateId: id,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
);

void main() {
  late _Accounts accounts;
  late _Server server;
  late TestRealtimeSyncPort realtime;
  late AttentionCase attention;
  late HomeAttentionCubit home;

  Future<void> report({
    Set<String> inbox = const {},
    Set<String> myWork = const {},
  }) async {
    accounts.emit('U1');
    await _settle();
    home
      ..reportInboxSnapshot(accountId: 'U1', beaconIds: inbox, loaded: true)
      ..reportMyWorkSnapshot(accountId: 'U1', beaconIds: myWork, loaded: true);
    await _settle();
  }

  Future<void> pumpNav(WidgetTester tester) => tester.pumpWidget(
    BlocProvider<HomeAttentionCubit>.value(
      value: home,
      child: const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Row(children: [MyWorkNavbarItem(), InboxNavbarItem()]),
        ),
      ),
    ),
  );

  setUp(() async {
    accounts = _Accounts();
    server = _Server();
    final sync = buildTestRealtimeSync();
    realtime = sync.port;
    attention = AttentionCase(
      server,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('nav-dot-test'),
    );
    home = HomeAttentionCubit(attention, accounts, Logger('nav-dot-test'));
  });

  tearDown(() async {
    await home.close();
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  group('My Work dot', () {
    test('shows while an owned Request has an unread item', () async {
      server
        ..readable = {'R1'}
        ..unreadBeacons = {'R1'}
        ..myDeskDot = true;
      await report(myWork: {'R1'});

      expect(home.state.showRedesignMyWorkUnreadDot, isTrue);
      expect(home.state.myWorkMarkerIds, {'R1'});
    });

    test('clears without a reload once the Request is opened', () async {
      server
        ..readable = {'R1'}
        ..unreadBeacons = {'R1'}
        ..myDeskDot = true;
      await report(myWork: {'R1'});
      expect(home.state.showRedesignMyWorkUnreadDot, isTrue);

      await attention.markSeenForBeacon('R1');
      await _settle();

      expect(home.state.showRedesignMyWorkUnreadDot, isFalse);
      expect(home.state.myWorkMarkerIds, isEmpty);
      expect(home.state.hasMyWorkDot, isFalse);
    });

    test('a Request the viewer can no longer open does not hold the dot',
        () async {
      server
        ..readable = {'R1'}
        ..unreadBeacons = {'R1'}
        ..myDeskDot = true;
      await report(myWork: {'R1'});
      expect(home.state.hasMyWorkDot, isTrue);

      server
        ..readable = {}
        ..myDeskDot = false;
      realtime.emitChange(_beaconChange('R1'));
      await _settle();

      expect(home.state.hasMyWorkDot, isFalse);
      expect(home.state.showRedesignMyWorkUnreadDot, isFalse);
    });
  });

  group('Activity dot', () {
    test('shows while an Activity Request has an unread item', () async {
      server
        ..readable = {'A1'}
        ..unreadBeacons = {'A1'}
        ..forYouDot = true;
      await report(inbox: {'A1'});

      expect(home.state.showRedesignActivityUnreadDot, isTrue);
      expect(home.state.inboxMarkerIds, {'A1'});
    });

    test('clears without a reload once its receipt is marked seen', () async {
      server
        ..readable = {'A1'}
        ..unreadBeacons = {'A1'}
        ..receiptBeacon = {'r1': 'A1'}
        ..forYouDot = true;
      await report(inbox: {'A1'});
      expect(home.state.hasInboxDot, isTrue);

      await attention.markSeen(['r1']);
      await _settle();

      expect(home.state.showRedesignActivityUnreadDot, isFalse);
      expect(home.state.inboxMarkerIds, isEmpty);
      expect(home.state.hasInboxDot, isFalse);
    });

    test('clears without a reload once the Request is opened', () async {
      server
        ..readable = {'A1'}
        ..unreadBeacons = {'A1'}
        ..forYouDot = true;
      await report(inbox: {'A1'});
      expect(home.state.hasInboxDot, isTrue);

      await attention.markSeenForBeacon('A1');
      await _settle();

      expect(home.state.inboxMarkerIds, isEmpty);
      expect(home.state.showRedesignActivityUnreadDot, isFalse);
    });

    test('a Request the viewer can no longer open does not hold the dot',
        () async {
      server
        ..readable = {'A1'}
        ..unreadBeacons = {'A1'}
        ..forYouDot = true;
      await report(inbox: {'A1'});
      expect(home.state.hasInboxDot, isTrue);

      server
        ..readable = {}
        ..forYouDot = false;
      realtime.emitChange(_beaconChange('A1'));
      await _settle();

      expect(home.state.inboxMarkerIds, isEmpty);
      expect(home.state.showRedesignActivityUnreadDot, isFalse);
    });

    test('a marker for an item missing from the snapshot is ignored', () async {
      server
        ..readable = {'A1', 'GONE'}
        ..unreadBeacons = {'A1', 'GONE'};
      await report(inbox: {'A1'});
      expect(home.state.inboxMarkerIds, {'A1'});

      await attention.markSeenForBeacon('A1');
      await _settle();

      expect(home.state.hasInboxDot, isFalse);
    });
  });

  group('dots clear from what was seen while the server summary still reports a dot', () {
    setUp(() async {
      // Rebuild the stack on the seen-only server.
      await home.close();
      await attention.dispose();
      await realtime.dispose();
      await accounts.close();
      accounts = _Accounts();
      server = _ClearAxisServer();
      final sync = buildTestRealtimeSync();
      realtime = sync.port;
      attention = AttentionCase(
        server,
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('nav-dot-test'),
      );
      home = HomeAttentionCubit(attention, accounts, Logger('nav-dot-test'));
    });

    test('My Work dot clears once every unread item has been seen', () async {
      server
        ..readable = {'R1'}
        ..unreadBeacons = {'R1'}
        ..receiptBeacon = {'r1': 'R1'}
        ..myDeskDot = true;
      await report(myWork: {'R1'});
      expect(home.state.showRedesignMyWorkUnreadDot, isTrue);

      await attention.markSeen(['r1']);
      await _settle();

      expect(home.state.showRedesignMyWorkUnreadDot, isFalse);
      expect(home.state.hasMyWorkDot, isFalse);
      expect(home.state.myWorkMarkerIds, isEmpty);
    });

    test('Activity dot clears once every unread item has been seen', () async {
      server
        ..readable = {'A1'}
        ..unreadBeacons = {'A1'}
        ..receiptBeacon = {'r1': 'A1'}
        ..forYouDot = true;
      await report(inbox: {'A1'});
      expect(home.state.showRedesignActivityUnreadDot, isTrue);

      await attention.markSeen(['r1']);
      await _settle();

      expect(home.state.showRedesignActivityUnreadDot, isFalse);
      expect(home.state.hasInboxDot, isFalse);
      expect(home.state.inboxMarkerIds, isEmpty);
    });

    test('opening the Request clears the My Work dot', () async {
      server
        ..readable = {'R1'}
        ..unreadBeacons = {'R1'}
        ..myDeskDot = true;
      await report(myWork: {'R1'});
      expect(home.state.showRedesignMyWorkUnreadDot, isTrue);

      await attention.markSeenForBeacon('R1');
      await _settle();

      expect(home.state.showRedesignMyWorkUnreadDot, isFalse);
    });

    testWidgets('My Work icon drops its dot after its item is seen',
        (tester) async {
      await tester.runAsync(() async {
        server
          ..readable = {'R1'}
          ..unreadBeacons = {'R1'}
          ..receiptBeacon = {'r1': 'R1'}
          ..myDeskDot = true;
        await report(myWork: {'R1'});
      });
      await pumpNav(tester);
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);

      await tester.runAsync(() async {
        await attention.markSeen(['r1']);
        await _settle();
      });
      await tester.pump();

      expect(find.byKey(MyWorkNavbarItem.dotKey), findsNothing);
    });

    testWidgets('Activity icon drops its dot after its item is seen',
        (tester) async {
      await tester.runAsync(() async {
        server
          ..readable = {'A1'}
          ..unreadBeacons = {'A1'}
          ..receiptBeacon = {'r1': 'A1'}
          ..forYouDot = true;
        await report(inbox: {'A1'});
      });
      await pumpNav(tester);
      expect(
        find.bySemanticsIdentifier('activity-surface-unread-dot'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await attention.markSeen(['r1']);
        await _settle();
      });
      await tester.pump();

      expect(
        find.bySemanticsIdentifier('activity-surface-unread-dot'),
        findsNothing,
      );
    });
  });

  group('nav widgets', () {
    testWidgets('My Work icon drops its dot after the Request is opened',
        (tester) async {
      await tester.runAsync(() async {
        server
          ..readable = {'R1'}
          ..unreadBeacons = {'R1'}
          ..myDeskDot = true;
        await report(myWork: {'R1'});
      });
      await pumpNav(tester);
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);

      await tester.runAsync(() async {
        await attention.markSeenForBeacon('R1');
        await _settle();
      });
      await tester.pump();

      expect(find.byKey(MyWorkNavbarItem.dotKey), findsNothing);
    });

    testWidgets('Activity icon drops its dot once its receipt is seen',
        (tester) async {
      await tester.runAsync(() async {
        server
          ..readable = {'A1'}
          ..unreadBeacons = {'A1'}
          ..receiptBeacon = {'r1': 'A1'}
          ..forYouDot = true;
        await report(inbox: {'A1'});
      });
      await pumpNav(tester);
      expect(
        find.bySemanticsIdentifier('activity-surface-unread-dot'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await attention.markSeen(['r1']);
        await _settle();
      });
      await tester.pump();

      expect(
        find.bySemanticsIdentifier('activity-surface-unread-dot'),
        findsNothing,
      );
    });

    testWidgets('My Work icon drops its dot when the Request is no longer '
        'openable', (tester) async {
      await tester.runAsync(() async {
        server
          ..readable = {'R1'}
          ..unreadBeacons = {'R1'}
          ..myDeskDot = true;
        await report(myWork: {'R1'});
      });
      await pumpNav(tester);
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);

      await tester.runAsync(() async {
        server
          ..readable = {}
          ..myDeskDot = false;
        realtime.emitChange(_beaconChange('R1'));
        await _settle();
      });
      await tester.pump();

      expect(find.byKey(MyWorkNavbarItem.dotKey), findsNothing);
    });

    testWidgets('Activity icon drops its dot when the Request is no longer '
        'openable', (tester) async {
      await tester.runAsync(() async {
        server
          ..readable = {'A1'}
          ..unreadBeacons = {'A1'}
          ..forYouDot = true;
        await report(inbox: {'A1'});
      });
      await pumpNav(tester);
      expect(
        find.bySemanticsIdentifier('activity-surface-unread-dot'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        server
          ..readable = {}
          ..forYouDot = false;
        realtime.emitChange(_beaconChange('A1'));
        await _settle();
      });
      await tester.pump();

      expect(
        find.bySemanticsIdentifier('activity-surface-unread-dot'),
        findsNothing,
      );
    });
  });
}
