import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_surface.dart';
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
  late BeaconViewState state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(state);

  @override
  Future<void> reportPeopleSurfaceViewed() {
    return super.noSuchMethod(
          Invocation.method(#reportPeopleSurfaceViewed, const []),
          returnValue: Future<void>.value(),
          returnValueForMissingStub: Future<void>.value(),
        )
        as Future<void>;
  }

  int legacyMarkPeopleSeenCalls = 0;

  @override
  Future<void> markPeopleSeen() async {
    legacyMarkPeopleSeenCalls++;
  }
}

final _t = DateTime.utc(2025);

BeaconViewState _state({
  required List<TimelineHelpOffer> helpOffers,
  String myId = 'auth',
  List<BeaconParticipant> roomParticipants = const [],
}) => BeaconViewState(
  beacon: Beacon(
    id: 'B1',
    title: 'T',
    author: const Profile(id: 'auth', displayName: 'Author'),
    createdAt: _t,
    updatedAt: _t,
  ),
  myProfile: Profile(id: myId, displayName: 'Me'),
  helpOffers: helpOffers,
  roomParticipants: roomParticipants,
);

BeaconParticipant _steward(String userId) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: 'B1',
  userId: userId,
  userTitle: 'Steward',
  role: BeaconParticipantRoleBits.steward,
  status: BeaconParticipantStatusBits.committed,
  roomAccess: RoomAccessBits.admitted,
  createdAt: _t,
  updatedAt: _t,
);

List<TimelineHelpOffer> _offers() => [
  TimelineHelpOffer(
    user: const Profile(id: 'h1', displayName: 'Helper'),
    message: 'I can help',
    createdAt: _t,
    updatedAt: _t,
  ),
];

Widget _wrap(
  _MockBeaconViewCubit cubit,
  BeaconViewState state, {
  int epoch = 0,
}) {
  cubit.state = state;
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        BlocProvider<BeaconViewCubit>.value(value: cubit),
      ],
      child: Scaffold(
        body: BeaconPeopleSurface(
          beaconViewCubit: cubit,
          beaconState: state,
          focusUserId: null,
          peopleTabAttentionActive: false,
          peopleFoldEpoch: epoch,
        ),
      ),
    ),
  );
}

void main() {
  late _MockBeaconViewCubit cubit;

  setUp(() => cubit = _MockBeaconViewCubit());

  testWidgets('mount reports the People surface viewed once', (tester) async {
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: _offers())));
    await tester.pump();

    verify(cubit.reportPeopleSurfaceViewed()).called(1);
    expect(cubit.legacyMarkPeopleSeenCalls, 0);
  });

  testWidgets('new helpOffers list instance reports again', (tester) async {
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: _offers())));
    await tester.pump();
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: _offers())));
    await tester.pump();

    verify(cubit.reportPeopleSurfaceViewed()).called(2);
    expect(cubit.legacyMarkPeopleSeenCalls, 0);
  });

  testWidgets('same list instance and unchanged flag does not report again', (
    tester,
  ) async {
    final offers = _offers();
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: offers)));
    await tester.pump();
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: offers), epoch: 1));
    await tester.pump();

    verify(cubit.reportPeopleSurfaceViewed()).called(1);
    expect(cubit.legacyMarkPeopleSeenCalls, 0);
  });

  testWidgets('isAuthorOrSteward flipping false to true reports again', (
    tester,
  ) async {
    final offers = _offers();
    await tester.pumpWidget(
      _wrap(cubit, _state(helpOffers: offers, myId: 'viewer')),
    );
    await tester.pump();
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: offers)));
    await tester.pump();

    verify(cubit.reportPeopleSurfaceViewed()).called(2);
    expect(cubit.legacyMarkPeopleSeenCalls, 0);
  });

  testWidgets('viewer promoted to steward reports again', (tester) async {
    final offers = _offers();
    await tester.pumpWidget(
      _wrap(cubit, _state(helpOffers: offers, myId: 'viewer')),
    );
    await tester.pump();
    await tester.pumpWidget(
      _wrap(
        cubit,
        _state(
          helpOffers: offers,
          myId: 'viewer',
          roomParticipants: [_steward('viewer')],
        ),
      ),
    );
    await tester.pump();

    verify(cubit.reportPeopleSurfaceViewed()).called(2);
    expect(cubit.legacyMarkPeopleSeenCalls, 0);
  });

  testWidgets('isAuthorOrSteward flipping true to false does not report', (
    tester,
  ) async {
    final offers = _offers();
    await tester.pumpWidget(_wrap(cubit, _state(helpOffers: offers)));
    await tester.pump();
    await tester.pumpWidget(
      _wrap(cubit, _state(helpOffers: offers, myId: 'viewer')),
    );
    await tester.pump();

    verify(cubit.reportPeopleSurfaceViewed()).called(1);
    expect(cubit.legacyMarkPeopleSeenCalls, 0);
  });

  testWidgets(
    'new helpOffers list reports again even while viewer is not author/steward',
    (tester) async {
      await tester.pumpWidget(
        _wrap(cubit, _state(helpOffers: _offers(), myId: 'viewer')),
      );
      await tester.pump();
      await tester.pumpWidget(
        _wrap(cubit, _state(helpOffers: _offers(), myId: 'viewer')),
      );
      await tester.pump();

      verify(cubit.reportPeopleSurfaceViewed()).called(2);
      expect(cubit.legacyMarkPeopleSeenCalls, 0);
    },
  );
}
