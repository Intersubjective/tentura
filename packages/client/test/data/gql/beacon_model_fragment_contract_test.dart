import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

void main() {
  late String doc;
  late GqlSchema schema;

  setUpAll(() {
    doc = File('lib/data/gql/beacon_model.graphql').readAsStringSync();
    schema = GqlSchema(File('lib/data/gql/schema.graphql').readAsStringSync());
  });

  test('BeaconModel fragment is a valid selection on `beacon`', () {
    final stripped = stripGqlComments(doc);
    final match = RegExp(
      r'fragment\s+BeaconModel\s+on\s+(\w+)\s*\{',
    ).firstMatch(stripped);
    expect(match, isNotNull, reason: 'fragment BeaconModel is missing');
    final fields = parseSelectionAt(stripped, match!.end - 1);
    expect(fields, isNotEmpty);
    final names = fields.map((f) => f.name).toSet();
    expect(
      names,
      containsAll(['id', 'primary_need_slug', 'help_offers_aggregate']),
    );
    expect(
      schema.validateSelection(match.group(1)!, fields),
      isEmpty,
      reason: 'selection must only use fields of the Hasura schema',
    );
  });
}
