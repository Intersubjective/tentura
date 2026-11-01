// #742: a live admission line names a user before the room's participant
// list has them, and the line showed their raw ID («U95a5d2e6d869 was
// admitted to the discussion by You»). It never shows the ID.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _author = Profile(id: 'u-alice', displayName: 'Alice');

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

RoomMessage _joinedLine({required Profile admittedBy, String reason = ''}) =>
    RoomMessage(
      id: 'R-joined',
      beaconId: 'B1',
      authorId: admittedBy.id,
      author: admittedBy,
      body: '',
      createdAt: DateTime.utc(2026, 10, 24, 17, 30),
      semanticMarker: BeaconRoomSemanticMarker.participantJoined,
      systemPayloadJson:
          '{"joinedUserId":"U95a5d2e6d869","actorUserId":"${admittedBy.id}",'
          '"admissionReason":"$reason"}',
    );

Future<void> _pump(
  WidgetTester tester,
  RoomMessage line, {
  required Locale locale,
}) async {
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
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
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: RoomMessageTile(
                message: line,
                myProfile: _viewer,
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final l10n = lookupL10n(locale);
    final lang = locale.languageCode;
    final unknown = l10n.beaconRoomUnknownParticipant;

    final cases = {
      'admitted by me': (
        _joinedLine(admittedBy: _viewer),
        l10n.beaconRoomParticipantJoinedBySelfUnknown,
      ),
      'admitted by another member': (
        _joinedLine(admittedBy: _author),
        l10n.beaconRoomParticipantJoinedByActor(unknown, 'Alice'),
      ),
      'auto-admitted': (
        _joinedLine(admittedBy: _author, reason: 'autoAdmit'),
        l10n.beaconRoomParticipantJoinedAutoAdmit(unknown),
      ),
    };
    for (final MapEntry(key: name, value: (line, expected)) in cases.entries) {
      testWidgets('$lang 375×667, $name: no raw user ID before the '
          'participant list has them', (tester) async {
        await _pump(tester, line, locale: locale);

        expect(find.textContaining('U95a5d2e6d869'), findsNothing);
        expect(
          find.textContaining('U95a5d2e6d869', findRichText: true),
          findsNothing,
        );
        expect(find.text(expected), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
