import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_promise_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';

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
  late ResolvePromiseCase sut;

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
    sut = ResolvePromiseCase(
      items,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('resolves open promise', () async {
    final result = await sut.call(userId: targetId, itemId: itemId);
    expect(result.status, coordinationItemStatusResolved);
    expect(items.lastNewStatus, coordinationItemStatusResolved);
  });

  test('resolves accepted promise', () async {
    items.item = items.item!.copyWith(status: coordinationItemStatusAccepted);
    final result = await sut.call(userId: targetId, itemId: itemId);
    expect(result.status, coordinationItemStatusResolved);
    expect(items.lastNewStatus, coordinationItemStatusResolved);
  });

  test('rejects when not found', () async {
    items.item = null;
    await expectLater(
      () => sut.call(userId: targetId, itemId: itemId),
      throwsA(isA<IdNotFoundException>()),
    );
    expect(items.lastNewStatus, null);
  });

  test('rejects wrong kind', () async {
    items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
    await expectLater(
      () => sut.call(userId: targetId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastNewStatus, null);
  });

  test('rejects cancelled promise', () async {
    items.item = items.item!.copyWith(status: coordinationItemStatusCancelled);
    await expectLater(
      () => sut.call(userId: targetId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
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
