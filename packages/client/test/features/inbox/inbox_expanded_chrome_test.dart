import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

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

class _Repository implements AttentionRepositoryPort {
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
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

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

Future<void> _pumpInbox(
  WidgetTester tester, {
  required Size logicalSize,
  Widget Function(String beaconId, VoidCallback onLeave)? embeddedPaneBuilder,
}) async {
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
  addTearDown(inboxCubit.close);

  final accounts = _Accounts();
  addTearDown(accounts.close);
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final attentionCase = AttentionCase(
    _Repository(),
    accounts,
    sync.case_,
    noopBlockCase(),
    Logger('inbox-chrome-test'),
  );
  addTearDown(attentionCase.dispose);
  final attention = HomeAttentionCubit(
    attentionCase,
    accounts,
    Logger('inbox-chrome-test'),
  );
  addTearDown(attention.close);

  InboxScreen.debugEmbeddedPaneBuilder = embeddedPaneBuilder;
  addTearDown(() => InboxScreen.debugEmbeddedPaneBuilder = null);

  await tester.pumpWidget(
    MultiBlocProvider(
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
  );
  await tester.pump();
}

Widget _stubPane(String beaconId, VoidCallback onLeave) {
  return Column(
    children: [
      Text('stub-pane-$beaconId'),
      IconButton(
        key: const Key('inbox-stub-back'),
        onPressed: onLeave,
        icon: const Icon(Icons.arrow_back),
      ),
    ],
  );
}

void main() {
  test('expanded 1024 after extended rail still fits tight ops|room', () {
    const viewport = 1024.0;
    const extendedRail = 256.0;
    expect(
      myWorkDetailFitsOpsRoom(viewport - extendedRail, tight: true),
      isTrue,
    );
  });

  testWidgets('expanded list shows host TopBar and tab strip', (tester) async {
    await _pumpInbox(
      tester,
      logicalSize: const Size(1024, 800),
      embeddedPaneBuilder: _stubPane,
    );

    expect(find.byType(TenturaTopBar), findsOneWidget);
    expect(find.byType(TenturaPrimaryTabBar), findsOneWidget);
    expect(find.text('Needs-me request'), findsOneWidget);
    expect(find.text('stub-pane-b-needs'), findsNothing);
  });

  testWidgets('expanded tap opens pane and hides host TopBar', (tester) async {
    await _pumpInbox(
      tester,
      logicalSize: const Size(1024, 800),
      embeddedPaneBuilder: _stubPane,
    );

    await tester.tap(find.text('Needs-me request'));
    await tester.pump();

    expect(find.text('stub-pane-b-needs'), findsOneWidget);
    expect(find.byType(TenturaTopBar), findsNothing);
    expect(find.byType(TenturaPrimaryTabBar), findsNothing);
  });

  testWidgets('embedded back returns to list chrome', (tester) async {
    await _pumpInbox(
      tester,
      logicalSize: const Size(1024, 800),
      embeddedPaneBuilder: _stubPane,
    );

    await tester.tap(find.text('Needs-me request'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('inbox-stub-back')));
    await tester.pump();

    expect(find.text('stub-pane-b-needs'), findsNothing);
    expect(find.byType(TenturaTopBar), findsOneWidget);
    expect(find.byType(TenturaPrimaryTabBar), findsOneWidget);
    expect(find.text('Needs-me request'), findsOneWidget);
  });

  testWidgets('regular width keeps host TopBar and no pane', (tester) async {
    await _pumpInbox(
      tester,
      logicalSize: const Size(800, 800),
      embeddedPaneBuilder: _stubPane,
    );

    expect(find.byType(TenturaTopBar), findsOneWidget);
    expect(find.byType(TenturaPrimaryTabBar), findsOneWidget);
    expect(find.text('Needs-me request'), findsOneWidget);
    expect(find.text('stub-pane-b-needs'), findsNothing);
  });
}
