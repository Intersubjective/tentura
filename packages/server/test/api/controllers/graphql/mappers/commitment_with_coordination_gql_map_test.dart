import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/gql_public/commitment_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

void main() {
  test('commitmentWithCoordinationToGqlMap includes roomAccess for auto-admit', () {
    const user = UserPublicRecord(
      id: 'U1',
      title: 't',
      description: '',
    );
    final row = CommitmentWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      user: user,
      roomAccess: RoomAccessBits.admitted,
    );
    final m = commitmentWithCoordinationToGqlMap(row);
    expect(m['roomAccess'], RoomAccessBits.admitted);
  });

  test('commitmentWithCoordinationToGqlMap omits roomAccess when null', () {
    const user = UserPublicRecord(
      id: 'U1',
      title: 't',
      description: '',
    );
    final row = CommitmentWithCoordinationRow(
      beaconId: 'B1',
      userId: 'U1',
      message: 'm',
      status: 0,
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      user: user,
    );
    final m = commitmentWithCoordinationToGqlMap(row);
    expect(m['roomAccess'], isNull);
  });
}
