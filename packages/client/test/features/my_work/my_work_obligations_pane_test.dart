import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/domain/my_work_obligations_gate.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligations_pane.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'my_work_test_support.dart';

const _accountId = 'user-obligations-test';
const _beaconId = 'beacon-obligation-merge';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ObligationsFeedRepository implements AttentionRepositoryPort {
  _ObligationsFeedRepository({required this.liveReceipts});

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

AttentionReceipt _obligationReceipt(String id) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Review needed',
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

// `Future.delayed`, even with Duration.zero, schedules via a Timer, which
// AutomatedTestWidgetsFlutterBinding fakes and never fires without an
// explicit WidgetTester.pump() -- this runs before any pump has happened.
// Future.microtask is not Timer-based, so it drains on its own.
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

Future<({AttentionCase attention, _Accounts accounts})> _bootAttention(
  _ObligationsFeedRepository repo,
) async {
  final accounts = _Accounts();
  final attention = AttentionCase(
    repo,
    accounts,
    buildTestRealtimeSync().case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-obligations-pane-test'),
  );
  GetIt.I.registerSingleton<AttentionCase>(attention);
  accounts.emit(_accountId);
  await _drain();
  return (attention: attention, accounts: accounts);
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

Future<void> _pumpMyWorkScreen(
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
          child: const MyWorkScreen(),
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

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-obligations-pane'));
    }
    // _AuthoredActiveCard looks these up directly from GetIt at build time
    // (not via MyWorkCase's constructor injection), so a widget-mounting
    // test needs them registered even though buildTestMyWorkCase() already
    // wires its own FakeBeaconRepository into the use case separately.
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<EvaluationRepository>()) {
      GetIt.I.registerSingleton<EvaluationRepository>(
        EvaluationRepositoryMock(),
      );
    }
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
    if (GetIt.I.isRegistered<AttentionCase>()) {
      final attention = GetIt.I<AttentionCase>();
      unawaited(attention.dispose());
      GetIt.I.unregister<AttentionCase>();
    }
  });

  testWidgets('gate off does not mount the obligations pane', (tester) async {
    _registerGate(false);
    final repo = _ObligationsFeedRepository(
      liveReceipts: [_obligationReceipt('r-gate-off')],
    );
    final boot = await _bootAttention(repo);
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('gate-off'),
    );
    final myWork = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: FakeMyWorkRepository(),
        attentionCase: boot.attention,
        obligationsGateEnabled: false,
      ),
    );

    await _pumpMyWorkScreen(
      tester,
      myWork: myWork,
      homeAttention: homeAttention,
    );

    expect(find.byKey(const Key(TestIds.myWorkObligationsPane)), findsNothing);

    unawaited(homeAttention.close());
    unawaited(myWork.close());
  });

  testWidgets('gate on lists live obligations in the feed', (tester) async {
    _registerGate(true);
    const receiptId = 'r-live-1';
    final repo = _ObligationsFeedRepository(
      liveReceipts: [_obligationReceipt(receiptId)],
    );
    final boot = await _bootAttention(repo);
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('gate-on-list'),
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

    await _pumpMyWorkScreen(
      tester,
      myWork: myWork,
      homeAttention: homeAttention,
    );

    expect(find.byKey(const Key(TestIds.myWorkObligationsPane)), findsOneWidget);
    expect(find.text('Review needed'), findsOneWidget);

    unawaited(homeAttention.close());
    unawaited(myWork.close());
  });

  testWidgets(
    'settling an obligation removes it from the pane but keeps the My Work card',
    (tester) async {
      _registerGate(true);
      const receiptId = 'r-settle-1';
      final repo = _ObligationsFeedRepository(
        liveReceipts: [_obligationReceipt(receiptId)],
      );
      final boot = await _bootAttention(repo);
      final homeAttention = HomeAttentionCubit(
        boot.attention,
        boot.accounts,
        Logger('settle-test'),
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

      await _pumpMyWorkScreen(
        tester,
        myWork: myWork,
        homeAttention: homeAttention,
      );

      final l10n = L10n.of(tester.element(find.byType(MyWorkScreen)))!;
      expect(find.text(l10n.updatesMarkDone), findsOneWidget);

      await tester.tap(find.text(l10n.updatesMarkDone));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Review needed'), findsNothing);
      expect(find.text('Authored with obligation'), findsOneWidget);

      unawaited(homeAttention.close());
      unawaited(myWork.close());
    },
  );

  testWidgets('MyWorkObligationsPane uses the needs-you destination session',
      (tester) async {
    _registerGate(true);
    const receiptId = 'r-pane-only';
    final repo = _ObligationsFeedRepository(
      liveReceipts: [_obligationReceipt(receiptId)],
    );
    final boot = await _bootAttention(repo);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              height: 480,
              width: 800,
              child: const MyWorkObligationsPane(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Review needed'), findsOneWidget);
    expect(
      boot.attention
          .feedSession(AttentionFeedDestinationId.myWorkObligations)
          .activeView,
      AttentionView.needsYou,
    );
  });
}
