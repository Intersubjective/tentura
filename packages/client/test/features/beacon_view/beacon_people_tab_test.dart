import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

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
import 'package:tentura/ui/test_ids.dart';

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
  List<Profile> admittedHelperRoster = const [],
  BeaconAccessLevel? accessLevel,
  bool forwardsLoaded = false,
  bool forwardsLoading = false,
  Profile? myProfile,
}) {
  return BeaconViewState(
    beacon: Beacon(
      id: 'B1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      accessLevel: accessLevel,
    ),
    myProfile: myProfile ?? const Profile(id: 'auth', displayName: 'Author'),
    helpOffers: helpOffers,
    roomParticipants: roomParticipants,
    viewerForwardEdges: viewerForwardEdges,
    admittedHelperRoster: admittedHelperRoster,
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

  testWidgets('People tab shows willing to help fold with count', (
    tester,
  ) async {
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

  testWidgets('observer People tab shows only read-only Active helpers', (
    tester,
  ) async {
    _state = _peopleState(
      accessLevel: BeaconAccessLevel.observer,
      myProfile: const Profile(id: 'obs', displayName: 'Observer'),
      admittedHelperRoster: const [
        Profile(id: 'h1', displayName: 'Helper One'),
        Profile(id: 'h2', displayName: 'Helper Two'),
      ],
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'w1', displayName: 'Willing'),
          message: 'I can help',
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

    expect(find.text('Active helpers (3)'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('Helper One'), findsOneWidget);
    expect(find.text('Helper Two'), findsOneWidget);
    expect(find.text('Forwards'), findsNothing);
    expect(find.textContaining('Willing to help'), findsNothing);
    expect(find.text('Willing'), findsNothing);
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

    expect(find.text('Forwards (0)'), findsOneWidget);
    expect(find.text('please help'), findsNothing);
    final graphButtons = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Track of forwards',
    );
    expect(graphButtons, findsOneWidget);

    await tester.tap(find.text('Forwards (0)'));
    await tester.pumpAndSettle();

    expect(cubit.loadForwardsCalls, 1);
    expect(find.text('please help'), findsNothing);
    expect(find.text('Helper'), findsOneWidget);
  });

  for (final bucket in ['active', 'willing', 'not fitting', 'backup']) {
    for (final inbound in [false, true]) {
      testWidgets(
        '$bucket person appears once with ${inbound ? 'inbound' : 'outgoing'} forwards',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(800, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          const helper = Profile(id: 'h1', displayName: 'Helper');
          const author = Profile(id: 'auth', displayName: 'Author');
          _state = _peopleState(
            helpOffers: [
              TimelineHelpOffer(
                user: helper,
                message: 'I can help',
                createdAt: _t,
                updatedAt: _t,
                offerKind: bucket == 'backup' ? 1 : 0,
                roomAccess: bucket == 'active' ? RoomAccessBits.admitted : null,
                coordinationResponse: bucket == 'not fitting'
                    ? CoordinationResponseType.notSuitable
                    : null,
              ),
              // Backup offers must not duplicate a higher-priority primary offer.
              TimelineHelpOffer(
                user: helper,
                message: 'Backup',
                createdAt: _t,
                updatedAt: _t,
                offerKind: 1,
              ),
            ],
            viewerForwardEdges: [
              ForwardEdge(
                id: 'e1',
                beaconId: 'B1',
                createdAt: _t,
                sender: inbound ? helper : author,
                recipient: inbound ? author : helper,
                note: 'please help',
              ),
            ],
            forwardsLoaded: true,
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
          await tester.tap(find.textContaining('Forwards ('));
          await tester.pumpAndSettle();
          if (bucket == 'not fitting') {
            await tester.tap(find.text('Not fitting (1)'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Helper'), findsOneWidget);
          expect(find.text('Forwards (0)'), findsOneWidget);
          expect(find.text('please help'), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'forward-only recipients remain unique and move to Active after offering help',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const helper = Profile(id: 'h1', displayName: 'Helper');
      final edges = [
        for (final id in ['e1', 'e2'])
          ForwardEdge(
            id: id,
            beaconId: 'B1',
            createdAt: _t,
            sender: const Profile(id: 'auth', displayName: 'Author'),
            recipient: helper,
            note: 'please help',
          ),
      ];
      Future<void> render(List<TimelineHelpOffer> offers) async {
        _state = _peopleState(
          helpOffers: offers,
          viewerForwardEdges: edges,
          forwardsLoaded: true,
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
      }

      await render([]);
      await tester.tap(find.textContaining('Forwards ('));
      await tester.pumpAndSettle();
      expect(find.text('Helper'), findsOneWidget);
      expect(find.text('Forwards (1)'), findsOneWidget);
      await render([
        TimelineHelpOffer(
          user: helper,
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
          roomAccess: RoomAccessBits.admitted,
        ),
      ]);
      expect(find.text('Helper'), findsOneWidget);
      expect(find.text('Active helpers (2)'), findsOneWidget);
      expect(find.text('Forwards (0)'), findsOneWidget);
      expect(find.text('please help'), findsNothing);
    },
  );

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

  testWidgets('own offer edit sheet starts with previous text (#147)', (
    tester,
  ) async {
    const helper = Profile(id: 'h1', displayName: 'Helper');
    const firstText = 'I can help Monday morning';
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: helper,
          message: firstText,
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
    ).copyWith(myProfile: helper);
    final cubit = _MockBeaconViewCubit();

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

    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(TestIds.key(TestIds.helpOfferMessage)),
    );
    expect(field.controller?.text, firstText);
  });

  testWidgets(
    'backup group shows header hint once and not on each tile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final l10n = lookupL10n(const Locale('en'));
      const helper1 = Profile(id: 'h1', displayName: 'Helper One');
      const helper2 = Profile(id: 'h2', displayName: 'Helper Two');
      _state = _peopleState(
        helpOffers: [
          TimelineHelpOffer(
            user: helper1,
            message: 'Backup one',
            createdAt: _t,
            updatedAt: _t,
            offerKind: 1,
          ),
          TimelineHelpOffer(
            user: helper2,
            message: 'Backup two',
            createdAt: _t,
            updatedAt: _t,
            offerKind: 1,
          ),
        ],
        forwardsLoaded: true,
      );
      await tester.pumpWidget(
        _wrapPeople(
          BeaconPeopleTabBody(
            state: _state,
            beaconViewCubit: _MockBeaconViewCubit(),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Backup offers (2)'), findsOneWidget);
      expect(find.text(l10n.helpOffersBackupGroupHint), findsOneWidget);
      expect(find.text(l10n.helpOfferBackupBadge), findsNWidgets(2));
      expect(find.text(l10n.helpOfferBackupHint), findsNothing);
      expect(find.text(l10n.helpOffersTabNoAuthorLabelYet), findsNothing);
    },
  );
}
