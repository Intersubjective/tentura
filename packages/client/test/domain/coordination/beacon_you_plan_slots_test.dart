import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/plan/plan_schedule.dart';

import 'package:tentura/domain/coordination/beacon_you_plan_slots.dart';

final _now = DateTime.utc(2026, 10, 12, 10, 20);

PlanStepState _step(
  String id, {
  String? assignee = 'ME',
  DateTime? start,
  DateTime? end,
  DateTime? done,
}) => PlanStepState(
  id: id,
  title: 'Step $id',
  assigneeId: assignee,
  startAt: start,
  endAt: end,
  doneAt: done,
);

PlanYouInput _input(
  List<PlanStepState> steps, {
  Set<String> pending = const {},
}) => PlanYouInput(
  schedule: PlanSchedule.forViewer('ME', steps, _now),
  pendingAck: pending.isNotEmpty,
  pendingStepIds: pending,
);

BeaconYouPlanSlots _derive(
  PlanYouInput input, {
  bool system = false,
  bool finished = false,
}) => deriveBeaconYouPlanSlots(
  plan: input,
  systemOccupiesYou: system,
  requestFinished: finished,
  now: _now,
);

void main() {
  final started = _step('a', start: DateTime.utc(2026, 10, 12, 10, 10));
  final overdue = _step(
    'late',
    start: DateTime.utc(2026, 10, 12, 9),
    end: DateTime.utc(2026, 10, 12, 9, 30),
  );
  final later = _step('b', start: DateTime.utc(2026, 10, 12, 11, 30));
  final othersStep = _step(
    'o',
    assignee: 'OLGA',
    start: DateTime.utc(2026, 10, 12, 8),
  );

  test('no steps for the viewer: no plan rows', () {
    final slots = _derive(_input([othersStep]));
    expect(slots.isEmpty, isTrue);
  });

  test('a finished Request shows no plan rows', () {
    final slots = _derive(_input([started, later]), finished: true);
    expect(slots.isEmpty, isTrue);
  });

  test('current step takes YOU with actions; NEXT is the next step', () {
    final slots = _derive(_input([othersStep, started, later]));
    expect(slots.you?.kind, PlanYouSlotKind.step);
    expect(slots.you?.step?.id, 'a');
    expect(slots.you?.actionable, isTrue);
    expect(slots.you?.canTick, isTrue);
    expect(slots.you?.overdueBy, isNull);
    expect(slots.byPlan, isNull);
    expect(slots.next?.step?.id, 'b');
    expect(slots.next?.actionable, isFalse);
    expect(slots.next?.alsoRunning, isFalse);
  });

  test('overdue goes first; the other active step is «also running»', () {
    final slots = _derive(_input([started, overdue, later]));
    expect(slots.you?.step?.id, 'late');
    expect(slots.you?.overdueBy, const Duration(minutes: 50));
    expect(slots.next?.step?.id, 'a');
    expect(slots.next?.alsoRunning, isTrue);
  });

  test('only future steps: free until the next start, NEXT = that step', () {
    final slots = _derive(_input([later]));
    expect(slots.you?.kind, PlanYouSlotKind.freeUntil);
    expect(slots.you?.freeUntil, later.startAt);
    expect(slots.next?.step?.id, 'b');
  });

  test('an untimed step waiting on the previous one: NEXT only', () {
    final blocker = _step('x', assignee: 'OLGA');
    final mine = _step('u');
    final slots = _derive(_input([blocker, mine]));
    expect(slots.you, isNull);
    expect(slots.next?.step?.id, 'u');
  });

  test('a system situation pushes the current step to BY PLAN', () {
    final slots = _derive(_input([started, later]), system: true);
    expect(slots.you, isNull);
    expect(slots.byPlan?.step?.id, 'a');
    expect(slots.byPlan?.actionable, isTrue);
    expect(slots.next?.step?.id, 'b');
  });

  test('pending change takes YOU; the untouched current step is BY PLAN', () {
    final slots = _derive(_input([started, later], pending: {'b'}));
    expect(slots.you?.kind, PlanYouSlotKind.pendingAck);
    expect(slots.you?.canTick, isFalse);
    expect(slots.byPlan?.step?.id, 'a');
    expect(slots.next?.step?.id, 'b');
  });

  test('pending change on the current step offers «Готово» in YOU', () {
    final slots = _derive(_input([started, later], pending: {'a'}));
    expect(slots.you?.kind, PlanYouSlotKind.pendingAck);
    expect(slots.you?.canTick, isTrue);
    expect(slots.you?.step?.id, 'a');
    expect(slots.byPlan, isNull);
    expect(slots.next?.step?.id, 'b');
  });

  test('system + pending: pending in BY PLAN, current drops to NEXT', () {
    final slots = _derive(
      _input([started, later], pending: {'b'}),
      system: true,
    );
    expect(slots.you, isNull);
    expect(slots.byPlan?.kind, PlanYouSlotKind.pendingAck);
    expect(slots.next?.step?.id, 'a');
    expect(slots.next?.actionable, isFalse);
  });

  test('a pending change never drops, even with nothing else', () {
    final slots = _derive(_input([othersStep], pending: {'gone'}));
    expect(slots.you?.kind, PlanYouSlotKind.pendingAck);
    expect(slots.byPlan, isNull);
    expect(slots.next, isNull);
  });

  test('done steps are ignored', () {
    final done = _step(
      'd',
      start: DateTime.utc(2026, 10, 12, 9),
      done: DateTime.utc(2026, 10, 12, 9, 10),
    );
    final slots = _derive(_input([done, later]));
    expect(slots.you?.kind, PlanYouSlotKind.freeUntil);
  });
}
