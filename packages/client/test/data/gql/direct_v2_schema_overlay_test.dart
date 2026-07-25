import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // schema.graphql is produced by `docker compose run --rm schema_fetcher`
  // against live Hasura. Do not hand-add aliases: Hasura remote-schema
  // stitching already prefixes Tentura V2 inputs (`Coordinates` →
  // `v2_Coordinates`, `Upload` → `v2_Upload`). Client documents must use
  // those stitched names. Hasura `user` exposes `display_name` (snake_case).
  test('fetched schema exposes stitched V2 inputs and review-extension types', () {
    final schema = File('lib/data/gql/schema.graphql').readAsStringSync();

    expect(schema, contains('input v2_Coordinates {'));
    expect(schema, isNot(contains('input Coordinates {')));
    expect(schema, contains('coordinates: v2_Coordinates = {}'));
    expect(schema, contains('input v2_Upload {'));
    expect(schema, isNot(contains('input Upload {')));
    expect(
      schema,
      contains(
        'beaconExtendReview(id: String!): '
        'v2_BeaconExtendReviewResult!',
      ),
    );
    expect(schema, contains('type v2_BeaconExtendReviewResult {'));
    expect(schema, contains('extensionsRemaining: Int!'));

    final userStart = schema.indexOf('type user {');
    final userEnd = schema.indexOf('input user_bool_exp', userStart);
    expect(userStart, isNonNegative);
    expect(userEnd, greaterThan(userStart));
    final userType = schema.substring(userStart, userEnd);
    expect(userType, contains('display_name: String!'));
    expect(userType, isNot(contains('displayName: String!')));
  });
}
