// tentura-50o: invoked from hasura_pg_jwt_keys_test.dart after repo `.env` is
// hidden — exercises production setUpAll call shape (no loader overrides).

import 'package:test/test.dart';

import 'hasura_pg_jwt_keys.dart';

void main() {
  test('tentura-50o loadJwtKeysForHasuraPgTests default path fresh checkout', () {
    expect(() => loadJwtKeysForHasuraPgTests(), returnsNormally);
    final keys = loadJwtKeysForHasuraPgTests();
    expect(keys.publicKey, isNotEmpty);
    expect(keys.privateKey, isNotEmpty);
  });
}
