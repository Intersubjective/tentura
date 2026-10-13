import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';

final _t0 = DateTime.utc(2026, 10, 12, 8);

DateTime _at(int min) => _t0.add(Duration(minutes: min));

PlanStepSnapshot _s(String id, {int? startMin, int? endMin}) =>
    PlanStepSnapshot(
      id: id,
      title: id,
      startAt: startMin == null ? null : _at(startMin),
      endAt: endMin == null ? null : _at(endMin),
    );

List<String> _ordered(List<PlanStepSnapshot> steps) => [
  for (final s in orderPlanChronologically<PlanStepSnapshot>(
    steps,
    startOf: (s) => s.startAt,
    endOf: (s) => s.endAt,
  ))
    s.id,
];

bool _isOrdered(List<PlanStepSnapshot> steps) =>
    isPlanChronological<PlanStepSnapshot>(
      steps,
      startOf: (s) => s.startAt,
      endOf: (s) => s.endAt,
    );

void main() {
  group('orderPlanChronologically', () {
    test('keeps an already sorted plan in the same order', () {
      final steps = [
        _s('a', startMin: 0),
        _s('b'),
        _s('c', startMin: 30),
        _s('d', startMin: 60),
      ];
      expect(_ordered(steps), ['a', 'b', 'c', 'd']);
    });

    test(
      'moves a timed step to its anchor with the untimed steps after it',
      () {
        final steps = [
          _s('late', startMin: 60),
          _s('late-note'),
          _s('early', startMin: 10),
          _s('early-note-1'),
          _s('early-note-2'),
        ];
        expect(_ordered(steps), [
          'early',
          'early-note-1',
          'early-note-2',
          'late',
          'late-note',
        ]);
      },
    );

    test('keeps untimed steps before the first timed step at the front', () {
      final steps = [
        _s('intro-1'),
        _s('intro-2'),
        _s('late', startMin: 60),
        _s('early', startMin: 10),
      ];
      expect(_ordered(steps), ['intro-1', 'intro-2', 'early', 'late']);
    });

    test('sorts an end-only step by its end instant', () {
      final steps = [
        _s('start-45', startMin: 45),
        _s('end-only-20', endMin: 20),
        _s('start-30', startMin: 30),
      ];
      expect(_ordered(steps), ['end-only-20', 'start-30', 'start-45']);
    });

    test('anchors on the start instant when both start and end are set', () {
      final steps = [
        _s('b', startMin: 50, endMin: 55),
        _s('a', startMin: 10, endMin: 90),
      ];
      expect(_ordered(steps), ['a', 'b']);
    });

    test('keeps input order among steps with equal anchors', () {
      final steps = [
        _s('x', startMin: 30),
        _s('y', endMin: 30),
        _s('first', startMin: 5),
        _s('z', startMin: 30),
      ];
      expect(_ordered(steps), ['first', 'x', 'y', 'z']);
    });

    test('compares instants in UTC regardless of the zone they carry', () {
      final local = DateTime.fromMillisecondsSinceEpoch(
        _at(20).millisecondsSinceEpoch,
      );
      final steps = [
        PlanStepSnapshot(
          id: 'later',
          title: 'later',
          startAt: _at(40),
        ),
        PlanStepSnapshot(
          id: 'sooner',
          title: 'sooner',
          startAt: local,
        ),
      ];
      expect(_ordered(steps), ['sooner', 'later']);
    });

    test('leaves a plan without timed steps unchanged', () {
      final steps = [_s('c'), _s('a'), _s('b')];
      expect(_ordered(steps), ['c', 'a', 'b']);
    });

    test('returns an empty list for an empty plan', () {
      expect(_ordered(const []), isEmpty);
    });

    test('does not mutate the input list', () {
      final steps = [_s('late', startMin: 60), _s('early', startMin: 10)];
      _ordered(steps);
      expect([for (final s in steps) s.id], ['late', 'early']);
    });

    test('applying it twice gives the same order as applying it once', () {
      final steps = [
        _s('n0'),
        _s('t60', startMin: 60),
        _s('t60-note'),
        _s('e20', endMin: 20),
        _s('t20', startMin: 20),
        _s('t20-note'),
        _s('t5', startMin: 5),
      ];
      final once = orderPlanChronologically<PlanStepSnapshot>(
        steps,
        startOf: (s) => s.startAt,
        endOf: (s) => s.endAt,
      );
      expect(_ordered(once), [for (final s in once) s.id]);
    });

    test('works on any step type through the accessors', () {
      final items = [
        (name: 'b', at: _at(30)),
        (name: 'a', at: _at(10)),
      ];
      final out = orderPlanChronologically<({String name, DateTime at})>(
        items,
        startOf: (e) => e.at,
        endOf: (_) => null,
      );
      expect([for (final e in out) e.name], ['a', 'b']);
    });
  });

  group('isPlanChronological', () {
    test('is true for a plan already in canonical order', () {
      expect(
        _isOrdered([
          _s('intro'),
          _s('a', startMin: 0),
          _s('note'),
          _s('b', startMin: 30),
        ]),
        isTrue,
      );
    });

    test('is true for an empty plan', () {
      expect(_isOrdered(const []), isTrue);
    });

    test('is false when a timed step precedes an earlier one', () {
      expect(
        _isOrdered([_s('late', startMin: 60), _s('early', startMin: 10)]),
        isFalse,
      );
    });

    test('is false when an end-only step sits after a later start', () {
      expect(
        _isOrdered([_s('s', startMin: 45), _s('e', endMin: 20)]),
        isFalse,
      );
    });

    test(
      'agrees with the ordering function on whether the input order holds',
      () {
        final inputs = [
          [_s('a', startMin: 0), _s('b', startMin: 10)],
          [_s('b', startMin: 10), _s('a', startMin: 0)],
          [_s('n'), _s('b', startMin: 10), _s('x'), _s('a', startMin: 0)],
          [_s('x', startMin: 5), _s('y', endMin: 5), _s('z', startMin: 5)],
          [_s('u1'), _s('u2')],
        ];
        for (final steps in inputs) {
          final sameOrder =
              _ordered(steps).join(',') ==
              [for (final s in steps) s.id].join(',');
          expect(
            _isOrdered(steps),
            sameOrder,
            reason: steps.map((s) => s.id).join(','),
          );
        }
      },
    );
  });

  group('PlanSnapshot.chronological', () {
    test('returns a snapshot with steps in canonical order', () {
      final snap = PlanSnapshot([
        _s('intro'),
        _s('late', startMin: 60),
        _s('late-note'),
        _s('early', startMin: 10),
      ]);
      expect(snap.chronological().ids, ['intro', 'early', 'late', 'late-note']);
    });

    test('leaves the original snapshot untouched', () {
      final snap = PlanSnapshot([
        _s('late', startMin: 60),
        _s('early', startMin: 10),
      ])..chronological();
      expect(snap.ids, ['late', 'early']);
    });
  });
}
