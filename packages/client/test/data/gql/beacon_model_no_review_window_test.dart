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

  test('beacon_model.graphql no longer selects beacon_review_window', () {
    expect(doc, isNot(contains('beacon_review_window')));
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
    expect(names, isNot(contains('beacon_review_window')));
    expect(
      schema.validateSelection(match.group(1)!, fields),
      isEmpty,
      reason: 'selection must only use fields of the Hasura schema',
    );
  });

  // The client "compiles" only if nothing still reads the removed selection:
  // the generated `beacon_model.data.gql.dart` no longer has the getter, so a
  // leftover reference in hand-written code is a compile error.
  test('hand-written client code no longer reads beacon_review_window', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/_g/') ||
          f.path.endsWith('.g.dart') ||
          f.path.endsWith('.freezed.dart') ||
          f.path.endsWith('.gql.dart')) {
        continue;
      }
      if (f.readAsStringSync().contains('beacon_review_window')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('Beacon entity and mapper lose the review-window fields', () {
    final entity = File('lib/domain/entity/beacon.dart').readAsStringSync();
    expect(entity, isNot(contains('reviewWindowStatus')));
    expect(entity, isNot(contains('reviewClosesAt')));
    final model = File('lib/data/model/beacon_model.dart').readAsStringSync();
    expect(model, isNot(contains('reviewWindowStatus')));
    expect(model, isNot(contains('reviewClosesAt')));
  });

  test('the generated beacon_model selection has no review window getter', () {
    final generated = File(
      'lib/data/gql/_g/beacon_model.data.gql.dart',
    );
    if (!generated.existsSync()) return; // generated files may be untracked
    expect(generated.readAsStringSync(), isNot(contains('beacon_review_window')));
  });
}
