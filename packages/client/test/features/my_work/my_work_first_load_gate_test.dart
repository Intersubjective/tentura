import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_test_support.dart';

const _accountId = 'user-first-load';
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
  ProfileState get state => const ProfileState(
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
    TestRealtimeSyncPort syncPort,
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
    Logger('my-work-first-load-attention'),
  );
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  accounts.emit(_accountId);
  await _drain();
  return (attention: attention, accounts: accounts, syncPort: sync.port);
}

Future<({_VisibleFrame frame, DateTime mountedAt})> _pumpMyWork(
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

  DateTime? mountedAt;
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
            child: Builder(
              builder: (_) {
                // The gate starts its timers in initState, synchronously in
                // this first screen build. Fake time does not advance here.
                mountedAt ??= tester.binding.clock.now();
                return const MyWorkScreen();
              },
            ),
          ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await homeActivation.close();
    await inboxOperational.close();
  });
  // pumpWidget performs the first build; capture it before another pump.
  return (frame: _visibleFrame(), mountedAt: mountedAt!);
}

/// Keeps the card read pending until the test releases the network response.
class _ControlledMyWorkRepository extends FakeMyWorkRepository {
  Completer<MyWorkInitResult> response = Completer<MyWorkInitResult>();
  int reads = 0;

  @override
  Future<MyWorkInitResult> fetchInit({
    required String userId,
    List<String> obligationBeaconIds = const [],
  }) {
    reads++;
    return response.future;
  }
}

/// Holds attention separately from cards, including during background reads.
class _ControlledAttentionRepository extends StubAttentionRepository {
  Completer<List<MyWorkBeaconAttention>> response =
      Completer<List<MyWorkBeaconAttention>>();
  int reads = 0;

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention(Set<String> beaconIds) {
    reads++;
    return response.future;
  }
}

typedef _VisibleFrame = ({
  int gateSpinners,
  int allSpinners,
  int needsYou,
  int inProgress,
  int cards,
});

_VisibleFrame _visibleFrame() => (
  gateSpinners: find
      .descendant(
        of: find.byType(TenturaFirstLoadGate),
        matching: find.byType(CircularProgressIndicator),
      )
      .evaluate()
      .length,
  allSpinners: find.byType(CircularProgressIndicator).evaluate().length,
  needsYou: find.textContaining('NEEDS YOU').evaluate().length,
  inProgress: find.textContaining('IN PROGRESS').evaluate().length,
  cards:
      find.text('Active request').evaluate().length +
      find.text('Review request').evaluate().length,
);

const _waiting = (
  gateSpinners: 1,
  allSpinners: 1,
  needsYou: 0,
  inProgress: 0,
  cards: 0,
);
const _beforeSpinner = (
  gateSpinners: 0,
  allSpinners: 0,
  needsYou: 0,
  inProgress: 0,
  cards: 0,
);
const _loaded = (
  gateSpinners: 0,
  allSpinners: 0,
  needsYou: 1,
  inProgress: 1,
  cards: 2,
);

Future<void> _flush(WidgetTester tester) async {
  // Flush source completion and widget rebuilds without advancing gate time.
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}

Future<
  ({
    MyWorkCubit cubit,
    FakeForwardRepository forwards,
    _VisibleFrame firstFrame,
    DateTime mountedAt,
  })
>
_startMyWork(
  WidgetTester tester,
  _ControlledMyWorkRepository repo,
  _ControlledAttentionRepository attentionRepo,
) async {
  repo.initResult = (
    authoredNonArchived: [
      _beacon(_beaconActive, 'Active request'),
      _beacon(_beaconNeedsYou, 'Review request'),
    ],
    helpOfferedNonArchived: const <MyWorkHelpOfferedRow>[],
    obligationBeacons: const <MyWorkObligationRow>[],
    archivedCountHint: 0,
  );
  attentionRepo.myWorkAttentionResult = [
    MyWorkBeaconAttention(
      beaconId: _beaconNeedsYou,
      unseenCount: 0,
      liveObligations: [_obligation('review', _beaconNeedsYou)],
    ),
  ];
  final boot = await _bootAttention(attentionRepo);
  final forwards = FakeForwardRepository();
  final case_ = buildTestMyWorkCase(
    repo: repo,
    forwardRepo: forwards,
    attentionCase: boot.attention,
  );
  final loadStartedAt = tester.binding.clock.now();
  final cubit = MyWorkCubit(userId: _accountId, myWorkCase: case_);
  final homeAttention = HomeAttentionCubit(
    boot.attention,
    boot.accounts,
    Logger('my-work-first-load'),
  );
  addTearDown(() async {
    await cubit.close();
    await homeAttention.close();
    await forwards.dispose();
    await boot.attention.dispose();
    await boot.accounts.close();
    await boot.syncPort.dispose();
    GetIt.I.unregister<AttentionCase>();
    GetIt.I.unregister<InviteAcceptedSetupPort>();
    GetIt.I.unregister<RealtimeSyncCase>();
  });
  final firstFrame = await _pumpMyWork(
    tester,
    cubit: cubit,
    homeAttention: homeAttention,
  );
  // The card read may begin before the widget mounts, but both occur at
  // exactly the same fake-clock instant. No elapsed load time is uncounted.
  expect(firstFrame.mountedAt, loadStartedAt);
  expect(tester.binding.clock.now(), firstFrame.mountedAt);
  return (
    cubit: cubit,
    forwards: forwards,
    firstFrame: firstFrame.frame,
    mountedAt: firstFrame.mountedAt,
  );
}

