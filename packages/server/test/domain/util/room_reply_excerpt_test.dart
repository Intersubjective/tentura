import 'package:test/test.dart';

import 'package:tentura_server/domain/room/room_reply_excerpt.dart';

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
      const flag = '\u{1F1FA}\u{1F1F8}';
      final prefix = 'a' * (kRoomReplyExcerptMaxChars - 1);
      final body = '$prefix$flag';
      final excerpt = roomReplyExcerpt(body);
      expect(excerpt, endsWith('…'));
      expect(excerpt!.runes.length, kRoomReplyExcerptMaxChars + 1);
      expect(excerpt.contains('\uFFFD'), isFalse);
    });

    // #377: a poll has no body; the quote names its question instead.
    test('a poll with no body is quoted by its question', () {
      expect(
        roomReplyExcerpt('', pollQuestion: '  Which day\n works? '),
        '📊 Which day works?',
      );
      expect(roomReplyExcerpt('', pollQuestion: '  '), isNull);
      expect(roomReplyExcerpt('text', pollQuestion: 'Q'), 'text');
      expect(roomReplyExcerpt('📊'), '📊');
    });
  });
  group('shared rune excerpt policy', () {
    test('preserves boundary excerpts, whitespace and poll fallbacks', () {
      void expectExcerpt(String? body, String? expected, {String? question}) {
        expect(
          roomReplyExcerpt(body, pollQuestion: question),
          expected,
          reason: 'body: $body; question: $question',
        );
      }

      for (final rune in const ['a', 'я', '😀']) {
        for (final length in const [159, 160, 161]) {
          final body = rune * length;
          expectExcerpt(body, length <= 160 ? body : '${rune * 160}…');
        }
      }
      const mixedPrefix =
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀';
      expectExcerpt(mixedPrefix, mixedPrefix);
      expectExcerpt('$mixedPrefixЖ', '$mixedPrefixЖ');
      expectExcerpt('$mixedPrefixЖz', '$mixedPrefixЖ…');
      expectExcerpt('$mixedPrefix😀z', '$mixedPrefix😀…');
      expectExcerpt('${'a' * 159}🇺🇸', '${'a' * 159}🇺…');
      expectExcerpt('${'я' * 159}😀x', '${'я' * 159}😀…');
      expectExcerpt('${'a' * 158}e\u0301x', '${'a' * 158}e\u0301…');
      expectExcerpt(
        ' \t\r\n\u000b\u000c hello\t\r\nмир  😀 \n',
        'hello мир 😀',
      );
      expectExcerpt(' \t\r\n\u000b\u000c', null);
      expectExcerpt('', null);
      expectExcerpt(null, null);
      expectExcerpt(' \t', '📊 Как дела?', question: ' Как\nдела? ');
      expectExcerpt('', '📊 ${'я' * 158}…', question: 'я' * 159);
      expectExcerpt('body', 'body', question: 'ignored');
    });

    test('omits a combining sequence crossing the rune limit', () {
      const prefix =
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀'
          'aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀aя😀';
      expect(roomReplyExcerpt('${prefix}e\u0301tail'), '$prefix…');
    });
  });
}
