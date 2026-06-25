import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_promise_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';
import '../../../support/noop_beacon_room_notification_port.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? item;
  int? lastNewStatus;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

  @override
  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) async {
    lastNewStatus = newStatus;
    return item!.copyWith(status: newStatus);
  }
}

void main() {
  late _StubItems items;
  late CancelPromiseCase sut;

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
    sut = CancelPromiseCase(
      items,
      _NoopRoomPush(),
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('cancels open promise', () async {
    final result = await sut.call(userId: creatorId, itemId: itemId);
    expect(result.status, coordinationItemStatusCancelled);
    expect(items.lastNewStatus, coordinationItemStatusCancelled);
  });

  test('rejects when not found', () async {
    items.item = null;
    await expectLater(
      () => sut.call(userId: creatorId, itemId: itemId),
      throwsA(
        isA<IdNotFoundException>().having(
          (e) => e.description,
          'description',
          'Promise not found',
        ),
      ),
    );
    expect(items.lastNewStatus, null);
  });

  test('rejects wrong kind', () async {
    items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
    await expectLater(
      () => sut.call(userId: creatorId, itemId: itemId),
      throwsA(
        isA<BeaconCreateException>().having(
          (e) => e.description,
          'description',
          'Item is not a promise',
        ),
      ),
    );
    expect(items.lastNewStatus, null);
  });

  test('rejects already resolved', () async {
    items.item = items.item!.copyWith(status: coordinationItemStatusResolved);
    await expectLater(
      () => sut.call(userId: creatorId, itemId: itemId),
      throwsA(
        isA<BeaconCreateException>().having(
          (e) => e.description,
          'description',
          'Promise is already closed',
        ),
      ),
    );
    expect(items.lastNewStatus, null);
  });

  test('rejects already cancelled', () async {
    items.item = items.item!.copyWith(status: coordinationItemStatusCancelled);
    await expectLater(
      () => sut.call(userId: creatorId, itemId: itemId),
      throwsA(
        isA<BeaconCreateException>().having(
          (e) => e.description,
          'description',
          'Promise is already closed',
        ),
      ),
    );
    expect(items.lastNewStatus, null);
  });
}

CoordinationItemRecord _samplePromise({
  required String id,
  required String creatorId,
  required String targetPersonId,
  int status = coordinationItemStatusOpen,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: 'Bbbbbbbbbbbbb',
    kind: coordinationItemKindPromise,
    status: status,
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

class _NoopRoomPush extends NoopBeaconRoomNotificationPort {}
