import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'auth', displayName: 'Author'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  int loadForwardsCalls = 0;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> loadForwards() async {
    loadForwardsCalls++;
  }
}

final _t = DateTime.utc(2025);
late BeaconViewState _state;

BeaconViewState _peopleState({
  List<TimelineHelpOffer> helpOffers = const [],
  List<BeaconParticipant> roomParticipants = const [],
  List<ForwardEdge> viewerForwardEdges = const [],
  bool forwardsLoaded = false,
  bool forwardsLoading = false,
}) {
  return BeaconViewState(
    beacon: Beacon(
      id: 'B1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
    ),
    myProfile: const Profile(id: 'auth', displayName: 'Author'),
    helpOffers: helpOffers,
    roomParticipants: roomParticipants,
    viewerForwardEdges: viewerForwardEdges,
    forwardsLoaded: forwardsLoaded,
    forwardsLoading: forwardsLoading,
  );
}

Widget _wrapPeople(Widget child) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        BlocProvider<BeaconViewCubit>.value(value: _MockBeaconViewCubit()),
      ],
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
    );
  });

  testWidgets('People tab shows willing to help fold with count', (tester) async {
    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forwards'), findsOneWidget);
    expect(find.text('Active helpers (1)'), findsOneWidget);
    expect(find.text('Willing to help (1)'), findsOneWidget);
    expect(find.textContaining('Not fitting'), findsNothing);

    final forwardsTop = tester.getTopLeft(find.text('Forwards')).dy;
    final helpersTop = tester.getTopLeft(find.text('Active helpers (1)')).dy;
    expect(forwardsTop, lessThan(helpersTop));
  });

  testWidgets('Forwards fold starts closed and expand loads forwards', (
    tester,
  ) async {
    final cubit = _MockBeaconViewCubit();
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
      viewerForwardEdges: [
        ForwardEdge(
          id: 'e1',
          beaconId: 'B1',
          createdAt: _t,
          sender: const Profile(id: 'auth', displayName: 'Author'),
          recipient: const Profile(id: 'h1', displayName: 'Helper'),
          note: 'please help',
        ),
      ],
      forwardsLoaded: true,
    );

    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: cubit,
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forwards (1)'), findsOneWidget);
    expect(find.text('please help'), findsNothing);
    final graphButtons = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Track of forwards',
    );
    expect(graphButtons, findsOneWidget);

    await tester.tap(find.text('Forwards (1)'));
    await tester.pumpAndSettle();

    expect(cubit.loadForwardsCalls, 1);
    expect(find.text('please help'), findsOneWidget);
  });

  testWidgets('expanding Forwards does not collapse Active helpers', (
    tester,
  ) async {
    const compact = Size(500, 812);
    await tester.binding.setSurfaceSize(compact);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = _MockBeaconViewCubit();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: compact),
        child: _wrapPeople(
          SingleChildScrollView(
            child: BeaconPeopleTabBody(
              state: _state,
              beaconViewCubit: cubit,
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Author'), findsOneWidget);

    await tester.tap(find.text('Forwards'));
    await tester.pumpAndSettle();

    expect(cubit.loadForwardsCalls, 1);
    expect(find.text('Author'), findsOneWidget);
  });

  testWidgets('Not fitting fold is collapsed by default', (tester) async {
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h2', displayName: 'Rejected'),
          message: '',
          createdAt: _t,
          updatedAt: _t,
          coordinationResponse: CoordinationResponseType.notSuitable,
        ),
      ],
    );
    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not fitting (1)'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);
    await tester.tap(find.text('Not fitting (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('compact accordion collapses active when not fitting opens', (
    tester,
  ) async {
    const compact = Size(500, 812);
    await tester.binding.setSurfaceSize(compact);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
        ),
        TimelineHelpOffer(
          user: const Profile(id: 'h2', displayName: 'Rejected'),
          message: '',
          createdAt: _t,
          updatedAt: _t,
          coordinationResponse: CoordinationResponseType.notSuitable,
        ),
      ],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: compact),
        child: _wrapPeople(
          SingleChildScrollView(
            child: BeaconPeopleTabBody(
              state: _state,
              beaconViewCubit: _MockBeaconViewCubit(),
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Author'), findsOneWidget);
    expect(find.text('Helper'), findsNothing);
    await tester.tap(find.text('Not fitting (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Author'), findsNothing);
  });

  testWidgets('End participation visible when stake is acknowledged', (
    tester,
  ) async {
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
          stakeState: CommitmentStakeState.acknowledged,
          roomAccess: RoomAccessBits.admitted,
        ),
      ],
      roomParticipants: [
        BeaconParticipant(
          id: 'p-h1',
          beaconId: 'B1',
          userId: 'h1',
          userTitle: 'Helper',
          role: BeaconParticipantRoleBits.helper,
          status: BeaconParticipantStatusBits.committed,
          roomAccess: RoomAccessBits.admitted,
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('End participation'), findsOneWidget);
    expect(find.text('Remove from discussion'), findsNothing);
    expect(find.text('Participation ended'), findsNothing);
  });

  testWidgets('End participation hidden after release stake state', (
    tester,
  ) async {
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
          stakeState: CommitmentStakeState.released,
          roomAccess: RoomAccessBits.admitted,
        ),
      ],
      roomParticipants: [
        BeaconParticipant(
          id: 'p-h1',
          beaconId: 'B1',
          userId: 'h1',
          userTitle: 'Helper',
          role: BeaconParticipantRoleBits.helper,
          status: BeaconParticipantStatusBits.committed,
          roomAccess: RoomAccessBits.admitted,
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('End participation'), findsNothing);
    expect(find.text('Participation ended'), findsOneWidget);
  });

  testWidgets('shows direct-forward chip for author when flagged', (
    tester,
  ) async {
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
          isDirectAuthorForward: true,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forwarded by you'), findsOneWidget);
  });

  testWidgets('direct-forward offers sort above others in willing section', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper Later'),
          message: 'first',
          createdAt: _t,
          updatedAt: _t,
        ),
        TimelineHelpOffer(
          user: const Profile(id: 'h2', displayName: 'Helper Direct'),
          message: 'second',
          createdAt: _t,
          updatedAt: _t,
          isDirectAuthorForward: true,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final directTop = tester.getTopLeft(find.text('Helper Direct')).dy;
    final laterTop = tester.getTopLeft(find.text('Helper Later')).dy;
    expect(directTop, lessThan(laterTop));

    await tester.binding.setSurfaceSize(null);
  });
}
