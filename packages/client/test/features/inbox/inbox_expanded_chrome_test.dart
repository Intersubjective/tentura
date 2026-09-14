import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/home/domain/work_activity_redesign_gate.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_item_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';

class _HarnessRouter extends Mock implements StackRouter {
  int pushCount = 0;
  PageRouteInfo? lastPush;

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

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);

  @override
  void setSort(InboxSort sort) => emit(state.copyWith(sort: sort));

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

InboxItem _needsItem() {
  final at = DateTime.utc(2026, 6, 20);
  final beacon = Beacon(
    id: 'b-needs',
    title: 'Needs-me request',
    author: const Profile(id: 'auth', displayName: 'Alex'),
    createdAt: at,
    updatedAt: at,
  );
  return InboxItem(
    beaconId: beacon.id,
    latestForwardAt: at,
    beacon: beacon,
  );
}

void _registerRedesignGate(bool enabled) {
  if (GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
    GetIt.I.unregister<bool>(instanceName: workActivityRedesignGate);
  }
  GetIt.I.registerSingleton<bool>(
    enabled,
    instanceName: workActivityRedesignGate,
  );
}

Future<void> _pumpInbox(
  WidgetTester tester, {
  required Size logicalSize,
  required _HarnessRouter router,
}) async {
  _registerRedesignGate(false);
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final inboxCubit = _TestInboxCubit(
    InboxState(
      items: [_needsItem()],
      status: const StateIsSuccess(),
      projectionLoaded: true,
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
    Logger('inbox-chrome-test'),
  );
  unawaited(attentionCase.dispose());
  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attentionCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  addTearDown(() {
    if (GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
      GetIt.I.unregister<bool>(instanceName: workActivityRedesignGate);
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
  final logger = Logger('inbox-chrome-test');
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(logger);
  }
  final attention = HomeAttentionCubit(
    attentionCase,
    accounts,
    Logger('inbox-chrome-test'),
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
          home: MediaQuery(
            data: MediaQueryData(size: logicalSize),
            child: TenturaResponsiveScope(
              child: const InboxScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('expanded list shows host TopBar without primary tab strip', (
    tester,
  ) async {
    await _pumpInbox(
      tester,
      logicalSize: const Size(1024, 800),
      router: _HarnessRouter(),
    );

    expect(find.byType(TenturaTopBar), findsOneWidget);
    expect(find.byType(TenturaPrimaryTabBar), findsNothing);
    expect(find.byType(UpdatesFeedPane), findsOneWidget);
    expect(find.text('Needs-me request'), findsOneWidget);
    expect(find.byType(InboxItemTile), findsNothing);
  });

  testWidgets('expanded screen keeps feed body mounted', (tester) async {
    final router = _HarnessRouter();
    await _pumpInbox(
      tester,
      logicalSize: const Size(1024, 800),
      router: router,
    );

    expect(find.byType(TenturaTopBar), findsOneWidget);
    expect(find.byType(TenturaPrimaryTabBar), findsNothing);
    expect(find.byType(UpdatesFeedPane), findsOneWidget);
  });

  testWidgets('regular width keeps host TopBar without tab strip', (
    tester,
  ) async {
    await _pumpInbox(
      tester,
      logicalSize: const Size(800, 800),
      router: _HarnessRouter(),
    );

    expect(find.byType(TenturaTopBar), findsOneWidget);
    expect(find.byType(TenturaPrimaryTabBar), findsNothing);
    expect(find.byType(UpdatesFeedPane), findsOneWidget);
  });
}
