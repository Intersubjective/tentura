// #489 (round 7): when the author ends a helper's participation, the server
// posts a `participantRemoved` system line (marker 19) whose payload carries
// only `removedUserId`. The room shows a centered NEUTRAL system line naming
// the removed helper — ARB `beaconRoomParticipantRemoved(name)`, en
// "{name} is no longer in the request", ru «{name} больше не в запросе» —
// never a raw user id or an empty bubble. Per U41
// (docs/plans/episode-closure-implementation-plan.md l.69) colleagues are not
// told who initiated a departure, so the line names neither the author (the
// message's author) nor the reason, even if a stray `reason` rides the
// payload.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _anna = Profile(id: 'u-anna', displayName: 'Anna Author');
const _omarId = 'U784390f7cdc3';

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

/// The removed helper keeps a participant row (room access revoked).
final _omarRow = BeaconParticipant(
  id: 'P-omar',
  beaconId: 'B1',
  userId: _omarId,
  role: 2,
  status: 0,
  roomAccess: RoomAccessBits.none,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 21),
  userTitle: 'Omar Dinner',
);

/// [strayReason] simulates a payload carrying a reason the line must ignore.
RoomMessage _removedLine({String? strayReason}) => RoomMessage(
  id: 'R-removed',
  beaconId: 'B1',
  authorId: _anna.id,
  author: _anna,
  body: '',
  createdAt: DateTime.utc(2026, 10, 21, 9),
  semanticMarker: BeaconRoomSemanticMarker.participantRemoved,
  systemPayloadJson: strayReason == null
      ? '{"removedUserId":"$_omarId"}'
      : '{"removedUserId":"$_omarId","reason":"$strayReason"}',
);

Widget _harness(RoomMessage message, {Locale locale = const Locale('en')}) =>
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: RoomMessageTile(
                  message: message,
                  myProfile: _viewer,
                  participants: [_omarRow],
                  onToggleReaction: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    final lang = locale.languageCode;

    testWidgets('$lang: shows the neutral ARB line naming the removed helper', (
      tester,
    ) async {
      final l10n = lookupL10n(locale);
      await tester.pumpWidget(_harness(_removedLine(), locale: locale));
      await tester.pumpAndSettle();

      expect(
        find.text(
          l10n.beaconRoomParticipantRemoved('Omar Dinner'),
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Omar Dinner', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining(_omarId, findRichText: true), findsNothing);
      // U41: colleagues are not told who initiated the removal.
      expect(
        find.textContaining('Anna Author', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('$lang: never shows a reason, even one left in the payload', (
      tester,
    ) async {
      final l10n = lookupL10n(locale);
      await tester.pumpWidget(
        _harness(_removedLine(strayReason: 'No-show twice'), locale: locale),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          l10n.beaconRoomParticipantRemoved('Omar Dinner'),
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('No-show twice', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Anna Author', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining(_omarId, findRichText: true), findsNothing);
    });
  }

  test('ARB wording is the settled neutral line', () {
    expect(
      lookupL10n(const Locale('en')).beaconRoomParticipantRemoved('Omar'),
      'Omar is no longer in the request',
    );
    expect(
      lookupL10n(const Locale('ru')).beaconRoomParticipantRemoved('Omar'),
      'Omar больше не в запросе',
    );
  });
}
