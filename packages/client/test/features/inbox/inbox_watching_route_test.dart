import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_watching_screen.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_watchlist_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show
        FakeInboxRepository,
        buildTestBeaconThreadsCase,
        buildTestInboxCase;
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import '../../support/noop_attention_actor_profiles.dart';

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  PageRouteInfo? lastPush;

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) =>
      false;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushCount++;
    lastPush = route;
    return null;
  }
}

class _RecordingRootRouter extends Mock implements RootRouter {
  PageRouteInfo? lastPush;
  List<PageRouteInfo>? lastReplaceAll;

  @override
  Future<void> replaceAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool updateExistingRoutes = true,
  }) async {
    lastReplaceAll = routes;
  }

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    lastPush = route;
    return null;
  }
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);


  @override
  void clearPendingMovedNudge() {
    emit(state.copyWith(pendingMovedNudge: null));
  }

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  Future<void> setWatching(String beaconId) async {}

  @override
  Future<void> stopWatching(String beaconId) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  Future<void> close() => _changes.close();
}

class _Repository extends AttentionRepositoryFake {
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

InboxItem _watchingItem(
  String id,
  String title, {
  String authorId = 'author-1',
}) {
  final at = DateTime.utc(2026, 6, 20);
  final beacon = Beacon(
    id: id,
    title: title,
    author: Profile(id: authorId, displayName: 'Author'),
    createdAt: at,
    updatedAt: at,
  );
  return InboxItem(
    beaconId: id,
    latestForwardAt: at,
    beacon: beacon,
    status: InboxItemStatus.watching,
  );
}


Future<void> _pumpInboxOverflow(
  WidgetTester tester, {
  required _HarnessRouter router,
  required List<InboxItem> items,
}) async {
  final inboxCubit = _TestInboxCubit(
    InboxState(
      items: items,
      status: const StateIsSuccess(),
      projectionLoaded: true,
      currentUserId: 'viewer',
    ),
  );
  unawaited(inboxCubit.close());

  final accounts = _Accounts();
  unawaited(accounts.close());
  final sync = buildTestRealtimeSync();
  unawaited(sync.port.dispose());
  final attentionCase = AttentionCase(
    _Repository(),
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('inbox-watching-test'),
  );
  unawaited(attentionCase.dispose());
  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attentionCase);
  ensureNoopAttentionActorProfilesRegistered();
  final inboxCase = buildTestInboxCase(
    FakeInboxRepository(),
    buildTestBeaconThreadsCase(),
  );
  GetIt.I.registerSingleton<InboxCase>(inboxCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  addTearDown(() {
    if (GetIt.I.isRegistered<InboxCase>()) {
      GetIt.I.unregister<InboxCase>();
    }
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
  });
  final logger = Logger('inbox-watching-test');
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(logger);
  }
  final attention = HomeAttentionCubit(
    attentionCase,
    accounts,
    Logger('inbox-watching-test'),
  );
  unawaited(attention.close());

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<InboxCubit>.value(value: inboxCubit),
          BlocProvider<HomeAttentionCubit>.value(value: attention),
          BlocProvider(create: (_) => HomeTabReselectCubit()),
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const TenturaResponsiveScope(
            child: InboxScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('InboxState.watching', () {
    test('keeps preference-muted watching rows in the collection', () {
      final state = InboxState(
        items: [_watchingItem('b-muted', 'Muted request')],
        currentUserId: 'viewer',
        status: const StateIsSuccess(),
        projectionLoaded: true,
      );
      expect(state.watching, hasLength(1));
      expect(state.watching.single.beaconId, 'b-muted');
    });

    test('omits blocked or unauthorized rows (not returned by fetch)', () {
      final state = InboxState(
        items: [
          _watchingItem('b-visible', 'Still visible'),
        ],
        currentUserId: 'viewer',
        status: const StateIsSuccess(),
        projectionLoaded: true,
      );
      expect(state.watching.map((e) => e.beaconId), ['b-visible']);
      const withoutBlocked = InboxState(
        items: const [],
        currentUserId: 'viewer',
      );
      expect(withoutBlocked.watching, isEmpty);
    });

    test('excludes the viewer own authored beacons', () {
      final state = InboxState(
        items: [_watchingItem('b-own', 'Own', authorId: 'viewer')],
        currentUserId: 'viewer',
      );
      expect(state.watching, isEmpty);
    });
  });

  testWidgets('overflow opens Watching and shows the count', (tester) async {
    final router = _HarnessRouter();
    await _pumpInboxOverflow(
      tester,
      router: router,
      items: [
        _watchingItem('b1', 'First'),
        _watchingItem('b2', 'Second'),
      ],
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Following (2)'), findsOneWidget);
    await tester.tap(find.text('Following (2)'));
    await tester.pumpAndSettle();

    expect(router.pushCount, 1);
    expect(router.lastPush, isA<InboxWatchingRoute>());
  });

  testWidgets('highlightBeaconId selects the named row once', (tester) async {
    final items = [
      _watchingItem('b-first', 'First'),
      _watchingItem('b-target', 'Target request'),
      _watchingItem('b-third', 'Third'),
    ];
    final cubit = _TestInboxCubit(
      InboxState(
        items: items,
        status: const StateIsSuccess(),
        projectionLoaded: true,
        currentUserId: 'viewer',
      ),
    );
    unawaited(cubit.close());

    final router = _HarnessRouter();
    await tester.pumpWidget(
      RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<InboxCubit>.value(value: cubit),
                  BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
                  BlocProvider(create: (_) => ScreenCubit.local()),
                ],
                child: const InboxWatchingScreen(highlightBeaconId: 'b-target'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final tiles = tester.widgetList<InboxWatchlistRow>(
      find.byType(InboxWatchlistRow),
    );
    expect(tiles.where((t) => t.isSelected), hasLength(1));
    expect(tiles.firstWhere((t) => t.isSelected).item.beaconId, 'b-target');
  });

  test('ForwardLocationMessage pushes Watching with highlight beacon', () async {
    final router = _RecordingRootRouter();
    if (GetIt.I.isRegistered<RootRouter>()) {
      GetIt.I.unregister<RootRouter>();
    }
    GetIt.I.registerSingleton<RootRouter>(router);
    addTearDown(() {
      if (GetIt.I.isRegistered<RootRouter>()) {
        GetIt.I.unregister<RootRouter>();
      }
    });

    const message = ForwardLocationMessage(beaconId: 'B-forward');
    message.onPressed?.call();
    await Future<void>.delayed(Duration.zero);

    expect(router.lastReplaceAll, isNotNull);
    expect(router.lastPush, isA<InboxWatchingRoute>());
    final route = router.lastPush! as InboxWatchingRoute;
    expect(route.args!.highlightBeaconId, 'B-forward');
  });
}
