// Analyzed only by tentura_7xz_no_raw_graphql_interpolation_test.dart.

Future<void> tentura7xzProbePostGraphQl(String query) async {}

void tentura7xzProbeSubscribe(String objectUserId) {
  tentura7xzProbePostGraphQl(
    'mutation { userSubscribe(objectId: "$objectUserId") }',
  );
}
