import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
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
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_test_support.dart';

// #491: the Requests filter is session state held above the tab shell, so an
// Archived choice outlives the visit (URL re-entry of #/home/work keeps it)
// and the screen then shows only archived work, which reads as data loss.
// The screen must say it is showing the archive and offer one tap back to
// Active requests (sort kept).

const _accountId = 'user-491';
const _liveId = 'beacon-live';
const _archivedId = 'beacon-archived';

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

Future<({AttentionCase attention, _Accounts accounts})> _bootAttention(
  AttentionRepositoryPort repo,
) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    repo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-archived-filter-notice-attention'),
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

Future<void> _pumpFor(WidgetTester tester, [int turns = 16]) async {
  for (var i = 0; i < turns; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpMyWork(
  WidgetTester tester, {
  required MyWorkCubit cubit,
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
    archivedCountHint: 1,
    myWorkLoaded: true,
  );

  await tester.binding.setSurfaceSize(const Size(360, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(360, 1200)),
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
  await _pumpFor(tester);
}

typedef _Harness = ({
  MyWorkCubit cubit,
  HomeAttentionCubit homeAttention,
  _Accounts accounts,
});

/// One live (non-archived) request on the desk and one in the archive.
Future<_Harness> _boot() async {
  final myWorkRepo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [_beacon(_liveId, 'Live request')],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 1,
    )
    ..archivedResult = (
      authoredArchived: [_beacon(_archivedId, 'Archived request')],
      helpOfferedArchived: const [],
    );
  final boot = await _bootAttention(
    StubAttentionRepository()..myWorkAttentionResult = const [],
  );
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
    Logger('my-work-archived-filter-notice'),
  );
  return (cubit: cubit, homeAttention: homeAttention, accounts: boot.accounts);
}

Set<String> _shownCardIds(WidgetTester tester) => {
  for (final w in tester.widgetList<MyWorkCardRouter>(
    find.byType(MyWorkCardRouter),
  ))
    w.vm.beaconId,
};

Future<void> _showArchived(WidgetTester tester, MyWorkCubit cubit) async {
  cubit.setFilter(MyWorkFilter.archived);
  for (var i = 0; i < 32 && !cubit.state.archivedDataFetched; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _pumpFor(tester);
}

void main() {
  final l10n = L10nEn();

  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-archived-notice'));
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
    if (GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.unregister<ClosureRepository>();
    }
  });

  testWidgets(
    'Archived filter says it is showing the archive and one tap returns to '
    'Active with the sort kept',
    (tester) async {
      final h = await _boot();
      await _pumpMyWork(tester, cubit: h.cubit, homeAttention: h.homeAttention);

      // Preconditions: the desk starts on Active and shows the live request.
      expect(h.cubit.state.filter, MyWorkFilter.active);
      expect(_shownCardIds(tester), {_liveId});

      h.cubit.setSort(MyWorkSort.alphabetical);
      await _pumpFor(tester, 4);
      await _showArchived(tester, h.cubit);

      // The repro: only the archived request is listed, the live one is gone.
      expect(h.cubit.state.filter, MyWorkFilter.archived);
      expect(_shownCardIds(tester), {_archivedId});

      // The screen names what it is showing and offers the way back.
      expect(
        find.text(l10n.myWorkShowingArchived, findRichText: true),
        findsOneWidget,
      );
      final showActive = find.text(l10n.myWorkShowActive, findRichText: true);
      expect(showActive, findsOneWidget);

      await tester.ensureVisible(showActive);
      await tester.tap(showActive);
      await _pumpFor(tester);

      expect(h.cubit.state.filter, MyWorkFilter.active);
      expect(h.cubit.state.sort, MyWorkSort.alphabetical);
      expect(_shownCardIds(tester), {_liveId});
      expect(
        find.text(l10n.myWorkShowingArchived, findRichText: true),
        findsNothing,
      );
      expect(
        find.text(l10n.myWorkShowActive, findRichText: true),
        findsNothing,
      );

      unawaited(h.cubit.close());
      unawaited(h.homeAttention.close());
      unawaited(h.accounts.close());
    },
  );

  testWidgets('Active filter shows no archive notice', (tester) async {
    final h = await _boot();
    await _pumpMyWork(tester, cubit: h.cubit, homeAttention: h.homeAttention);

    expect(h.cubit.state.filter, MyWorkFilter.active);
    expect(_shownCardIds(tester), {_liveId});
    expect(
      find.text(l10n.myWorkShowingArchived, findRichText: true),
      findsNothing,
    );
    expect(find.text(l10n.myWorkShowActive, findRichText: true), findsNothing);

    unawaited(h.cubit.close());
    unawaited(h.homeAttention.close());
    unawaited(h.accounts.close());
  });

  test('archive notice copy is translated in Russian', () {
    final ru = L10nRu();
    expect(ru.myWorkShowingArchived, isNotEmpty);
    expect(ru.myWorkShowActive, isNotEmpty);
    expect(ru.myWorkShowingArchived, isNot(l10n.myWorkShowingArchived));
    expect(ru.myWorkShowActive, isNot(l10n.myWorkShowActive));
  });

  test('a fresh Requests desk (app start) opens on Active', () async {
    // Guard: whatever the fix does, it must not start persisting the filter
    // across app starts. A new cubit is what a reload builds.
    final previous = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(),
    );
    await previous.stream.firstWhere((s) => s.isSuccess);
    previous.setFilter(MyWorkFilter.archived);
    await previous.stream.firstWhere((s) => s.archivedDataFetched);
    unawaited(previous.close());

    final next = MyWorkCubit(
      userId: _accountId,
      myWorkCase: buildTestMyWorkCase(),
    );
    expect(next.state.filter, MyWorkFilter.active);
    unawaited(next.close());
  });
}
