import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/add_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_plan_step_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? item;
  CoordinationItemRecord? nextReturn;
  _AddPlanStepCall? lastAddPlanStep;
  _UpdateStatusCall? lastUpdateStatus;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

  @override
  Future<CoordinationItemRecord> addPlanStep({
    required String parentItemId,
    required String creatorId,
    required String title,
    String body = '',
  }) async {
    lastAddPlanStep = _AddPlanStepCall(
      parentItemId: parentItemId,
      creatorId: creatorId,
      title: title,
      body: body,
    );
    return nextReturn ?? item!;
  }

  @override
  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) async {
    lastUpdateStatus = _UpdateStatusCall(
      id: id,
      newStatus: newStatus,
      actorId: actorId,
    );
    return nextReturn ?? item!.copyWith(status: newStatus);
  }
}

class _AddPlanStepCall {
  const _AddPlanStepCall({
    required this.parentItemId,
    required this.creatorId,
    required this.title,
    required this.body,
  });

  final String parentItemId;
  final String creatorId;
  final String title;
  final String body;
}

class _UpdateStatusCall {
  const _UpdateStatusCall({
    required this.id,
    required this.newStatus,
    required this.actorId,
  });

  final String id;
  final int newStatus;
  final String actorId;
}

CoordinationItemRecord _rootPlan({
  required String id,
  required String beaconId,
  required String creatorId,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindPlan,
    status: coordinationItemStatusOpen,
    title: 'Plan',
    body: 'Plan body',
    creatorId: creatorId,
    published: true,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}

CoordinationItemRecord _planStep({
  required String id,
  required String beaconId,
  required String parentId,
  required String creatorId,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindPlan,
    status: coordinationItemStatusOpen,
    title: 'Step',
    body: 'Step body',
    creatorId: creatorId,
    linkedParentItemId: parentId,
    published: true,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 1,
  );
}

void main() {
  const userId = 'Ucreator00001';
  const beaconId = 'Bbbbbbbbbbbbb';
  const parentId = 'Iparent000001';
  const stepId = 'Istep00000001';

  group('AddPlanStepCase', () {
    late _StubItems items;
    late AddPlanStepCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _rootPlan(
        id: parentId,
        beaconId: beaconId,
        creatorId: userId,
      );
      items.nextReturn = _planStep(
        id: stepId,
        beaconId: beaconId,
        parentId: parentId,
        creatorId: userId,
      );
      sut = AddPlanStepCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('adds step under plan parent', () async {
      final result = await sut.call(
        userId: userId,
        parentItemId: parentId,
        title: '  First step  ',
        body: '  Details  ',
      );

      expect(result.id, stepId);
      expect(items.lastAddPlanStep?.parentItemId, parentId);
      expect(items.lastAddPlanStep?.creatorId, userId);
      expect(items.lastAddPlanStep?.title, 'First step');
      expect(items.lastAddPlanStep?.body, 'Details');
    });

    test('rejects empty title', () async {
      await expectLater(
        () => sut.call(
          userId: userId,
          parentItemId: parentId,
          title: '   ',
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Step title is required',
          ),
        ),
      );
      expect(items.lastAddPlanStep, isNull);
    });

    test('rejects missing parent', () async {
      items.item = null;
      await expectLater(
        () => sut.call(
          userId: userId,
          parentItemId: parentId,
          title: 'Step',
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Plan not found',
          ),
        ),
      );
      expect(items.lastAddPlanStep, isNull);
    });

    test('rejects non-plan parent', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindBlocker);
      await expectLater(
        () => sut.call(
          userId: userId,
          parentItemId: parentId,
          title: 'Step',
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Parent is not a plan',
          ),
        ),
      );
      expect(items.lastAddPlanStep, isNull);
    });
  });

  group('ResolvePlanStepCase', () {
    late _StubItems items;
    late ResolvePlanStepCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _planStep(
        id: stepId,
        beaconId: beaconId,
        parentId: parentId,
        creatorId: userId,
      );
      items.nextReturn = items.item!.copyWith(
        status: coordinationItemStatusResolved,
      );
      sut = ResolvePlanStepCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('resolves plan step', () async {
      final result = await sut.call(userId: userId, itemId: stepId);

      expect(result.status, coordinationItemStatusResolved);
      expect(items.lastUpdateStatus?.id, stepId);
      expect(items.lastUpdateStatus?.actorId, userId);
      expect(
        items.lastUpdateStatus?.newStatus,
        coordinationItemStatusResolved,
      );
    });

    test('rejects missing item', () async {
      items.item = null;
      await expectLater(
        () => sut.call(userId: userId, itemId: stepId),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Item not found',
          ),
        ),
      );
      expect(items.lastUpdateStatus, isNull);
    });

    test('rejects root plan without parent link', () async {
      items.item = _rootPlan(
        id: parentId,
        beaconId: beaconId,
        creatorId: userId,
      );
      await expectLater(
        () => sut.call(userId: userId, itemId: parentId),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Not a plan step',
          ),
        ),
      );
      expect(items.lastUpdateStatus, isNull);
    });

    test('rejects non-plan item', () async {
      items.item = items.item!.copyWith(
        kind: coordinationItemKindAsk,
        linkedParentItemId: parentId,
      );
      await expectLater(
        () => sut.call(userId: userId, itemId: stepId),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Not a plan step',
          ),
        ),
      );
      expect(items.lastUpdateStatus, isNull);
    });
  });
}
