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
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_slow_desk_read_support.dart';
import 'my_work_test_support.dart';

const _accountId = 'user-dismiss-across-requests';
const _beaconA = 'beacon-a';
const _beaconB = 'beacon-b';

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
  ProfileState get state => const ProfileState(
    profile: Profile(id: _accountId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<
  ({
    AttentionCase attention,
    _Accounts accounts,
    TestRealtimeSyncPort sync,
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
  return (attention: attention, accounts: accounts, sync: sync.port);
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
              BlocProvider<InboxOperationalCubit>.value(
                value: inboxOperational,
              ),
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

AttentionReceipt _optionalEvent(String id, String beaconId) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'update',
  priority: 'normal',
  title: 'Update $id',
  body: 'Body of $id',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 10),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: beaconId,
);

Beacon _beacon(String id, String title) => Beacon.empty.copyWith(
  id: id,
  title: title,
  updatedAt: DateTime.utc(2026, 9, 5),
  status: BeaconStatus.open,
);

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-dismiss'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      unawaited(GetIt.I<AttentionCase>().dispose());
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
    if (GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.unregister<ClosureRepository>();
    }
  });

  Future<
    ({
      MyWorkCubit cubit,
      SlowDeskReadAttentionRepository repo,
      TestRealtimeSyncPort sync,
    })
  >
  pumpDeskWithTwoUpdates(WidgetTester tester) async {
    final attentionRepo = SlowDeskReadAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: _beaconA,
          unseenCount: 1,
          latestUnseen: _optionalEvent('r-a', _beaconA),
        ),
        MyWorkBeaconAttention(
          beaconId: _beaconB,
          unseenCount: 1,
          latestUnseen: _optionalEvent('r-b', _beaconB),
        ),
      ];
    final myWorkRepo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [
          _beacon(_beaconA, 'Request A'),
          _beacon(_beaconB, 'Request B'),
        ],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );

    final boot = await _bootAttention(attentionRepo);
    final homeAttention = HomeAttentionCubit(
      boot.attention,
      boot.accounts,
      Logger('dismiss-across-requests'),
    );
    final cubit = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(
        repo: myWorkRepo,
        attentionCase: boot.attention,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      await homeAttention.close();
      await boot.accounts.close();
    });

    await _pumpMyWork(tester, cubit: cubit, homeAttention: homeAttention);
    return (cubit: cubit, repo: attentionRepo, sync: boot.sync);
  }

  group('My Work update dismissal', () {
    testWidgets(
      "dismissing one Request's update and then another's clears each and "
      'removes each subcard',
      (tester) async {
        final desk = await pumpDeskWithTwoUpdates(tester);
        final dismiss = find.byKey(AttentionMiniCard.dismissButtonKey);
        final updateA = find.textContaining('Update r-a');
        final updateB = find.textContaining('Update r-b');
        Finder dismissOf(Finder update) => find.descendant(
          of: find.ancestor(
            of: update,
            matching: find.byType(AttentionMiniCard),
          ),
          matching: dismiss,
        );

        await tester.tap(dismissOf(updateA));
        await tester.pumpAndSettle();
        expect(desk.repo.clearSnapshotCalls, ['r-a']);
        expect(updateA, findsNothing);
        expect(updateB, findsOneWidget);

        await tester.tap(dismissOf(updateB));
        await tester.pumpAndSettle();

        expect(desk.repo.clearSnapshotCalls, ['r-a', 'r-b']);
        expect(desk.repo.clearCalls, hasLength(2));
        expect(updateB, findsNothing);
        expect(dismiss, findsNothing);
        expect(
          desk.cubit.state.attentionByBeacon[_beaconB]?.latestUnseen,
          isNull,
        );
      },
    );

    testWidgets(
      "an update dismissed after another Request's update is dismissed while "
      'the desk re-read is slow is cleared and stays removed',
      (tester) async {
        final desk = await pumpDeskWithTwoUpdates(tester);
        final dismiss = find.byKey(AttentionMiniCard.dismissButtonKey);
        final updateA = find.textContaining('Update r-a');
        final updateB = find.textContaining('Update r-b');
        Finder dismissOf(Finder update) => find.descendant(
          of: find.ancestor(
            of: update,
            matching: find.byType(AttentionMiniCard),
          ),
          matching: dismiss,
        );
        expect(updateA, findsOneWidget);
        expect(updateB, findsOneWidget);

        // First ×, on Request A. Let its row collapse and its clear go out, but
        // do not wait for anything the desk does afterwards.
        await tester.tap(dismissOf(updateA));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(desk.repo.clearSnapshotCalls, ['r-a']);
        expect(updateA, findsNothing);

        // The server announces that clear; the desk re-reads everything and
        // that answer is slow.
        desk.repo.holdNextRead();
        desk.sync.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.notification,
            aggregateId: 'r-a',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        // Deliver the hint, then advance fake time so its trailing refresh
        // starts before waiting for the held network response in runAsync.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => desk.repo.readIsHeld);

        // Second ×, on Request B, while that re-read is outstanding.
        expect(updateB, findsOneWidget);
        await tester.tap(dismissOf(updateB));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          desk.repo.clearSnapshotCalls,
          ['r-a', 'r-b'],
          reason: "B's × must send B's own clear",
        );
        expect(desk.repo.clearCalls, hasLength(2));
        expect(updateB, findsNothing);

        desk.repo.releaseHeldRead();
        await tester.pumpAndSettle();

        expect(
          updateB,
          findsNothing,
          reason:
              "the re-read began before B's clear; its older answer must "
              "not put B's dismissed update back",
        );
        expect(dismiss, findsNothing);
        expect(
          desk.cubit.state.attentionByBeacon[_beaconB]?.latestUnseen,
          isNull,
        );
        expect(
          desk.cubit.state.attentionByBeacon[_beaconA]?.latestUnseen,
          isNull,
        );
      },
    );
  });
}
