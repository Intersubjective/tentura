import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/beacon_view/ui/widget/unified_forward_row.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import '../../support/people_tags_widget_harness.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'auth', displayName: 'Author'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _PresenceCubit extends Mock implements PresenceCubit {
  _PresenceCubit(this._presence);

  final Map<String, UserPresenceStatus> _presence;

  @override
  Map<String, UserPresenceStatus> get state => _presence;

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(_presence);
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

/// A live forward from the author to [userId], as People › Forwards loads it.
ForwardEdge _authorForwardTo(String userId, {bool cancelled = false}) =>
    ForwardEdge(
      id: 'fwd-$userId',
      beaconId: 'B1',
      createdAt: _t,
      sender: const Profile(id: 'auth', displayName: 'Author'),
      recipient: Profile(id: userId, displayName: 'Helper'),
      cancelledAt: cancelled ? _t.add(const Duration(minutes: 5)) : null,
    );

/// An admitted helper `h1` whose offer the server flags as a direct author
/// forward (#496).
BeaconViewState _admittedDirectState({
  List<ForwardEdge> viewerForwardEdges = const [],
  bool forwardsLoaded = true,
  Profile? myProfile,
}) => _peopleState(
  myProfile: myProfile,
  helpOffers: [
    TimelineHelpOffer(
      user: const Profile(id: 'h1', displayName: 'Helper'),
      message: 'I have a couch',
      createdAt: _t,
      updatedAt: _t,
      roomAccess: RoomAccessBits.admitted,
      isDirectAuthorForward: true,
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
  viewerForwardEdges: viewerForwardEdges,
  forwardsLoaded: forwardsLoaded,
);

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
    await tester.pumpPeopleTagsWidget(
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
    // #346: the author's own card is not counted as an active helper.
    expect(find.text('Active helpers (1)'), findsNothing);
    expect(find.textContaining('Active helpers'), findsOneWidget);
    expect(find.text('Willing to help (1)'), findsOneWidget);
    expect(find.textContaining('Declined offers'), findsNothing);

    final forwardsTop = tester.getTopLeft(find.text('Forwards')).dy;
    final helpersTop = tester
        .getTopLeft(find.textContaining('Active helpers'))
        .dy;
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

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // #346: two helpers; the author is listed but not counted.
    expect(find.text('Active helpers (2)'), findsOneWidget);
    expect(find.text('Active helpers (3)'), findsNothing);
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

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: cubit,
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // #396: the forward to someone who offered help is still the trail.
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
    // One card (Willing to help) and one trail row.
    expect(find.text('Helper'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(UnifiedForwardRow),
        matching: find.text('Helper'),
      ),
      findsOneWidget,
    );
  });

  for (final bucket in ['active', 'willing', 'not fitting', 'backup']) {
    for (final inbound in [false, true]) {
      testWidgets(
        '$bucket person has one card and keeps the ${inbound ? 'inbound' : 'outgoing'} forward in the trail',
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
          await tester.pumpPeopleTagsWidget(
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
            await tester.tap(find.text('Declined offers (1)'));
            await tester.pumpAndSettle();
          }
          // People sections stay exclusive: one card. Forwards is the
          // trail (#396, #496): the forward stays, as one row.
          final row = find.byType(UnifiedForwardRow);
          expect(row, findsOneWidget);
          expect(
            find.descendant(of: row, matching: find.text('Helper')),
            findsOneWidget,
          );
          expect(find.text('Helper'), findsNWidgets(2));
          expect(
            find.descendant(
              of: find.byType(HelpOfferTile),
              matching: find.text('Helper'),
            ),
            findsOneWidget,
          );
          expect(find.text('Forwards (1)'), findsOneWidget);
          expect(find.text('please help'), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'a forward-only recipient has one trail row and keeps it after moving to Active',
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
        await tester.pumpPeopleTagsWidget(
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
      // #346: one helper; the author is not counted.
      expect(find.text('Active helpers (1)'), findsOneWidget);
      expect(find.text('Active helpers (2)'), findsNothing);
      // #396: offering help moves the card, not the forward.
      expect(find.text('Forwards (1)'), findsOneWidget);
      expect(find.text('please help'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(UnifiedForwardRow),
          matching: find.text('Helper'),
        ),
        findsOneWidget,
      );
    },
  );

  // #396: the spread of a request is history, not current membership. A
  // recipient who later withdraws their offer keeps the viewer's forward
  // edge in People > Forwards, and that row says they withdrew.
  testWidgets(
    'forward to a helper who later withdrew stays in Forwards, marked withdrawn',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const helper = Profile(id: 'h1', displayName: 'Helper');
      final l10n = lookupL10n(const Locale('en'));
      _state = _peopleState(
        helpOffers: [
          TimelineHelpOffer(
            user: helper,
            message: 'I can help',
            createdAt: _t,
            updatedAt: _t,
            // Repro: the author accepted the offer, then the helper withdrew.
            roomAccess: RoomAccessBits.admitted,
            isWithdrawn: true,
          ),
        ],
        viewerForwardEdges: [
          ForwardEdge(
            id: 'e1',
            beaconId: 'B1',
            createdAt: _t,
            sender: const Profile(id: 'auth', displayName: 'Author'),
            recipient: helper,
            note: 'please help',
          ),
        ],
        forwardsLoaded: true,
      );
      await tester.pumpPeopleTagsWidget(
        _wrapPeople(
          BeaconPeopleTabBody(
            state: _state,
            beaconViewCubit: _MockBeaconViewCubit(),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forwards (1)'), findsOneWidget);
      await tester.tap(find.text('Forwards (1)'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconForwardsEmpty), findsNothing);
      final row = find.byType(UnifiedForwardRow);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Helper')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('please help')),
        findsOneWidget,
      );
      // The withdrawn state is the row's reaction, not a delivery hint.
      expect(
        find.descendant(of: row, matching: find.text(l10n.forwardWithdrawn)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(l10n.forwardStatusNotYetSeen),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(l10n.forwardReactionHelpOffered),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'withdrawn forward recipient stays in Forwards even with a read receipt',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const helper = Profile(id: 'h2', displayName: 'Helper Two');
      final l10n = lookupL10n(const Locale('en'));
      _state = _peopleState(
        helpOffers: [
          // A still-pending offer from someone else keeps the other folds
          // populated; it must not disturb the Forwards count.
          TimelineHelpOffer(
            user: const Profile(id: 'h1', displayName: 'Helper'),
            message: 'I can help',
            createdAt: _t,
            updatedAt: _t,
          ),
          TimelineHelpOffer(
            user: helper,
            message: 'On it',
            createdAt: _t,
            updatedAt: _t,
            isWithdrawn: true,
          ),
        ],
        viewerForwardEdges: [
          ForwardEdge(
            id: 'e2',
            beaconId: 'B1',
            createdAt: _t,
            sender: const Profile(id: 'auth', displayName: 'Author'),
            recipient: helper,
            recipientReadAt: _t,
          ),
        ],
        forwardsLoaded: true,
      );
      await tester.pumpPeopleTagsWidget(
        _wrapPeople(
          BeaconPeopleTabBody(
            state: _state,
            beaconViewCubit: _MockBeaconViewCubit(),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forwards (1)'), findsOneWidget);
      await tester.tap(find.text('Forwards (1)'));
      await tester.pumpAndSettle();

      final row = find.byType(UnifiedForwardRow);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Helper Two')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(l10n.forwardWithdrawn)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(l10n.forwardStatusSeen)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a withdrawn offer followed by a live offer is Willing, and the forward row is not marked withdrawn',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const helper = Profile(id: 'h1', displayName: 'Helper');
      final l10n = lookupL10n(const Locale('en'));
      _state = _peopleState(
        helpOffers: [
          TimelineHelpOffer(
            user: helper,
            message: 'Earlier offer',
            createdAt: _t,
            updatedAt: _t,
            isWithdrawn: true,
          ),
          TimelineHelpOffer(
            user: helper,
            message: 'I can help again',
            createdAt: _t.add(const Duration(days: 1)),
            updatedAt: _t.add(const Duration(days: 1)),
          ),
        ],
        viewerForwardEdges: [
          ForwardEdge(
            id: 'e1',
            beaconId: 'B1',
            createdAt: _t,
            sender: const Profile(id: 'auth', displayName: 'Author'),
            recipient: helper,
            note: 'please help',
          ),
        ],
        forwardsLoaded: true,
      );
      await tester.pumpPeopleTagsWidget(
        _wrapPeople(
          BeaconPeopleTabBody(
            state: _state,
            beaconViewCubit: _MockBeaconViewCubit(),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Willing to help (1)'), findsOneWidget);
      expect(find.text('Forwards (1)'), findsOneWidget);
      await tester.tap(find.text('Forwards (1)'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedForwardRow), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(UnifiedForwardRow),
          matching: find.text(l10n.forwardWithdrawn),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('expanding Forwards does not collapse Active helpers', (
    tester,
  ) async {
    const compact = Size(500, 812);
    await tester.binding.setSurfaceSize(compact);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = _MockBeaconViewCubit();
    await tester.pumpPeopleTagsWidget(
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

    // The author's pending offer is the section open by default.
    expect(find.text('Helper'), findsOneWidget);

    await tester.tap(find.text('Forwards'));
    await tester.pumpAndSettle();

    expect(cubit.loadForwardsCalls, 1);
    expect(find.text('Helper'), findsOneWidget);
  });

  testWidgets('author sees pending offers above active helpers', (
    tester,
  ) async {
    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final willingTop = tester.getTopLeft(find.text('Willing to help (1)')).dy;
    // #346: only the author is in Active helpers, and the author is not
    // counted there.
    expect(find.text('Active helpers (1)'), findsNothing);
    final activeTop = tester
        .getTopLeft(find.textContaining('Active helpers'))
        .dy;
    expect(willingTop, lessThan(activeTop));
    expect(find.text('Helper'), findsOneWidget);
  });

  testWidgets('Declined offers fold is collapsed by default', (tester) async {
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
    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Declined offers (1)'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);
    await tester.tap(find.text('Declined offers (1)'));
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

    await tester.pumpPeopleTagsWidget(
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

    // Author view: pending offers open first, settled helpers collapsed.
    expect(find.text('Helper'), findsOneWidget);
    expect(find.text('Author'), findsNothing);
    await tester.tap(find.text('Declined offers (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Helper'), findsNothing);
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

    await tester.pumpPeopleTagsWidget(
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

    await tester.pumpPeopleTagsWidget(
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
      // #496: the chip follows the trail People › Forwards shows.
      viewerForwardEdges: [_authorForwardTo('h1')],
      forwardsLoaded: true,
    );

    await tester.pumpPeopleTagsWidget(
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

  // #496: "Forwarded by you" is the author's edge; a steward's own trail
  // (People › Forwards) does not hold it, so the steward's card must not
  // claim it.
  testWidgets('steward does not see "Forwarded by you" for the author edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const steward = Profile(id: 's1', displayName: 'Steward');
    _state = _peopleState(
      myProfile: steward,
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h1', displayName: 'Helper'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
          isDirectAuthorForward: true,
        ),
      ],
      roomParticipants: [
        BeaconParticipant(
          id: 'p-s1',
          beaconId: 'B1',
          userId: 's1',
          userTitle: 'Steward',
          role: BeaconParticipantRoleBits.steward,
          status: BeaconParticipantStatusBits.committed,
          roomAccess: RoomAccessBits.admitted,
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
    );

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_state.isAuthorOrSteward, isTrue);
    expect(find.text('Forwarded by you'), findsNothing);
  });

  // #396: cancellation is not deletion. A forward the viewer cancelled stays
  // in their trail, saying so; a forward someone cancelled towards the
  // viewer is not how the request reached them.
  testWidgets('a cancelled forward stays in the trail, marked cancelled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l10n = lookupL10n(const Locale('en'));
    _state = _peopleState(
      viewerForwardEdges: [
        ForwardEdge(
          id: 'e1',
          beaconId: 'B1',
          createdAt: _t,
          sender: const Profile(id: 'auth', displayName: 'Author'),
          recipient: const Profile(id: 'r1', displayName: 'Recipient'),
          note: 'taken back',
          cancelledAt: _t.add(const Duration(minutes: 5)),
        ),
        ForwardEdge(
          id: 'e2',
          beaconId: 'B1',
          createdAt: _t,
          sender: const Profile(id: 'x1', displayName: 'Other Sender'),
          recipient: const Profile(id: 'auth', displayName: 'Author'),
          note: 'never mind',
          cancelledAt: _t.add(const Duration(minutes: 5)),
        ),
      ],
      forwardsLoaded: true,
    );

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: l10n,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forwards (1)'), findsOneWidget);
    await tester.tap(find.text('Forwards (1)'));
    await tester.pumpAndSettle();

    final row = find.byType(UnifiedForwardRow);
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Recipient')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(l10n.forwardStatusCancelled),
      ),
      findsOneWidget,
    );
    expect(find.text('Other Sender'), findsNothing);
    expect(find.text('never mind'), findsNothing);
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
      viewerForwardEdges: [_authorForwardTo('h2')],
      forwardsLoaded: true,
    );

    await tester.pumpPeopleTagsWidget(
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

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: cubit,
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
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
      await tester.pumpPeopleTagsWidget(
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

  testWidgets("author's own row has no Edit / Withdraw and no edited marker", (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    _state = _peopleState(
      admittedHelperRoster: const [
        Profile(id: 'h1', displayName: 'Helper One'),
      ],
      roomParticipants: [
        BeaconParticipant(
          id: 'p-auth',
          beaconId: 'B1',
          userId: 'auth',
          userTitle: 'Author',
          role: BeaconParticipantRoleBits.helper,
          status: BeaconParticipantStatusBits.committed,
          roomAccess: RoomAccessBits.admitted,
          createdAt: _t,
          updatedAt: _t.add(const Duration(days: 1)),
        ),
      ],
    );

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: l10n,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // #346: the author is listed, but only the one helper is counted.
    expect(find.text('Active helpers (1)'), findsOneWidget);
    expect(find.text('Active helpers (2)'), findsNothing);
    expect(find.text(l10n.helpOffersTabActionWithdraw), findsNothing);
    expect(find.text(l10n.helpOffersTabActionEdit), findsNothing);
    expect(find.textContaining(l10n.labelEdited), findsNothing);
  });

  testWidgets('Active helpers lists the author but counts only helpers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l10n = lookupL10n(const Locale('en'));
    _state = _peopleState(
      admittedHelperRoster: const [
        Profile(id: 'h1', displayName: 'Helper One'),
        Profile(id: 'h2', displayName: 'Helper Two'),
      ],
    );

    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: l10n,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('${l10n.beaconPeopleLensActiveHelpersHeading} (2)'),
      findsOneWidget,
    );
    expect(
      find.text('${l10n.beaconPeopleLensActiveHelpersHeading} (3)'),
      findsNothing,
    );
    // The author is still shown in the section, as the author.
    expect(find.byType(HelpOfferTile), findsNWidgets(3));
    expect(find.text(l10n.beaconPeopleRoleAuthor), findsWidgets);
    expect(find.text('Helper One'), findsOneWidget);
    expect(find.text('Helper Two'), findsOneWidget);
  });

  group('#489 leaving stays possible while the Request is wrapping up', () {
    BeaconViewState acknowledgedHelperState(BeaconStatus status) {
      final base = _peopleState(
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
      return base.copyWith(beacon: base.beacon.copyWith(status: status));
    }

    BeaconViewState ownOfferState(BeaconStatus status) {
      const helper = Profile(id: 'h1', displayName: 'Helper');
      final base = _peopleState(
        helpOffers: [
          TimelineHelpOffer(
            user: helper,
            message: 'I can help Monday morning',
            createdAt: _t,
            updatedAt: _t,
          ),
        ],
        myProfile: helper,
      );
      return base.copyWith(beacon: base.beacon.copyWith(status: status));
    }

    Future<void> pumpPeople(WidgetTester tester) async {
      await tester.pumpPeopleTagsWidget(
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

    testWidgets('author still sees End participation in Wrapping up', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      _state = acknowledgedHelperState(BeaconStatus.reviewOpen);

      await pumpPeople(tester);

      expect(find.text(l10n.helpOfferReleaseCommitment), findsOneWidget);
      expect(
        find.byKey(TestIds.key(TestIds.helpOfferRelease('h1'))),
        findsOneWidget,
      );
    });

    // The People tab shows End participation for an admitted backup helper;
    // the offer sheet leaves backup offers out (help_offer_tile_sheet_cubit
    // test). Each call site keeps its own rule.
    testWidgets('author sees End participation for an admitted backup helper', (
      tester,
    ) async {
      final base = acknowledgedHelperState(BeaconStatus.open);
      _state = base.copyWith(
        helpOffers: [
          for (final offer in base.helpOffers) offer.copyWith(offerKind: 1),
        ],
      );

      await pumpPeople(tester);

      expect(
        find.byKey(TestIds.key(TestIds.helpOfferRelease('h1'))),
        findsOneWidget,
      );
    });

    testWidgets('author sees no End participation once closed', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      _state = acknowledgedHelperState(BeaconStatus.closed);

      await pumpPeople(tester);

      expect(find.text(l10n.helpOfferReleaseCommitment), findsNothing);
    });

    testWidgets('helper still sees Withdraw on their own card in Wrapping up', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      _state = ownOfferState(BeaconStatus.reviewOpen);

      await pumpPeople(tester);

      expect(find.text(l10n.helpOffersTabActionWithdraw), findsOneWidget);
    });

    BeaconViewState mixedState(BeaconStatus status) {
      final base = acknowledgedHelperState(status);
      return base.copyWith(
        helpOffers: [
          ...base.helpOffers,
          TimelineHelpOffer(
            user: const Profile(id: 'h2', displayName: 'Newcomer'),
            message: 'I could also help',
            createdAt: _t,
            updatedAt: _t,
          ),
        ],
      );
    }

    testWidgets('open: a pending offer still gets Accept and Decline', (
      tester,
    ) async {
      // Control for the Wrapping-up case below.
      // Two cards with action rows do not fit the default 800x600 surface.
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _state = mixedState(BeaconStatus.open);

      await pumpPeople(tester);

      expect(
        find.byKey(TestIds.key(TestIds.helpOfferAccept('h2'))),
        findsOneWidget,
      );
      expect(
        find.byKey(TestIds.key(TestIds.helpOfferDecline('h2'))),
        findsOneWidget,
      );
    });

    testWidgets(
      'Wrapping up: End participation shows, but a pending offer gets no '
      'Accept or Decline',
      (tester) async {
        // Two cards with action rows do not fit the default 800x600 surface.
        await tester.binding.setSurfaceSize(const Size(800, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        _state = mixedState(BeaconStatus.reviewOpen);

        await pumpPeople(tester);

        expect(
          find.byKey(TestIds.key(TestIds.helpOfferRelease('h1'))),
          findsOneWidget,
        );
        expect(
          find.byKey(TestIds.key(TestIds.helpOfferAccept('h2'))),
          findsNothing,
        );
        expect(
          find.byKey(TestIds.key(TestIds.helpOfferDecline('h2'))),
          findsNothing,
        );
      },
    );

    testWidgets('helper sees no Withdraw on their own card once closed', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      _state = ownOfferState(BeaconStatus.closed);

      await pumpPeople(tester);

      expect(find.text(l10n.helpOffersTabActionWithdraw), findsNothing);
    });
  });

  // #496: the helper card's admission line comes from the same forward
  // trail as People › Forwards; with no forward there, no direct claim.
  group('admission line follows the Forwards trail (#496)', () {
    const directEn = 'You forwarded this request to them directly';
    const networkEn = 'Joined via the network';

    Future<void> pumpPeople(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpPeopleTagsWidget(
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

    testWidgets('author: flagged direct but Forwards is empty: '
        'joined via the network', (tester) async {
      _state = _admittedDirectState();
      await pumpPeople(tester);

      // Forwards is loaded and shows no trail.
      expect(find.text('Forwards (0)'), findsOneWidget);
      expect(find.text(directEn), findsNothing);
      expect(find.text('Forwarded by you'), findsNothing);
      expect(find.text(networkEn), findsOneWidget);
    });

    testWidgets('author: Forwards not loaded yet: no direct claim', (
      tester,
    ) async {
      _state = _admittedDirectState(forwardsLoaded: false);
      await pumpPeople(tester);

      expect(find.text(directEn), findsNothing);
      expect(find.text(networkEn), findsOneWidget);
    });

    testWidgets('author: the forward was cancelled: no direct claim', (
      tester,
    ) async {
      _state = _admittedDirectState(
        viewerForwardEdges: [_authorForwardTo('h1', cancelled: true)],
      );
      await pumpPeople(tester);

      expect(find.text(directEn), findsNothing);
      expect(find.text(networkEn), findsOneWidget);
    });

    testWidgets('author: a live forward on the trail keeps the direct line', (
      tester,
    ) async {
      _state = _admittedDirectState(
        viewerForwardEdges: [_authorForwardTo('h1')],
      );
      await pumpPeople(tester);

      expect(find.text('Forwards (1)'), findsOneWidget);
      expect(find.text(directEn), findsOneWidget);
      expect(find.text(networkEn), findsNothing);
    });

    test('a flagged offer asks for the trail while it is unknown', () {
      expect(
        _admittedDirectState(forwardsLoaded: false).needsTrailForDirectForward,
        isTrue,
      );
      expect(_admittedDirectState().needsTrailForDirectForward, isFalse);
      // A steward's cards keep the server flag; no trail read is needed.
      expect(
        _admittedDirectState(
          forwardsLoaded: false,
          myProfile: const Profile(id: 's1', displayName: 'Steward'),
        ).needsTrailForDirectForward,
        isFalse,
      );
    });
  });

  testWidgets('a helper whose participation the author ended is listed '
      'under Participation ended, not Declined offers (#701)', (tester) async {
    _state = _peopleState(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'h2', displayName: 'Helper Two'),
          message: 'I can help',
          createdAt: _t,
          updatedAt: _t,
          coordinationResponse: CoordinationResponseType.useful,
          roomAccess: RoomAccessBits.none,
          admissionAction: HelpOfferAdmissionAction.remove,
          lastRemoveReason: 'Plans changed',
          stakeState: CommitmentStakeState.released,
        ),
      ],
    );
    await tester.pumpPeopleTagsWidget(
      _wrapPeople(
        BeaconPeopleTabBody(
          state: _state,
          beaconViewCubit: _MockBeaconViewCubit(),
          l10n: lookupL10n(const Locale('en')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Declined offers'), findsNothing);
    expect(find.text('Participation ended (1)'), findsOneWidget);
    await tester.tap(find.text('Participation ended (1)'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HelpOfferTile),
        matching: find.text('Helper Two'),
      ),
      findsOneWidget,
    );
  });

  group('accepted helper keeps the capability chips they offered (#731)', () {
    const offered = '["transport","support"]';
    final admitted = TimelineHelpOffer(
      user: const Profile(id: 'h1', displayName: 'Dave'),
      message: 'I have a truck',
      createdAt: _t,
      updatedAt: _t,
      helpType: offered,
      coordinationResponse: CoordinationResponseType.useful,
      roomAccess: RoomAccessBits.admitted,
      admissionAction: HelpOfferAdmissionAction.accept,
    );

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpPeopleTagsWidget(
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

    testWidgets('guard: the author sees the chips on the admitted card', (
      tester,
    ) async {
      _state = _peopleState(
        helpOffers: [admitted],
        admittedHelperRoster: const [Profile(id: 'h1', displayName: 'Dave')],
      );
      await pump(tester);

      final chips = find.byType(ForwardCapabilityChips);
      expect(chips, findsOneWidget);
      expect(tester.widget<ForwardCapabilityChips>(chips).slugs, [
        'transport',
        'support',
      ]);
    });

    testWidgets('the room row carries the chips when the offer row has none', (
      tester,
    ) async {
      _state = _peopleState(
        helpOffers: [
          TimelineHelpOffer(
            user: const Profile(id: 'h1', displayName: 'Dave'),
            message: 'I have a truck',
            createdAt: _t,
            updatedAt: _t,
            roomAccess: RoomAccessBits.admitted,
          ),
        ],
        roomParticipants: [
          BeaconParticipant(
            id: 'p-h1',
            beaconId: 'B1',
            userId: 'h1',
            userTitle: 'Dave',
            role: BeaconParticipantRoleBits.helper,
            status: BeaconParticipantStatusBits.committed,
            roomAccess: RoomAccessBits.admitted,
            createdAt: _t,
            updatedAt: _t,
            helpType: offered,
          ),
        ],
        admittedHelperRoster: const [Profile(id: 'h1', displayName: 'Dave')],
      );
      await pump(tester);

      expect(find.byType(ForwardCapabilityChips), findsOneWidget);
    });

    testWidgets('an observer sees the chips on the read-only helper row', (
      tester,
    ) async {
      _state = _peopleState(
        accessLevel: BeaconAccessLevel.observer,
        myProfile: const Profile(id: 'obs', displayName: 'Observer'),
        helpOffers: [admitted],
        admittedHelperRoster: const [Profile(id: 'h1', displayName: 'Dave')],
      );
      await pump(tester);

      expect(find.text('Dave'), findsOneWidget);
      final chips = find.byType(ForwardCapabilityChips);
      expect(chips, findsOneWidget);
      expect(tester.widget<ForwardCapabilityChips>(chips).slugs, [
        'transport',
        'support',
      ]);
    });
  });

  // #533: a phone has no header pile, so the People tab rows carry the
  // team's presence.
  group('People tab rows show who is online (#533)', () {
    Future<void> pumpWithPresence(
      WidgetTester tester,
      Map<String, UserPresenceStatus> presence,
    ) async {
      await tester.binding.setSurfaceSize(const Size(375, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = _admittedDirectState();
      _state = base.copyWith(
        beacon: base.beacon.copyWith(
          admittedHelperUsers: const [Profile(id: 'h1', displayName: 'Helper')],
        ),
      );
      await tester.pumpPeopleTagsWidget(
        BlocProvider<PresenceCubit>.value(
          value: _PresenceCubit(presence),
          child: _wrapPeople(
            BeaconPeopleTabBody(
              state: _state,
              beaconViewCubit: _MockBeaconViewCubit(),
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<bool> onlineFlags(WidgetTester tester) {
      final avatars = find.byWidgetPredicate(
        (w) => w is TenturaAvatar && w.profile.id == 'h1',
      );
      expect(avatars, findsWidgets);
      return [
        for (final a in tester.widgetList<TenturaAvatar>(avatars)) a.isOnline,
      ];
    }

    testWidgets('an online helper row has the dot and says online', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpWithPresence(tester, const {'h1': UserPresenceStatus.online});

      expect(onlineFlags(tester), contains(true));
      expect(find.bySemanticsLabel(RegExp('Helper, Online')), findsWidgets);
      semantics.dispose();
    });

    testWidgets('an offline helper row has no dot and no online label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpWithPresence(tester, const {'h1': UserPresenceStatus.offline});

      expect(onlineFlags(tester), isNot(contains(true)));
      expect(find.bySemanticsLabel(RegExp('Online')), findsNothing);
      semantics.dispose();
    });

    testWidgets('someone outside the watched team gets no dot', (
      tester,
    ) async {
      // Presence data from another screen (a picker) must not leak a dot
      // onto a row of someone this screen does not watch.
      await tester.binding.setSurfaceSize(const Size(375, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _state = _admittedDirectState();
      await tester.pumpPeopleTagsWidget(
        BlocProvider<PresenceCubit>.value(
          value: _PresenceCubit(const {'h1': UserPresenceStatus.online}),
          child: _wrapPeople(
            BeaconPeopleTabBody(
              state: _state,
              beaconViewCubit: _MockBeaconViewCubit(),
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(onlineFlags(tester), isNot(contains(true)));
    });
  });
}
