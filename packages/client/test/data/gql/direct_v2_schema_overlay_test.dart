import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracked schema retains native direct-V2 overlays', () {
    final schema = File('lib/data/gql/schema.graphql').readAsStringSync();
    final userStart = schema.indexOf('type user {');
    final userEnd = schema.indexOf('input user_bool_exp', userStart);
    final userType = schema.substring(userStart, userEnd);

    expect(userStart, isNonNegative);
    expect(userEnd, greaterThan(userStart));
    expect(userType, contains('displayName: String!'));
    expect(schema, contains('input Coordinates {'));
    expect(
      schema,
      contains('coordinates: Coordinates = {}'),
    );
    expect(
      schema,
      contains(
        'beaconExtendReview(id: String!): '
        'v2_BeaconExtendReviewResult!',
      ),
    );
    expect(schema, contains('type v2_BeaconExtendReviewResult {'));
    expect(schema, contains('extensionsRemaining: Int!'));
  });
}
