import 'package:test/test.dart';

import 'pg_test_public_keys.dart';

void main() {
  test('pgTestPublicKey is 44 chars and unique per namespace+slot', () {
    final a = pgTestPublicKey('visparity', 1);
    final b = pgTestPublicKey('inboxtest', 1);
    final c = pgTestPublicKey('visparity', 2);

    expect(a.length, 44);
    expect(b.length, 44);
    expect(c.length, 44);
    expect(a, isNot(equals(b)));
    expect(a, isNot(equals(c)));
  });
}
