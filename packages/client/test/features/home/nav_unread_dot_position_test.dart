// The unread dot sits in one place on every nav tab (top-end, as on Posts and
// Activity). My Work used to put it top-start to leave the trailing corner to
// the obligation count; now that count badge stands alone when both apply, and
// the Semantics label still states both.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/widget/conversations_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/inbox_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/my_work_navbar_item.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
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

final class _Repository extends AttentionRepositoryFake {
  AttentionSurfaceSummary surfaceSummaryValue = const AttentionSurfaceSummary();

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async => surfaceSummaryValue;

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
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => const {};

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

final class _Posts implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => [
    PostSummary(
      id: 'B1',
      authorId: 'Uauthor',
      authorName: 'Author',
      lastActivityAt: DateTime.utc(2026, 10, 2),
      unreadCount: 2,
    ),
  ];

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump();
  }
}

Future<HomeAttentionCubit> _bootHome(
  WidgetTester tester,
  _Accounts accounts,
  _Repository repository,
) async {
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repository,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('nav-unread-dot-position-test'),
  );
  final home = HomeAttentionCubit(
    attention,
    accounts,
    Logger('nav-unread-dot-position-test'),
  );
  accounts.emit('U1');
  await _settle(tester);
  return home;
}

Future<void> _pumpWithHome(
  WidgetTester tester,
  HomeAttentionCubit home,
  Widget child,
) async {
  await tester.pumpWidget(
    BlocProvider<HomeAttentionCubit>.value(
      value: home,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
}

/// The alignment a [Badge] actually draws with: its own, else the theme's,
/// else Material's default (top-end).
AlignmentGeometry _effectiveAlignment(WidgetTester tester, Finder badge) {
  final widget = tester.widget<Badge>(badge);
  return widget.alignment ??
      BadgeTheme.of(tester.element(badge)).alignment ??
      AlignmentDirectional.topEnd;
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

  group('unread dot alignment', () {
    testWidgets('My Work draws the unread dot top-end', (tester) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskDot: true,
      );
      final home = await _bootHome(tester, accounts, repository);
      await _pumpWithHome(tester, home, const MyWorkNavbarItem());

      expect(find.byKey(MyWorkNavbarItem.dotKey), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.countKey), findsNothing);
      expect(
        _effectiveAlignment(tester, find.byKey(MyWorkNavbarItem.dotKey)),
        AlignmentDirectional.topEnd,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(home.close());
    });

    testWidgets('Activity draws the unread dot top-end', (tester) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        forYouDot: true,
      );
      final home = await _bootHome(tester, accounts, repository);
      await _pumpWithHome(tester, home, const InboxNavbarItem());

      expect(find.byType(Badge), findsOneWidget);
      expect(
        _effectiveAlignment(tester, find.byType(Badge)),
        AlignmentDirectional.topEnd,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(home.close());
    });

    testWidgets('Posts draws the unread dot top-end', (tester) async {
      final repo = _Posts();
      final sync = buildTestRealtimeSync();
      final postsCase = PostsCase(
        repo,
        sync.case_,
        env: const Env(),
        logger: Logger('nav-unread-dot-position-test'),
      );
      GetIt.I.registerSingleton<PostsCase>(postsCase);
      addTearDown(() async {
        await GetIt.I.reset();
        await sync.port.dispose();
      });
      await tester.runAsync(postsCase.myPosts);

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: Center(child: ConversationsNavbarItem())),
        ),
      );

      expect(find.byType(Badge), findsOneWidget);
      expect(
        _effectiveAlignment(tester, find.byType(Badge)),
        AlignmentDirectional.topEnd,
      );
    });
  });

  group('My Work with both unread and obligations', () {
    testWidgets('draws only the count badge', (tester) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 3,
        myDeskDot: true,
      );
      final home = await _bootHome(tester, accounts, repository);
      await _pumpWithHome(tester, home, const MyWorkNavbarItem());

      expect(find.byType(Badge), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.countKey), findsOneWidget);
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(home.close());
    });

    testWidgets('semantics label states both the count and new activity', (
      tester,
    ) async {
      repository.surfaceSummaryValue = const AttentionSurfaceSummary(
        myDeskCount: 3,
        myDeskDot: true,
      );
      final home = await _bootHome(tester, accounts, repository);
      final handle = tester.ensureSemantics();
      await _pumpWithHome(tester, home, const MyWorkNavbarItem());

      final l10n = lookupL10n(const Locale('en'));
      final node = tester.getSemantics(
        find.bySemanticsIdentifier('my-work-surface-unread-dot'),
      );
      expect(node.label, contains(l10n.myWorkNavBadgeObligations(3)));
      expect(node.label, contains(l10n.activityNavBadgeNewActivity));
      // Only the count badge is drawn, yet nothing is dropped from the label.
      expect(find.byKey(MyWorkNavbarItem.dotKey), findsNothing);

      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(home.close());
    });
  });
}
