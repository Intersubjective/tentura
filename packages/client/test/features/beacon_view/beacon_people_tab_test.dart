import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
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
  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);
}

final _t = DateTime.utc(2025);
late BeaconViewState _state;

BeaconViewState _peopleState({
  List<TimelineHelpOffer> helpOffers = const [],
  List<BeaconParticipant> roomParticipants = const [],
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
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit()),
            BlocProvider<BeaconViewCubit>.value(value: _MockBeaconViewCubit()),
          ],
          child: Scaffold(
            body: BeaconPeopleTabBody(
              state: _state,
              beaconViewCubit: _MockBeaconViewCubit(),
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active helpers (1)'), findsOneWidget);
    expect(find.text('Willing to help (1)'), findsOneWidget);
    expect(find.textContaining('Not fitting'), findsNothing);
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
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit()),
            BlocProvider<BeaconViewCubit>.value(value: _MockBeaconViewCubit()),
          ],
          child: Scaffold(
            body: BeaconPeopleTabBody(
              state: _state,
              beaconViewCubit: _MockBeaconViewCubit(),
              l10n: lookupL10n(const Locale('en')),
            ),
          ),
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
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: compact),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit()),
              BlocProvider<BeaconViewCubit>.value(
                value: _MockBeaconViewCubit(),
              ),
            ],
            child: Scaffold(
              body: SingleChildScrollView(
                child: BeaconPeopleTabBody(
                  state: _state,
                  beaconViewCubit: _MockBeaconViewCubit(),
                  l10n: lookupL10n(const Locale('en')),
                ),
              ),
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
}
