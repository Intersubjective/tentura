// The fetched client `schema.graphql` must carry the mutation that takes back
// a «Can't make it» on an invitation (Hasura stitching exposes V2 mutation
// fields on `mutation_root` unprefixed), so the client can offer a real Undo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

void main() {
  late String schema;
  late Map<String, (String?, String)>? fields;

  setUpAll(() {
    schema = File('lib/data/gql/schema.graphql').readAsStringSync();
    fields = GqlSchema(schema).fields('mutation_root');
  });

  test('mutation_root reverts a declined invitation by its id and returns '
      'the same result as the other invitation transitions', () {
    expect(fields, isNotNull);
    final revert = fields?['beaconAuthorInviteRevertDecline'];
    final decline = fields?['beaconAuthorInviteDecline'];
    expect(revert, isNotNull);
    expect(revert, decline, reason: 'same args and result type as decline');
    expect(revert?.$2, 'v2_AuthorInviteResult!');
  });
}
