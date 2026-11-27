import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';

void main() {
  test('PhantomImportContactInput is registered and resolvable', () {
    final types = customTypes;
    expect(
      types.any((t) => identical(t, gqlInputPhantomImportContact)),
      isTrue,
    );
    expect(
      resolveStitchedV2Type('v2_PhantomImportContactInput', types),
      same(gqlInputPhantomImportContact),
    );
  });
}
