@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/widget/beacon_plan_surface.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_people_matrix.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_surface_tabs.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_plan_test_support.dart';

final _now = DateTime.utc(2026, 10, 12, 10, 20);

const _people = [
  Profile(id: 'U2', displayName: 'Olga'),
  Profile(id: 'ME', displayName: 'Ivan'),
];

PlanStep _step(String id, {DateTime? start, DateTime? end, String? who}) =>
    PlanStep(id: id, title: id, startAt: start, endAt: end, assigneeId: who);

Future<PlanCubit> _pumpView(
  WidgetTester tester,
  FakeBeaconPlanRepository repo, {
  required double width,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = PlanCubit(
    beaconId: 'B1',
    viewerId: 'ME',
    planCase: planCaseFor(repo),
    clock: () => _now,
  );
  await tester.runAsync(cubit.load);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: BeaconPlanView(
            admitted: _people,
            planCase: planCaseFor(repo),
            clock: () => _now,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  group('blocks', () {
    final start = DateTime.utc(2026, 10, 12, 10);
    final end = DateTime.utc(2026, 10, 12, 11, 30);

    test('start and end span the interval', () {
      final b = planMatrixBlocks([_step('a', start: start, end: end)]).single;
      expect(b.start, start);
      expect(b.end, end);
      expect(b.openStart || b.openEnd, isFalse);
    });

    test('start only: a 30-min block with an open end', () {
      final b = planMatrixBlocks([_step('a', start: start)]).single;
      expect(b.end, start.add(const Duration(minutes: 30)));
      expect(b.openEnd, isTrue);
    });

    test('end only: a 30-min block ending at endAt, open start', () {
      final b = planMatrixBlocks([_step('a', end: end)]).single;
      expect(b.end, end);
      expect(b.start, end.subtract(const Duration(minutes: 30)));
      expect(b.openStart, isTrue);
      expect(b.openEnd, isFalse);
    });

    test('untimed steps are not blocks', () {
      expect(planMatrixBlocks([_step('a')]), isEmpty);
    });

    test('rows: assignees in plan order, «no assignee» last', () {
      expect(
        planMatrixRows([
          _step('a', who: 'B'),
          _step('b'),
          _step('c', who: 'A'),
          _step('d', who: 'B'),
        ]),
        ['B', 'A', null],
      );
    });

    test('opens on today, else the first later day', () {
      final days = [DateTime(2026, 10, 11), DateTime(2026, 10, 13)];
      expect(planMatrixInitialDay(days, DateTime(2026, 10, 12, 9)), 1);
      expect(planMatrixInitialDay(days, DateTime(2026, 10, 14)), 1);
      expect(planMatrixInitialDay(days, DateTime(2026, 10, 10)), 0);
    });
  });

  testWidgets('narrow panel: no list / people toggle', (tester) async {
    final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
    final cubit = await _pumpView(tester, repo, width: 500);
    expect(find.byKey(BeaconPlanView.viewPeopleKey), findsNothing);
    expect(find.byKey(PlanPeopleMatrix.matrixKey), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('wide panel: «By people» shows people × time', (tester) async {
    final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
    final cubit = await _pumpView(tester, repo, width: 700);
    expect(find.byKey(BeaconPlanView.viewPeopleKey), findsOneWidget);
    await tester.tap(find.byKey(BeaconPlanView.viewPeopleKey));
    await tester.pump();

    expect(find.byKey(PlanPeopleMatrix.matrixKey), findsOneWidget);
    expect(find.byKey(PlanPeopleMatrix.rowKey('U2')), findsOneWidget);
    expect(find.byKey(PlanPeopleMatrix.rowKey('ME')), findsOneWidget);
    expect(find.byKey(PlanPeopleMatrix.rowKey(null)), findsOneWidget);
    for (final id in ['PS000000000001', 'PS000000000002', 'PS000000000003']) {
      expect(find.byKey(PlanPeopleMatrix.blockKey(id)), findsOneWidget);
    }
    // The untimed step is listed aside, not on the axis.
    expect(find.byKey(PlanPeopleMatrix.untimedKey), findsOneWidget);
    expect(
      find.byKey(PlanPeopleMatrix.blockKey('PS000000000004')),
      findsNothing,
    );
    expect(find.textContaining('Return the cart'), findsOneWidget);
    expect(find.byKey(PlanPeopleMatrix.nowLineKey), findsOneWidget);

    // A 30-min open-ended block is as wide as half an hour.
    final open = tester.getSize(
      find.byKey(PlanPeopleMatrix.blockKey('PS000000000003')),
    );
    final full = tester.getSize(
      find.byKey(PlanPeopleMatrix.blockKey('PS000000000002')),
    );
    expect(open.width, closeTo(full.width, 1));

    await tester.tap(find.byKey(BeaconPlanView.viewListKey));
    await tester.pump();
    expect(find.byKey(PlanPeopleMatrix.matrixKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  group('Plan tab badge', () {
    PlanState state(BeaconPlan plan) =>
        PlanState(beaconId: 'B1', viewerId: 'ME', plan: plan);

    test('a running step of mine: dot', () {
      final badge = BeaconPlanTabBadge.of(
        state(BeaconPlan.decode(planJson())),
        _now,
      );
      expect(badge.overdue, 0);
      expect(badge.dot, isTrue);
    });

    test('my overdue steps: count, no dot', () {
      final badge = BeaconPlanTabBadge.of(
        state(BeaconPlan.decode(planJson())),
        DateTime.utc(2026, 10, 12, 10, 45),
      );
      expect(badge.overdue, 1);
      expect(badge.dot, isFalse);
    });

    test('changes to confirm: dot even with nothing running', () {
      final plan = BeaconPlan.decode(
        planJson(
          viewerPending: {
            'fromSeq': 3,
            'headSeq': 4,
            'changes': [
              {'seq': 4, 'op': 'removed', 'stepId': 'PSx', 'title': 'Gone'},
            ],
          },
        ),
      );
      final badge = BeaconPlanTabBadge.of(
        state(plan),
        DateTime.utc(2026, 10, 12, 7),
      );
      expect(badge.dot, isTrue);
    });

    test('nothing of mine: no mark', () {
      final badge = BeaconPlanTabBadge.of(
        state(BeaconPlan.decode(planJson())),
        DateTime.utc(2026, 10, 12, 7),
      );
      expect(badge.overdue, 0);
      expect(badge.dot, isFalse);
    });
  });

  testWidgets('tabs render a dot without a count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: TenturaUnderlineTabs(
            tabs: const ['Now', 'Plan'],
            selectedIndex: 0,
            onChanged: (_) {},
            dots: const [false, true],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('tentura-tab-dot')), findsOneWidget);
  });
}
