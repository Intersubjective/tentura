// The «X was admitted to the discussion» line quotes the helper's offer. The
// quote is a snapshot the server stored in the line's system payload
// (`offerNote`) when the author admitted them; the tile renders it from the
// message alone, never from the room's live participant list, so it neither
// depends on that list nor disappears when the helper later edits or
// withdraws the offer.

import 'dart:convert';

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

const _line = 'Omar Dinner was admitted to the discussion by Alice';

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

RoomMessage _joinedLine({String? offerNote}) => RoomMessage(
  id: 'R-joined',
  beaconId: 'B1',
  authorId: _author.id,
  author: _author,
  body: '',
  createdAt: DateTime.utc(2026, 10, 21, 9),
  semanticMarker: BeaconRoomSemanticMarker.participantJoined,
  systemPayloadJson: jsonEncode({
    'joinedUserId': 'u-omar',
    'actorUserId': 'u-alice',
    'admissionReason': 'accept',
    'offerNote': ?offerNote,
  }),
);

Future<void> _pump(
  WidgetTester tester,
  RoomMessage message,
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
                  message: message,
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

/// The quote as the viewer sees it: found by what it says, not by how the
/// widget is built.
Finder _quoteText(String text) => find.text(text);

void main() {
  group('admission line quote from the message payload', () {
    testWidgets(
      'quotes the offer stored in the line when the live participant record '
      'has no offer text',
      (tester) async {
        await _pump(
          tester,
          _joinedLine(offerNote: '  I have a van, free 10-12.  '),
          [_omar()],
        );

        expect(find.text(_line), findsOneWidget);
        final quote = _quoteText('“I have a van, free 10-12.”');
        expect(quote, findsOneWidget);
        // Under the line, not beside it.
        expect(
          tester.getTopLeft(quote).dy,
          greaterThan(tester.getBottomLeft(find.text(_line)).dy),
        );
      },
    );

    testWidgets('quotes it the Russian way in Russian', (tester) async {
      await _pump(
        tester,
        _joinedLine(offerNote: 'Есть машина'),
        [_omar()],
        locale: const Locale('ru'),
      );

      expect(_quoteText('«Есть машина»'), findsOneWidget);
    });

    testWidgets(
      'keeps the original quote when the helper’s live offer text has '
      'changed since admission',
      (tester) async {
        await _pump(
          tester,
          _joinedLine(offerNote: 'I have a van'),
          [_omar(offerNote: 'Actually a bike')],
        );

        expect(_quoteText('“I have a van”'), findsOneWidget);
        expect(find.textContaining('bike'), findsNothing);
      },
    );

    testWidgets(
      'shows no quote on a line stored without a snapshot, whatever the '
      'participant list says',
      (tester) async {
        await _pump(tester, _joinedLine(), [_omar(offerNote: 'Live note')]);

        expect(find.text(_line), findsOneWidget);
        expect(find.textContaining('Live note'), findsNothing);
        expect(find.textContaining('“'), findsNothing);
      },
    );

    testWidgets('shows no quote when the snapshot is blank', (tester) async {
      await _pump(tester, _joinedLine(offerNote: '   '), [_omar()]);

      expect(find.text(_line), findsOneWidget);
      expect(find.textContaining('“'), findsNothing);
      expect(find.textContaining('”'), findsNothing);
    });

    testWidgets(
      'folds a long quote to two lines and a tap on it shows all of it',
      (tester) async {
        // One line of the same style is the unit the fold is measured in.
        await _pump(tester, _joinedLine(offerNote: 'van'), [_omar()]);
        final oneLine = tester.getSize(_quoteText('“van”')).height;
        expect(oneLine, greaterThan(0));

        final longNote = List.filled(80, 'word').join(' ');
        final longQuote = _quoteText('“$longNote”');
        await _pump(tester, _joinedLine(offerNote: longNote), [_omar()]);

        expect(longQuote, findsOneWidget);
        final folded = tester.getSize(longQuote).height;
        expect(
          folded,
          lessThanOrEqualTo(oneLine * 2 + 1),
          reason: 'folded to at most two lines',
        );
        expect(
          folded,
          greaterThan(oneLine * 1.5),
          reason: 'a long quote uses both of its two lines',
        );

        await tester.tap(longQuote);
        await tester.pumpAndSettle();

        expect(
          tester.getSize(longQuote).height,
          greaterThan(oneLine * 2 + 1),
          reason: 'a tap shows more than the two folded lines',
        );

        await tester.tap(longQuote);
        await tester.pumpAndSettle();

        expect(
          tester.getSize(longQuote).height,
          lessThanOrEqualTo(oneLine * 2 + 1),
          reason: 'another tap folds it again',
        );
      },
    );
  });
}
