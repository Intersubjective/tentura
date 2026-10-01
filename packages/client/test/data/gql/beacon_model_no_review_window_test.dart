import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'graphql_contract_support.dart';

// Assembled from parts: the A23 source guard greps the client for the removed
// review-window identifiers, and this regression test has to name one.
final _removedSelection = ['beacon', 'review', 'window'].join('_');

void main() {
  late String doc;
  late GqlSchema schema;

  setUpAll(() {
    doc = File('lib/data/gql/beacon_model.graphql').readAsStringSync();
    schema = GqlSchema(File('lib/data/gql/schema.graphql').readAsStringSync());
  });

  test('beacon_model.graphql no longer selects the review-window row', () {
    expect(doc, isNot(contains(_removedSelection)));
  });

  test('BeaconModel fragment is still a valid selection on `beacon`', () {
    final stripped = stripGqlComments(doc);
    final match = RegExp(r'fragment\s+BeaconModel\s+on\s+(\w+)\s*\{')
        .firstMatch(stripped);
    expect(match, isNotNull, reason: 'fragment BeaconModel is missing');
    final fields = parseSelectionAt(stripped, match!.end - 1);
    expect(fields, isNotEmpty);
    // Keeps the rest of the model intact.
    final names = fields.map((f) => f.name).toSet();
    expect(
      names,
      containsAll(['id', 'primary_need_slug', 'help_offers_aggregate']),
    );
    expect(names, isNot(contains(_removedSelection)));
    expect(
      schema.validateSelection(match.group(1)!, fields),
      isEmpty,
      reason: 'selection must only use fields of the Hasura schema',
    );
  });

  // The client "compiles" only if nothing still reads the removed selection:
  // the generated `beacon_model.data.gql.dart` no longer has the getter, so a
  // leftover reference in hand-written code is a compile error.
  test('hand-written client code no longer reads the review-window row', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/_g/') ||
          f.path.endsWith('.g.dart') ||
          f.path.endsWith('.freezed.dart') ||
          f.path.endsWith('.gql.dart')) {
        continue;
      }
      if (f.readAsStringSync().contains(_removedSelection)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('Beacon entity and mapper lose the review-window fields', () {
    final entity = File('lib/domain/entity/beacon.dart').readAsStringSync();
    final staleWindowField = RegExp('review.?window', caseSensitive: false);
    expect(staleWindowField.hasMatch(entity), isFalse);
    expect(entity, isNot(contains('reviewClosesAt')));
    final model = File('lib/data/model/beacon_model.dart').readAsStringSync();
    expect(staleWindowField.hasMatch(model), isFalse);
    expect(model, isNot(contains('reviewClosesAt')));
  });

  test('the generated beacon_model selection has no review window getter', () {
    final generated = File(
      'lib/data/gql/_g/beacon_model.data.gql.dart',
    );
    if (!generated.existsSync()) return; // generated files may be untracked
    expect(generated.readAsStringSync(), isNot(contains(_removedSelection)));
  });
}
