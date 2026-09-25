import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

void main() {
  test('helpOfferWithCoordinationToGqlMap includes stakeState and offerKind', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 't',
      description: '',
      userAvailability: null,
    );
    final row = HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      user: user,
      stakeState: 4,
      offerKind: 0,
    );
    final m = helpOfferWithCoordinationToGqlMap(row);
    expect(m['stakeState'], 4);
    expect(m['offerKind'], 0);
  });

  test('helpOfferWithCoordinationToGqlMap includes isDirectAuthorForward', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 't',
      description: '',
      userAvailability: null,
    );
    final row = HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      user: user,
      isDirectAuthorForward: true,
    );
    final m = helpOfferWithCoordinationToGqlMap(row);
    expect(m['isDirectAuthorForward'], true);
  });

  test('helpOfferWithCoordinationToGqlMap includes roomAccess for auto-admit', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 't',
      description: '',
      userAvailability: null,
    );
    final row = HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      user: user,
      roomAccess: RoomAccessBits.admitted,
    );
    final m = helpOfferWithCoordinationToGqlMap(row);
    expect(m['roomAccess'], RoomAccessBits.admitted);
  });

  test('helpOfferWithCoordinationToGqlMap emits authorSeenAt as ISO UTC Z', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 't',
      description: '',
      userAvailability: null,
    );
    final seen = DateTime.utc(2026, 3, 4, 5, 6, 7);
    final row = HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      user: user,
      authorSeenAt: seen,
    );
    final m = helpOfferWithCoordinationToGqlMap(row);
    expect(m['authorSeenAt'], '2026-03-04T05:06:07.000Z');
  });

  test('helpOfferWithCoordinationToGqlMap emits null authorSeenAt', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 't',
      description: '',
      userAvailability: null,
    );
    final row = HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      user: user,
    );
    final m = helpOfferWithCoordinationToGqlMap(row);
    expect(m['authorSeenAt'], isNull);
  });

  test('helpOfferWithCoordinationToGqlMap omits roomAccess when null', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 't',
      description: '',
      userAvailability: null,
    );
    final row = HelpOfferWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      user: user,
    );
    final m = helpOfferWithCoordinationToGqlMap(row);
    expect(m['roomAccess'], isNull);
  });
}
