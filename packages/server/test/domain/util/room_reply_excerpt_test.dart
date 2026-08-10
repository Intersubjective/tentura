import 'package:test/test.dart';

import 'package:tentura_server/domain/util/room_reply_excerpt.dart';

void main() {
  group('roomReplyExcerpt', () {
    test('returns null for null, empty, and whitespace-only input', () {
      expect(roomReplyExcerpt(null), isNull);
      expect(roomReplyExcerpt(''), isNull);
      expect(roomReplyExcerpt('   '), isNull);
      expect(roomReplyExcerpt('\n\t'), isNull);
    });

    test('collapses whitespace runs to single spaces', () {
      expect(
        roomReplyExcerpt('hello\n\tworld'),
        'hello world',
      );
      expect(
        roomReplyExcerpt('  spaced   out  '),
        'spaced out',
      );
    });

    test('returns body unchanged at exactly 160 runes', () {
      final body = 'a' * kRoomReplyExcerptMaxChars;
      expect(roomReplyExcerpt(body), body);
      expect(roomReplyExcerpt(body)!.length, kRoomReplyExcerptMaxChars);
    });

    test('truncates at 161 runes with ellipsis', () {
      final body = 'a' * (kRoomReplyExcerptMaxChars + 1);
      final excerpt = roomReplyExcerpt(body);
      expect(excerpt, '${'a' * kRoomReplyExcerptMaxChars}…');
      expect(excerpt!.length, kRoomReplyExcerptMaxChars + 1);
    });

    test('does not split a surrogate pair at the boundary', () {
      final flag = '\u{1F1FA}\u{1F1F8}';
      final prefix = 'a' * (kRoomReplyExcerptMaxChars - 1);
      final body = '$prefix$flag';
      final excerpt = roomReplyExcerpt(body);
      expect(excerpt, endsWith('…'));
      expect(excerpt!.runes.length, kRoomReplyExcerptMaxChars + 1);
      expect(excerpt.contains('\uFFFD'), isFalse);
    });
  });
}
