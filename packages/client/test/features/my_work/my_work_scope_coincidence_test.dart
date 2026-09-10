import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/widget/my_work_navbar_item.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/domain/my_work_obligations_gate.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_test_support.dart';

const _accountId = 'user-scope-coincidence';
const _beaconId = 'beacon-scope-coincidence';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _CoincidenceFeedRepository implements AttentionRepositoryPort {
  _CoincidenceFeedRepository({required this.liveReceipts});

  List<AttentionReceipt> liveReceipts;
  final settledIds = <String>{};

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async {
    if (view != AttentionView.needsYou) {
      return const AttentionFeed(
        summary: AttentionSummary(),
        page: AttentionFeedPage(),
      );
    }
    final items = liveReceipts
        .where((r) => !settledIds.contains(r.id))
        .toList(growable: false);
    return AttentionFeed(
      summary: AttentionSummary(needsYouTotal: items.length),
      page: AttentionFeedPage(items: items),
    );
  }

  @override
  Future<Set<String>> liveObligationBeacons() async => {_beaconId};

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      const {};

  @override
  Future<int> markAllSeen() async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    settledIds.add(receiptId);
    return 1;
  }
}

AttentionReceipt _obligationReceipt(
  String id, {
  String title = 'Review needed',
}) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: title,
  body: 'Please review this request',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 10),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  beaconId: _beaconId,
  presentationKey: 'needs_me',
  requiresAction: true,
);

Beacon _authoredBeacon() => Beacon.empty.copyWith(
  id: _beaconId,
  title: 'Authored with obligation',
  updatedAt: DateTime(2026, 9, 1),
  status: BeaconStatus.open,
);

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

void _registerGate(bool enabled) {
  if (GetIt.I.isRegistered<bool>(instanceName: myWorkObligationsGate)) {
    GetIt.I.unregister<bool>(instanceName: myWorkObligationsGate);
  }
  GetIt.I.registerSingleton<bool>(enabled, instanceName: myWorkObligationsGate);
}

