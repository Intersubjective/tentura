import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/widget/inbox_navbar_item.dart';
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
  Set<String> unread = const {};

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
      unread.intersection(beaconIds);

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
          body: Center(child: InboxNavbarItem(selected: selected)),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _badgeLabelVisible(WidgetTester tester) {
  final badge = tester.widget<Badge>(find.byType(Badge));
  return badge.isLabelVisible;
}

String? _badgeLabelText(WidgetTester tester) {
  final badge = tester.widget<Badge>(find.byType(Badge));
  final label = badge.label;
  if (label is Text) return label.data;
  return null;
}

SemanticsNode _navSemantics(WidgetTester tester) {
  return tester.getSemantics(find.byType(InboxNavbarItem));
}

Future<void> _seedInboxAttention({
  required HomeAttentionCubit home,
  required _Accounts accounts,
  required _Repository repository,
  required int triageCount,
  Set<String> inboxBeaconIds = const {},
}) async {
  repository.unread = inboxBeaconIds;
  accounts.emit('U1');
  await _settle();
  home.reportInboxTriageCount(
    accountId: 'U1',
    triageCount: triageCount,
    loaded: true,
  );
  home.reportInboxSnapshot(
    accountId: 'U1',
    beaconIds: inboxBeaconIds,
    loaded: true,
  );
  home.reportMyWorkSnapshot(
    accountId: 'U1',
    beaconIds: const {},
    loaded: true,
  );
  await _settle();
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
      Logger('inbox-navbar-item-test'),
    );
    home = HomeAttentionCubit(
      attention,
      accounts,
      Logger('inbox-navbar-item-test'),
    );
  });

  tearDown(() async {
    unawaited(home.close());
    await attention.dispose();
    await realtime.dispose();
    await accounts.close();
  });

  testWidgets('shows numeric badge for pending triage', (tester) async {
    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 3,
      inboxBeaconIds: const {'B1'},
    );
    await _pumpNavItem(tester, home);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelVisible(tester), isTrue);
    expect(_badgeLabelText(tester), '3');
    expect(
      _navSemantics(tester).label,
      '3 requests need your response',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows dot when only unread markers are present', (tester) async {
    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 0,
      inboxBeaconIds: const {'B1'},
    );
    await _pumpNavItem(tester, home);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelText(tester), isNull);
    expect(
      _navSemantics(tester).label,
      'New activity',
    );
    expect(_navSemantics(tester).identifier, 'updates-unread-count-1');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows nothing when triage and unread are both zero', (
    tester,
  ) async {
    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 0,
    );
    await _pumpNavItem(tester, home);

    expect(find.byType(Badge), findsNothing);
    expect(_navSemantics(tester).identifier, 'updates-unread-count-0');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('triage count wins over unread dot', (tester) async {
    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 2,
      inboxBeaconIds: const {'B1'},
    );
    await _pumpNavItem(tester, home);

    expect(_badgeLabelText(tester), '2');
    expect(
      _navSemantics(tester).label,
      isNot('New activity'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps numeric badge on the active Activity tab', (tester) async {
    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 1,
      inboxBeaconIds: const {'B1'},
    );
    home.setActiveHomeTab(HomeTab.inbox);
    await _pumpNavItem(tester, home, selected: true);

    expect(find.byType(Badge), findsOneWidget);
    expect(_badgeLabelVisible(tester), isTrue);
    expect(_badgeLabelText(tester), '1');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('semantics differ between triage and unread dot', (tester) async {
    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 1,
    );
    await _pumpNavItem(tester, home);
    final triageLabel = _navSemantics(tester).label;
    await tester.pumpWidget(const SizedBox.shrink());

    await _seedInboxAttention(
      home: home,
      accounts: accounts,
      repository: repository,
      triageCount: 0,
      inboxBeaconIds: const {'B1'},
    );
    await _pumpNavItem(tester, home);
    final unreadLabel = _navSemantics(tester).label;

    expect(triageLabel, isNot(unreadLabel));
    expect(triageLabel, contains('needs your response'));
    expect(unreadLabel, 'New activity');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
