import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/features/beacon_plan/data/model/beacon_plan_error_mapper.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_conflict.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_revision.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_state.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

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
      expect(plan.editable, isTrue);
      expect(plan.steps, hasLength(4));
      expect(plan.doneCount, 1);
      expect(plan.lastEditedAt, DateTime.utc(2026, 10, 12, 7, 10));
      final boards = plan.stepById('PS000000000002')!;
      expect(boards.assigneeAckPending, isTrue);
      expect(boards.endAt, DateTime.utc(2026, 10, 12, 10, 30));
      expect(plan.stepById('PS000000000004')!.assigneeId, isNull);
      expect(plan.memberOf('ME')!.ackedAt, DateTime.utc(2026, 10, 12, 6));
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
              'kind': 4,
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
      expect(page.items.first.kind, PlanRevisionKind.cantMake);
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
    test('1336 carries currentSeq and conflict ids', () {
      expect(
        () => throwIfBeaconPlanError(1336, {
          'code': '1336',
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

    test('1337..1345 map to typed exceptions; others pass through', () {
      const expected = <int, Type>{
        1337: PlanStepNotFoundException,
        1338: PlanNotEditableException,
        1339: PlanActionStaleException,
        1340: PlanRestoreSourceMissingException,
        1341: PlanRateLimitedException,
        1342: PlanAssigneeNotAdmittedException,
        1343: PlanTooLargeException,
        1344: PlanDisabledException,
        1345: PlanInvalidException,
      };
      for (final MapEntry(key: code, value: type) in expected.entries) {
        try {
          throwIfBeaconPlanError(code, null);
          fail('no throw for $code');
        } on BeaconPlanException catch (e) {
          expect(e.runtimeType, type);
        }
      }
      expect(() => throwIfBeaconPlanError(1335, null), returnsNormally);
      expect(() => throwIfBeaconPlanError(null, null), returnsNormally);
    });
  });

  group('planTakeTheirSteps', () {
    const a = PlanStepSnapshot(id: 'PSa', title: 'A');
    const b = PlanStepSnapshot(id: 'PSb', title: 'B');
    const c = PlanStepSnapshot(id: 'PSc', title: 'C');
    final mine = PlanSnapshot([
      a.copyWith(title: 'A mine'),
      b.copyWith(title: 'B mine'),
    ]);

    test('a conflicting step takes their content, my other edits stay', () {
      final theirs = PlanSnapshot([a.copyWith(title: 'A theirs'), b]);
      final r = planTakeTheirSteps(mine, theirs, const ['PSa']);
      expect(r.steps.map((s) => s.title), ['A theirs', 'B mine']);
    });

    test('their removal wins', () {
      final r = planTakeTheirSteps(mine, const PlanSnapshot([b]), const [
        'PSa',
      ]);
      expect(r.ids, ['PSb']);
    });

    test('a step only I removed comes back after its neighbour', () {
      final theirs = PlanSnapshot([a, b, c.copyWith(title: 'C theirs')]);
      final r = planTakeTheirSteps(mine, theirs, const ['PSc']);
      expect(r.ids, ['PSa', 'PSb', 'PSc']);
      expect(r.byId['PSc']!.title, 'C theirs');
    });
  });

  group('planStepWhenLabel', () {
    final l10n = L10nEn();

    setUpAll(() async {
      await initializeDateFormatting('en');
    });

    test('same-day range keeps day on start and time-only end', () {
      final start = DateTime(2026, 10, 12, 10);
      final end = DateTime(2026, 10, 12, 11, 30);
      final label = planStepWhenLabel(
        startAt: start,
        endAt: end,
        l10n: l10n,
      );
      expect(label, contains(planDayTime(start, l10n.localeName)));
      expect(label, contains(planTime(end, l10n.localeName)));
      expect(label, isNot(contains(planDayTime(end, l10n.localeName))));
    });

    test('untimed uses semantics copy', () {
      expect(
        planStepWhenLabel(startAt: null, endAt: null, l10n: l10n),
        l10n.planUntimedSemantics,
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
            PlanEditStep() => 'edit',
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

  group('plan rows grouped by day', () {
    // Local-zone wall times, so the day grouping is the same in any TZ.
    DateTime at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 10, day, hour, minute).toUtc();

    PlanStep timed(String id, DateTime start, [DateTime? end]) =>
        PlanStep(id: id, title: id, startAt: start, endAt: end);

    String label(PlanListItem i) => switch (i) {
      PlanListDay(:final day) => 'day ${day.toLocal().day}',
      PlanListNow() => 'now',
      PlanListStep(:final step) => step.id,
      PlanEditStep(:final step) => step.id,
      _ => 'other',
    };

    test('Plan tab shows one header for a day stored out of order', () {
      final items = buildPlanListItems(
        steps: [
          timed('mon-a', at(12, 9)),
          timed('tue', at(13, 9)),
          timed('mon-b', at(12, 15)),
        ],
        filter: const PlanFilter.all(),
        viewerId: 'ME',
        now: at(11, 8),
      );
      expect(
        items.where((i) => i is! PlanListNow).map(label),
        ['day 12', 'mon-a', 'mon-b', 'day 13', 'tue'],
      );
      expect(items.whereType<PlanListDay>(), hasLength(2));
    });

    group('buildPlanEditItems', () {
      test('headers come in date order and untimed steps stay under the '
          'day of the timed step before them', () {
        final items = buildPlanEditItems([
          const PlanStepSnapshot(id: 'lead', title: 'lead'),
          PlanStepSnapshot(id: 'tue', title: 'tue', startAt: at(13, 10)),
          const PlanStepSnapshot(id: 'tue-after', title: 'tue-after'),
          PlanStepSnapshot(id: 'mon', title: 'mon', startAt: at(12, 9)),
          const PlanStepSnapshot(id: 'mon-after', title: 'mon-after'),
        ]);
        expect(items.map(label), [
          'lead',
          'day 12',
          'mon',
          'mon-after',
          'day 13',
          'tue',
          'tue-after',
        ]);
      });

      test('has no now line and no filtering', () {
        final items = buildPlanEditItems([
          PlanStepSnapshot(
            id: 'past',
            title: 'past',
            assigneeId: 'U2',
            startAt: DateTime.utc(2000),
          ),
          PlanStepSnapshot(id: 'future', title: 'future', startAt: at(12, 9)),
        ]);
        expect(items.whereType<PlanListNow>(), isEmpty);
        expect(items.whereType<PlanEditStep>(), hasLength(2));
      });

      test('days follow the viewer zone, not the UTC date', () {
        int localDays(Iterable<DateTime> instants) => {
          for (final t in instants)
            (t.toLocal().year, t.toLocal().month, t.toLocal().day),
        }.length;

        // Two instants one hour apart that straddle UTC midnight: the same
        // local day in any zone ahead of or behind UTC by 1h or more.
        final aroundUtcMidnight = [
          DateTime.utc(2026, 10, 12, 23, 30),
          DateTime.utc(2026, 10, 13, 0, 30),
        ];
        // Two instants one hour apart that straddle local midnight: the same
        // UTC day in any zone offset from UTC by 1h or more.
        final aroundLocalMidnight = [
          DateTime(2026, 10, 12, 23, 30).toUtc(),
          DateTime(2026, 10, 13, 0, 30).toUtc(),
        ];

        for (final instants in [aroundUtcMidnight, aroundLocalMidnight]) {
          final items = buildPlanEditItems([
            for (var i = 0; i < instants.length; i++)
              PlanStepSnapshot(id: 's$i', title: 's$i', startAt: instants[i]),
          ]);
          final days = items.whereType<PlanEditDay>().toList();
          expect(days, hasLength(localDays(instants)));
          PlanEditDay? current;
          for (final item in items) {
            if (item is PlanEditDay) {
              current = item;
            } else if (item is PlanEditStep) {
              expect(current, isNotNull, reason: 'a timed step has a header');
              expect(
                PlanDays.isSameDayLocal(current!.day, item.step.startAt!),
                isTrue,
                reason: 'every step sits under the header of its local day',
              );
            }
          }
        }
      });

      test('a later start-only step beats an earlier end for the per-day '
          'add', () {
        final items = buildPlanEditItems([
          PlanStepSnapshot(
            id: 'a',
            title: 'a',
            startAt: at(12, 9),
            endAt: at(12, 10),
          ),
          PlanStepSnapshot(id: 'b', title: 'b', startAt: at(12, 11)),
        ]);
        expect(items.whereType<PlanEditDay>().single.lastAt, at(12, 11));
      });

      test('an untimed step does not move the per-day add time', () {
        final items = buildPlanEditItems([
          PlanStepSnapshot(id: 'a', title: 'a', startAt: at(12, 9)),
          const PlanStepSnapshot(id: 'u', title: 'u'),
        ]);
        expect(items.whereType<PlanEditDay>().single.lastAt, at(12, 9));
      });

      test('Plan tab and editor group the same steps under the same days', () {
        final times = [
          at(13, 0, 30),
          at(12, 23, 30),
          DateTime.utc(2026, 10, 12, 23, 30),
          at(12, 9),
          DateTime.utc(2026, 10, 13, 0, 30),
        ];
        final list = buildPlanListItems(
          steps: [
            for (var i = 0; i < times.length; i++) timed('s$i', times[i]),
          ],
          filter: const PlanFilter.all(),
          viewerId: 'ME',
          now: at(11, 8),
        );
        final edit = buildPlanEditItems([
          for (var i = 0; i < times.length; i++)
            PlanStepSnapshot(id: 's$i', title: 's$i', startAt: times[i]),
        ]);
        expect(
          edit.map(label).toList(),
          list.where((i) => i is! PlanListNow).map(label).toList(),
        );
      });

      test('an empty plan has no rows', () {
        expect(buildPlanEditItems(const []), isEmpty);
      });

      test(
        'a day carries the latest end among its steps for a per-day add',
        () {
          final items = buildPlanEditItems([
            PlanStepSnapshot(
              id: 'a',
              title: 'a',
              startAt: at(12, 9),
              endAt: at(12, 9, 30),
            ),
            PlanStepSnapshot(
              id: 'b',
              title: 'b',
              startAt: at(12, 9, 45),
              endAt: at(12, 12),
            ),
            PlanStepSnapshot(id: 'c', title: 'c', startAt: at(12, 10)),
            PlanStepSnapshot(id: 'd', title: 'd', startAt: at(13, 14)),
          ]);
          final days = items.whereType<PlanEditDay>().toList();
          expect(days, hasLength(2));
          expect(days[0].day.toLocal().day, 12);
          expect(days[0].lastAt, at(12, 12));
          expect(days[1].day.toLocal().day, 13);
          expect(days[1].lastAt, at(13, 14), reason: 'start when no end');
        },
      );
    });
  });
}
