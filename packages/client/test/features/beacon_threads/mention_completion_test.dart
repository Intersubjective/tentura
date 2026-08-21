import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';
import 'package:tentura/features/beacon_threads/ui/widget/mention_text_controller.dart';
import 'package:tentura/features/beacon_threads/ui/widget/participants_matching_mention_query.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';

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

    test(
      'empty query returns admitted participants with a mentionable identity',
      () {
        final out = participantsMatchingMentionQuery(
          participants: people,
          query: '',
        );
        expect(out.map((p) => p.handle), ['alice', 'bob', '']);
      },
    );

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

    test('tracks and shifts an id-anchored mention through edits', () {
      final c = MentionTextController(text: '@bo');
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(
        c.insertLiteralMentionText('@Bob Smith', userId: 'bob'),
        isTrue,
      );
      c.value = c.value.copyWith(
        text: 'Hi ${c.text}',
        selection: TextSelection.collapsed(offset: c.text.length + 3),
      );
      expect(c.committedMentions, [
        (userId: 'bob', start: 3, end: 13),
      ]);
      c.value = c.value.copyWith(
        text: 'Hi @Bob Jones ',
        selection: const TextSelection.collapsed(offset: 14),
      );
      expect(c.committedMentions, isEmpty);
    });

    test(
      'keeps the surviving duplicate-name identity when deleting the first',
      () {
        final c = MentionTextController(text: '@a');
        c.selection = const TextSelection.collapsed(offset: 2);
        expect(c.insertLiteralMentionText('@Sam', userId: 'a'), isTrue);
        c.value = c.value.copyWith(
          text: '@Sam @b',
          selection: const TextSelection.collapsed(offset: 7),
        );
        expect(c.insertLiteralMentionText('@Sam', userId: 'b'), isTrue);
        expect(c.committedMentions, [
          (userId: 'a', start: 0, end: 4),
          (userId: 'b', start: 5, end: 9),
        ]);

        c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
        c.value = c.value.copyWith(
          text: '@Sam ',
          selection: const TextSelection.collapsed(offset: 0),
        );
        expect(c.committedMentions, [(userId: 'b', start: 0, end: 4)]);

        // A TextEditingController has no undo-operation identity. Recreating
        // text must never resurrect a deleted recipient merely because text
        // and selection happen to match a past editing state.
        c.value = c.value.copyWith(
          text: '@Sam @Sam ',
          selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        );
        expect(c.committedMentions, [(userId: 'b', start: 5, end: 9)]);
      },
    );
  });

  test('mention-span parsing and rendering boundary drop malformed ranges', () {
    expect(
      parseRoomMessageMentionSpansJson(
        '[{"userId":"u1","offset":0,"length":4},'
        '{"userId":"fractional","offset":0.9,"length":4.1},'
        '{"userId":4}]',
      ),
      [const RoomMessageMentionSpan(userId: 'u1', offset: 0, length: 4)],
    );
    expect(
      usableRoomMessageMentionSpans(
        body: '@Bob',
        spans: const [
          RoomMessageMentionSpan(userId: 'bad', offset: -1, length: 2),
          RoomMessageMentionSpan(userId: 'u1', offset: 0, length: 4),
          RoomMessageMentionSpan(userId: 'overlap', offset: 2, length: 2),
        ],
      ),
      [const RoomMessageMentionSpan(userId: 'u1', offset: 0, length: 4)],
    );
  });
}
