import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_message_reaction_local.dart';

void main() {
  final thumb = BeaconRoomMessageReaction.quickPickerEmojis.first;

  const me = Profile(id: 'me', title: 'Me');

  RoomMessage baseMessage() => RoomMessage(
    id: 'm1',
    beaconId: 'b1',
    authorId: 'u1',
    body: 'hi',
    createdAt: DateTime.utc(2026),
  );

  test('add reaction: increments count and sets myReaction', () {
    final m = baseMessage();
    final next = toggleRoomMessageReactionLocally(m, thumb, me);
    expect(next.reactionCounts[thumb], 1);
    expect(next.myReaction, thumb);
    expect(next.reactors[thumb]?.map((p) => p.id).toList(), ['me']);
  });

  test('remove reaction: decrements count and clears myReaction', () {
    final m = baseMessage().copyWith(
      reactionCounts: {thumb: 2},
      myReaction: thumb,
      reactors: {
        thumb: [me, const Profile(id: 'other', title: 'Other')],
      },
    );
    final next = toggleRoomMessageReactionLocally(m, thumb, me);
    expect(next.reactionCounts[thumb], 1);
    expect(next.myReaction, null);
    expect(next.reactors[thumb]?.length, 1);
    expect(next.reactors[thumb]?.single.id, 'other');
  });

  test('remove last reaction: drops emoji key from counts', () {
    final m = baseMessage().copyWith(
      reactionCounts: {thumb: 1},
      myReaction: thumb,
      reactors: {thumb: [me]},
    );
    final next = toggleRoomMessageReactionLocally(m, thumb, me);
    expect(next.reactionCounts.containsKey(thumb), false);
    expect(next.myReaction, null);
    expect(next.reactors.containsKey(thumb), false);
  });

  test('second emoji: myReaction comma-sorted', () {
    final other = BeaconRoomMessageReaction.quickPickerEmojis[3];
    final m = baseMessage().copyWith(
      reactionCounts: {thumb: 1},
      myReaction: thumb,
      reactors: {thumb: [const Profile(id: 'x', title: 'X')]},
    );
    final next = toggleRoomMessageReactionLocally(m, other, me);
    final expected = <String>[thumb, other]..sort();
    expect(next.myReaction, expected.join(','));
    expect(next.reactionCounts[thumb], 1);
    expect(next.reactionCounts[other], 1);
    expect(next.reactors[thumb]?.single.id, 'x');
    expect(next.reactors[other]?.map((p) => p.id).toList(), ['me']);
  });
}
