import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_promise_case.dart';
import 'package:tentura_server/env.dart';

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

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  int? lastKind;
  String? lastTarget;

  @override
  Future<CoordinationItem> create({
    required String beaconId,
    required int kind,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
    String? linkedParentItemId,
    int ordering = 0,
  }) async {
    lastKind = kind;
    lastTarget = targetPersonId;
    final now = PgDateTime(DateTime.utc(2024));
    return CoordinationItem(
      id: 'Piiiiiiiiiiii',
      beaconId: beaconId,
      kind: kind,
      status: coordinationItemStatusOpen,
      title: title,
      body: body,
      creatorId: creatorId,
      targetPersonId: targetPersonId,
      published: true,
      source: coordinationItemSourceDefault,
      createdAt: now,
      updatedAt: now,
      ordering: ordering,
    );
  }
}

void main() {
  late _StubBeacons beacons;
  late _StubItems items;
  late CreatePromiseCase sut;

  const creatorId = 'Ucreator00001';
  const targetId = 'Utarget000001';
  const beaconId = 'Bbbbbbbbbbbbb';

  setUp(() {
    beacons = _StubBeacons(_openBeacon(beaconId));
    items = _StubItems();
    sut = CreatePromiseCase(
      beacons,
      items,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('creates promise with target', () async {
    await sut.call(
      userId: creatorId,
      beaconId: beaconId,
      title: 'Do X',
      targetPersonId: targetId,
      body: 'details',
    );
    expect(items.lastKind, coordinationItemKindPromise);
    expect(items.lastTarget, targetId);
  });

  test('rejects self-target', () async {
    await expectLater(
      () => sut.call(
        userId: creatorId,
        beaconId: beaconId,
        title: 't',
        targetPersonId: creatorId,
        body: 'b',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastKind, null);
  });

  test('rejects empty body', () async {
    await expectLater(
      () => sut.call(
        userId: creatorId,
        beaconId: beaconId,
        title: 't',
        targetPersonId: targetId,
        body: '  ',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastKind, null);
  });

  test('rejects inactive beacon', () async {
    beacons.entity = _openBeacon(beaconId).copyWith(state: 1);
    await expectLater(
      () => sut.call(
        userId: creatorId,
        beaconId: beaconId,
        title: 't',
        targetPersonId: targetId,
        body: 'b',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastKind, null);
  });
}

BeaconEntity _openBeacon(String id) => BeaconEntity(
      id: id,
      title: 'Beacon',
      author: const UserEntity(id: 'Uauthor000001'),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );
