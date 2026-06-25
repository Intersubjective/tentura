import 'package:test/test.dart';

import 'package:tentura_server/domain/util/email_auth_util.dart';

void main() {
  test('normalizeAuthEmail lowercases and trims', () {
    expect(normalizeAuthEmail('  Ada@Example.COM '), 'ada@example.com');
  });

  test('displayNameFromEmail uses local part', () {
    expect(displayNameFromEmail('ada.lovelace@example.com'), 'ada lovelace');
  });

  test('displayNameFromEmail keeps local parts up to 50 characters', () {
    final local = 'a' * 50;
    expect(displayNameFromEmail('$local@example.com'), local);
  });

  test('displayNameFromEmail truncates long local parts to 50 characters', () {
    final local = 'a' * 51;
    expect(displayNameFromEmail('$local@example.com'), 'a' * 50);
  });

  test('isValidAuthEmailFormat accepts common addresses', () {
    expect(isValidAuthEmailFormat('user@example.com'), isTrue);
    expect(isValidAuthEmailFormat('not-an-email'), isFalse);
  });
}
