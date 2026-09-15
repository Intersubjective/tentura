import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/room_body_harness.dart';

void main() {
  final baseTime = DateTime.utc(2026, 6, 30, 12);
  const author = Profile(id: 'other', displayName: 'Alex');

  RoomMessage message() => RoomMessage(
    id: 'm1',
    beaconId: 'b1',
    authorId: author.id,
    author: author,
    body: 'Hello room',
    createdAt: baseTime,
  );

  Future<void> longPressBody(WidgetTester tester) =>
      tester.longPressAt(
        tester.getTopLeft(find.byType(RoomMessageTextBody)) +
            const Offset(8, 8),
      );

  testWidgets('closed request disables composer and nulls write callbacks', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [message()],
        beaconStatus: BeaconStatus.closed,
      ),
    );
    await tester.pumpAndSettle();

    final chat = tester.widget<BasicChatBody>(find.byType(BasicChatBody));
    expect(chat.onSend, isNotNull);
    expect(chat.onToggleReaction, isNull);
    expect(chat.onVotePoll, isNull);
    expect(chat.onReply, isNull);
    expect(chat.composerReadOnlyHint, l10n.beaconRoomMessageReadOnlyHint);

    final field = tester.widget<TextField>(
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(field.enabled, isFalse);
    expect(find.text(l10n.beaconRoomMessageReadOnlyHint), findsOneWidget);
  });

  testWidgets('cancelled request also locks the composer', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [message()],
        beaconStatus: BeaconStatus.cancelled,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(TestIds.key(TestIds.roomMessageInput)))
          .enabled,
      isFalse,
    );
    expect(find.text(l10n.beaconRoomMessageReadOnlyHint), findsOneWidget);
  });

  testWidgets('reviewOpen keeps composer writable', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [message()],
        beaconStatus: BeaconStatus.reviewOpen,
      ),
    );
    await tester.pumpAndSettle();

    final chat = tester.widget<BasicChatBody>(find.byType(BasicChatBody));
    expect(chat.onToggleReaction, isNotNull);
    expect(chat.onVotePoll, isNotNull);
    expect(chat.onReply, isNotNull);
    expect(chat.composerReadOnlyHint, isNull);

    final field = tester.widget<TextField>(
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(field.enabled, isTrue);
    expect(find.text(l10n.beaconRoomMessageHint), findsOneWidget);
  });

  testWidgets('closed request message sheet hides write actions', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(
        messages: [message()],
        beaconStatus: BeaconStatus.closed,
      ),
    );
    await tester.pumpAndSettle();

    await longPressBody(tester);
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconRoomActionReply), findsNothing);
    expect(find.text(l10n.beaconRoomActionEditMessage), findsNothing);
    expect(find.text(l10n.beaconRoomActionDeleteMessage), findsNothing);
    expect(find.text(l10n.beaconRoomActionCopyText), findsOneWidget);
  });
}
