import 'package:test/test.dart';

import 'package:tentura_server/domain/util/email_auth_util.dart';

void main() {
  test('normalizeAuthEmail lowercases and trims', () {
    expect(normalizeAuthEmail('  Ada@Example.COM '), 'ada@example.com');
  });

  test('new accounts get a neutral name, not one made from the email', () {
    expect(kNewMemberDisplayName, 'New member');
  });

  test('isValidAuthEmailFormat accepts common addresses', () {
    expect(isValidAuthEmailFormat('user@example.com'), isTrue);
    expect(isValidAuthEmailFormat('not-an-email'), isFalse);
  });
}
