// The fetched client `schema.graphql` must carry the server-served invitation
// TTL (Hasura stitching exposes V2 query fields on `query_root` unprefixed), so
// the client can read the effective expiry instead of the compiled default.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

void main() {
  late Map<String, (String?, String)>? fields;

  setUpAll(() {
    fields = GqlSchema(
      File('lib/data/gql/schema.graphql').readAsStringSync(),
    ).fields('query_root');
  });

  test('query_root serves the invitation TTL in hours as a non-null Int', () {
    expect(fields, isNotNull);
    expect(fields?['invitationTtlHours'], (null, 'Int!'));
  });
}
