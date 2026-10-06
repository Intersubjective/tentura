import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_revision.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_history_cubit.dart';

import 'beacon_plan_test_support.dart';

void main() {
  late FakeBeaconPlanRepository repo;

  setUp(() => repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson())));
  tearDown(() => repo.dispose());

  group('PlanCubit', () {
    PlanCubit cubit() => PlanCubit(
      beaconId: 'B1',
      viewerId: 'ME',
      planCase: planCaseFor(repo),
      clock: () => DateTime.utc(2026, 10, 12, 10, 15),
    );

    test('loads and refetches on realtime beacon_plan', () async {
      final c = cubit();
      await c.load();
      expect(c.state.plan?.steps, hasLength(4));
      expect(c.state.isSuccess, isTrue);
      repo.changesController.add('OTHER');
      repo.changesController.add('B1');
      await pumpEventQueue();
      expect(repo.fetchCount, 2);
      await c.close();
    });

    test('optimistic tick then server ok', () async {
      final c = cubit();
      await c.load();
      final future = c.toggleDone('PS000000000003');
      expect(c.state.plan!.stepById('PS000000000003')!.isDone, isTrue);
      await future;
      expect(repo.setDoneCalls, [('PS000000000003', true)]);
      expect(c.state.busyStepIds, isEmpty);
      await c.close();
    });

    test('failed tick rolls back with a notice', () async {
      repo.setDoneError = const PlanNotEditableException();
      final c = cubit();
      await c.load();
      await c.toggleDone('PS000000000001');
      final step = c.state.plan!.stepById('PS000000000001')!;
      expect(step.isDone, isTrue, reason: 'restored to done');
      expect(step.doneById, 'U2');
      expect(c.state.notice, isA<PlanNoticeError>());
      expect((c.state.notice! as PlanNoticeError).tickFailed, isTrue);
      expect(c.state.noticeSeq, 1);
      await c.close();
    });

    test('ack confirms up to the pending head', () async {
      repo.plan = BeaconPlan.decode(
        planJson(
          viewerPending: {
            'fromSeq': 3,
            'headSeq': 4,
            'changes': [
              {
                'op': 'reassigned',
                'stepId': 'PS000000000002',
                'title': 'Bring boards',
                'toAssigneeId': 'ME',
                'seq': 3,
              },
            ],
            'actorIds': ['U2'],
          },
        ),
      );
      final c = cubit();
      await c.load();
      expect(c.state.plan!.hasViewerPending, isTrue);
      await c.ack();
      expect(repo.ackCalls, [4]);
      await c.close();
    });

    test('cantMake sends the base revision', () async {
      final c = cubit();
      await c.load();
      final ok = await c.cantMake(
        stepId: 'PS000000000002',
        option: PlanCantMakeOption.handover,
        toUserId: 'U2',
      );
      expect(ok, isTrue);
      expect(repo.cantMakeCalls, [
        ('PS000000000002', PlanCantMakeOption.handover, 'U2'),
      ]);
      await c.close();
    });
  });

  group('PlanEditCubit', () {
    test('draft edits and save with the base taken at open', () async {
      final c = PlanEditCubit(
        plan: repo.plan,
        planCase: planCaseFor(repo),
        newStepId: () => 'PS0000000000ff',
      );
      expect(c.state.isDirty, isFalse);
      c
        ..putStep(c.newStep().copyWith(title: 'Water the beds'))
        ..reorder(4, 0)
        ..removeStep('PS000000000004')
        ..setComment('rain');
      expect(c.state.steps.first.id, 'PS0000000000ff');
      expect(c.state.isDirty, isTrue);
      expect(c.state.validationError, isNull);
      await c.save();
      expect(repo.saveCalls.single.$1, 4);
      expect(repo.saveCalls.single.$2.ids, [
        'PS0000000000ff',
        'PS000000000001',
        'PS000000000002',
        'PS000000000003',
      ]);
      expect(repo.saveCalls.single.$3, 'rain');
      expect(c.state.saved?.outcome.kind, PlanSaveOutcomeKind.applied);
      await c.close();
    });

    test('validation blocks empty titles and reversed times', () {
      final c = PlanEditCubit(plan: repo.plan, planCase: planCaseFor(repo))
        ..putStep(const PlanStepSnapshot(id: 'PSx', title: ' '));
      expect(c.state.validationError, PlanDraftError.titleRequired);
      c.putStep(
        PlanStepSnapshot(
          id: 'PSx',
          title: 'ok',
          startAt: DateTime.utc(2026, 1, 2),
          endAt: DateTime.utc(2026),
        ),
      );
      expect(c.state.validationError, PlanDraftError.endBeforeStart);
      unawaited(c.close());
    });

    test(
      'conflict → their step taken, my other edits kept, user told',
      () async {
        final fresh = (jsonDecode(planJson()) as Map).cast<String, Object?>();
        fresh['revisionSeq'] = 5;
        fresh['lastEditedById'] = 'U2';
        for (final step in fresh['steps']! as List) {
          final s = step as Map;
          if (s['id'] == 'PS000000000002') s['title'] = 'Boards (theirs)';
        }
        repo.saveErrors.add(
          const PlanEditConflictException(
            currentSeq: 5,
            conflictStepIds: ['PS000000000002'],
          ),
        );
        final c = PlanEditCubit(plan: repo.plan, planCase: planCaseFor(repo));
        repo.plan = BeaconPlan.fromJson(fresh);
        final mine = c.state.steps.firstWhere((s) => s.id == 'PS000000000002');
        c
          ..putStep(mine.copyWith(title: 'Boards (mine)'))
          ..putStep(
            c.state.steps
                .firstWhere((s) => s.id == 'PS000000000003')
                .copyWith(title: 'Frame (mine)'),
          );
        await c.save();
        expect(repo.saveCalls, hasLength(1), reason: 'no silent resave');
        expect(c.state.saved, isNull);
        expect(c.state.conflictSeq, 1);
        final notice = c.state.conflictSteps.single;
        expect(notice.stepId, 'PS000000000002');
        expect(notice.title, 'Boards (theirs)');
        expect(notice.actorName, 'Olga');
        expect(c.state.baseSeq, 5, reason: 'rebased onto the head');
        final byId = c.state.draft.byId;
        expect(byId['PS000000000002']!.title, 'Boards (theirs)');
        expect(byId['PS000000000003']!.title, 'Frame (mine)');

        await c.save();
        expect(repo.saveCalls, hasLength(2));
        expect(repo.saveCalls.last.$1, 5);
        expect(c.state.saved, isNotNull);
        await c.close();
      },
    );

    test('conflict the client can merge → rebased and saved again', () async {
      final fresh = (jsonDecode(planJson()) as Map).cast<String, Object?>();
      fresh['revisionSeq'] = 5;
      for (final step in fresh['steps']! as List) {
        final s = step as Map;
        if (s['id'] == 'PS000000000004') s['title'] = 'Cart (theirs)';
      }
      repo.saveErrors.add(const PlanEditConflictException(currentSeq: 5));
      final c = PlanEditCubit(plan: repo.plan, planCase: planCaseFor(repo));
      repo.plan = BeaconPlan.fromJson(fresh);
      c.putStep(
        c.state.steps
            .firstWhere((s) => s.id == 'PS000000000003')
            .copyWith(title: 'Frame (mine)'),
      );
      await c.save();
      expect(repo.saveCalls, hasLength(2));
      final resave = repo.saveCalls.last;
      expect(resave.$1, 5);
      expect(resave.$2.byId['PS000000000004']!.title, 'Cart (theirs)');
      expect(resave.$2.byId['PS000000000003']!.title, 'Frame (mine)');
      expect(c.state.conflictSteps, isEmpty);
      expect(c.state.saved, isNotNull);
      await c.close();
    });
  });

  group('PlanHistoryCubit', () {
    test('restore uses the newest revision as base', () async {
      repo.page = PlanRevisionPage(
        items: [
          PlanRevisionEntry(
            seq: 4,
            kind: PlanRevisionKind.edited,
            createdAt: DateTime.utc(2026),
          ),
          PlanRevisionEntry(
            seq: 3,
            kind: PlanRevisionKind.created,
            createdAt: DateTime.utc(2026),
          ),
        ],
      );
      final c = PlanHistoryCubit(beaconId: 'B1', planCase: planCaseFor(repo));
      await c.load();
      expect(c.state.headSeq, 4);
      await c.restore(3);
      expect(repo.restoreCalls, [(3, 4)]);
      expect(c.state.restoredFromSeq, 3);
      expect(c.state.restoredSeq, 1);
      await c.close();
    });
  });
}
