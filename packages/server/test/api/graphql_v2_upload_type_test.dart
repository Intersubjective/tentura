import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

void main() {
  test('V2 schema registers v2_Upload for client operation documents', () {
    expect(InputFieldUpload.type.name, 'v2_Upload');
    expect(
      customTypes.any(
        (t) => t is GraphQLInputObjectType && t.name == 'v2_Upload',
      ),
      isTrue,
    );
  });
}
