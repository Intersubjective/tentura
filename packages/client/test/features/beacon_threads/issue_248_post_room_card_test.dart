import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';

import '../../support/phone_surface.dart';
import 'support/room_body_harness.dart';

void main() {
  const postId = 'B248post001';
  const rootId = 'M248root001';
  const rootText = 'Кто в субботу на велопрогулку?';
  const author = Profile(id: 'Uauthor', displayName: 'Олег');
  const reader = Profile(id: 'Ureader', displayName: 'Мария');

  final createdAt = DateTime.utc(2026, 10, 2, 12);
  final expiresAt = createdAt.add(const Duration(days: 3));

  DateTime postNow() => createdAt.add(const Duration(hours: 2));

  RoomMessage rootMessage() => RoomMessage(
    id: rootId,
    beaconId: postId,
    authorId: author.id,
    author: author,
    body: rootText,
    createdAt: createdAt,
  );

  RoomState postRoomState({List<RoomMessage>? messages}) => RoomState(
    beaconId: postId,
    myUserId: reader.id,
    messages: messages ?? [rootMessage()],
    participantsLoaded: true,
    beaconAuthorId: author.id,
    beaconStatus: BeaconStatus.open,
    firstLoadDone: true,
  );

  group('#248 Post room card', () {
    testWidgets('375×667 RU: Replies header and Reply composer hint', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpBeaconRoomBody(
        tester,
        roomState: postRoomState(
          messages: [
            rootMessage(),
            RoomMessage(
              id: 'Mreply1',
              beaconId: postId,
              authorId: reader.id,
              author: reader,
              body: 'Я могу!',
              createdAt: createdAt.add(const Duration(minutes: 1)),
            ),
          ],
        ),
        capabilities: const RoomCapabilities.post(),
        postRoot: RoomPostRootPin(
          messageId: rootId,
          excerpt: rootText,
          startedBy: author.displayName,
        ),
        postExpiresAt: expiresAt,
        postNow: postNow,
        beaconAuthorId: author.id,
        beaconAuthor: author,
        locale: const Locale('ru'),
      );
      await pumpUntilViewportDone(tester);
      await tester.pump();

      expect(find.text('Ответы'), findsOneWidget);
      expect(find.text('Ответить…'), findsOneWidget);
      expect(find.textContaining(rootText, findRichText: true), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.textContaining(rootText, findRichText: true),
        ),
        findsNothing,
      );
    });

    testWidgets('expanded card shows lifetime hourglass', (tester) async {
      await pumpBeaconRoomBody(
        tester,
        roomState: postRoomState(),
        capabilities: const RoomCapabilities.post(),
        postRoot: const RoomPostRootPin(messageId: rootId, excerpt: rootText),
        postExpiresAt: expiresAt,
        postNow: postNow,
        beaconAuthorId: author.id,
        beaconAuthor: author,
      );
      await pumpUntilViewportDone(tester);

      expect(find.byKey(const Key('PostRootPinCard.expanded')), findsOneWidget);
      expect(find.textContaining('⏳', findRichText: true), findsWidgets);
    });
  });
}
