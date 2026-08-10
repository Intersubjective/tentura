import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';

final _baseTime = DateTime.utc(2026, 6, 30, 12);

List<RoomMessage> _recentMessagesForJump() {
  return List<RoomMessage>.generate(
    24,
    (i) => RoomMessage(
      id: 'recent-$i',
      beaconId: 'b1',
      authorId: 'peer',
      author: const Profile(id: 'peer', displayName: 'Peer'),
      body: 'Recent message $i with enough text to grow the list height',
      createdAt: _baseTime.add(Duration(minutes: i)),
    ),
  );
}

RoomMessage _historicalJumpTarget({
  String? threadItemId,
}) {
  return RoomMessage(
    id: 'historical-parent',
    beaconId: 'b1',
    threadItemId: threadItemId,
    authorId: 'old-peer',
    author: const Profile(id: 'old-peer', displayName: 'Old'),
    body: 'Historical parent message body for harness jump',
    createdAt: _baseTime.subtract(const Duration(hours: 2)),
  );
}

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

  testWidgets('main room harness scroll listener jumps to pinned historical target',
      (tester) async {
    final recent = _recentMessagesForJump();
    final historical = _historicalJumpTarget();

    final cubit = await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(messages: recent),
      enableComposer: false,
    );
    await pumpUntilViewportDone(tester);

    final scrollable = listScrollableState(tester);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    final bottomPixels = scrollable.position.pixels;

    cubit.emitHarnessState(
      roomBodyState(
        messages: [historical, ...recent],
        scrollToMessageId: historical.id,
        pinnedJumpMessageIds: [historical.id],
      ),
    );
    await tester.pump();

    await pumpUntilScrollTargetCleared(tester, cubit);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(cubit.clearScrollTargetInvocations, greaterThan(0));
    expect(cubit.state.scrollToMessageId, isNull);

    final finalPosition = listScrollableState(tester).position;
    expect(
      finalPosition.pixels,
      lessThan(finalPosition.maxScrollExtent - 40),
    );
    expect(
      finalPosition.pixels,
      lessThan(bottomPixels - 40),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('item thread harness scroll listener jumps to pinned historical target',
      (tester) async {
    const threadItemId = 'item-thread-1';
    final recent = _recentMessagesForJump()
        .map(
          (m) => m.copyWith(threadItemId: threadItemId),
        )
        .toList();
    final historical = _historicalJumpTarget(threadItemId: threadItemId);

    final cubit = await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        threadItemId: threadItemId,
        messages: recent,
      ),
      enableComposer: false,
    );
    await pumpUntilViewportDone(tester);

    final scrollable = listScrollableState(tester);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    final bottomPixels = scrollable.position.pixels;

    cubit.emitHarnessState(
      roomBodyState(
        threadItemId: threadItemId,
        messages: [historical, ...recent],
        scrollToMessageId: historical.id,
        pinnedJumpMessageIds: [historical.id],
      ),
    );
    await tester.pump();

    await pumpUntilScrollTargetCleared(tester, cubit);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(cubit.clearScrollTargetInvocations, greaterThan(0));
    expect(cubit.state.scrollToMessageId, isNull);

    final finalPosition = listScrollableState(tester).position;
    expect(
      finalPosition.pixels,
      lessThan(finalPosition.maxScrollExtent - 40),
    );
    expect(
      finalPosition.pixels,
      lessThan(bottomPixels - 40),
    );
    expect(tester.takeException(), isNull);
  });
}
