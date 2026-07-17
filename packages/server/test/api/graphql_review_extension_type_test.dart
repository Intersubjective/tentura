import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

void main() {
  test('review extension has its own response contract', () {
    expect(gqlTypeBeaconExtendReviewResult.name, 'BeaconExtendReviewResult');
    expect(
      gqlTypeBeaconExtendReviewResult.fields.map((field) => field.name),
      containsAll(['id', 'closesAt', 'extensionsRemaining']),
    );
    expect(
      customTypes.whereType<GraphQLObjectType>().any(
        (type) => type.name == 'BeaconExtendReviewResult',
      ),
      isTrue,
    );
  });
}
