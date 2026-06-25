import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/coordination_room_access.dart';

import '../../../support/coordination_item_record_fixtures.dart';

const _beaconId = 'Bbbbbbbbbbbbb';
const _userId = 'Uuser00000001';

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  _StubRoom({
    this.authorIds = const {},
    this.stewardIds = const {},
    this.participants = const {},
  });

  final Set<String> authorIds;
  final Set<String> stewardIds;
  final Map<String, int> participants;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      authorIds.contains(userId);

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      stewardIds.contains(userId);

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async {
    final roomAccess = participants[userId];
    if (roomAccess == null) {
      return null;
    }
    return testBeaconParticipant(
      beaconId: beaconId,
      userId: userId,
      roomAccess: roomAccess,
    );
  }
}

class _ThrowOnFindParticipantRoom extends Fake
    implements BeaconRoomRepositoryPort {
  _ThrowOnFindParticipantRoom({required this.authorId});

  final String authorId;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      userId == authorId;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async {
    throw StateError('findParticipant should not run for beacon author');
  }
}

void main() {
  group('ensureCanCoordinateOnBeacon', () {
    test('allows beacon author without participant lookup', () async {
      final room = _ThrowOnFindParticipantRoom(authorId: _userId);
      await expectLater(
        ensureCanCoordinateOnBeacon(
          room: room,
          beaconId: _beaconId,
          userId: _userId,
        ),
        completes,
      );
    });

    test('allows beacon steward', () async {
      final room = _StubRoom(stewardIds: {_userId});
      await expectLater(
        ensureCanCoordinateOnBeacon(
          room: room,
          beaconId: _beaconId,
          userId: _userId,
        ),
        completes,
      );
    });

    test('allows admitted room participant', () async {
      final room = _StubRoom(
        participants: {_userId: RoomAccessBits.admitted},
      );
      await expectLater(
        ensureCanCoordinateOnBeacon(
          room: room,
          beaconId: _beaconId,
          userId: _userId,
        ),
        completes,
      );
    });

    test('rejects when user is not author, steward, or admitted', () async {
      final room = _StubRoom();
      await expectLater(
        () => ensureCanCoordinateOnBeacon(
          room: room,
          beaconId: _beaconId,
          userId: _userId,
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'You must be an admitted beacon participant to coordinate',
          ),
        ),
      );
    });

    test('rejects non-admitted participant room access states', () async {
      for (final roomAccess in <int>[
        RoomAccessBits.none,
        RoomAccessBits.requested,
        RoomAccessBits.invited,
        RoomAccessBits.muted,
        RoomAccessBits.left,
      ]) {
        final room = _StubRoom(participants: {_userId: roomAccess});
        await expectLater(
          () => ensureCanCoordinateOnBeacon(
            room: room,
            beaconId: _beaconId,
            userId: _userId,
          ),
          throwsA(isA<BeaconCreateException>()),
          reason: 'roomAccess=$roomAccess',
        );
      }
    });
  });
}
