// #865: RU discussion log when the viewer is the actor, and one Enough help
// name on the status line and in status-changed log lines.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/coordination/beacon_coordination_phase_input.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

import '../../support/phone_surface.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Alice Author');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

RoomMessage _admittedLine() => RoomMessage(
  id: 'R-join',
  beaconId: 'B1',
  authorId: _viewer.id,
  author: _viewer,
  body: '',
  createdAt: DateTime.utc(2026, 10, 14, 9),
  semanticMarker: BeaconRoomSemanticMarker.participantJoined,
  systemPayloadJson: '{"joinedUserId":"u-bob","actorUserId":"viewer"}',
);

RoomMessage _statusToEnoughHelp() => RoomMessage(
  id: 'R-status',
  beaconId: 'B1',
  authorId: _viewer.id,
  author: _viewer,
  body: '',
  createdAt: DateTime.utc(2026, 10, 14, 9),
  systemMessageKind: BeaconRoomSystemMessageKind.statusChanged,
  systemPayloadJson:
      '{"version":1,"fromStatus":0,"toStatus":8,"reason":"enoughHelp"}',
);

Widget _harness(RoomMessage message) => MultiBlocProvider(
  providers: [
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: MediaQuery(
      data: const MediaQueryData(size: kPhoneSurface),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SingleChildScrollView(
            child: RoomMessageTile(
              message: message,
              myProfile: _viewer,
              participants: [
                BeaconParticipant(
                  id: 'P-bob',
                  beaconId: 'B1',
                  userId: 'u-bob',
                  role: BeaconParticipantRoleBits.helper,
                  status: 0,
                  roomAccess: RoomAccessBits.admitted,
                  createdAt: DateTime.utc(2026, 10),
                  updatedAt: DateTime.utc(2026, 10),
                  userTitle: 'Bob GQ2',
                ),
              ],
              onToggleReaction: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('Enough help label matches HUD status line and room log', () {
    final ru = lookupL10n(const Locale('ru'));
    final sheetLabel = beaconStatusMenuRowLabel(
      ru,
      BeaconStatusMenuRowId.enoughHelp,
    );
    final logLabel = RoomMessageTile.roomLogStatusLabel(
      ru,
      BeaconStatus.enoughHelp,
    );
    expect(logLabel, sheetLabel);
    expect(logLabel, ru.coordinationEnoughHelp);

    final now = DateTime.utc(2026, 6, 20, 12);
    final phase = deriveBeaconCoordinationPhase(
      BeaconCoordinationPhaseInput(
        beacon: Beacon.empty.copyWith(
          id: 'b1',
          status: BeaconStatus.enoughHelp,
          updatedAt: now,
        ),
        tier: BeaconVisibilityTier.coordination,
        now: now,
      ),
    );
    final hud = formatBeaconPhaseStatus(ru, phase, now: now);
    expect(hud.slot1, logLabel);
  });

  testWidgets('viewer as actor reads «Вы допустили …» at phone width', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(_harness(_admittedLine()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Вы допустили Bob GQ2 в обсуждение',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('пользователем Вы', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('допущен(а)', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('status log and HUD share Enough help name on same screen', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final ru = lookupL10n(const Locale('ru'));
    final enoughHelp = ru.coordinationEnoughHelp;

    await tester.pumpWidget(_harness(_statusToEnoughHelp()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Вы изменили статус', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(enoughHelp, findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Помощи хватает', findRichText: true),
      findsWidgets,
    );
    expect(find.textContaining('В работе', findRichText: true), findsNothing);
  });
}
