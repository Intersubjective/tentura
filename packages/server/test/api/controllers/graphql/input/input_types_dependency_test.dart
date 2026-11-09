import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

/// Pins that moving `PlanStepTimeInput` next to its input field left the wire
/// type unchanged. The import-direction check between `custom_types.dart` and
/// `input/_input_types.dart` lives in
/// test/architecture/layer_import_direction_test.dart.
void main() {
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
