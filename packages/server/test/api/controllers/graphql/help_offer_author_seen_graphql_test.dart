import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

const _user = UserPublicRecord(
  id: 'U1',
  displayName: 't',
  description: '',
  userAvailability: null,
);

HelpOfferWithCoordinationRow _row({DateTime? authorSeenAt}) =>
    HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      user: _user,
      authorSeenAt: authorSeenAt,
    );

GraphQLObjectType _customObject(String name) => customTypes
    .whereType<GraphQLObjectType>()
    .singleWhere((t) => t.name == name);

/// Issue #178 part 2 (P1.4, P2.3): `authorSeenAt` on help offers and the
/// `MarkBeaconPeopleSeen` mutation.
void main() {
  group('HelpOfferWithCoordinationRow.authorSeenAt', () {
    test('GQL map emits authorSeenAt as ISO UTC', () {
      final seen = DateTime.utc(2026, 6, 15, 12, 30);
      final m = helpOfferWithCoordinationToGqlMap(_row(authorSeenAt: seen));
      expect(m['authorSeenAt'], '2026-06-15T12:30:00.000Z');
    });

    test('GQL map emits null authorSeenAt when never seen', () {
      final m = helpOfferWithCoordinationToGqlMap(_row());
      expect(m.containsKey('authorSeenAt'), isTrue);
      expect(m['authorSeenAt'], isNull);
    });

    test(
      'copyWith keeps authorSeenAt; clearAdmissionFields clears it (D6)',
      () {
        final seen = DateTime.utc(2026, 6, 15);
        final row = _row(authorSeenAt: seen);
        expect(row.copyWith(stakeState: 1).authorSeenAt, seen);
        expect(row.copyWith(clearAdmissionFields: true).authorSeenAt, isNull);
      },
    );

    test('HelpOfferWithCoordinationRow GQL type has nullable authorSeenAt', () {
      final field = _customObject(
        'HelpOfferWithCoordinationRow',
      ).fields.singleWhere((f) => f.name == 'authorSeenAt');
      expect(
        field.type,
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
      );
    });
  });

  group('MarkBeaconPeopleSeen', () {
    test('BeaconPeopleSeenResult type is registered with beaconId/seenAt', () {
      final type = _customObject('BeaconPeopleSeenResult');
      final names = type.fields.map((f) => f.name).toSet();
      expect(names, containsAll(const ['beaconId', 'seenAt']));
      for (final f in type.fields.where(
        (f) => f.name == 'beaconId' || f.name == 'seenAt',
      )) {
        expect(
          f.type,
          isA<GraphQLNonNullableType<dynamic, dynamic>>(),
          reason: f.name,
        );
      }
    });
  });
}
