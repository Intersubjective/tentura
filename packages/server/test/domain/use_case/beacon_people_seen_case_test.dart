import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_people_seen_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_people_seen_case.dart';
import 'package:tentura_server/env.dart';

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  bool author = false;
  bool steward = false;
  final authorChecks = <({String beaconId, String userId})>[];
  final stewardChecks = <({String beaconId, String userId})>[];

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async {
    authorChecks.add((beaconId: beaconId, userId: userId));
    return author;
  }

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async {
    stewardChecks.add((beaconId: beaconId, userId: userId));
    return steward;
  }
}

class _StubSeen extends Fake implements BeaconPeopleSeenRepositoryPort {
  final calls = <({String userId, String beaconId, DateTime at})>[];
  DateTime? returnValue;

  @override
  Future<DateTime> markSeen({
    required String userId,
    required String beaconId,
    required DateTime at,
  }) async {
    calls.add((userId: userId, beaconId: beaconId, at: at));
    return returnValue ?? at;
  }
}

void main() {
  late _StubRoom room;
  late _StubSeen seen;
  late BeaconPeopleSeenCase sut;

  const beaconId = 'Baaaaaaaaaaaa';
  const userId = 'Uaaaaaaaaaaaa';

  setUp(() {
    room = _StubRoom();
    seen = _StubSeen();
    sut = BeaconPeopleSeenCase(
      room,
      seen,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconPeopleSeenCaseTest'),
    );
  });

  Future<Map<String, Object?>> call([String? iso]) => sut.markPeopleSeen(
    beaconId: beaconId,
    userId: userId,
    readThroughAtIso: iso,
  );

  test('author: markSeen once, returns the port value', () async {
    room.author = true;
    final persisted = DateTime.utc(2026, 5, 1, 12);
    seen.returnValue = persisted;

    final out = await call(DateTime.utc(2026, 5, 1, 10).toIso8601String());

    expect(room.authorChecks, [(beaconId: beaconId, userId: userId)]);
    expect(seen.calls, hasLength(1));
    expect(seen.calls.single.userId, userId);
    expect(seen.calls.single.beaconId, beaconId);
    expect(out['beaconId'], beaconId);
    expect(out['seenAt'], persisted.toUtc().toIso8601String());
  });

  test('steward (not author) is allowed', () async {
    room.steward = true;

    await call();

    expect(room.authorChecks, [(beaconId: beaconId, userId: userId)]);
    expect(room.stewardChecks, [(beaconId: beaconId, userId: userId)]);
    expect(seen.calls, hasLength(1));
    expect(seen.calls.single.userId, userId);
    expect(seen.calls.single.beaconId, beaconId);
  });

  test('helper is rejected and markSeen never called', () async {
    await expectLater(
      call(),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.description,
          'description',
          'Author or steward only',
        ),
      ),
    );
    expect(seen.calls, isEmpty);
  });

  test('future readThroughAt is clamped to now', () async {
    room.author = true;
    final future = DateTime.timestamp().add(const Duration(hours: 1));

    await call(future.toIso8601String());

    final at = seen.calls.single.at;
    expect(at.isUtc, isTrue);
    expect(
      at.difference(DateTime.timestamp()).abs(),
      lessThan(const Duration(seconds: 5)),
    );
  });

  test('malformed and blank ISO fall back to now', () async {
    room.author = true;

    await call('not-a-date');
    await call('   ');
    await call();

    expect(seen.calls, hasLength(3));
    for (final c in seen.calls) {
      expect(c.at.isUtc, isTrue);
      expect(
        c.at.difference(DateTime.timestamp()).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    }
  });

  test('past readThroughAt is passed through unchanged', () async {
    room.author = true;
    final past = DateTime.utc(2026, 5, 1, 10);

    await call(past.toIso8601String());

    expect(seen.calls.single.at, past);
  });
}
