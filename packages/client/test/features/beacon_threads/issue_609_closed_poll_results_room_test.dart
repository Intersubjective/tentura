import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/room_body_harness.dart';

// Issue #609 (from #482), wiring: a final (read-only) Request tells every
// poll card in its room that the poll is closed, so viewers who never voted
// see the results; an open or wrapping-up Request does not.

void main() {
  const author = Profile(id: 'other', displayName: 'Alex');

  final pollJson = jsonEncode({
    'id': 'poll-609',
    'question': 'Which day works?',
    'pollType': 'single',
    'isAnonymous': false,
    'allowRevote': true,
    'myVariantIds': <String>[],
    'totalVotes': 3,
    'variants': [
      {'id': 'variant-sun', 'description': 'Sunday', 'votesCount': 2},
      {'id': 'variant-sat', 'description': 'Saturday', 'votesCount': 1},
    ],
  });

  RoomMessage pollMessage() => RoomMessage(
    id: 'm-poll',
    beaconId: 'b1',
    authorId: author.id,
    author: author,
    body: 'Which day works?',
    createdAt: DateTime.utc(2026, 6, 30, 12),
    linkedPollingId: 'poll-609',
    pollDataJson: pollJson,
  );

  testWidgets('closed request shows poll results to a viewer who never '
      'voted', (tester) async {
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [pollMessage()],
        beaconStatus: BeaconStatus.closed,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<BasicChatBody>(find.byType(BasicChatBody)).pollsClosed,
      isTrue,
    );
    expect(
      tester.widget<RoomPollCard>(find.byType(RoomPollCard)).isClosed,
      isTrue,
    );
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('Poll closed · 3 votes'), findsOneWidget);
  });

  testWidgets('wrapping-up request keeps the poll open', (tester) async {
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [pollMessage()],
        beaconStatus: BeaconStatus.reviewOpen,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<RoomPollCard>(find.byType(RoomPollCard)).isClosed,
      isFalse,
    );
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('unknown request status does not mark the poll closed', (
    tester,
  ) async {
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(messages: [pollMessage()], beaconStatus: null),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<RoomPollCard>(find.byType(RoomPollCard)).isClosed,
      isFalse,
    );
  });
}
