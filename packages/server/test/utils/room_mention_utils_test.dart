import 'package:test/test.dart';

import 'package:tentura_server/utils/room_mention_utils.dart';

void main() {
  group('extractMentionHandleTokens', () {
    test('returns empty list when no mentions', () {
      expect(extractMentionHandleTokens('Hello everyone'), isEmpty);
    });

    test('extracts valid handles and lowercases them', () {
      expect(
        extractMentionHandleTokens('Ping @Alice and @bob_smith please'),
        ['alice', 'bob_smith'],
      );
    });

    test('deduplicates repeated mentions', () {
      expect(
        extractMentionHandleTokens('@same_user hi @Same_User'),
        ['same_user'],
      );
    });

    test('ignores handles shorter than minimum length', () {
      expect(extractMentionHandleTokens('@ab @abc'), ['abc']);
    });

    test('captures at most max handle length from longer tokens', () {
      final truncated = '@${'a' * 31}';
      final expected = 'a' * 30;
      expect(
        extractMentionHandleTokens(truncated),
        [expected],
      );
    });
  });
}
