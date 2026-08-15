import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_scroll_view.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream<ThreadsState>.value(_state);
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bscroll01';
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    startAt: DateTime.utc(2099, 6, 20, 12),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  BeaconFactCard fact({
    required String id,
    required DateTime createdAt,
  }) =>
      BeaconFactCard(
        id: id,
        beaconId: beaconId,
        factText: 'Fact $id',
        visibility: BeaconFactCardVisibilityBits.public,
        pinnedBy: 'other',
        createdAt: createdAt,
        status: BeaconFactCardStatusBits.active,
      );

  testWidgets('scroll-view buildWhen rebuilds when pinnedFactsSeenAt changes', (
    tester,
  ) async {
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
      factCardsRepo: FakeBeaconViewFactCardRepository(
        cards: [
          fact(id: 'old', createdAt: t0),
          fact(id: 'new', createdAt: t1),
        ],
      ),
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: beaconId,
      userId: myProfile.id,
      facts: [fact(id: 'old', createdAt: t0)],
    );
    final cubit = BeaconViewCubit(
      id: beaconId,
      myProfile: myProfile,
      beaconViewCase: case_,
      coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(
              value: _MockProfileCubit(myProfile),
            ),
            BlocProvider<ThreadsCubit>.value(
              value: _MockThreadsCubit(
                const ThreadsState(status: StateIsSuccess()),
              ),
            ),
          ],
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconOperationalScrollView(
                beaconViewCubit: cubit,
                screenCubit: screenCubit,
                tabIndex: kBeaconTabLog,
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
                beaconState: cubit.state,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30 && !cubit.state.beaconContextLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(cubit.state.beaconContextLoaded, isTrue);
    expect(cubit.state.factCards, hasLength(2));

    final l10n = await L10n.delegate.load(const Locale('en'));
    final factsOpen = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
    expect(factsOpen, findsOneWidget);
    expect(
      find.descendant(
        of: factsOpen,
        matching: find.text(l10n.beaconYouNewCount(1)),
      ),
      findsOneWidget,
    );

    cubit.markPinnedFactsSeen();
    expect(cubit.state.pinnedFactsSeenAt, t1);
    await tester.idle();
    await tester.pump();

    expect(
      tester
          .widget<BeaconOperationalHeaderCard>(
            find.byType(BeaconOperationalHeaderCard),
          )
          .state
          .pinnedFactsSeenAt,
      t1,
    );
    expect(
      find.descendant(
        of: find.byKey(TestIds.key(TestIds.beaconFactsOpen)),
        matching: find.text(l10n.beaconYouNewCount(1)),
      ),
      findsNothing,
    );
  });
}