void _expectLoadedSections(WidgetTester tester) {
  final needsYou = find.textContaining('NEEDS YOU · 1');
  final review = find.text('Review request');
  final inProgress = find.textContaining('IN PROGRESS');
  final active = find.text('Active request');
  for (final finder in [needsYou, review, inProgress, active]) {
    expect(finder, findsOneWidget);
  }
  // Check the contents of each displayed section by their reading order:
  // Review belongs under Needs you; Active belongs under In progress.
  expect(
    tester.getTopLeft(needsYou).dy,
    lessThan(tester.getTopLeft(review).dy),
  );
  expect(
    tester.getTopLeft(review).dy,
    lessThan(tester.getTopLeft(inProgress).dy),
  );
  expect(
    tester.getTopLeft(inProgress).dy,
    lessThan(tester.getTopLeft(active).dy),
  );
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

Future<void> _pumpToElapsed(
  WidgetTester tester,
  DateTime mountedAt,
  Duration elapsed,
) async {
  final current = tester.binding.clock.now().difference(mountedAt);
  expect(current, lessThanOrEqualTo(elapsed));
  await tester.pump(elapsed - current);
  expect(tester.binding.clock.now().difference(mountedAt), elapsed);
}

void main() {
  setUp(() {
    GetIt.I.registerSingleton<Logger>(Logger('my-work-first-load'));
    GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
  });
  tearDown(() async {
    await GetIt.I<BeaconRepository>().dispose();
    GetIt.I.unregister<BeaconRepository>();
    GetIt.I.unregister<ClosureRepository>();
    GetIt.I.unregister<Logger>();
  });

  testWidgets(
    'My Work shows one gate spinner after 150 ms while initial sources are pending',
    (tester) async {
      final repo = _ControlledMyWorkRepository();
      final attentionRepo = _ControlledAttentionRepository();
      final harness = await _startMyWork(tester, repo, attentionRepo);
      await _flush(tester);
      expect(repo.reads, 1);
      await _pumpToElapsed(
        tester,
        harness.mountedAt,
        const Duration(milliseconds: 151),
      );
      expect(repo.response.isCompleted, isFalse);
      expect(attentionRepo.response.isCompleted, isFalse);
      expect(
        find.descendant(
          of: find.byType(TenturaFirstLoadGate),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason:
            'The gate spinner must be visible after its 150 ms delay '
            'while the first card response is still pending',
      );
      expect(_visibleFrame(), _waiting);
    },
  );

  testWidgets(
    'My Work withholds partial sections until cards and attention arrive and refreshes in place',
    (tester) async {
      final repo = _ControlledMyWorkRepository();
      final attentionRepo = _ControlledAttentionRepository();
      final harness = await _startMyWork(tester, repo, attentionRepo);
      await _flush(tester);
      expect(repo.reads, 1);
      expect(attentionRepo.reads, 0);
      await tester.pump(const Duration(milliseconds: 149));
      final beforeDelay = _visibleFrame();
      await tester.pump(const Duration(milliseconds: 2));

      final waitingForCards = <_VisibleFrame>[_visibleFrame()];
      // Sample every rendered frame while the card source is pending.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(repo.response.isCompleted, isFalse);
        waitingForCards.add(_visibleFrame());
      }

      repo.response.complete(repo.initResult);
      await _flush(tester);
      expect(attentionRepo.reads, 1);
      expect(attentionRepo.response.isCompleted, isFalse);
      final waitingForAttention = <_VisibleFrame>[_visibleFrame()];
      // Cards are now available, but the section split needs attention.
      // Stay well inside the 2.5-second escape timeout.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(attentionRepo.response.isCompleted, isFalse);
        waitingForAttention.add(_visibleFrame());
      }
      attentionRepo.response.complete(attentionRepo.myWorkAttentionResult);
      await _flush(tester);
      expect(_visibleFrame(), _loaded);
      expect(find.textContaining('NEEDS YOU · 1'), findsOneWidget);
      _expectLoadedSections(tester);

      // A background signal starts another real read. Both source waits must
      // retain the loaded sections, including beyond the old gate timeout.
      repo.response = Completer<MyWorkInitResult>();
      attentionRepo.response = Completer<List<MyWorkBeaconAttention>>();
      harness.forwards.emitForwardCompleted(_beaconActive);
      await _flush(tester);
      expect(repo.reads, 2);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(repo.response.isCompleted, isFalse);
        expect(_visibleFrame(), _loaded);
      }
      repo.response.complete(repo.initResult);
      await _flush(tester);
      expect(attentionRepo.reads, 2);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(attentionRepo.response.isCompleted, isFalse);
        expect(_visibleFrame(), _loaded);
      }
      attentionRepo.response.complete(attentionRepo.myWorkAttentionResult);
      await _flush(tester);
      expect(_visibleFrame(), _loaded);

      // Completing a refresh must also apply newly received card content.
      repo.response = Completer<MyWorkInitResult>();
      attentionRepo.response = Completer<List<MyWorkBeaconAttention>>();
      attentionRepo.response.complete(attentionRepo.myWorkAttentionResult);
      harness.forwards.emitForwardCompleted(_beaconActive);
      await _flush(tester);
      expect(repo.reads, 3);
      repo.response.complete((
        authoredNonArchived: [
          _beacon(_beaconActive, 'Updated active request'),
          _beacon(_beaconNeedsYou, 'Review request'),
        ],
        helpOfferedNonArchived: const <MyWorkHelpOfferedRow>[],
        obligationBeacons: const <MyWorkObligationRow>[],
        archivedCountHint: 0,
      ));
      await _flush(tester);
      expect(attentionRepo.reads, 3);
      expect(find.text('Updated active request'), findsOneWidget);
      expect(find.text('Active request'), findsNothing);
      expect(find.text('Review request'), findsOneWidget);
      expect(find.textContaining('NEEDS YOU · 1'), findsOneWidget);
      expect(find.textContaining('IN PROGRESS'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Assert captured frames last so today's implementation also exercises
      // completion and both background source waits before failing.
      expect(
        waitingForAttention,
        everyElement(_waiting),
        reason:
            'Available cards must stay behind the gate spinner while '
            'their attention projection is still pending',
      );
      expect(waitingForCards, everyElement(_waiting));
      expect(harness.firstFrame, _beforeSpinner);
      expect(beforeDelay, _beforeSpinner);
    },
  );

  testWidgets(
    'My Work reveals available cards after 2.5 seconds when attention stalls',
    (tester) async {
      final repo = _ControlledMyWorkRepository();
      final attentionRepo = _ControlledAttentionRepository();
      final harness = await _startMyWork(tester, repo, attentionRepo);
      await _flush(tester);
      expect(repo.reads, 1);
      repo.response.complete(repo.initResult);
      await _flush(tester);
      expect(attentionRepo.reads, 1);
      expect(attentionRepo.response.isCompleted, isFalse);

      // The origin is the first screen build (gate initState), and the
      // harness proved the card read began at that same fake-clock instant.
      await _pumpToElapsed(
        tester,
        harness.mountedAt,
        const Duration(milliseconds: 151),
      );
      final beforeTimeout = <_VisibleFrame>[_visibleFrame()];
      // Poll the whole waiting interval, then check the exact boundary.
      for (var i = 0; i < 146; i++) {
        await _pumpToElapsed(
          tester,
          harness.mountedAt,
          Duration(milliseconds: 151 + (i + 1) * 16),
        );
        expect(attentionRepo.response.isCompleted, isFalse);
        beforeTimeout.add(_visibleFrame());
      } // 2487 ms
      await _pumpToElapsed(
        tester,
        harness.mountedAt,
        const Duration(milliseconds: 2499),
      );
      beforeTimeout.add(_visibleFrame());
      await _pumpToElapsed(
        tester,
        harness.mountedAt,
        const Duration(milliseconds: 2501),
      );
      expect(attentionRepo.response.isCompleted, isFalse);
      expect(find.text('Active request'), findsOneWidget);
      expect(find.text('Review request'), findsOneWidget);
      expect(find.textContaining('IN PROGRESS'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(attentionRepo.response.isCompleted, isFalse);
        expect(find.text('Active request'), findsOneWidget);
        expect(find.text('Review request'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      // A late source response fills the visible sections in place.
      attentionRepo.response.complete(attentionRepo.myWorkAttentionResult);
      await _flush(tester);
      expect(_visibleFrame(), _loaded);
      expect(find.textContaining('NEEDS YOU · 1'), findsOneWidget);
      _expectLoadedSections(tester);

      expect(
        beforeTimeout,
        everyElement(_waiting),
        reason:
            'Withhold partial sections through 2499 ms, then reveal '
            'available cards at 2501 ms without waiting for attention',
      );
    },
  );
}
