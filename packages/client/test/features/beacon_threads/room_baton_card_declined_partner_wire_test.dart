// A candidate whose invited partner declined: the server-shaped payload
// (`batonDataJson`) is parsed by the real entity parser and shown by the real
// card, which asks the viewer again by naming the partner who can't join.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _serverPayload =
    '{"id":"Lbaton000001","status":"collecting","viewerRole":"candidate",'
    '"myResponse":"waiting",'
    '"myPartner":{"id":"u-boris","title":"Boris Mate","status":"declined"}}';

BeaconParticipant _participant(String userId, String title) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: 'b-baton',
      userId: userId,
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      userTitle: title,
    );

Widget _card(RoomBatonCandidateData baton, Locale locale) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900)),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: SingleChildScrollView(
          child: RoomBatonCard(
            baton: baton,
            participants: [
              _participant('u-anna', 'Anna Author'),
              _participant('u-viewer', 'Viewer Self'),
              _participant('u-boris', 'Boris Mate'),
            ],
            viewerUserId: 'u-viewer',
            batonAuthorUserId: 'u-anna',
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('declined partner on a candidate baton, from the wire', () {
    test(
      'the payload parses to a waiting candidate with a declined partner',
      () {
        final data = RoomBatonData.tryParse(_serverPayload);

        expect(data, isA<RoomBatonCandidateData>());
        final candidate = data! as RoomBatonCandidateData;
        expect(candidate.myResponse, RoomBatonResponse.waiting);
        expect(candidate.myPartner, isNotNull);
        expect(candidate.myPartner!.id, 'u-boris');
        expect(candidate.myPartner!.title, 'Boris Mate');
        expect(candidate.myPartner!.status, 'declined');
      },
    );

    testWidgets("the card says who can't join, in English", (tester) async {
      final data =
          RoomBatonData.tryParse(_serverPayload)! as RoomBatonCandidateData;
      await tester.pumpWidget(_card(data, const Locale('en')));
      await tester.pumpAndSettle();

      expect(
        find.text("Boris Mate can't join. Can you help?"),
        findsOneWidget,
      );
    });

    testWidgets('the card says who can not join, in Russian', (tester) async {
      final data =
          RoomBatonData.tryParse(_serverPayload)! as RoomBatonCandidateData;
      await tester.pumpWidget(_card(data, const Locale('ru')));
      await tester.pumpAndSettle();

      expect(
        find.text('Boris Mate не сможет присоединиться. Сможете помочь?'),
        findsOneWidget,
      );
    });
  });
}
