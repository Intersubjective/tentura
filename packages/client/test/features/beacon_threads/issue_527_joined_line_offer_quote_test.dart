// #527 (V3-B, Vadim 2026-10-27): once a helper is admitted, what they wrote
// in their offer was only on their People card. The room now quotes it under
// the line that says they joined, so the team sees what each person offered.

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
const _author = Profile(id: 'u-alice', displayName: 'Alice');
const _quoteKey = Key('room-participant-joined-offer-quote');

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

BeaconParticipant _omar({String offerNote = ''}) => BeaconParticipant(
  id: 'P-omar',
  beaconId: 'B1',
  userId: 'u-omar',
  role: BeaconParticipantRoleBits.helper,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 21),
  userTitle: 'Omar Dinner',
  offerNote: offerNote,
);

final _joinedLine = RoomMessage(
  id: 'R-joined',
  beaconId: 'B1',
  authorId: _author.id,
  author: _author,
  body: '',
  createdAt: DateTime.utc(2026, 10, 21, 9),
  semanticMarker: BeaconRoomSemanticMarker.participantJoined,
  systemPayloadJson: '{"joinedUserId":"u-omar","actorUserId":"u-alice"}',
);

Future<void> _pump(
  WidgetTester tester,
  List<BeaconParticipant> participants, {
  Locale locale = const Locale('en'),
}) async {
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
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: RoomMessageTile(
                  message: _joinedLine,
                  myProfile: _viewer,
                  participants: participants,
                  onToggleReaction: (_, _) async {},
                ),
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
  testWidgets('quotes the helper\u2019s offer under the joined line', (
    tester,
  ) async {
    await _pump(tester, [_omar(offerNote: '  I have a van, free 10-12.  ')]);

    expect(
      find.text('Omar Dinner was admitted to the discussion by Alice'),
      findsOneWidget,
    );
    final quote = find.byKey(_quoteKey);
    expect(quote, findsOneWidget);
    expect(
      tester.widget<Text>(quote).data,
      '\u201cI have a van, free 10-12.\u201d',
    );
    // Under the line, not beside it.
    expect(
      tester.getTopLeft(quote).dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.text('Omar Dinner was admitted to the discussion by Alice'),
            )
            .dy,
      ),
    );
  });

  testWidgets('quotes it the Russian way in Russian', (tester) async {
    await _pump(tester, [
      _omar(offerNote: 'Есть машина'),
    ], locale: const Locale('ru'));

    expect(
      tester.widget<Text>(find.byKey(_quoteKey)).data,
      '\u00abЕсть машина\u00bb',
    );
  });

  // Guards: nothing to quote, nothing shown.
  testWidgets('shows no quote when the offer had no text', (tester) async {
    await _pump(tester, [_omar(offerNote: '   ')]);

    expect(
      find.text('Omar Dinner was admitted to the discussion by Alice'),
      findsOneWidget,
    );
    expect(find.byKey(_quoteKey), findsNothing);
  });

  testWidgets('shows no quote when the helper is not in the list', (
    tester,
  ) async {
    await _pump(tester, const []);

    expect(find.byKey(_quoteKey), findsNothing);
  });
}
