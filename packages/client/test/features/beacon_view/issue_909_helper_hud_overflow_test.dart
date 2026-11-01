// #909: a helper (an admitted member, not the author) opening a Request at
// phone width hit "A RenderFlex overflowed … on the right". The author and an
// outsider (showcase) at the same size are the siblings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';

import 'beacon_view_screen_harness.dart';

const _longAuthor =
    'Konstantin Konstantinopolsky-Rimsky-Korsakov the Very Patient Author';
const _helper = Profile(id: 'helper-909', displayName: 'Helper');

BeaconViewState _state({required Profile viewer, required int access}) {
  final base = beaconViewHarnessAuthorState();
  const author = Profile(
    id: kBeaconViewHarnessAuthorId,
    displayName: _longAuthor,
  );
  return base.copyWith(
    beacon: base.beacon.copyWith(
      author: author,
      title: 'Help moving a very heavy sofa up to the fifth floor on Saturday',
      accessLevel: BeaconAccessLevel.fromInt(access),
      viewerCanForward: true,
    ),
    beaconRoomCue: BeaconRoomState(
      beaconId: kBeaconViewHarnessBeaconId,
      updatedAt: kBeaconViewHarnessNow,
      currentLine: 'Van at 9:45, dolly from Omar, meet at the back door',
    ),
    myProfile: viewer.id == kBeaconViewHarnessAuthorId ? author : viewer,
    isHelpOffered: viewer.id == _helper.id,
    helpOffers: [
      if (viewer.id == _helper.id)
        TimelineHelpOffer(
          user: _helper,
          message: 'I can help',
          createdAt: kBeaconViewHarnessNow,
          updatedAt: kBeaconViewHarnessNow,
          coordinationResponse: CoordinationResponseType.useful,
          admissionAction: HelpOfferAdmissionAction.accept,
          roomAccess: RoomAccessBits.admitted,
          stakeState: CommitmentStakeState.acknowledged,
        ),
    ],
    roomParticipants: [
      ...base.roomParticipants,
      if (viewer.id == _helper.id)
        BeaconParticipant(
          id: 'p-helper',
          beaconId: kBeaconViewHarnessBeaconId,
          userId: _helper.id,
          role: BeaconParticipantRoleBits.helper,
          status: BeaconParticipantStatusBits.committed,
          roomAccess: RoomAccessBits.admitted,
          createdAt: kBeaconViewHarnessNow,
          updatedAt: kBeaconViewHarnessNow,
        ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required BeaconViewState state,
  required Size size,
  required Locale locale,
}) async {
  await pumpBeaconViewHarness(
    tester,
    size: size,
    beaconState: state,
    threadsState: beaconViewHarnessThreadsState(),
    viewTab: 'now',
    locale: locale,
  );
  // The first-load gate reveals partial data after its timeout.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(unregisterBeaconViewHarnessGetIt);

  const sizes = [Size(390, 844), Size(375, 667), Size(320, 568)];
  const locales = [Locale('en'), Locale('ru')];

  for (final size in sizes) {
    for (final locale in locales) {
      final tag =
          '${size.width.toInt()}x${size.height.toInt()} '
          '${locale.languageCode}';

      testWidgets('#909 helper HUD does not overflow at $tag', (tester) async {
        await _pump(
          tester,
          state: _state(viewer: _helper, access: 1),
          size: size,
          locale: locale,
        );
        expect(find.byType(BeaconHudPinnedBlock), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('#909 author HUD does not overflow at $tag', (tester) async {
        await _pump(
          tester,
          state: _state(
            viewer: const Profile(id: kBeaconViewHarnessAuthorId),
            access: 0,
          ),
          size: size,
          locale: locale,
        );
        expect(find.byType(BeaconHudPinnedBlock), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('#909 showcase does not overflow at $tag', (tester) async {
        await _pump(
          tester,
          state: _state(
            viewer: const Profile(id: 'outsider-909', displayName: 'Out'),
            access: 2,
          ),
          size: size,
          locale: locale,
        );
        expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
