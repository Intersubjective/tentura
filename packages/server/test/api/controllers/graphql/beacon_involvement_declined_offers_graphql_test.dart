import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/gql_v2_dto_maps.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_involvement_result.dart';

GraphQLObjectType _beaconInvolvementType() => gqlTypeBeaconInvolvement;

List<String> _stringListIds(Map<String, dynamic> gql, String key) =>
    List<String>.from(gql[key] as List? ?? const []);

/// Issue #770: author-declined help offers belong in `declinedOfferIds`, not
/// `withdrawnIds`.
void main() {
  group('BeaconInvolvement GraphQL type', () {
    test('declares declinedOfferIds as a nullable string id list', () {
      final field = _beaconInvolvementType().fields.singleWhere(
        (f) => f.name == 'declinedOfferIds',
        orElse: () => throw TestFailure('declinedOfferIds field is missing'),
      );
      expect(field.type, isA<GraphQLListType<Object?, Object?>>());
      final elementType =
          (field.type as GraphQLListType<Object?, Object?>).ofType;
      expect(elementType, isA<GraphQLNonNullableType<Object?, Object?>>());
      expect(
        (elementType as GraphQLNonNullableType<Object?, Object?>).ofType,
        graphQLString,
      );
    });
  });

  group('beaconInvolvementResultToGqlMap', () {
    const empty = BeaconInvolvementResult(
      forwardedToIds: [],
      helpOfferedIds: [],
      withdrawnIds: [],
      declinedOfferIds: [],
      rejectedIds: [],
      watchingIds: [],
      onwardForwarderIds: [],
      myForwardedRecipients: [],
    );

    test('always emits declinedOfferIds alongside the other id lists', () {
      final gql = beaconInvolvementResultToGqlMap(empty);
      expect(gql.keys, contains('declinedOfferIds'));
      expect(_stringListIds(gql, 'declinedOfferIds'), isEmpty);
    });
  });
}
