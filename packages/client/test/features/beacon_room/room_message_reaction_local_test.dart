import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_message_reaction_local.dart';

void main() {
  const thumb = BeaconRoomMessageReaction.defaultEmoji;

  RoomMessage baseMessage() => RoomMessage(
        id: 'm1',
        beaconId: 'b1',
        authorId: 'u1',
        body: 'hi',
        createdAt: DateTime.utc(2026),
      );

  test('add reaction: increments count and sets myReaction', () {
    final m = baseMessage();
    final next = toggleRoomMessageReactionLocally(m, thumb);
    expect(next.reactionCounts[thumb], 1);
    expect(next.myReaction, thumb);
  });

  test('remove reaction: decrements count and clears myReaction', () {
    final m = baseMessage().copyWith(
      reactionCounts: {thumb: 2},
      myReaction: thumb,
    );
    final next = toggleRoomMessageReactionLocally(m, thumb);
    expect(next.reactionCounts[thumb], 1);
    expect(next.myReaction, null);
  });

  test('remove last reaction: drops emoji key from counts', () {
    final m = baseMessage().copyWith(
      reactionCounts: {thumb: 1},
      myReaction: thumb,
    );
    final next = toggleRoomMessageReactionLocally(m, thumb);
    expect(next.reactionCounts.containsKey(thumb), false);
    expect(next.myReaction, null);
  });

  test('second emoji: myReaction comma-sorted', () {
    const other = '❤️';
    final m = baseMessage().copyWith(
      reactionCounts: {thumb: 1},
      myReaction: thumb,
    );
    final next = toggleRoomMessageReactionLocally(m, other);
    expect(next.myReaction, '$other,$thumb');
    expect(next.reactionCounts[thumb], 1);
    expect(next.reactionCounts[other], 1);
  });
}
