import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_participant_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
        profile: Profile(id: 'me', title: 'Me'),
      );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// Records the last `showCommitterForwardPathFor` call so the test can
/// assert routing parameters without spinning up the AutoRoute stack.
class _RecordingScreenCubit extends ScreenCubit {
  String? lastBeaconId;
  String? lastCommitterId;
  String? lastCommitterName;

  @override
  void showCommitterForwardPathFor({
    required String beaconId,
    required String committerId,
    String? committerName,
  }) {
    lastBeaconId = beaconId;
    lastCommitterId = committerId;
    lastCommitterName = committerName;
  }
}

BeaconParticipant _participant({
  required String userId,
  required int status,
  String userTitle = 'Alice',
}) =>
    BeaconParticipant(
      id: 'P-$userId',
      beaconId: 'B-1',
      userId: userId,
      role: BeaconParticipantRoleBits.helper,
      status: status,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      userTitle: userTitle,
    );

Widget _wrap(Widget child, {required _RecordingScreenCubit screenCubit}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>.value(value: screenCubit),
      ],
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  const author = Profile(id: 'auth', title: 'Author');
  final beacon = Beacon.empty.copyWith(
    id: 'B-1',
    updatedAt: DateTime(2025),
    author: author,
  );

  testWidgets(
    'forward-path button is shown for an active committer who is not the author',
    (tester) async {
      final screenCubit = _RecordingScreenCubit();
      addTearDown(screenCubit.close);

      await tester.pumpWidget(
        _wrap(
          BeaconPeopleParticipantCard(
            beacon: beacon,
            participant: _participant(
              userId: 'committer1',
              status: BeaconParticipantStatusBits.committed,
            ),
            commitments: const [],
          ),
          screenCubit: screenCubit,
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byTooltip('Show forward path');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(screenCubit.lastBeaconId, 'B-1');
      expect(screenCubit.lastCommitterId, 'committer1');
      expect(screenCubit.lastCommitterName, isNotNull);
    },
  );

  testWidgets('forward-path button is hidden for non-committed participants',
      (tester) async {
    final screenCubit = _RecordingScreenCubit();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      _wrap(
        BeaconPeopleParticipantCard(
          beacon: beacon,
          participant: _participant(
            userId: 'watcher1',
            status: BeaconParticipantStatusBits.watching,
          ),
          commitments: const [],
        ),
        screenCubit: screenCubit,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show forward path'), findsNothing);
  });

  testWidgets('forward-path button is hidden for the beacon author',
      (tester) async {
    final screenCubit = _RecordingScreenCubit();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      _wrap(
        BeaconPeopleParticipantCard(
          beacon: beacon,
          participant: _participant(
            userId: author.id,
            status: BeaconParticipantStatusBits.committed,
          ),
          commitments: const [],
        ),
        screenCubit: screenCubit,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show forward path'), findsNothing);
  });

  testWidgets('forward-path button is hidden for withdrawn participants',
      (tester) async {
    final screenCubit = _RecordingScreenCubit();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      _wrap(
        BeaconPeopleParticipantCard(
          beacon: beacon,
          participant: _participant(
            userId: 'withdrawn1',
            status: BeaconParticipantStatusBits.withdrawn,
          ),
          commitments: const [],
        ),
        screenCubit: screenCubit,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show forward path'), findsNothing);
  });
}
