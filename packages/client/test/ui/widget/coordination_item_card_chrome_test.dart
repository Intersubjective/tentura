import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'u1', displayName: 'Alice'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('directed avatar trail shows arrow between two participants', (
    tester,
  ) async {
    final t = DateTime.utc(2026);
    final participants = [
      BeaconParticipant(
        id: 'p1',
        beaconId: 'b1',
        userId: 'u1',
        role: 0,
        status: 0,
        roomAccess: 1,
        createdAt: t,
        updatedAt: t,
        userTitle: 'Alice',
        handle: 'alice',
      ),
      BeaconParticipant(
        id: 'p2',
        beaconId: 'b1',
        userId: 'u2',
        role: 0,
        status: 0,
        roomAccess: 1,
        createdAt: t,
        updatedAt: t,
        userTitle: 'Bob',
        handle: 'bob',
      ),
    ];

    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: _TestProfileCubit(),
        child: MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: coordinationDirectedAvatarTrailForItem(
              participants: participants,
              creatorId: 'u1',
              targetPersonId: 'u2',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_right_alt), findsOneWidget);
    expect(find.byType(Semantics), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
