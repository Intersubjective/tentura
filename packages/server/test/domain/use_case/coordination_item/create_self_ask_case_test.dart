import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_self_ask_case.dart';
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

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  final List<_SelfAskCall> calls = [];
  CoordinationItem? nextReturn;

  @override
  Future<CoordinationItem> createSelfAcceptedAsk({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? linkedMessageId,
  }) async {
    calls.add(
      _SelfAskCall(
        beaconId: beaconId,
        creatorId: creatorId,
        title: title,
        body: body,
        linkedMessageId: linkedMessageId,
      ),
    );
    return nextReturn!;
  }
}

class _SelfAskCall {
  const _SelfAskCall({
    required this.beaconId,
    required this.creatorId,
    required this.title,
    required this.body,
    required this.linkedMessageId,
  });

  final String beaconId;
  final String creatorId;
  final String title;
  final String body;
  final String? linkedMessageId;
}

void main() {
  late _StubBeacons beacons;
  late _StubItems items;
  late CreateSelfAskCase sut;

  setUp(() {
    beacons = _StubBeacons(_openBeacon());
    items = _StubItems();
    sut = CreateSelfAskCase(
      beacons,
      items,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('throws when body is empty', () async {
    expect(
      () => sut.call(
        userId: 'Uaaaaaaaaaaaa',
        beaconId: beacons.entity.id,
        title: 'Bring cookies',
        body: '   ',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.calls, isEmpty);
  });

  test('throws when beacon is not open', () async {
    beacons.entity = beacons.entity.copyWith(state: 1);
    expect(
      () => sut.call(
        userId: 'Uaaaaaaaaaaaa',
        beaconId: beacons.entity.id,
        title: '',
        body: 'Do the thing',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.calls, isEmpty);
  });

  test('calls createSelfAcceptedAsk with trimmed body and optional title', () async {
    const uid = 'Uaaaaaaaaaaaa';
    items.nextReturn = _sampleItem(beaconId: beacons.entity.id, creatorId: uid);

    final out = await sut.call(
      userId: uid,
      beaconId: beacons.entity.id,
      title: '',
      body: '  oven ',
      linkedMessageId: 'Rmsg1',
    );

    expect(out.id, items.nextReturn!.id);
    expect(items.calls, hasLength(1));
    expect(items.calls.single.title, '');
    expect(items.calls.single.body, 'oven');
    expect(items.calls.single.linkedMessageId, 'Rmsg1');
    expect(items.calls.single.creatorId, uid);
    expect(items.calls.single.beaconId, beacons.entity.id);
  });

  test('trims non-empty title when provided', () async {
    const uid = 'Uaaaaaaaaaaaa';
    items.nextReturn = _sampleItem(beaconId: beacons.entity.id, creatorId: uid);

    await sut.call(
      userId: uid,
      beaconId: beacons.entity.id,
      title: '  Bring cookies ',
      body: 'oven',
    );

    expect(items.calls.single.title, 'Bring cookies');
    expect(items.calls.single.body, 'oven');
  });
}

BeaconEntity _openBeacon() => BeaconEntity(
  id: 'Baaaaaaaaaaaa',
  title: 't',
  author: const UserEntity(id: 'Ubbbbbbbbbbbb'),
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);

CoordinationItem _sampleItem({
  required String beaconId,
  required String creatorId,
}) {
  final now = PgDateTime(DateTime.utc(2025, 5));
  return CoordinationItem(
    id: 'CIaaaaaaaaaaa',
    beaconId: beaconId,
    kind: coordinationItemKindAsk,
    status: coordinationItemStatusAccepted,
    title: 'Bring cookies',
    body: 'oven',
    creatorId: creatorId,
    targetPersonId: creatorId,
    acceptedById: creatorId,
    source: coordinationItemSourceSelfPromise,
    published: true,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}
