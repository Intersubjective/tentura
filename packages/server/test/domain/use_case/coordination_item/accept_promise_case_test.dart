import 'package:drift_postgres/drift_postgres.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_promise_case.dart';
import 'package:tentura_server/env.dart';
import '../../../support/coordination_item_record_fixtures.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? item;
  String? lastAcceptedById;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

  @override
  Future<CoordinationItemRecord> acceptItem({
    required String id,
    required String actorId,
    required String acceptedById,
  }) async {
    lastAcceptedById = acceptedById;
    return item!;
  }
}

void main() {
  late _StubItems items;
  late AcceptPromiseCase sut;

  const itemId = 'Piiiiiiiiiiii';
  const creatorId = 'Ucreator00001';
  const targetId = 'Utarget000001';

  setUp(() {
    items = _StubItems();
    items.item = _samplePromise(
      id: itemId,
      creatorId: creatorId,
      targetPersonId: targetId,
    );
    sut = AcceptPromiseCase(
      items,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('accepts when caller is target', () async {
    final result = await sut.call(userId: targetId, itemId: itemId);
    expect(result.id, itemId);
    expect(items.lastAcceptedById, targetId);
  });

  test('rejects when caller is not target', () async {
    await expectLater(
      () => sut.call(userId: creatorId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastAcceptedById, null);
  });
}

CoordinationItemRecord _samplePromise({
  required String id,
  required String creatorId,
  required String targetPersonId,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: 'Bbbbbbbbbbbbb',
    kind: coordinationItemKindPromise,
    status: coordinationItemStatusOpen,
    title: 'Promise',
    body: 'Body',
    creatorId: creatorId,
    targetPersonId: targetPersonId,
    published: true,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}
