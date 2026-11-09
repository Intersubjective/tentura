// One-way import directions that keep layers apart:
// - GraphQL `custom_types.dart` may import `input/_input_types.dart` (to
//   register input types), never the reverse.
// - The public availability projection is a domain rule: its policy file
//   carries no data-layer or drift imports, and the GraphQL layer reads it
//   from domain/policy rather than from data/mapper.

import 'dart:io';

import 'package:test/test.dart';

const _inputTypesPath = 'lib/api/controllers/graphql/input/_input_types.dart';
const _availabilityPolicyPath =
    'lib/domain/policy/public_user_availability_policy.dart';
const _graphqlControllersDir = 'lib/api/controllers/graphql';
const _availabilityDataMapperImport =
    'data/mapper/user_availability_mapper.dart';

void main() {
  group('GraphQL input types', () {
    test('input/_input_types.dart does not import custom_types.dart', () {
      final source = File(_inputTypesPath).readAsStringSync();
      expect(source, isNot(contains('custom_types.dart')));
    });
  });

  group('public user availability policy', () {
    test('policy file has no data-layer or drift imports', () {
      final source = File(_availabilityPolicyPath).readAsStringSync();
      expect(source, isNot(contains('/data/')));
      expect(source, isNot(contains('drift')));
    });

    test('GraphQL layer no longer imports the availability data mapper', () {
      final offenders = Directory(_graphqlControllersDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(
            (f) => f.readAsStringSync().contains(_availabilityDataMapperImport),
          )
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty);
    });
  });
}
