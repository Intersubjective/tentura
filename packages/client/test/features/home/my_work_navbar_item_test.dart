import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/widget/my_work_navbar_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
  AttentionSurfaceSummary surfaceSummaryValue = const AttentionSurfaceSummary(
    activityUnreadTotal: 0,
    myWorkUnreadTotal: 0,
    needsYouTotal: 0,
  );

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      surfaceSummaryValue;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async =>
      const AttentionFeed(
        summary: AttentionSummary(),
        page: AttentionFeedPage(),
      );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      const {};

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

Future<void> _settle(WidgetTester tester, [int pumps = 24]) async {
  for (var i = 0; i < pumps; i++) {
    await tester.pump();
  }
}

Future<HomeAttentionCubit> _bootHome({
  required _Accounts accounts,
  required _Repository repository,
  required WidgetTester tester,
}) async {
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-navbar-item-test'),
  );
  final home = HomeAttentionCubit(
    attention,
    accounts,
    Logger('my-work-navbar-item-test'),
  );
  accounts.emit('U1');
  await _settle(tester);
  return home;
}

Future<void> _pumpNavItem(
  WidgetTester tester,
  HomeAttentionCubit home, {
  bool selected = false,
}) async {
  await tester.pumpWidget(
    BlocProvider<HomeAttentionCubit>.value(
      value: home,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(child: MyWorkNavbarItem(selected: selected)),
        ),
      ),
    ),
  );
  await tester.pump();
}

String? _badgeLabelText(WidgetTester tester) {
  final badge = tester.widget<Badge>(
    find.byKey(MyWorkNavbarItem.countKey),
  );
  final label = badge.label;
  if (label is Text) return label.data;
  return null;
}

void main() {
  late _Accounts accounts;
  late _Repository repository;

  setUp(() {
    accounts = _Accounts();
    repository = _Repository();
  });

  tearDown(() async {
    await accounts.close();
  });

  testWidgets('shows numeric badge for live obligations', (tester) async {
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 0,
      // CHANGES IN U15R-e: the number is §6 `my desk.count`, not the legacy
      // unscoped `needsYouTotal`. The two are given different values on
      // purpose — a widget still reading the old field renders '9'.
      needsYouTotal: 9,
      myDeskCount: 4,
    );
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    home.setActiveHomeTab(HomeTab.inbox);
    await _pumpNavItem(tester, home);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelText(tester), '4');
    expect(find.byKey(MyWorkNavbarItem.dotKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });

  testWidgets('keeps numeric badge on the active My Work tab', (tester) async {
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 0,
      needsYouTotal: 9,
      myDeskCount: 2,
    );
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    home.setActiveHomeTab(HomeTab.work);
    await _pumpNavItem(tester, home, selected: true);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelText(tester), '2');
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });

  /// R7 — §6 and D09: "Dot and number are independent: a Request with both
  /// shows both, and a tab shows its dot whether or not it also shows a
  /// number." The navbar used to return as soon as it had a number.
  testWidgets('shows the dot and the number together', (tester) async {
    // CHANGES IN U15R-d: §6 `my desk.dot` is its own field; the unread total
    // beside it includes obligations and never was the dot's rule.
    // CHANGES IN U15R-e: and the number beside the dot is `my desk.count`.
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 5,
      needsYouTotal: 9,
      myDeskCount: 2,
      myDeskDot: true,
    );
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    home.setActiveHomeTab(HomeTab.work);
    await _pumpNavItem(tester, home);

    expect(find.byKey(MyWorkNavbarItem.countKey), findsOneWidget);
    expect(_badgeLabelText(tester), '2');
    expect(
      find.byKey(MyWorkNavbarItem.dotKey),
      findsOneWidget,
      reason: 'the dot does not hide behind the number (§6, D09)',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });

  /// U15R-e — §6 `my desk.count` is a field, not the legacy total renamed.
  ///
  /// `needsYouTotal` counts every live obligation unscoped and keeps that
  /// meaning until U18, so a navbar reading it would show a number §6 never
  /// asked for. The two are given opposite values here: only one of them can
  /// be the source of the rendered badge.
  testWidgets('the number is my desk.count, not the legacy needsYouTotal', (
    tester,
  ) async {
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 7,
      needsYouTotal: 7,
      myDeskCount: 0,
    );
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    home.setActiveHomeTab(HomeTab.work);
    await _pumpNavItem(tester, home);

    expect(find.byKey(MyWorkNavbarItem.countKey), findsNothing);
    expect(find.text('7'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });

  /// The other direction of the same flip, so neither assertion can hold by
  /// the badge simply never rendering.
  testWidgets('the count alone raises the number with no legacy total', (
    tester,
  ) async {
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 0,
      needsYouTotal: 0,
      myDeskCount: 7,
    );
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    home.setActiveHomeTab(HomeTab.work);
    await _pumpNavItem(tester, home);

    expect(find.byKey(MyWorkNavbarItem.countKey), findsOneWidget);
    expect(_badgeLabelText(tester), '7');
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });

  testWidgets('shows the dot alone when nothing is owed', (tester) async {
    // CHANGES IN U15R-d: §6 `my desk.dot` is its own field.
    // CHANGES IN U15R-e: the number is `my desk.count`, which is zero here
    // even though the legacy total is not.
    repository.surfaceSummaryValue = const AttentionSurfaceSummary(
      activityUnreadTotal: 0,
      myWorkUnreadTotal: 3,
      // The legacy total still counts obligations the §6 count does not own;
      // the badge must follow `myDeskCount`, so there is no number here.
      needsYouTotal: 9,
      myDeskCount: 0,
      myDeskDot: true,
    );
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    await _pumpNavItem(tester, home);

    expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);
    expect(find.byKey(MyWorkNavbarItem.countKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });

  testWidgets('shows no badge when obligation count is zero', (tester) async {
    final home = await _bootHome(
      accounts: accounts,
      repository: repository,
      tester: tester,
    );
    await _pumpNavItem(tester, home);

    expect(find.byType(Badge), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(home.close());
  });
}
