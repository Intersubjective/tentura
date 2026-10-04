import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/ui/widget/mention_text_controller.dart';
import 'package:tentura/features/emoji/domain/emoji_catalog.dart';
import 'package:tentura/features/emoji/domain/emoji_shortcode_token.dart';

/// Simulates typing [ch] at the caret, as the text field would.
void _type(MentionTextController c, String ch) {
  final caret = c.selection.baseOffset;
  c.value = TextEditingValue(
    text: c.text.replaceRange(caret, caret, ch),
    selection: TextSelection.collapsed(offset: caret + ch.length),
  );
}

MentionTextController _typed(String text) {
  final c = MentionTextController(
    emojiForShortcode: EmojiCatalog.emojiForShortcode,
  )..selection = const TextSelection.collapsed(offset: 0);
  for (final ch in text.split('')) {
    _type(c, ch);
  }
  return c;
}

void main() {
  group('activeEmojiShortcodeToken', () {
    String? query(String text) =>
        activeEmojiShortcodeToken(text, text.length)?.query;

    test('opens after start, whitespace, punctuation or an emoji', () {
      expect(query(':sm'), 'sm');
      expect(query('hi :sm'), 'sm');
      expect(query('(:sm'), 'sm');
      expect(query('😄:joy'), 'joy');
      expect(query('ok :+1'), '+1');
      expect(query(':улыб'), 'улыб');
    });

    test('needs two characters after the colon', () {
      expect(query(':'), isNull);
      expect(query(':s'), isNull);
    });

    test('ignores times, URLs and colons glued to words', () {
      expect(query('10:30'), isNull);
      expect(query('https://example'), isNull);
      expect(query('note:sm'), isNull);
      expect(query('Итог:ок'), isNull);
      expect(query('::sm'), isNull);
      expect(query(':sm ile'), isNull);
    });
  });

  group('EmojiCatalog', () {
    test('resolves exact shortcodes from GitHub and Slack sets', () {
      expect(EmojiCatalog.emojiForShortcode('smile'), '😄');
      expect(EmojiCatalog.emojiForShortcode('+1'), '👍');
      expect(EmojiCatalog.emojiForShortcode('thumbsup'), '👍');
      expect(EmojiCatalog.emojiForShortcode('no_such_emoji'), isNull);
    });

    test('ranks exact, then prefix, then word prefix', () {
      final hits = EmojiCatalog.search('joy', limit: 20);
      expect(hits.first.entry.emoji, '😂');
      expect(hits.first.shortcode, 'joy');
      expect(hits.map((h) => h.shortcode), contains('joy_cat'));
      final heart = EmojiCatalog.search('heart', limit: 5).first;
      expect(heart.shortcode, 'heart');
      expect(EmojiCatalog.search('smi', limit: 5).first.shortcode, 'smile');
    });

    test('finds emoji by Russian keywords, folding ё', () {
      final emoji = EmojiCatalog.search(
        'улыб',
        limit: 50,
      ).map((m) => m.entry.emoji);
      expect(emoji, contains('😄'));
      final tree = EmojiCatalog.search(
        'ЁЛКА',
        limit: 5,
      ).map((m) => m.entry.emoji);
      expect(tree, contains('🎄'));
      expect(
        tree,
        EmojiCatalog.search('елка', limit: 5).map((m) => m.entry.emoji),
      );
    });

    test('respects the limit and ignores blank queries', () {
      expect(EmojiCatalog.search('s', limit: 3), hasLength(3));
      expect(EmojiCatalog.search('  ', limit: 5), isEmpty);
    });
  });

  group('MentionTextController emoji shortcodes', () {
    test('exposes the active :query token', () {
      final c = _typed('hi :smi');
      expect(c.activeEmojiToken, (query: 'smi', start: 3, end: 7));
      expect(c.activeMentionQuery, isNull);
    });

    test('insertEmoji replaces the token and moves the caret', () {
      final c = _typed('hi :smi there')
        ..selection = const TextSelection.collapsed(offset: 7);
      expect(c.insertEmoji('😄'), isTrue);
      expect(c.text, 'hi 😄 there');
      expect(c.selection.baseOffset, 3 + '😄'.length);
      expect(c.activeEmojiToken, isNull);
    });

    test('typing the closing colon of a known shortcode replaces it', () {
      final c = _typed('nice :+1: and :smile: ok');
      expect(c.text, 'nice 👍 and 😄 ok');
    });

    test('unknown shortcodes and times stay literal', () {
      expect(_typed(':nope: at 10:30:').text, ':nope: at 10:30:');
    });

    test('pasted shortcodes are not replaced', () {
      final c =
          MentionTextController(
              emojiForShortcode: EmojiCatalog.emojiForShortcode,
            )
            ..value = const TextEditingValue(
              text: ':smile:',
              selection: TextSelection.collapsed(offset: 7),
            );
      expect(c.text, ':smile:');
    });

    test('no lookup means no replacement', () {
      final c = MentionTextController()
        ..selection = const TextSelection.collapsed(offset: 0);
      for (final ch in ':smile:'.split('')) {
        _type(c, ch);
      }
      expect(c.text, ':smile:');
    });

    test('replacement keeps committed mentions anchored', () {
      final c = _typed('@bo');
      expect(c.insertLiteralMentionText('@Bob', userId: 'bob'), isTrue);
      for (final ch in ':wave:'.split('')) {
        _type(c, ch);
      }
      expect(c.text, '@Bob 👋');
      expect(c.committedMentions, [(userId: 'bob', start: 0, end: 4)]);
    });
  });
}
