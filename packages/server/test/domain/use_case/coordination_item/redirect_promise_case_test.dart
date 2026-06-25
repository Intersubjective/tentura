import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/redirect_promise_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? item;
  String? lastNewTarget;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

  @override
  Future<CoordinationItemRecord> redirectTarget({
    required String id,
    required String actorId,
    required String newTargetPersonId,
  }) async {
    lastNewTarget = newTargetPersonId;
    return item!.copyWith(targetPersonId: newTargetPersonId);
  }
}

void main() {
  late _StubItems items;
  late RedirectPromiseCase sut;

  const itemId = 'Piiiiiiiiiiii';
  const creatorId = 'Ucreator00001';
  const targetId = 'Utarget000001';
  const newTargetId = 'Unewtarget001';

  setUp(() {
    items = _StubItems();
    items.item = _samplePromise(
      id: itemId,
      creatorId: creatorId,
      targetPersonId: targetId,
    );
    sut = RedirectPromiseCase(
      items,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('creator can redirect open promise', () async {
    final result = await sut.call(
      userId: creatorId,
      itemId: itemId,
      newTargetPersonId: newTargetId,
    );
    expect(result.targetPersonId, newTargetId);
    expect(items.lastNewTarget, newTargetId);
  });

  test('rejects when not found', () async {
    items.item = null;
    await expectLater(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        newTargetPersonId: newTargetId,
      ),
      throwsA(isA<IdNotFoundException>()),
    );
    expect(items.lastNewTarget, null);
  });

  test('rejects wrong kind', () async {
    items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
    await expectLater(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        newTargetPersonId: newTargetId,
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastNewTarget, null);
  });

  test('rejects non-open status', () async {
    items.item = items.item!.copyWith(status: coordinationItemStatusAccepted);
    await expectLater(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        newTargetPersonId: newTargetId,
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastNewTarget, null);
  });

  test('rejects non-creator', () async {
    await expectLater(
      () => sut.call(
        userId: targetId,
        itemId: itemId,
        newTargetPersonId: newTargetId,
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastNewTarget, null);
  });

  test('rejects empty target', () async {
    await expectLater(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        newTargetPersonId: '  ',
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastNewTarget, null);
  });

  test('rejects self-target', () async {
    await expectLater(
      () => sut.call(
        userId: creatorId,
        itemId: itemId,
        newTargetPersonId: creatorId,
      ),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(items.lastNewTarget, null);
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
