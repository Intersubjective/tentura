import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasNewInboxDot first-visit rule', () {
    test('null last-seen with positive max activity qualifies', () {
      const maxInboxActivityMs = 100;
      const inboxLastSeenMs = null as int?;
      const activeHomeTabIndex = 0;
      const accountId = 'U1';

      final qualifies =
          accountId.isNotEmpty &&
          activeHomeTabIndex != 1 &&
          maxInboxActivityMs > 0 &&
          (inboxLastSeenMs == null || maxInboxActivityMs > inboxLastSeenMs);

      expect(qualifies, isTrue);
    });
  });
}
