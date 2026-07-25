import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

void main() {
  // Hasura remote-schema stitching prefixes every Tentura V2 named type with
  // `v2_` (Beacon → v2_Beacon, AuthResponse → v2_AuthResponse, …). The server
  // therefore declares this input as unprefixed `Upload`. Naming it
  // `v2_Upload` on the server would stitch to `v2_v2_Upload` — do not "fix"
  // the server name back. Client operation documents and the introspected
  // schema.graphql correctly see `v2_Upload` after Hasura stitching.
  test('server registers Upload unprefixed; Hasura stitches it to v2_Upload', () {
    expect(InputFieldUpload.type.name, 'Upload');
    expect(
      customTypes.any(
        (t) => t is GraphQLInputObjectType && t.name == 'Upload',
      ),
      isTrue,
    );
    expect(
      customTypes.any(
        (t) => t is GraphQLInputObjectType && t.name == 'v2_Upload',
      ),
      isFalse,
    );
  });
}
