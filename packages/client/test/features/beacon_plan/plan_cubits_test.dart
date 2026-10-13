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
    test('time places a step among timed ones; sortByTime keeps untimed', () {
      PlanStepSnapshot st(String id, [int? h]) => PlanStepSnapshot(
        id: id,
        title: id,
        startAt: h == null ? null : DateTime.utc(2030, 1, 1, h),
      );
      final c = PlanEditCubit(plan: repo.plan, planCase: planCaseFor(repo));
      for (final s in [...c.state.steps]) {
        c.removeStep(s.id);
      }
      c
        ..putStep(st('a', 9))
        ..putStep(st('b', 12))
        ..putStep(st('u'))
        ..putStep(st('n', 10));
      expect(c.state.steps.map((s) => s.id), ['a', 'n', 'b', 'u']);
      c.putStep(st('x', 20));
      expect(c.state.steps.map((s) => s.id), ['a', 'n', 'b', 'x', 'u']);
      c.putStep(st('n', 8));
      expect(c.state.steps.map((s) => s.id), ['n', 'a', 'b', 'x', 'u']);
      c.putStep(st('n', 8).copyWith(title: 'renamed'));
      expect(c.state.steps.first.title, 'renamed');
      c.reorder(0, 3);
      expect(c.state.orderContradictsTime, isTrue);
      c.sortByTime();
      expect(c.state.steps.map((s) => s.id), ['n', 'a', 'b', 'x', 'u']);
      expect(c.state.orderContradictsTime, isFalse);
      // Equal times keep their order.
      c
        ..putStep(st('e1', 15))
        ..putStep(st('e2', 15))
        ..putStep(st('e3', 15))
        ..sortByTime();
      expect(
        c.state.steps.map((s) => s.id).where((i) => i.startsWith('e')),
        ['e1', 'e2', 'e3'],
      );
    });

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

    group('chronological draft', () {
      const timedFirst = 'PS000000000001';
      const timedSecond = 'PS000000000002';
      const timedThird = 'PS000000000003';
      const untimed = 'PS000000000004';

      PlanEditCubit open([BeaconPlan? plan]) =>
          PlanEditCubit(plan: plan ?? repo.plan, planCase: planCaseFor(repo));

      /// The stored plan with its steps listed in [order].
      BeaconPlan planStoredAs(List<String> order) {
        final json = (jsonDecode(planJson()) as Map).cast<String, Object?>();
        final byId = {
          for (final s in json['steps']! as List) (s as Map)['id']: s,
        };
        json['steps'] = [for (final id in order) byId[id]];
        return BeaconPlan.fromJson(json);
      }

      test('editing a step to a later day moves it with its untimed '
          'followers and reports the move', () {
        final c = open()
          // The untimed step now follows the first timed step.
          ..reorder(3, 1);
        expect(c.state.steps.map((s) => s.id), [
          timedFirst,
          untimed,
          timedSecond,
          timedThird,
        ]);
        expect(c.state.movedSeq, 0);

        c.putStep(
          c.state.steps
              .firstWhere((s) => s.id == timedFirst)
              .copyWith(startAt: () => DateTime.utc(2026, 10, 13, 9)),
        );

        expect(c.state.steps.map((s) => s.id), [
          timedSecond,
          timedThird,
          timedFirst,
          untimed,
        ]);
        expect(c.state.movedStepId, timedFirst);
        expect(c.state.movedSeq, 1);
        unawaited(c.close());
      });

      test('editing a step without changing its place does not report a '
          'move', () {
        final c = open();
        c.putStep(
          c.state.steps
              .firstWhere((s) => s.id == timedSecond)
              .copyWith(title: 'Bring planks'),
        );
        expect(c.state.steps.map((s) => s.id), [
          timedFirst,
          timedSecond,
          timedThird,
          untimed,
        ]);
        expect(c.state.movedStepId, isNull);
        expect(c.state.movedSeq, 0);
        unawaited(c.close());
      });

      test('a new step without a time is appended at the end', () {
        final c = open();
        c.putStep(c.newStep().copyWith(title: 'Sweep up'));
        expect(c.state.steps.last.title, 'Sweep up');
        expect(c.state.steps, hasLength(5));
        unawaited(c.close());
      });

      test('a new step that already has a time goes to its place and is '
          'reported', () {
        final c = PlanEditCubit(
          plan: repo.plan,
          planCase: planCaseFor(repo),
          newStepId: () => 'PS0000000000ff',
        );
        c.putStep(
          c.newStep().copyWith(
            title: 'Early coffee',
            startAt: () => DateTime.utc(2026, 10, 12, 9),
          ),
        );
        expect(c.state.steps.map((s) => s.id), [
          timedFirst,
          'PS0000000000ff',
          timedSecond,
          timedThird,
          untimed,
        ]);
        expect(c.state.movedStepId, 'PS0000000000ff');
        expect(c.state.movedSeq, 1);
        unawaited(c.close());
      });

      test('a timed step cannot be dragged', () {
        final c = open()..reorder(0, 2);
        expect(c.state.steps.map((s) => s.id), [
          timedFirst,
          timedSecond,
          timedThird,
          untimed,
        ]);
        expect(c.state.isDirty, isFalse);
        unawaited(c.close());
      });

      test('an untimed step dropped between two timed steps sticks to the '
          'one above it', () {
        final c = open()..reorder(3, 2);
        expect(c.state.steps.map((s) => s.id), [
          timedFirst,
          timedSecond,
          untimed,
          timedThird,
        ]);
        unawaited(c.close());
      });

      test('opening a plan stored out of order gives a chronological draft '
          'that is not dirty', () {
        final c = open(
          planStoredAs([timedThird, timedSecond, timedFirst, untimed]),
        );
        expect(c.state.steps.map((s) => s.id), [
          timedFirst,
          untimed,
          timedSecond,
          timedThird,
        ]);
        expect(c.state.base.ids, c.state.steps.map((s) => s.id));
        expect(c.state.isDirty, isFalse);
        unawaited(c.close());
      });

      test('the draft rebased after a conflict is chronological', () async {
        final fresh = (jsonDecode(planJson()) as Map).cast<String, Object?>();
        fresh['revisionSeq'] = 5;
        for (final step in fresh['steps']! as List) {
          final s = step as Map;
          // Someone moved the first step to a later day, keeping its slot.
          if (s['id'] == timedFirst) s['startAt'] = '2026-10-13T09:00:00.000Z';
          if (s['id'] == timedSecond) s['title'] = 'Boards (theirs)';
        }
        repo.saveErrors.add(
          const PlanEditConflictException(
            currentSeq: 5,
            conflictStepIds: [timedSecond],
          ),
        );
        final c = open();
        repo.plan = BeaconPlan.fromJson(fresh);
        c
          ..putStep(
            c.state.steps
                .firstWhere((s) => s.id == timedSecond)
                .copyWith(title: 'Boards (mine)'),
          )
          ..putStep(
            c.state.steps
                .firstWhere((s) => s.id == timedThird)
                .copyWith(title: 'Frame (mine)'),
          );
        await c.save();
        expect(c.state.conflictSeq, 1);
        // The untimed step follows the third step it was stored after.
        expect(c.state.steps.map((s) => s.id), [
          timedSecond,
          timedThird,
          untimed,
          timedFirst,
        ]);
        await c.close();
      });
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
