import 'package:test/test.dart';

import 'package:tentura_server/domain/util/email_auth_util.dart';

void main() {
  test('normalizeAuthEmail lowercases and trims', () {
    expect(normalizeAuthEmail('  Ada@Example.COM '), 'ada@example.com');
  });

  test('displayNameFromEmail uses local part', () {
    expect(displayNameFromEmail('ada.lovelace@example.com'), 'ada lovelace');
  });

  test('isValidAuthEmailFormat accepts common addresses', () {
    expect(isValidAuthEmailFormat('user@example.com'), isTrue);
    expect(isValidAuthEmailFormat('not-an-email'), isFalse);
  });
}
