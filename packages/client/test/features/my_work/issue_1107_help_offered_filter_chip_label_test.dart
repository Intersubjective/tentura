// #1107: narrow Requests header shows the full meaning of the Help offered
// filter via a short chip label (menu keeps the long form).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

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
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart'
    show ProfileCubit, ProfileState;
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'my_work_test_support.dart';
import '../updates/support/noop_invite_setup_port.dart';

const _accountId = 'user-1107';

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
    Logger('1107-attention'),
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

void main() {
  const iphoneSeSize = Size(375, 667);

  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('1107-filter-test'));
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
    if (GetIt.I.isRegistered<ProfileCubit>()) {
      GetIt.I.unregister<ProfileCubit>();
    }
  });

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      'Help offered filter shows compact chip label at 375px ($locale)',
      (tester) async {
        tester.view.physicalSize = iphoneSeSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final l10n = lookupL10n(locale);

        final myWorkRepo = FakeMyWorkRepository()
          ..initResult = (
            authoredNonArchived: [_beacon('b1', 'Test request')],
            helpOfferedNonArchived: const [],
            obligationBeacons: const [],
            archivedCountHint: 0,
          );
        final boot = await _bootAttention(
          StubAttentionRepository()..myWorkAttentionResult = const [],
        );
        final myWorkCubit = MyWorkCubit(
          userId: _accountId,
          myWorkCase: buildTestMyWorkCase(
            repo: myWorkRepo,
            attentionCase: boot.attention,
          ),
        );
        final homeAttention = HomeAttentionCubit(
          boot.attention,
          boot.accounts,
          Logger('1107-my-work'),
        );
        final profileCubit = _TestProfileCubit();
        GetIt.I.registerSingleton<ProfileCubit>(profileCubit);

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
          MediaQuery(
            data: const MediaQueryData(
              size: iphoneSeSize,
              textScaler: TextScaler.linear(0.55),
            ),
            child: MaterialApp(
              locale: locale,
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<MyWorkCubit>.value(value: myWorkCubit),
                    BlocProvider<HomeActivationCubit>.value(
                      value: homeActivation,
                    ),
                    BlocProvider<HomeAttentionCubit>.value(
                      value: homeAttention,
                    ),
                    BlocProvider<InboxOperationalCubit>.value(
                      value: inboxOperational,
                    ),
                    BlocProvider<ProfileCubit>.value(value: profileCubit),
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
        for (var i = 0; i < 40 && !myWorkCubit.state.isSuccess; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        myWorkCubit.setFilter(MyWorkFilter.helpOffered);
        await tester.pumpAndSettle();

        expect(find.text(l10n.myWorkFilterHelpOfferedChip), findsOneWidget);
        expect(find.text(l10n.myWorkFilterHelpOffered), findsNothing);

        unawaited(myWorkCubit.close());
        unawaited(homeAttention.close());
        unawaited(boot.accounts.close());
      },
    );
  }
}
