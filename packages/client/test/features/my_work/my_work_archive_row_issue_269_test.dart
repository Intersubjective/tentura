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

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_test_support.dart';

// #269: the archive was reachable only through the filter menu; the
// "Archived (N)" shortcut existed only in the empty state. Owner decision:
// an "Archived (N)" / «Архив (N)» row sits at the bottom of the Requests
// list also when the list is not empty, opens the Archived filter, and is
// hidden when nothing is archived (N = 0) or when the archive is already
// shown. It reuses the empty-state key `myWorkEmptyArchiveShortcut`.

const _accountId = 'user-269';
const _liveId = 'beacon-live';
const _secondLiveId = 'beacon-live-2';

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
    Logger('my-work-archive-row-attention'),
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
  required int archivedCount,
}) async {
  final homeActivation = HomeActivationCubit(_FakeOrientationPrefs());
  final inboxOperational = InboxOperationalCubit()
    ..report(needsMeCount: 0, loadComplete: true);
  await homeActivation.bindAccount(_accountId);
  homeActivation.reportMyWork(
    accountId: _accountId,
    myWorkCardCount: 1,
    draftCount: 0,
    archivedCountHint: archivedCount,
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

/// Two live (non-archived) requests on the desk and [archivedCount] in the
/// archive.
Future<_Harness> _boot({required int archivedCount}) async {
  final myWorkRepo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [
        _beacon(_liveId, 'Live request'),
        _beacon(_secondLiveId, 'Second live request'),
      ],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: archivedCount,
    )
    ..archivedResult = (
      authoredArchived: [
        for (var i = 0; i < archivedCount; i++)
          _beacon('beacon-archived-$i', 'Archived request $i'),
      ],
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
    Logger('my-work-archive-row'),
  );
  return (cubit: cubit, homeAttention: homeAttention, accounts: boot.accounts);
}

Set<String> _shownCardIds(WidgetTester tester) => {
  for (final w in tester.widgetList<MyWorkCardRouter>(
    find.byType(MyWorkCardRouter),
  ))
    w.vm.beaconId,
};

void main() {
  final l10n = L10nEn();

  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-archive-row'));
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

  void close(_Harness h) {
    unawaited(h.cubit.close());
    unawaited(h.homeAttention.close());
    unawaited(h.accounts.close());
  }

  testWidgets(
    'non-empty list with 3 archived: Archived (3) row at the end opens the '
    'archive',
    (tester) async {
      final h = await _boot(archivedCount: 3);
      await _pumpMyWork(
        tester,
        cubit: h.cubit,
        homeAttention: h.homeAttention,
        archivedCount: 3,
      );

      expect(h.cubit.state.filter, MyWorkFilter.active);
      expect(_shownCardIds(tester), {_liveId, _secondLiveId});

      final row = find.text(
        l10n.myWorkEmptyArchiveShortcut(3),
        findRichText: true,
      );
      expect(row, findsOneWidget);
      await tester.ensureVisible(row);
      await _pumpFor(tester);

      // At the bottom: below every card in the list.
      final rowTop = tester.getRect(row).top;
      final cards = find.byType(MyWorkCardRouter);
      for (var i = 0; i < cards.evaluate().length; i++) {
        expect(
          rowTop,
          greaterThanOrEqualTo(tester.getRect(cards.at(i)).bottom),
        );
      }

      await tester.tap(row);
      for (var i = 0; i < 32 && !h.cubit.state.archivedDataFetched; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _pumpFor(tester);

      expect(h.cubit.state.filter, MyWorkFilter.archived);
      // Inside the archive the row would point at itself: it is gone.
      expect(
        find.text(l10n.myWorkEmptyArchiveShortcut(3), findRichText: true),
        findsNothing,
      );

      close(h);
    },
  );

  testWidgets('nothing archived: no archive row', (tester) async {
    final h = await _boot(archivedCount: 0);
    await _pumpMyWork(
      tester,
      cubit: h.cubit,
      homeAttention: h.homeAttention,
      archivedCount: 0,
    );

    expect(_shownCardIds(tester), {_liveId, _secondLiveId});
    expect(
      find.text(l10n.myWorkEmptyArchiveShortcut(0), findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('Archived ('), findsNothing);

    close(h);
  });
}
