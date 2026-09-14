import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show
        FakeInboxRepository,
        buildTestBeaconThreadsCase,
        buildTestInboxCase;

class _HarnessRouter extends Mock implements StackRouter {
  PageRouteInfo? lastPush;

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
  void clearPendingMovedNudge() {}

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
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChromeAttentionRepo extends AttentionRepositoryFake {
  _ChromeAttentionRepo({this.activityUnread = 0});

  int activityUnread;
  AttentionSurface? lastMarkAllSurface;

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async =>
      AttentionSurfaceSummary(
        activityUnreadTotal: activityUnread,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      );

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
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async {
    lastMarkAllSurface = surface;
    activityUnread = 0;
    return 0;
  }

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

Future<void> _pumpInbox(
  WidgetTester tester, {
  required _ChromeAttentionRepo attentionRepo,
  required _HarnessRouter router,
}) async {
  const logicalSize = Size(800, 800);
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('activity-chrome-test'),
  );
  accounts.emit('viewer');
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }

  final inboxRepo = FakeInboxRepository()..openForwardsCount = 0;
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton(inboxCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('activity-chrome-test'));
  }
  addTearDown(() async {
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InboxCase>()) {
      GetIt.I.unregister<InboxCase>();
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

  final inboxCubit = _TestInboxCubit(
    const InboxState(status: StateIsSuccess(), projectionLoaded: true),
  );
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('activity-chrome-test'),
  );

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<InboxCubit>.value(value: inboxCubit),
          BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
          BlocProvider(create: (_) => HomeTabReselectCubit()),
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: logicalSize),
            child: const TenturaResponsiveScope(child: InboxScreen()),
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

  testWidgets('gate on: top bar uses Activity title and mark-all control', (
    tester,
  ) async {
    final repo = _ChromeAttentionRepo(activityUnread: 2);
    final router = _HarnessRouter();
    await _pumpInbox(tester, attentionRepo: repo, router: router);

    final l10n = L10nEn();
    expect(find.text(l10n.inbox), findsOneWidget);
    expect(find.text(l10n.updatesTitle), findsNothing);
    expect(find.byIcon(Icons.done_all), findsOneWidget);

    final markAll = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.done_all),
    );
    expect(markAll.onPressed, isNotNull);

    expect(find.byType(ActivityStreamView), findsOneWidget);
  });

  testWidgets('gate on: mark-all is disabled when activity unread is zero', (
    tester,
  ) async {
    await _pumpInbox(
      tester,
      attentionRepo: _ChromeAttentionRepo(activityUnread: 0),
      router: _HarnessRouter(),
    );

    final markAll = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.done_all),
    );
    expect(markAll.onPressed, isNull);
  });

  testWidgets('gate on: mark-all calls activity-scoped markAllSeen', (
    tester,
  ) async {
    final repo = _ChromeAttentionRepo(activityUnread: 3);
    await _pumpInbox(
      tester,
      attentionRepo: repo,
      router: _HarnessRouter(),
    );

    await tester.tap(find.byIcon(Icons.done_all));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(repo.lastMarkAllSurface, AttentionSurface.activity);
  });

  testWidgets('gate on: overflow includes notification history entry', (
    tester,
  ) async {
    final router = _HarnessRouter();
    await _pumpInbox(
      tester,
      attentionRepo: _ChromeAttentionRepo(),
      router: router,
    );

    final l10n = L10nEn();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.notificationHistoryTitle), findsOneWidget);

    await tester.tap(find.text(l10n.notificationHistoryTitle));
    await tester.pumpAndSettle();
    expect(router.lastPush, isA<UpdatesRoute>());
  });

}
