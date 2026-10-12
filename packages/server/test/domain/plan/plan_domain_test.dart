import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';

final _t0 = DateTime.utc(2026, 10, 12, 8);

PlanStepSnapshot _s(
  String id, {
  String? title,
  String description = '',
  String? who,
  int? startMin,
  int? endMin,
}) => PlanStepSnapshot(
  id: id,
  title: title ?? id,
  description: description,
  assigneeId: who,
  startAt: startMin == null ? null : _t0.add(Duration(minutes: startMin)),
  endAt: endMin == null ? null : _t0.add(Duration(minutes: endMin)),
);

PlanStepState _st(
  String id, {
  String? who,
  int? startMin,
  int? endMin,
  int? doneMin,
}) => PlanStepState(
  id: id,
  title: id,
  assigneeId: who,
  startAt: startMin == null ? null : _t0.add(Duration(minutes: startMin)),
  endAt: endMin == null ? null : _t0.add(Duration(minutes: endMin)),
  doneAt: doneMin == null ? null : _t0.add(Duration(minutes: doneMin)),
);

DateTime _at(int min) => _t0.add(Duration(minutes: min));

void main() {
  group('PlanSnapshot', () {
    test('round-trips through JSON with UTC millisecond instants', () {
      final snap = PlanSnapshot([
        _s('PSa', who: 'U1', startMin: 30, endMin: 90, description: 'd'),
        _s('PSb'),
      ]);
      final back = PlanSnapshot.fromJson(snap.encode());
      expect(back.sameAs(snap), isTrue);
      expect(back.steps.first.startAt!.isUtc, isTrue);
      expect(snap.toJson().first['startAt'], '2026-10-12T08:30:00.000Z');
    });

    test('tolerates garbage', () {
      expect(PlanSnapshot.fromJson(null).isEmpty, isTrue);
      expect(PlanSnapshot.fromJson('').isEmpty, isTrue);
      expect(PlanSnapshot.fromJson(const ['x']).isEmpty, isTrue);
    });
  });

  group('PlanDiff', () {
    test('reports add, remove, retitle, retime, reassign, describe, move', () {
      final a = PlanSnapshot([
        _s('A', who: 'U1', startMin: 0),
        _s('B', who: 'U2'),
        _s('C', who: 'U3'),
        _s('D'),
      ]);
      final b = PlanSnapshot([
        _s('C', who: 'U3', description: 'more'),
        _s('A', who: 'U1', startMin: 60),
        _s('B', title: 'B2', who: 'U4'),
        _s('E', who: 'U5'),
      ]);
      final ops = PlanDiff.between(a, b).map((c) => '${c.op.wire}:${c.stepId}');
      expect(
        ops,
        containsAll([
          'redescribed:C',
          'retimed:A',
          'retitled:B',
          'reassigned:B',
          'added:E',
          'removed:D',
        ]),
      );
      // Moving C to the front is one move, not three.
      expect(ops.where((o) => o.startsWith('moved')), ['moved:C']);
    });

    test('affected people: timing, title, assignee and removal need ack', () {
      final a = PlanSnapshot([
        _s('A', who: 'U1', startMin: 0),
        _s('B', who: 'U2'),
        _s('C', who: 'U3'),
        _s('D', who: 'U6'),
      ]);
      final b = PlanSnapshot([
        _s('A', who: 'U1', startMin: 30),
        _s('B', who: 'U4'),
        _s('C', who: 'U3', description: 'only details'),
      ]);
      expect(
        PlanDiff.affectedUserIds(PlanDiff.between(a, b)),
        {'U1', 'U2', 'U4', 'U6'},
      );
    });

    test('changes survive JSON', () {
      final c = PlanDiff.between(
        PlanSnapshot([_s('A', startMin: 0)]),
        PlanSnapshot([_s('A', startMin: 15)]),
      ).single;
      final back = PlanChange.fromJson(c.toJson());
      expect(back.op, PlanChangeOp.retimed);
      expect(back.toStartAt, _at(15));
      expect(back.fromStartAt, _at(0));
    });
  });

  group('PlanMerge.threeWay', () {
    final base = PlanSnapshot([_s('A'), _s('B'), _s('C')]);

    test('takes each side where only it changed', () {
      final theirs = PlanSnapshot([_s('A', title: 'A*'), _s('B'), _s('C')]);
      final mine = PlanSnapshot([_s('A'), _s('B', who: 'U1'), _s('C')]);
      final r = PlanMerge.threeWay(base, theirs, mine) as PlanMergeMerged;
      expect(r.snapshot.byId['A']!.title, 'A*');
      expect(r.snapshot.byId['B']!.assigneeId, 'U1');
      expect(r.theirChangedStepIds, {'A'});
    });

    test('conflicts only when both changed the same step differently', () {
      final theirs = PlanSnapshot([_s('A', title: 'x'), _s('B'), _s('C')]);
      final mine = PlanSnapshot([_s('A', title: 'y'), _s('B'), _s('C')]);
      expect(
        (PlanMerge.threeWay(base, theirs, mine) as PlanMergeConflict).stepIds,
        ['A'],
      );
      final same = PlanSnapshot([_s('A', title: 'x'), _s('B'), _s('C')]);
      expect(PlanMerge.threeWay(base, theirs, same), isA<PlanMergeMerged>());
    });

    test('edit against removal conflicts; two removals agree', () {
      final theirs = PlanSnapshot([_s('B'), _s('C')]);
      final mineEdit = PlanSnapshot([_s('A', title: 'A!'), _s('B'), _s('C')]);
      expect(
        PlanMerge.threeWay(base, theirs, mineEdit),
        isA<PlanMergeConflict>(),
      );
      final mineRemove = PlanSnapshot([_s('B'), _s('C')]);
      final r = PlanMerge.threeWay(base, theirs, mineRemove) as PlanMergeMerged;
      expect(r.snapshot.ids, ['B', 'C']);
    });

    test('order never conflicts; my moves and additions follow my order', () {
      final theirs = PlanSnapshot([_s('A'), _s('B'), _s('C'), _s('T')]);
      final mine = PlanSnapshot([_s('C'), _s('A'), _s('M'), _s('B')]);
      final r = PlanMerge.threeWay(base, theirs, mine) as PlanMergeMerged;
      expect(r.snapshot.ids, ['C', 'A', 'M', 'B', 'T']);
    });

    test('when both moved the same step, theirs wins', () {
      final theirs = PlanSnapshot([_s('B'), _s('C'), _s('A')]);
      final mine = PlanSnapshot([_s('B'), _s('A'), _s('C')]);
      final r = PlanMerge.threeWay(base, theirs, mine) as PlanMergeMerged;
      expect(r.snapshot.ids, ['B', 'C', 'A']);
    });
  });

  group('PlanSchedule.forViewer', () {
    test('timed step is current once started; next waits', () {
      final steps = [
        _st('A', who: 'me', startMin: 0, endMin: 30),
        _st('B', who: 'me', startMin: 120),
      ];
      final s = PlanSchedule.forViewer('me', steps, _at(10));
      expect(s.current!.id, 'A');
      expect(s.next!.id, 'B');
      expect(s.freeUntil, isNull);
    });

    test('free until the next timed step', () {
      final steps = [_st('A', who: 'me', startMin: 60)];
      final s = PlanSchedule.forViewer('me', steps, _at(10));
      expect(s.current, isNull);
      expect(s.freeUntil, _at(60));
    });

    test('untimed step becomes current after the previous step is done', () {
      final open = [_st('A', who: 'other', startMin: 0), _st('B', who: 'me')];
      expect(PlanSchedule.forViewer('me', open, _at(5)).current, isNull);
      final done = [
        _st('A', who: 'other', startMin: 0, doneMin: 5),
        _st('B', who: 'me'),
      ];
      expect(PlanSchedule.forViewer('me', done, _at(6)).current!.id, 'B');
      expect(
        PlanSchedule.forViewer('me', [_st('X', who: 'me')], _at(0)).current!.id,
        'X',
      );
    });

    test('overdue steps go first; others are also running', () {
      final steps = [
        _st('A', who: 'me', startMin: 0, endMin: 120),
        _st('B', who: 'me', startMin: 5, endMin: 10),
      ];
      final s = PlanSchedule.forViewer('me', steps, _at(20));
      expect(s.current!.id, 'B');
      expect(s.alsoActive.map((e) => e.id), ['A']);
    });
  });

  group('overdue', () {
    test('after end; without end, start + 15 min; untimed never', () {
      expect(_st('A', startMin: 0, endMin: 60).isOverdueAt(_at(59)), isFalse);
      expect(_st('A', startMin: 0, endMin: 60).isOverdueAt(_at(60)), isTrue);
      expect(_st('A', startMin: 0).isOverdueAt(_at(14)), isFalse);
      expect(
        _st('A', startMin: 0).overdueBy(_at(20)),
        const Duration(minutes: 5),
      );
      expect(_st('A').isOverdueAt(_at(10000)), isFalse);
      expect(_st('A', startMin: 0, doneMin: 1).isOverdueAt(_at(100)), isFalse);
    });
  });

  group('PlanSchedule.effectiveNow', () {
    final steps = [
      _st('A', who: 'U1', startMin: 0),
      _st('B', who: 'U2', startMin: 60),
      _st('C'),
    ];

    test('plan step wins when it started after the manual line was set', () {
      final now = PlanSchedule.effectiveNow(
        manualText: 'waiting',
        manualSetAt: _at(30),
        steps: steps,
        openFamily: true,
        now: _at(61),
      );
      expect(now.isPlan, isTrue);
      expect(now.step!.id, 'B');
      expect(now.index, 2);
      expect(now.count, 3);
    });

    test('manual line written later wins', () {
      final now = PlanSchedule.effectiveNow(
        manualText: 'stuck',
        manualSetAt: _at(65),
        steps: steps,
        openFamily: true,
        now: _at(70),
      );
      expect(now.source, PlanNowSource.manual);
    });

    test('review and closed requests keep the manual line', () {
      final now = PlanSchedule.effectiveNow(
        manualText: '',
        manualSetAt: null,
        steps: steps,
        openFamily: false,
        now: _at(70),
      );
      expect(now.source, PlanNowSource.none);
    });

    test('a step ticked before its start never takes NOW', () {
      final now = PlanSchedule.effectiveNow(
        manualText: '',
        manualSetAt: null,
        steps: [
          _st('A', startMin: 0),
          _st('B', startMin: 60, doneMin: 30),
        ],
        openFamily: true,
        now: _at(70),
      );
      expect(now.step!.id, 'A');
    });
  });
}
