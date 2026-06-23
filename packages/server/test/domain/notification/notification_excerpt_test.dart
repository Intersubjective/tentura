import 'package:test/test.dart';

import 'package:tentura_server/domain/notification/notification_excerpt.dart';

void main() {
  group('notificationExcerpt', () {
    test('returns empty for blank input', () {
      expect(notificationExcerpt(''), '');
      expect(notificationExcerpt('   '), '');
    });

    test('returns trimmed text when under limit', () {
      expect(notificationExcerpt('  hello world  '), 'hello world');
    });

    test('truncates with ellipsis when over limit', () {
      final text = 'a' * 100;
      final excerpt = notificationExcerpt(text, maxChars: 20);
      expect(excerpt.length, 20);
      expect(excerpt, endsWith('…'));
      expect(excerpt, startsWith('a' * 19));
    });
  });
}
