@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/screen/plan_edit_screen.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_step_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_plan_test_support.dart';

const _people = [Profile(id: 'ME', displayName: 'Ivan')];

String _iso(int day, int hour) =>
    DateTime(2026, 10, day, hour).toUtc().toIso8601String();

Map<String, Object?> _step(String id, {int? day, int hour = 9}) => {
  'id': id,
  'index': 1,
  'title': 'Step $id',
  'description': '',
  'assigneeId': null,
  'startAt': day == null ? null : _iso(day, hour),
  'endAt': null,
  'doneAt': null,
  'doneById': null,
  'contentSeq': 1,
  'ackSeq': 1,
  'assigneeAckPending': false,
};

/// Untimed `U`, then two steps on the 12th and two on the 13th.
BeaconPlan _plan() {
  final json = jsonDecode(planJson()) as Map<String, Object?>;
  json['steps'] = [
    _step('U'),
    _step('A', day: 12),
    _step('B', day: 12, hour: 10),
    _step('C', day: 13),
    _step('D', day: 13, hour: 10),
  ];
  return BeaconPlan.decode(jsonEncode(json));
}

Future<PlanEditCubit> _pump(WidgetTester tester) async {
  final repo = FakeBeaconPlanRepository(_plan());
  final cubit = PlanEditCubit(plan: repo.plan, planCase: planCaseFor(repo));
  addTearDown(cubit.close);
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider.value(
        value: cubit,
        child: PlanEditScreen(
          people: PlanPeople(admitted: _people),
          onClose: () {},
          onSaved: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

final _handles = find.bySemanticsLabel(RegExp('Drag to reorder'));

Finder _row(String id) => find.text('Step $id');

List<String> _ids(PlanEditCubit c) => [for (final s in c.state.steps) s.id];

void main() {
  group('plan editor day layout', () {
    testWidgets('steps on two days sit under two day headers in date order', (
      tester,
    ) async {
      await _pump(tester);

      final headers = find.byType(PlanDayHeader);
      expect(headers, findsNWidgets(2));
      final first = tester.getTopLeft(headers.at(0)).dy;
      final second = tester.getTopLeft(headers.at(1)).dy;
      expect(first, lessThan(second));
      expect(tester.widget<PlanDayHeader>(headers.at(0)).day.day, 12);
      expect(tester.widget<PlanDayHeader>(headers.at(1)).day.day, 13);
      // Day one's steps are above the second header, day two's below it.
      expect(tester.getTopLeft(_row('B')).dy, lessThan(second));
      expect(tester.getTopLeft(_row('C')).dy, greaterThan(second));
    });

    testWidgets('only untimed steps carry a reorder handle', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(_handles, findsOneWidget);
      final handle = tester.getCenter(_handles);
      expect(handle.dy, closeTo(tester.getCenter(_row('U')).dy, 40));
      semantics.dispose();
    });

    testWidgets("dragging an untimed step under the second day's first step "
        'lands it there', (tester) async {
      final semantics = tester.ensureSemantics();
      final cubit = await _pump(tester);
      expect(find.byType(PlanDayHeader), findsNWidgets(2));

      final handle = tester.getCenter(_handles);
      final target = tester.getCenter(_row('D')).dy - 8;
      final gesture = await tester.startGesture(handle);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(Offset(handle.dx, target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_ids(cubit), ['A', 'B', 'C', 'U', 'D']);
      semantics.dispose();
    });

    testWidgets('editing a step to another day re-renders it under that '
        "day's header", (tester) async {
      final cubit = await _pump(tester);
      final before = tester.getTopLeft(find.byType(PlanDayHeader).at(1)).dy;
      expect(tester.getTopLeft(_row('A')).dy, lessThan(before));

      final a = cubit.state.steps.firstWhere((s) => s.id == 'A');
      cubit.putStep(a.copyWith(startAt: () => DateTime(2026, 10, 13, 8).toUtc()));
      await tester.pumpAndSettle();

      expect(find.byType(PlanDayHeader), findsNWidgets(2));
      final second = tester.getTopLeft(find.byType(PlanDayHeader).at(1)).dy;
      expect(tester.getTopLeft(_row('A')).dy, greaterThan(second));
      expect(tester.getTopLeft(_row('B')).dy, lessThan(second));
    });
  });
}
