import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_coordination_item_case.dart';
import 'package:tentura_server/env.dart';

import 'package:injectable/injectable.dart' show Environment;

class _StubBeacons extends Fake implements BeaconRepositoryPort {
  _StubBeacons(this.entity);

  BeaconEntity entity;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    if (entity.id != beaconId) {
      throw StateError('missing beacon');
    }
    return entity;
  }
}

class _StubRoom extends Fake implements BeaconRoomRepository {
  bool author = false;
  bool steward = false;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      author;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      steward;
}

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  final List<_UpdateCall> calls = [];
  CoordinationItem? item;
  CoordinationItem? nextReturn;

  @override
  Future<CoordinationItem?> getById(String id) async => item;

  @override
  Future<CoordinationItem> updatePublishedItem({
    required String id,
    required String actorId,
    required String title,
    String body = '',
  }) async {
    calls.add(
      _UpdateCall(id: id, actorId: actorId, title: title, body: body),
    );
    return nextReturn ?? item!;
  }
}

class _UpdateCall {
  const _UpdateCall({
    required this.id,
    required this.actorId,
    required this.title,
    required this.body,
  });

  final String id;
  final String actorId;
  final String title;
  final String body;
}

void main() {
  late _StubBeacons beacons;
  late _StubItems items;
  late _StubRoom room;
  late UpdateCoordinationItemCase sut;

  const creatorId = 'Ucreator00001';
  const otherId = 'Uother0000001';
  const beaconId = 'Bbbbbbbbbbbbb';
  const itemId = 'Iiiiiiiiiiiii';

  setUp(() {
    beacons = _StubBeacons(_openBeacon(beaconId));
    items = _StubItems();
    room = _StubRoom();
    items.item = _sampleBlocker(
      id: itemId,
      beaconId: beaconId,
      creatorId: creatorId,
    );
    items.nextReturn = items.item;
    sut = UpdateCoordinationItemCase(
      beacons,
      items,
      room,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('creator can update open published blocker', () async {
    final result = await sut.call(
      userId: creatorId,
      itemId: itemId,
      title: 'Updated title',
      body: 'Body',
    );
    expect(result.id, itemId);
    expect(items.calls, hasLength(1));
    expect(items.calls.single.title, 'Updated title');
    expect(items.calls.single.actorId, creatorId);
  });

  test('beacon author can update item they did not create', () async {
    room.author = true;
    await sut.call(
      userId: otherId,
      itemId: itemId,
      title: 'Author edit',
    );
    expect(items.calls.single.actorId, otherId);
  });

  test('denies non-creator non-author', () async {
    expect(
      () => sut.call(
        userId: otherId,
        itemId: itemId,
        title: 'Nope',
      ),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(items.calls, isEmpty);
  });

  test('rejects resolved item', () async {
    items.item = _sampleBlocker(
      id: itemId,
      beaconId: beaconId,
      creatorId: creatorId,
      status: coordinationItemStatusResolved,
    );
    expect(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        title: 'Too late',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.calls, isEmpty);
  });

  test('rejects draft (unpublished) item', () async {
    items.item = _sampleBlocker(
      id: itemId,
      beaconId: beaconId,
      creatorId: creatorId,
      published: false,
    );
    expect(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        title: 'Draft',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.calls, isEmpty);
  });
}

BeaconEntity _openBeacon(String id) => BeaconEntity(
      id: id,
      title: 'Beacon',
      author: const UserEntity(id: 'Uauthor000001'),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

CoordinationItem _sampleBlocker({
  required String id,
  required String beaconId,
  required String creatorId,
  int status = coordinationItemStatusOpen,
  bool published = true,
}) {
  final now = PgDateTime(DateTime.utc(2024));
  return CoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindBlocker,
    status: status,
    title: 'Blocker',
    body: '',
    creatorId: creatorId,
    published: published,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}
