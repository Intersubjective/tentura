import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/screen/updates_screen.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

class _HarnessRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) =>
      true;
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

AttentionReceipt _receipt({
  required String id,
  required String title,
  required AttentionSurface surface,
}) =>
    AttentionReceipt(
      id: id,
      category: 'requestProgress',
      kind: 'commitmentAccepted',
      priority: 'normal',
      title: title,
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 9, 10, 12),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: surface,
      beaconId: 'beacon-$id',
    );

class _HistoryFeedRepo extends AttentionRepositoryFake {
  _HistoryFeedRepo(this._items);

  final List<AttentionReceipt> _items;
  String? lastSearch;
  AttentionSurface? lastFetchSurface;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    lastSearch = search;
    lastFetchSurface = surface;
    final query = (search ?? '').trim().toLowerCase();
    final filtered = query.isEmpty
        ? _items
        : _items
              .where((r) => r.title.toLowerCase().contains(query))
              .toList();
    return AttentionFeed(
      summary: AttentionSummary(unreadTotal: filtered.length),
      page: AttentionFeedPage(items: filtered),
    );
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

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

Future<void> _pumpHistory(
  WidgetTester tester, {
  required _HistoryFeedRepo repository,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('notification-history-test'),
  );
  accounts.emit('viewer');

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('notification-history-test'));
  }
  addTearDown(() async {
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<Logger>()) {
      GetIt.I.unregister<Logger>();
    }
  });

  final router = _HarnessRouter();
  await tester.pumpWidget(
    RouterScope(
      controller: router,
      stateHash: 0,
      inheritableObserversBuilder: () => const [],
      child: StackRouterScope(
        controller: router,
        stateHash: 0,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 800)),
          child: TenturaResponsiveScope(
            child: MaterialApp(
              locale: const Locale('en'),
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: const UpdatesScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('history screen shows receipts from activity and my work surfaces', (
    tester,
  ) async {
    final repo = _HistoryFeedRepo([
      _receipt(
        id: 'a1',
        title: 'Activity surface event',
        surface: AttentionSurface.activity,
      ),
      _receipt(
        id: 'm1',
        title: 'My work surface event',
        surface: AttentionSurface.myWork,
      ),
    ]);
    await _pumpHistory(tester, repository: repo);

    final l10n = L10nEn();
    expect(find.text(l10n.notificationHistoryTitle), findsOneWidget);
    expect(find.text('Activity surface event'), findsOneWidget);
    expect(find.text('My work surface event'), findsOneWidget);
    expect(repo.lastFetchSurface, isNull);
  });

  testWidgets('history search filters visible receipts', (tester) async {
    final repo = _HistoryFeedRepo([
      _receipt(
        id: 'a1',
        title: 'Garden cleanup activity',
        surface: AttentionSurface.activity,
      ),
      _receipt(
        id: 'm1',
        title: 'Desk obligation item',
        surface: AttentionSurface.myWork,
      ),
    ]);
    await _pumpHistory(tester, repository: repo);

    expect(find.text('Garden cleanup activity'), findsOneWidget);
    expect(find.text('Desk obligation item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Garden');
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Garden cleanup activity'), findsOneWidget);
    expect(find.text('Desk obligation item'), findsNothing);
    expect(repo.lastSearch, 'Garden');
  });

  testWidgets('history uses unscoped destination (both surfaces on first fetch)', (
    tester,
  ) async {
    final repo = _HistoryFeedRepo([
      _receipt(
        id: 'a1',
        title: 'Only activity',
        surface: AttentionSurface.activity,
      ),
    ]);
    await _pumpHistory(tester, repository: repo);

    expect(find.byType(UpdatesFeedTile), findsWidgets);
    expect(repo.lastFetchSurface, isNull);
  });
}
