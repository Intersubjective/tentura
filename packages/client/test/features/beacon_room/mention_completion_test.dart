import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_room/ui/widget/mention_text_controller.dart';
import 'package:tentura/features/beacon_room/ui/widget/participants_matching_mention_query.dart';

BeaconParticipant _p({
  required String handle,
  String title = '',
  int roomAccess = RoomAccessBits.admitted,
}) => BeaconParticipant(
  id: 'p-$handle',
  beaconId: 'b1',
  userId: 'u-$handle',
  role: 0,
  status: 0,
  roomAccess: roomAccess,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  handle: handle,
  userTitle: title.isEmpty ? 'User $handle' : title,
);

void main() {
  group('participantsMatchingMentionQuery', () {
    final people = [
      _p(handle: 'alice', title: 'Alice Wonder'),
      _p(handle: 'bob', title: 'Robert'),
      _p(handle: 'carol', title: 'Carol', roomAccess: RoomAccessBits.requested),
      _p(handle: '', title: 'NoHandle'),
    ];

    test('empty query returns admitted with handles', () {
      final out = participantsMatchingMentionQuery(
        participants: people,
        query: '',
      );
      expect(out.map((p) => p.handle), ['alice', 'bob']);
    });

    test('matches handle or display title', () {
      expect(
        participantsMatchingMentionQuery(
          participants: people,
          query: 'ali',
        ).map((p) => p.handle),
        ['alice'],
      );
      expect(
        participantsMatchingMentionQuery(
          participants: people,
          query: 'robert',
        ).map((p) => p.handle),
        ['bob'],
      );
    });
  });

  group('MentionTextController', () {
    test('detects @query after whitespace', () {
      final c = MentionTextController(text: 'hi @al');
      c.selection = const TextSelection.collapsed(offset: 6);
      expect(c.activeMentionQuery, 'al');
    });

    test('emoji before @ without space is not a mention', () {
      final c = MentionTextController(text: '👋@alice');
      c.selection = TextSelection.collapsed(offset: c.text.length);
      expect(c.activeMentionQuery, isNull);
    });

    test('emoji then space then @ is a mention', () {
      final c = MentionTextController(text: '👋 @al');
      c.selection = TextSelection.collapsed(offset: c.text.length);
      expect(c.activeMentionQuery, 'al');
    });

    test('insertMention replaces active token', () {
      final c = MentionTextController(text: 'hi @al');
      c.selection = const TextSelection.collapsed(offset: 6);
      expect(c.insertMention('alice'), isTrue);
      expect(c.text, 'hi @alice ');
    });
  });
}
