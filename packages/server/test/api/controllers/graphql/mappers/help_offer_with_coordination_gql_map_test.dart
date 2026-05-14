import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

void main() {
  test('helpOfferWithCoordinationToGqlMap includes roomAccess for auto-admit', () {
    const user = UserPublicRecord(
      id: 'U1',
      title: 't',
      description: '',
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

  test('helpOfferWithCoordinationToGqlMap omits roomAccess when null', () {
    const user = UserPublicRecord(
      id: 'U1',
      title: 't',
      description: '',
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
