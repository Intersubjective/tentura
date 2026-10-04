// The shared attention receipt fragment is what every Activity / My Work query
// spreads. For the For You stream to tell a Post group from a Request group
// and to draw a Post's root message, the fragment itself has to select the
// beacon kind, the root excerpt and the root image id — the schema declaring
// them is not enough, a field the fragment does not select never reaches the
// mapper.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

void main() {
  late List<GqlField> selection;
  late String fragmentType;
  late GqlSchema schema;

  setUpAll(() {
    final stripped = stripGqlComments(
      File(
        'lib/features/attention/data/gql/attention_receipt_fields.graphql',
      ).readAsStringSync(),
    );
    final match = RegExp(
      r'fragment\s+AttentionReceiptFields\s+on\s+(\w+)\s*\{',
    ).firstMatch(stripped);
    expect(match, isNotNull, reason: 'fragment AttentionReceiptFields missing');
    fragmentType = match!.group(1)!;
    selection = parseSelectionAt(stripped, match.end - 1);
    schema = GqlSchema(File('lib/data/gql/schema.graphql').readAsStringSync());
  });

  group('AttentionReceiptFields fragment Post fields', () {
    test('selects the beacon kind', () {
      expect(selection.map((f) => f.name), contains('beaconKind'));
    });

    test('selects the Post root excerpt', () {
      expect(selection.map((f) => f.name), contains('postRootExcerpt'));
    });

    test('selects the Post root image id', () {
      expect(selection.map((f) => f.name), contains('postRootImageId'));
    });

    test('still selects only fields the receipt type declares', () {
      expect(schema.validateSelection(fragmentType, selection), isEmpty);
    });
  });
}
