// The fetched client `schema.graphql` must carry the Post fields of an
// attention receipt exactly as the server `AttentionReceipt` type declares
// them (Hasura stitching: `v2_` prefix): the beacon kind as an Int and the
// Post root excerpt and root image id as nullable strings.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

void main() {
  late Map<String, (String?, String)>? fields;

  setUpAll(() {
    fields = GqlSchema(
      File('lib/data/gql/schema.graphql').readAsStringSync(),
    ).fields('v2_AttentionReceipt');
  });

  group('v2_AttentionReceipt Post fields', () {
    test('the receipt type is present in the schema', () {
      expect(fields, isNotNull);
    });

    test('beaconKind is a nullable Int', () {
      expect(fields?['beaconKind'], (null, 'Int'));
    });

    test('postRootExcerpt is a nullable String', () {
      expect(fields?['postRootExcerpt'], (null, 'String'));
    });

    test('postRootImageId is a nullable String', () {
      expect(fields?['postRootImageId'], (null, 'String'));
    });
  });
}
