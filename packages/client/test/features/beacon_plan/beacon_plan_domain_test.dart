import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_conflict.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_revision.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_state.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';

import 'beacon_plan_test_support.dart';

void main() {
  group('BeaconPlan JSON', () {
    test('parses the server view', () {
      final plan = BeaconPlan.decode(
        planJson(
          viewerPending: {
            'fromSeq': 3,
            'headSeq': 4,
            'changes': [
              {
                'op': 'retimed',
                'stepId': 'PS000000000002',
                'title': 'Bring boards',
                'fromStartAt': '2026-10-12T09:00:00.000Z',
                'toStartAt': '2026-10-12T10:00:00.000Z',
                'fromAssigneeId': 'ME',
                'seq': 3,
              },
              {'op': 'cantMake', 'stepId': 'x', 'title': 'ignored'},
            ],
            'actorIds': ['U2'],
          },
        ),
      );
      expect(plan.beaconId, 'B1');
      expect(plan.revisionSeq, 4);
      expect(plan.changeSeq, 9);
      expect(plan.editable, isTrue);
      expect(plan.steps, hasLength(4));
      expect(plan.doneCount, 1);
      expect(plan.lastEditedAt, DateTime.utc(2026, 10, 12, 7, 10));
      final boards = plan.stepById('PS000000000002')!;
      expect(boards.assigneeAckPending, isTrue);
      expect(boards.endAt, DateTime.utc(2026, 10, 12, 10, 30));
      expect(plan.stepById('PS000000000004')!.assigneeId, isNull);
      expect(plan.memberOf('ME')!.pendingFromSeq, 3);
      expect(plan.nameOf('U2'), 'Olga');
      final pending = plan.viewerPending!;
      expect(pending.headSeq, 4);
      expect(pending.changes, hasLength(1), reason: 'unknown ops dropped');
      expect(pending.changes.single.change.op, PlanChangeOp.retimed);
      expect(pending.actorIds, ['U2']);
      expect(plan.hasViewerPending, isTrue);
    });

    test('snapshot round-trips into the save payload', () {
      final plan = BeaconPlan.decode(planJson());
      final encoded = jsonDecode(plan.snapshot.encode()) as List;
      expect(encoded, hasLength(4));
      expect((encoded.first as Map)['id'], 'PS000000000001');
      expect((encoded.first as Map).containsKey('doneAt'), isFalse);
      expect(
        PlanSnapshot.fromJson(plan.snapshot.encode()).sameAs(plan.snapshot),
        isTrue,
      );
    });

    test('viewerSchedule uses the shared rules', () {
      final plan = BeaconPlan.decode(planJson());
      final at1015 = DateTime.utc(2026, 10, 12, 10, 15);
      final schedule = plan.viewerSchedule(now: at1015, viewerId: 'ME');
      expect(schedule.current?.id, 'PS000000000002');
      expect(schedule.next?.id, 'PS000000000003');
      final at0900 = DateTime.utc(2026, 10, 12, 9);
      final free = plan.viewerSchedule(now: at0900, viewerId: 'ME');
      expect(free.current, isNull);
      expect(free.freeUntil, DateTime.utc(2026, 10, 12, 10));
      final late = DateTime.utc(2026, 10, 12, 10, 50);
      expect(plan.viewerOverdueCount(now: late, viewerId: 'ME'), 1);
      expect(plan.overdueCount(late), 1);
    });

    test('optimistic tick flips one step only', () {
      final plan = BeaconPlan.decode(planJson());
      final ticked = plan.withStepDone(
        'PS000000000003',
        done: true,
        actorId: 'ME',
        now: DateTime.utc(2026, 10, 12, 12),
      );
      expect(ticked.stepById('PS000000000003')!.isDone, isTrue);
      expect(ticked.stepById('PS000000000003')!.doneById, 'ME');
      expect(ticked.doneCount, 2);
      expect(plan.doneCount, 1, reason: 'original untouched');
    });

    test('broken payloads stay lenient', () {
      final plan = BeaconPlan.fromJson(const {
        'beaconId': 'B',
        'steps': [
          {'title': 'no id'},
          'garbage',
        ],
        'viewerPending': 'nope',
      });
      expect(plan.steps, isEmpty);
      expect(plan.viewerPending, isNull);
      expect(() => BeaconPlan.decode('[]'), throwsFormatException);
    });
  });

  group('outcomes and history', () {
    test('save outcome', () {
      final o = PlanSaveOutcome.decode(
        '{"outcome":"merged","revisionSeq":7,'
        '"theirStepIds":["PS1"],"theirActorIds":["U2"]}',
      );
      expect(o.kind, PlanSaveOutcomeKind.merged);
      expect(o.revisionSeq, 7);
      expect(o.theirStepIds, ['PS1']);
      expect(o.theirActorIds, ['U2']);
      expect(
        PlanSaveOutcome.decode('{"outcome":"noop","revisionSeq":3}').kind,
        PlanSaveOutcomeKind.noop,
      );
    });

    test('revision page', () {
      final page = PlanRevisionPage.decode(
        jsonEncode({
          'items': [
            {
              'seq': 5,
              'kind': 6,
              'actorId': 'ME',
              'comment': 'stuck',
              'restoredFromSeq': null,
              'changes': [
                {'op': 'cantMake', 'stepId': 'PS2', 'title': 'Bring boards'},
              ],
              'createdAt': '2026-10-12T10:07:00.000Z',
            },
            {
              'seq': 4,
              'kind': 2,
              'actorId': 'U2',
              'comment': '',
              'restoredFromSeq': 2,
              'changes': [
                {'op': 'added', 'stepId': 'PS4', 'title': 'Return the cart'},
              ],
              'createdAt': '2026-10-12T07:10:00.000Z',
            },
          ],
          'names': {'U2': 'Olga'},
          'nextBeforeSeq': 4,
        }),
      );
      expect(page.items, hasLength(2));
      expect(page.items.first.kind, PlanRevisionKind.cantMakeChat);
      expect(page.items.first.changes, isEmpty);
      expect(page.items.last.kind, PlanRevisionKind.restored);
      expect(page.items.last.restoredFromSeq, 2);
      expect(page.items.last.changes.single.op, PlanChangeOp.added);
      expect(page.names['U2'], 'Olga');
      expect(page.nextBeforeSeq, 4);
    });

    test('revision snapshot', () {
      final r = PlanRevisionSnapshot.decode(
        jsonEncode({
          'seq': 2,
          'kind': 1,
          'steps': [
            {'id': 'PS000000000001', 'title': 'A', 'assigneeId': 'U2'},
          ],
          'createdAt': '2026-10-12T07:10:00.000Z',
        }),
      );
      expect(r.seq, 2);
      expect(r.snapshot.steps.single.assigneeId, 'U2');
    });
  });

  group('exceptions', () {
    test('1330 carries currentSeq and conflict ids', () {
      expect(
        () => throwIfBeaconPlanError(1330, {
          'code': '1330',
          'currentSeq': 6,
          'conflictStepIds': ['PS1', 'PS2'],
        }),
        throwsA(
          isA<PlanEditConflictException>()
              .having((e) => e.currentSeq, 'currentSeq', 6)
              .having((e) => e.conflictStepIds, 'ids', ['PS1', 'PS2']),
        ),
      );
    });

    test('1331..1338 map to typed exceptions; others pass through', () {
      const expected = <int, Type>{
        1331: PlanStepNotFoundException,
        1332: PlanNotEditableException,
        1333: PlanActionStaleException,
        1334: PlanRestoreSourceMissingException,
        1335: PlanRateLimitedException,
        1336: PlanAssigneeNotAdmittedException,
        1337: PlanTooLargeException,
        1338: PlanDisabledException,
      };
      for (final MapEntry(key: code, value: type) in expected.entries) {
        try {
          throwIfBeaconPlanError(code, null);
          fail('no throw for $code');
        } on BeaconPlanException catch (e) {
          expect(e.runtimeType, type);
        }
      }
      expect(() => throwIfBeaconPlanError(1329, null), returnsNormally);
      expect(() => throwIfBeaconPlanError(null, null), returnsNormally);
    });
  });

  group('PlanConflict.resolve', () {
    const a = PlanStepSnapshot(id: 'PSa', title: 'A');
    const b = PlanStepSnapshot(id: 'PSb', title: 'B');
    const base = PlanSnapshot([a, b]);
    final theirs = PlanSnapshot([a.copyWith(title: 'A theirs'), b]);
    final mine = PlanSnapshot([
      a.copyWith(title: 'A mine'),
      b.copyWith(title: 'B mine'),
    ]);
    final conflict = PlanConflict(
      base: base,
      theirs: theirs,
      mine: mine,
      currentSeq: 3,
      stepIds: const ['PSa'],
    );

    test('mine keeps my content and my other edits', () {
      final r = conflict.resolve({'PSa': PlanConflictChoice.mine});
      expect(r.steps.map((s) => s.title), ['A mine', 'B mine']);
    });

    test('theirs takes their content but keeps my other edits', () {
      final r = conflict.resolve({'PSa': PlanConflictChoice.theirs});
      expect(r.steps.map((s) => s.title), ['A theirs', 'B mine']);
    });

    test('their removal wins when chosen', () {
      final c = PlanConflict(
        base: base,
        theirs: const PlanSnapshot([b]),
        mine: mine,
        currentSeq: 3,
        stepIds: const ['PSa'],
      );
      expect(
        c.resolve({'PSa': PlanConflictChoice.theirs}).ids,
        ['PSb'],
      );
      expect(
        c.resolve({'PSa': PlanConflictChoice.mine}).ids,
        ['PSa', 'PSb'],
      );
    });
  });

  group('buildPlanListItems', () {
    final plan = BeaconPlan.decode(planJson());

    test('now line sits after the last started step', () {
      final items = buildPlanListItems(
        steps: plan.steps,
        filter: const PlanFilter.all(),
        viewerId: 'ME',
        now: DateTime.utc(2026, 10, 12, 10, 20),
      );
      final kinds = [
        for (final i in items)
          switch (i) {
            PlanListDay() => 'day',
            PlanListNow() => 'now',
            PlanListStep(:final step) => step.id.substring(12),
          },
      ];
      expect(kinds.where((k) => k == 'now'), hasLength(1));
      expect(kinds.indexOf('now'), kinds.indexOf('02') + 1);
      expect(kinds.first, 'day');
    });

    test('Mine keeps my steps and dims neighbours', () {
      final items = buildPlanListItems(
        steps: plan.steps,
        filter: const PlanFilter.mine(),
        viewerId: 'ME',
        now: DateTime.utc(2026, 10, 12, 7),
      ).whereType<PlanListStep>().toList();
      expect(items.map((i) => (i.step.id.substring(12), i.dimmed)), [
        ('01', true),
        ('02', false),
        ('03', false),
        ('04', true),
      ]);
    });

    test('unassigned filter', () {
      final items = buildPlanListItems(
        steps: plan.steps,
        filter: const PlanFilter.unassigned(),
        viewerId: 'ME',
        now: DateTime.utc(2026, 10, 12, 7),
      ).whereType<PlanListStep>();
      expect(items.single.step.id, 'PS000000000004');
    });
  });
}
