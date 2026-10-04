import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/emoji/emoji_catalog.dart';
import 'package:tentura/ui/emoji/emoji_recents.dart';

void main() {
  group('EmojiCatalog', () {
    test('every shortcode maps to exactly one emoji', () {
      final seen = <String>{};
      for (final e in EmojiCatalog.all) {
        for (final alias in e.aliases) {
          expect(seen.add(alias), isTrue, reason: 'duplicate :$alias:');
          expect(alias, matches(RegExp(r'^[a-z0-9_+\-]+$')));
        }
      }
    });

    test('every category has emoji, in picker order', () {
      for (final category in EmojiCategory.values) {
        expect(EmojiCatalog.byCategory[category], isNotEmpty);
      }
      expect(EmojiCatalog.all.first.category, EmojiCategory.smileys);
    });

    test('byShortcode is exact and accepts surrounding colons', () {
      expect(EmojiCatalog.byShortcode('smile')?.emoji, '😄');
      expect(EmojiCatalog.byShortcode(':tada:')?.emoji, '🎉');
      expect(EmojiCatalog.byShortcode('+1')?.emoji, '👍');
      expect(EmojiCatalog.byShortcode('THUMBSUP')?.emoji, '👍');
      expect(EmojiCatalog.byShortcode('smil'), isNull);
    });

    test('search puts the exact shortcode first, then prefixes', () {
      final results = EmojiCatalog.search('smile');
      expect(results.first.shortcode, 'smile');
      final names = results.map((e) => e.shortcode).toList();
      expect(names.indexOf('smiley'), lessThan(names.indexOf('sweat_smile')));
    });

    test('search matches words inside shortcodes and keywords', () {
      expect(
        EmojiCatalog.search('smile').map((e) => e.shortcode),
        contains('sweat_smile'),
      );
      // `happy` is a keyword of :smile:, not a shortcode.
      expect(
        EmojiCatalog.search('happy').map((e) => e.shortcode),
        contains('smile'),
      );
    });

    test('search honours limit and ignores blank queries', () {
      expect(EmojiCatalog.search('s', limit: 5), hasLength(5));
      expect(EmojiCatalog.search('  '), isEmpty);
      expect(EmojiCatalog.search('zzzzqqq'), isEmpty);
    });
  });

  group('EmojiRecents', () {
    setUp(EmojiRecents.reset);
    tearDown(EmojiRecents.reset);

    test('keeps newest first without duplicates, capped', () {
      EmojiRecents.add('😄');
      EmojiRecents.add('🎉');
      EmojiRecents.add('😄');
      expect(EmojiRecents.value, ['😄', '🎉']);
      for (final e in EmojiCatalog.all.take(EmojiRecents.maxLength + 5)) {
        EmojiRecents.add(e.emoji);
      }
      expect(EmojiRecents.value, hasLength(EmojiRecents.maxLength));
    });
  });
}
