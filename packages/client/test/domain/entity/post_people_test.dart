// #417: a Post's participant rows are its addressees; the author is added.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/post_people.dart';
import 'package:tentura/domain/entity/profile.dart';

final _createdAt = DateTime.utc(2026, 10, 2);

Beacon _post({String authorId = 'Uauthor'}) => Beacon(
  id: 'Bpost01',
  createdAt: _createdAt,
  updatedAt: _createdAt,
  author: Profile(id: authorId, displayName: 'Oleg'),
);

BeaconParticipant _row(String userId, int role) => BeaconParticipant(
  id: 'P-$userId',
  beaconId: 'Bpost01',
  userId: userId,
  role: role,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: _createdAt,
  updatedAt: _createdAt,
);

void main() {
  test('adds the author, admitted, in front of the addressees', () {
    final rows = withPostAuthor([
      _row('Ureader', BeaconParticipantRoleBits.addressee),
    ], _post());

    expect(rows.map((p) => p.userId), ['Uauthor', 'Ureader']);
    expect(rows.first.role, BeaconParticipantRoleBits.author);
    expect(rows.first.roomAccess, RoomAccessBits.admitted);
    expect(rows.first.userTitle, 'Oleg');
  });

  test('does not add the author twice', () {
    final rows = [_row('Uauthor', BeaconParticipantRoleBits.author)];

    expect(withPostAuthor(rows, _post()), same(rows));
  });

  test('adds nobody while the author is not loaded', () {
    final rows = [_row('Ureader', BeaconParticipantRoleBits.addressee)];

    expect(withPostAuthor(rows, _post(authorId: '')), same(rows));
  });
}
