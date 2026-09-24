import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/widget/caught_up_panel.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_test_support.dart';

const _accountId = 'user-sectioned-body';
const _beaconActive = 'beacon-active';
const _beaconNeedsYou = 'beacon-needs-you';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
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

AttentionReceipt _obligation(String id, String beaconId) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Review needed',
  body: 'Please review',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 10),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: beaconId,
  requiresAction: true,
);

Beacon _beacon(String id, String title) => Beacon.empty.copyWith(
  id: id,
  title: title,
  updatedAt: DateTime.utc(2026, 9, 5),
  status: BeaconStatus.open,
);

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<
  ({
    AttentionCase attention,
    _Accounts accounts,
  })
>
_bootAttention(AttentionRepositoryPort repo) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-sectioned-body-attention'),
  );
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  accounts.emit(_accountId);
  await _drain();
  return (attention: attention, accounts: accounts);
}

Future<void> _pumpMyWork(
  WidgetTester tester, {
  required MyWorkCubit cubit,
  required HomeAttentionCubit homeAttention,
  double textScale = 1,
}) async {
  final homeActivation = HomeActivationCubit(_FakeOrientationPrefs());
  final inboxOperational = InboxOperationalCubit()
    ..report(needsMeCount: 0, loadComplete: true);
  await homeActivation.bindAccount(_accountId);
  homeActivation.reportMyWork(
    accountId: _accountId,
    myWorkCardCount: 2,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );

  await tester.binding.setSurfaceSize(const Size(360, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 1200),
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<MyWorkCubit>.value(value: cubit),
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
    ),
  );
  await tester.pump();
  for (var i = 0; i < 32 && !cubit.state.isSuccess; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-sectioned-body'));
    }
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
    if (GetIt.I.isRegistered<AttentionCase>()) {
      final attention = GetIt.I<AttentionCase>();
      unawaited(attention.dispose());
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.unregister<BeaconRepository>();
    }
    if (GetIt.I.isRegistered<EvaluationRepository>()) {
      GetIt.I.unregister<EvaluationRepository>();
    }
  });

  testWidgets('redesign on: section headers and obligation count at 360×1200',
      (tester) async {

    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: _beaconNeedsYou,
          unseenCount: 0,
          liveObligations: [
            _obligation('o1', _beaconNeedsYou),
            _obligation('o2', _beaconNeedsYou),
            _obligation('o3', _beaconNeedsYou),
          ],
        ),
      ];

    final myWorkRepo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [
          _beacon(_beaconActive, 'Active request'),
          _beacon(_beaconNeedsYou, 'Needs you request'),
        ],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );

    final boot = await _bootAttention(attentionRepo);
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('sectioned'),
    );
    final cubit = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: myWorkRepo,
        attentionCase: boot.attention,
      ),
    );

    await _pumpMyWork(tester, cubit: cubit, homeAttention: homeAttention);

    expect(find.textContaining('NEEDS YOU · 3'), findsOneWidget);
    expect(find.textContaining('IN PROGRESS'), findsOneWidget);
    unawaited(cubit.close());
    unawaited(homeAttention.close());
    unawaited(boot.accounts.close());
  });

  testWidgets('redesign on: no Needs you header when zero obligations',
      (tester) async {

    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = const [];

    final myWorkRepo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [_beacon(_beaconActive, 'Only active')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );

    final boot = await _bootAttention(attentionRepo);
    final cubit = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: myWorkRepo,
        attentionCase: boot.attention,
      ),
    );
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('no-needs-you'),
    );

    await _pumpMyWork(tester, cubit: cubit, homeAttention: homeAttention);

    expect(find.textContaining('NEEDS YOU'), findsNothing);
    expect(find.textContaining('IN PROGRESS'), findsOneWidget);

    unawaited(cubit.close());
    unawaited(homeAttention.close());
    unawaited(boot.accounts.close());
  });

  testWidgets(
    'D18: a desk with work and no attention on it says so, once',
    (tester) async {
      // "My Desk can be attention-clear while authored / active-help Requests
      // remain" — so the line and the cards must both be there.
      final attentionRepo = StubAttentionRepository()
        ..myWorkAttentionResult = const [];

      final myWorkRepo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [_beacon(_beaconActive, 'Still my work')],
          helpOfferedNonArchived: const [],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );

      final boot = await _bootAttention(attentionRepo);
      final cubit = MyWorkCubit(
        userId: _accountId,
        myWorkCase: buildTestMyWorkCase(
          repo: myWorkRepo,
          attentionCase: boot.attention,
        ),
      );
      final homeAttention = HomeAttentionCubit(
        boot.attention,
        boot.accounts,
        Logger('desk-caught-up'),
      );

      await _pumpMyWork(tester, cubit: cubit, homeAttention: homeAttention);

      final l10n = L10nEn();
      expect(find.text(l10n.myWorkCaughtUp), findsOneWidget);
      expect(
        find.text('Still my work'),
        findsOneWidget,
        reason: 'caught up is not the same claim as an empty desk',
      );
      expect(
        find.byKey(CaughtUpPanel.illustrationKey),
        findsNothing,
        reason: 'a line above live work is a note, not a celebration',
      );

      unawaited(cubit.close());
      unawaited(homeAttention.close());
      unawaited(boot.accounts.close());
    },
  );

  testWidgets('D18: a desk with a live obligation says nothing reassuring', (
    tester,
  ) async {
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: _beaconNeedsYou,
          unseenCount: 0,
          liveObligations: [_obligation('o1', _beaconNeedsYou)],
        ),
      ];

    final myWorkRepo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [
          _beacon(_beaconActive, 'Active request'),
          _beacon(_beaconNeedsYou, 'Needs you request'),
        ],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );

    final boot = await _bootAttention(attentionRepo);
    final cubit = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: myWorkRepo,
        attentionCase: boot.attention,
      ),
    );
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('desk-not-caught-up'),
    );

    await _pumpMyWork(tester, cubit: cubit, homeAttention: homeAttention);

    final l10n = L10nEn();
    // The positive first: this screen really did render.
    expect(find.textContaining('NEEDS YOU · 1'), findsOneWidget);
    expect(find.text(l10n.myWorkCaughtUp), findsNothing);

    unawaited(cubit.close());
    unawaited(homeAttention.close());
    unawaited(boot.accounts.close());
  });

  testWidgets('redesign on: first card fully visible on first paint',
      (tester) async {

    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = const [];

    final myWorkRepo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [_beacon(_beaconActive, 'Top card title')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );

    final boot = await _bootAttention(attentionRepo);
    final cubit = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: myWorkRepo,
        attentionCase: boot.attention,
      ),
    );
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('first-card'),
    );

    await _pumpMyWork(
      tester,
      cubit: cubit,
      homeAttention: homeAttention,
      textScale: 1.3,
    );

    final cardFinder = find.byType(MyWorkCardRouter);
    expect(cardFinder, findsWidgets);
    final rect = tester.getRect(cardFinder.first);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(1200));
    unawaited(cubit.close());
    unawaited(homeAttention.close());
    unawaited(boot.accounts.close());
  });
}
