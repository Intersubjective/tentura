import 'dart:io';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

/// Pins the one-way dependency between the GraphQL custom types and the
/// input-field library: `custom_types.dart` may import `input/_input_types.dart`
/// (to register input types), never the reverse. Also pins that moving
/// `PlanStepTimeInput` next to its input field left the wire type unchanged.
void main() {
  test('input/_input_types.dart does not import custom_types.dart', () {
    final source = File(
      'lib/api/controllers/graphql/input/_input_types.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('custom_types.dart')));
  });

  test('PlanStepTimeInput is still registered with the same fields', () {
    final type = customTypes.whereType<GraphQLInputObjectType>().singleWhere(
      (t) => t.name == 'PlanStepTimeInput',
    );
    final fields = {
      for (final f in type.inputFields) f.name: f.type.toString(),
    };
    expect(fields, {
      'sourceStepId': graphQLString.nonNullable().toString(),
      'startAt': graphQLString.toString(),
      'endAt': graphQLString.toString(),
    });
    expect(type.inputFields.map((f) => f.name).toList(), [
      'sourceStepId',
      'startAt',
      'endAt',
    ]);
  });
}
