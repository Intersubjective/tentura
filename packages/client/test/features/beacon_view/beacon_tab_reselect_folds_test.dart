import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_scroll_view.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'auth', displayName: 'Author'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeBeaconViewCubit extends Mock implements BeaconViewCubit {
  _FakeBeaconViewCubit(this._state);

  BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> loadForwards() async {}
}

class _TrackingThreadsCubit extends Cubit<ThreadsState>
    implements ThreadsCubit {
  _TrackingThreadsCubit()
      : super(const ThreadsState(status: StateIsSuccess(), activeForMeOnly: true));

  int setActiveForMeOnlyCalls = 0;

  @override
  void setActiveForMeOnly(bool value) {
    setActiveForMeOnlyCalls++;
    emit(state.copyWith(activeForMeOnly: value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final t = DateTime.utc(2026);

  BeaconViewState peopleState() => BeaconViewState(
    beacon: Beacon(
      id: 'B1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      status: BeaconStatus.open,
      canReadContent: true,
    ),
    myProfile: const Profile(id: 'auth', displayName: 'Author'),
    helpOffers: [
      TimelineHelpOffer(
        user: const Profile(id: 'h1', displayName: 'Helper'),
        message: 'I can help',
        createdAt: t,
        updatedAt: t,
      ),
      TimelineHelpOffer(
        user: const Profile(id: 'h2', displayName: 'Rejected'),
        message: '',
        createdAt: t,
        updatedAt: t,
        coordinationResponse: CoordinationResponseType.notSuitable,
      ),
    ],
    beaconContentLoaded: true,
    beaconContextLoaded: true,
  );

  testWidgets('same-tab People reselect remounts folds to default', (
    tester,
  ) async {
    const compact = Size(500, 900);
    await tester.binding.setSurfaceSize(compact);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final beaconCubit = _FakeBeaconViewCubit(peopleState());
    final threadsCubit = _TrackingThreadsCubit();
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);

    var peopleFoldEpoch = 0;
    var threadsFoldEpoch = 0;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: compact),
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              BlocProvider<ThreadsCubit>.value(value: threadsCubit),
              BlocProvider<BeaconViewCubit>.value(value: beaconCubit),
            ],
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    return BeaconOperationalScrollView(
                      beaconViewCubit: beaconCubit,
                      screenCubit: screenCubit,
                      tabIndex: kBeaconTabPeople,
                      onTabChanged: (_) {},
                      peopleTabAttentionActive: false,
                      onPeopleTabAttentionCleared: () {},
                      onActivatePeopleTabAttention: () {},
                      onFocusCoordinationItem: (_) {},
                      focusThreadId: null,
                      focusUserId: null,
                      onOperationalFocusCleared: () {},
                      onTapCoordinationLogEvent: (_) {},
                      onOpenThread: (_) {},
                      onOpenGeneralThread: () {},
                      onThreadsTabRefresh: () {},
                      peopleFoldEpoch: peopleFoldEpoch,
                      threadsFoldEpoch: threadsFoldEpoch,
                      onTabReselected: (tab) {
                        setState(() {
                          if (tab == kBeaconTabPeople) {
                            peopleFoldEpoch++;
                          } else if (tab == kBeaconTabThreads) {
                            threadsFoldEpoch++;
                          }
                        });
                      },
                      beaconState: beaconCubit.state,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Author'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);

    await tester.tap(find.text('Not fitting (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Author'), findsNothing);

    await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
    await tester.pumpAndSettle();

    expect(find.text('Author'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);
  });

  testWidgets('same-tab Threads reselect clears activeForMeOnly', (
    tester,
  ) async {
    const compact = Size(500, 900);
    await tester.binding.setSurfaceSize(compact);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final beaconCubit = _FakeBeaconViewCubit(peopleState());
    final threadsCubit = _TrackingThreadsCubit();
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: compact),
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              BlocProvider<ThreadsCubit>.value(value: threadsCubit),
              BlocProvider<BeaconViewCubit>.value(value: beaconCubit),
            ],
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BeaconOperationalScrollView(
                  beaconViewCubit: beaconCubit,
                  screenCubit: screenCubit,
                  tabIndex: kBeaconTabThreads,
                  onTabChanged: (_) {},
                  peopleTabAttentionActive: false,
                  onPeopleTabAttentionCleared: () {},
                  onActivatePeopleTabAttention: () {},
                  onFocusCoordinationItem: (_) {},
                  focusThreadId: null,
                  focusUserId: null,
                  onOperationalFocusCleared: () {},
                  onTapCoordinationLogEvent: (_) {},
                  onOpenThread: (_) {},
                  onOpenGeneralThread: () {},
                  onThreadsTabRefresh: () {},
                  onTabReselected: (_) {},
                  beaconState: beaconCubit.state,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(threadsCubit.state.activeForMeOnly, isTrue);

    await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabThreads)));
    await tester.pumpAndSettle();

    expect(threadsCubit.setActiveForMeOnlyCalls, 1);
    expect(threadsCubit.state.activeForMeOnly, isFalse);
  });
}
