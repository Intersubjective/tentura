import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';

final _baseTime = DateTime.utc(2026, 6, 30, 12);

RoomMessage _replyMessage({
  String id = 'reply-1',
  String? threadItemId,
  String body = 'Short reply',
}) {
  return RoomMessage(
    id: id,
    beaconId: 'b1',
    threadItemId: threadItemId,
    authorId: 'other',
    author: const Profile(id: 'other', displayName: 'Alex'),
    body: body,
    createdAt: _baseTime,
    replyToMessageId: 'parent-1',
    replyToAuthorId: 'anna',
    replyToAuthorTitle: 'Anna',
    replyToBodyExcerpt: 'Parent excerpt for harness',
  );
}

void main() {
  testWidgets('main room harness shows reply quote in message list', (
    tester,
  ) async {
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [_replyMessage()],
      ),
      enableComposer: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Parent excerpt for harness'), findsOneWidget);
    expect(find.byType(RoomMessageReplyQuote), findsOneWidget);
  });

  testWidgets('item thread harness shows reply quote in message list', (
    tester,
  ) async {
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        threadItemId: 'item-thread-1',
        messages: [
          _replyMessage(
            id: 'thread-reply',
            threadItemId: 'item-thread-1',
          ),
        ],
      ),
      enableComposer: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsOneWidget);
    expect(find.byType(RoomMessageReplyQuote), findsOneWidget);
  });

  testWidgets('main room harness shows composer reply banner', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    final target = RoomMessage(
      id: 'target-1',
      beaconId: 'b1',
      authorId: 'anna',
      author: const Profile(id: 'anna', displayName: 'Anna'),
      body: 'Bring the ladder tomorrow',
      createdAt: _baseTime,
    );

    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(replyTarget: target),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.beaconRoomReplyingTo('Anna')),
      findsOneWidget,
    );
    expect(find.text('Bring the ladder tomorrow'), findsOneWidget);
  });

  testWidgets('item thread harness shows composer reply banner', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final target = RoomMessage(
      id: 'target-thread',
      beaconId: 'b1',
      threadItemId: 'item-thread-1',
      authorId: 'anna',
      author: const Profile(id: 'anna', displayName: 'Anna'),
      body: 'Thread target excerpt',
      createdAt: _baseTime,
    );

    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        threadItemId: 'item-thread-1',
        replyTarget: target,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.beaconRoomReplyingTo('Anna')),
      findsOneWidget,
    );
    expect(find.text('Thread target excerpt'), findsOneWidget);
  });
}
