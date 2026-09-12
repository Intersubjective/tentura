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
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
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

final class _Repository implements AttentionRepositoryPort {
  int needsYouTotal = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async => AttentionFeed(
    summary: AttentionSummary(needsYouTotal: needsYouTotal),
    page: const AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      const {};

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

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
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
  final badge = tester.widget<Badge>(find.byType(Badge));
  final label = badge.label;
  if (label is Text) return label.data;
  return null;
}

Future<({HomeAttentionCubit home, AttentionCase attention})> _bootHome({
  required _Accounts accounts,
  required _Repository repository,
  required int obligationCount,
}) async {
  repository.needsYouTotal = obligationCount;
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-navbar-item-test'),
  );
  attention.attachFeedSession(AttentionFeedDestinationId.myWorkObligations);
  attention.setActiveView(
    AttentionFeedDestinationId.myWorkObligations,
    AttentionView.needsYou,
  );
  accounts.emit('U1');
  await attention.refresh(
    destinationId: AttentionFeedDestinationId.myWorkObligations,
  );
  await _settle(20);
  final home = HomeAttentionCubit(
    attention,
    accounts,
    Logger('my-work-navbar-item-test'),
  );
  return (home: home, attention: attention);
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
    final boot = await _bootHome(
      accounts: accounts,
      repository: repository,
      obligationCount: 4,
    );
    boot.home.setActiveHomeTab(HomeTab.inbox);
    await _pumpNavItem(tester, boot.home);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelText(tester), '4');
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(boot.home.close());
    unawaited(boot.attention.dispose());
  });

  testWidgets('keeps numeric badge on the active My Work tab', (tester) async {
    final boot = await _bootHome(
      accounts: accounts,
      repository: repository,
      obligationCount: 2,
    );
    boot.home.setActiveHomeTab(HomeTab.work);
    await _pumpNavItem(tester, boot.home, selected: true);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelText(tester), '2');
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(boot.home.close());
    unawaited(boot.attention.dispose());
  });

  testWidgets('shows no badge when obligation count is zero', (tester) async {
    final boot = await _bootHome(
      accounts: accounts,
      repository: repository,
      obligationCount: 0,
    );
    await _pumpNavItem(tester, boot.home);

    expect(find.byType(Badge), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(boot.home.close());
    unawaited(boot.attention.dispose());
  });
}