final class _FakeOrientationPrefs implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<void> setActivated({required String userId}) async {}

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<void> setOrientationDismissed({required String userId}) async {}

  @override
  Future<void> resetFirstRunState({required String userId}) async {}

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {}
}

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => ProfileState(
    profile: Profile(id: _accountId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

int _obligationRowCount(WidgetTester tester, L10n l10n) =>
    find.text(l10n.updatesMarkDone).evaluate().length;

String? _myWorkBadgeLabel(WidgetTester tester) {
  final badgeFinder = find.descendant(
    of: find.byType(MyWorkNavbarItem),
    matching: find.byType(Badge),
  );
  if (badgeFinder.evaluate().isEmpty) return null;
  final badge = tester.widget<Badge>(badgeFinder);
  final label = badge.label;
  if (label is Text) return label.data;
  return null;
}

Future<void> _pumpScopeFixture(
  WidgetTester tester, {
  required MyWorkCubit myWork,
  required HomeAttentionCubit homeAttention,
}) async {
  final homeActivation = HomeActivationCubit(_FakeOrientationPrefs());
  final inboxOperational = InboxOperationalCubit()
    ..report(needsMeCount: 0, loadComplete: true);
  await homeActivation.bindAccount(_accountId);
  homeActivation.reportMyWork(
    accountId: _accountId,
    myWorkCardCount: 1,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );

  homeAttention.setActiveHomeTab(HomeTab.inbox);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: myWork),
            BlocProvider<HomeActivationCubit>.value(value: homeActivation),
            BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
            BlocProvider<InboxOperationalCubit>.value(value: inboxOperational),
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider(create: (_) => HomeTabReselectCubit()),
            BlocProvider(create: (_) => ScreenCubit.local()),
          ],
          child: Column(
            children: [
              const MyWorkNavbarItem(),
              Expanded(child: const MyWorkScreen()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 24 && !myWork.state.isSuccess; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<
  ({
    AttentionCase attention,
    _Accounts accounts,
    HomeAttentionCubit homeAttention,
    _CoincidenceFeedRepository repo,
    TestRealtimeSyncPort realtime,
  })
>
_boot({
  required List<AttentionReceipt> liveReceipts,
}) async {
  final accounts = _Accounts();
  final repo = _CoincidenceFeedRepository(liveReceipts: liveReceipts);
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-scope-coincidence'),
  );
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  accounts.emit(_accountId);
  await _drain();
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('my-work-scope-coincidence'),
  );
  await attention.refresh(
    destinationId: AttentionFeedDestinationId.myWorkObligations,
  );
  await _drain();
  return (
    attention: attention,
    accounts: accounts,
    homeAttention: homeAttention,
    repo: repo,
    realtime: sync.port,
  );
}

Future<void> _disposeBoot(
  ({
    AttentionCase attention,
    _Accounts accounts,
    HomeAttentionCubit homeAttention,
    TestRealtimeSyncPort realtime,
  })
  boot,
) async {
  unawaited(boot.homeAttention.close());
  unawaited(boot.attention.dispose());
  unawaited(boot.realtime.dispose());
  await boot.accounts.close();
  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
    GetIt.I.unregister<InviteAcceptedSetupPort>();
  }
  if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
    GetIt.I.unregister<RealtimeSyncCase>();
  }
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-scope-coincidence'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<EvaluationRepository>()) {
      GetIt.I.registerSingleton<EvaluationRepository>(
        EvaluationRepositoryMock(),
      );
    }
    _registerGate(true);
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.unregister<BeaconRepository>();
    }
    if (GetIt.I.isRegistered<EvaluationRepository>()) {
      GetIt.I.unregister<EvaluationRepository>();
    }
    if (GetIt.I.isRegistered<bool>(instanceName: myWorkObligationsGate)) {
      GetIt.I.unregister<bool>(instanceName: myWorkObligationsGate);
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
  });

  testWidgets('badge count matches mounted obligation rows', (tester) async {
    final boot = await _boot(
      liveReceipts: [_obligationReceipt('r-coinc-1')],
    );
    final myWork = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: FakeMyWorkRepository()
          ..initResult = (
            authoredNonArchived: [_authoredBeacon()],
            helpOfferedNonArchived: const [],
            obligationBeacons: const [],
            archivedCountHint: 0,
          ),
        attentionCase: boot.attention,
        obligationsGateEnabled: true,
      ),
    );

    await _pumpScopeFixture(
      tester,
      myWork: myWork,
      homeAttention: boot.homeAttention,
    );

    final l10n = L10n.of(tester.element(find.byType(MyWorkScreen)))!;
    final rows = _obligationRowCount(tester, l10n);
    expect(rows, 1);
    expect(_myWorkBadgeLabel(tester), '$rows');
    expect(boot.homeAttention.state.myWorkObligationCount, rows);

    unawaited(myWork.close());
    await _disposeBoot((
      attention: boot.attention,
      accounts: boot.accounts,
      homeAttention: boot.homeAttention,
      realtime: boot.realtime,
    ));
  });

  testWidgets(
    'multiplicity: two live receipts on one Request show two badge and rows but one card',
    (tester) async {
      final boot = await _boot(
        liveReceipts: [
          _obligationReceipt('r-multi-1', title: 'Review needed A'),
          _obligationReceipt('r-multi-2', title: 'Review needed B'),
        ],
      );
      final myWork = MyWorkCubit(
        userId: _accountId,
        myWorkCase: buildTestMyWorkCase(
          repo: FakeMyWorkRepository()
            ..initResult = (
              authoredNonArchived: [_authoredBeacon()],
              helpOfferedNonArchived: const [],
              obligationBeacons: const [],
              archivedCountHint: 0,
            ),
          attentionCase: boot.attention,
          obligationsGateEnabled: true,
        ),
      );

      await _pumpScopeFixture(
        tester,
        myWork: myWork,
        homeAttention: boot.homeAttention,
      );

      expect(boot.homeAttention.state.myWorkObligationCount, 2);
      expect(_myWorkBadgeLabel(tester), '2');
      expect(find.text('Authored with obligation'), findsOneWidget);

      unawaited(myWork.close());
      await _disposeBoot((
        attention: boot.attention,
        accounts: boot.accounts,
        homeAttention: boot.homeAttention,
        realtime: boot.realtime,
      ));
    },
  );

  testWidgets(
    'settling one of two obligations keeps the card and decrements the badge',
    (tester) async {
      final boot = await _boot(
        liveReceipts: [
          _obligationReceipt('r-part-1', title: 'Review needed A'),
          _obligationReceipt('r-part-2', title: 'Review needed B'),
        ],
      );
      final myWork = MyWorkCubit(
        userId: _accountId,
        myWorkCase: buildTestMyWorkCase(
          repo: FakeMyWorkRepository()
            ..initResult = (
              authoredNonArchived: [_authoredBeacon()],
              helpOfferedNonArchived: const [],
              obligationBeacons: const [],
              archivedCountHint: 0,
            ),
          attentionCase: boot.attention,
          obligationsGateEnabled: true,
        ),
      );

      await _pumpScopeFixture(
        tester,
        myWork: myWork,
        homeAttention: boot.homeAttention,
      );

      final l10n = L10n.of(tester.element(find.byType(MyWorkScreen)))!;
      expect(boot.homeAttention.state.myWorkObligationCount, 2);
      expect(_myWorkBadgeLabel(tester), '2');

      await tester.tap(find.text(l10n.updatesMarkDone).first);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(boot.homeAttention.state.myWorkObligationCount, 1);
      expect(_myWorkBadgeLabel(tester), '1');
      expect(find.text('Authored with obligation'), findsOneWidget);

      unawaited(myWork.close());
      await _disposeBoot((
        attention: boot.attention,
        accounts: boot.accounts,
        homeAttention: boot.homeAttention,
        realtime: boot.realtime,
      ));
    },
  );
}
