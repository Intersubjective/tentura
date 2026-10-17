@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/screen/plan_edit_screen.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_step_row.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_step_edit_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';

import 'beacon_plan_test_support.dart';

const _people = [Profile(id: 'ME', displayName: 'Ivan')];

String _iso(int day, int hour) =>
    DateTime(2026, 10, day, hour).toUtc().toIso8601String();

Map<String, Object?> _step(
  String id, {
  int? day,
  int hour = 9,
  int? endHour,
  int endMinute = 0,
}) => {
  'id': id,
  'index': 1,
  'title': 'Step $id',
  'description': '',
  'assigneeId': null,
  'startAt': day == null ? null : _iso(day, hour),
  'endAt': day == null || endHour == null
      ? null
      : DateTime(2026, 10, day, endHour, endMinute).toUtc().toIso8601String(),
  'doneAt': null,
  'doneById': null,
  'contentSeq': 1,
  'ackSeq': 1,
  'assigneeAckPending': false,
};

/// Untimed `U`, then two steps on the 12th and two on the 13th.
BeaconPlan _plan([List<Map<String, Object?>>? steps]) {
  final json = jsonDecode(planJson()) as Map<String, Object?>;
  json['steps'] =
      steps ??
      [
        _step('U'),
        _step('A', day: 12),
        _step('B', day: 12, hour: 10),
        _step('C', day: 13),
        _step('D', day: 13, hour: 10),
      ];
  return BeaconPlan.decode(jsonEncode(json));
}

Future<PlanEditCubit> _pump(
  WidgetTester tester, {
  BeaconPlan? plan,
  Size size = const Size(800, 1600),
}) async {
  final repo = FakeBeaconPlanRepository(plan ?? _plan());
  final cubit = PlanEditCubit(plan: repo.plan, planCase: planCaseFor(repo));
  addTearDown(cubit.close);
  tester.view.physicalSize = size;
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

/// The per-day «add step» actions (every text action but the bottom add).
final _dayAdds = find.byWidgetPredicate(
  (w) => w is TenturaTextAction && w.key != PlanEditScreen.addKey,
);

bool _isDisabled(WidgetTester tester, Finder f) =>
    tester.widget<TenturaTextAction>(f).onPressed == null;

Future<void> _saveSheet(WidgetTester tester, String title) async {
  await tester.enterText(find.byKey(PlanStepEditSheet.titleFieldKey), title);
  await tester.pump();
  await tester.tap(find.byKey(PlanStepEditSheet.applyKey));
  await tester.pumpAndSettle();
}

PlanStepSnapshot _stepByTitle(PlanEditCubit c, String title) =>
    c.state.steps.firstWhere((s) => s.title == title);

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
      cubit.putStep(
        a.copyWith(startAt: () => DateTime(2026, 10, 13, 8).toUtc()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlanDayHeader), findsNWidgets(2));
      final second = tester.getTopLeft(find.byType(PlanDayHeader).at(1)).dy;
      expect(tester.getTopLeft(_row('A')).dy, greaterThan(second));
      expect(tester.getTopLeft(_row('B')).dy, lessThan(second));
    });
  });

  group('plan editor per-day add step', () {
    // Day 12 ends at 11:30 (step A); day 13 holds C and D.
    BeaconPlan planWithEnd() => _plan([
      _step('U'),
      _step('A', day: 12, endHour: 11, endMinute: 30),
      _step('B', day: 12, hour: 10),
      _step('C', day: 13),
      _step('D', day: 13, hour: 10),
    ]);

    testWidgets('every day group offers its own add action', (tester) async {
      await _pump(tester);

      expect(_dayAdds, findsNWidgets(2));
      final firstDay = tester.getTopLeft(find.byType(PlanDayHeader).at(0)).dy;
      final secondDay = tester.getTopLeft(find.byType(PlanDayHeader).at(1)).dy;
      expect(tester.getTopLeft(_dayAdds.at(0)).dy, greaterThan(firstDay));
      expect(tester.getTopLeft(_dayAdds.at(0)).dy, lessThan(secondDay));
      expect(tester.getTopLeft(_dayAdds.at(1)).dy, greaterThan(secondDay));
    });

    testWidgets("a day's add opens the sheet with the start on that day at "
        "the day's latest end", (tester) async {
      await _pump(tester, plan: planWithEnd());

      await tester.tap(_dayAdds.at(0));
      await tester.pumpAndSettle();

      expect(find.byType(PlanStepEditSheet), findsOneWidget);
      final expected = planDayTime(DateTime(2026, 10, 12, 11, 30), 'en');
      expect(
        find.descendant(
          of: find.byType(PlanStepEditSheet),
          matching: find.text(expected),
        ),
        findsOneWidget,
      );
    });

    testWidgets("a day whose steps have no end is prefilled with the day's "
        'latest start', (tester) async {
      await _pump(tester);

      await tester.tap(_dayAdds.at(0));
      await tester.pumpAndSettle();

      // Day 12 holds A at 09:00 and B at 10:00, neither with an end.
      expect(
        find.descendant(
          of: find.byType(PlanStepEditSheet),
          matching: find.text(planDayTime(DateTime(2026, 10, 12, 10), 'en')),
        ),
        findsOneWidget,
      );
    });

    testWidgets("the second day's add is prefilled from that day's own steps, "
        'not the first when saved', (tester) async {
      final cubit = await _pump(tester, plan: planWithEnd());

      await tester.tap(_dayAdds.at(1));
      await tester.pumpAndSettle();

      // Day 13 holds C at 09:00 and D at 10:00; day 12's 11:30 end is not it.
      expect(
        find.descendant(
          of: find.byType(PlanStepEditSheet),
          matching: find.text(planDayTime(DateTime(2026, 10, 13, 10), 'en')),
        ),
        findsOneWidget,
      );
      await _saveSheet(tester, 'Second day step');
      expect(
        _stepByTitle(cubit, 'Second day step').startAt,
        DateTime(2026, 10, 13, 10).toUtc(),
      );
      final headers = find.byType(PlanDayHeader);
      expect(
        tester.getTopLeft(find.text('Second day step')).dy,
        greaterThan(tester.getTopLeft(headers.at(1)).dy),
      );
    });

    testWidgets('saving the sheet opened from a day places the new step '
        'under that day', (tester) async {
      final cubit = await _pump(tester, plan: planWithEnd());

      await tester.tap(_dayAdds.at(0));
      await tester.pumpAndSettle();
      await _saveSheet(tester, 'Fresh step');

      expect(
        _stepByTitle(cubit, 'Fresh step').startAt,
        DateTime(2026, 10, 12, 11, 30).toUtc(),
      );
      final headers = find.byType(PlanDayHeader);
      expect(headers, findsNWidgets(2));
      final fresh = tester.getTopLeft(find.text('Fresh step')).dy;
      expect(fresh, greaterThan(tester.getTopLeft(headers.at(0)).dy));
      expect(fresh, lessThan(tester.getTopLeft(headers.at(1)).dy));
    });

    testWidgets('the bottom add still creates an untimed step', (
      tester,
    ) async {
      final cubit = await _pump(tester);

      await tester.tap(find.byKey(PlanEditScreen.addKey));
      await tester.pumpAndSettle();
      await _saveSheet(tester, 'Loose step');

      final loose = _stepByTitle(cubit, 'Loose step');
      expect(loose.startAt, isNull);
      expect(loose.endAt, isNull);
    });

    // Tall enough that both day groups (and the bottom add) are built.
    const tall = Size(800, 12000);

    BeaconPlan planOf(int count) => _plan([
      _step('A', day: 12),
      _step('B', day: 12, hour: 10),
      for (var i = 0; i < count - 2; i++)
        _step('S$i', day: 13, hour: 8 + i % 10),
    ]);

    testWidgets('all add actions are disabled at the step limit', (
      tester,
    ) async {
      await _pump(tester, plan: planOf(PlanLimits.maxSteps), size: tall);

      expect(find.byType(PlanDayHeader), findsNWidgets(2));
      expect(_dayAdds, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(_isDisabled(tester, _dayAdds.at(i)), isTrue, reason: 'day $i');
      }
      expect(_isDisabled(tester, find.byKey(PlanEditScreen.addKey)), isTrue);
    });

    testWidgets('all add actions stay enabled just below the step limit', (
      tester,
    ) async {
      await _pump(tester, plan: planOf(PlanLimits.maxSteps - 1), size: tall);

      expect(_dayAdds, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(_isDisabled(tester, _dayAdds.at(i)), isFalse, reason: 'day $i');
      }
      expect(_isDisabled(tester, find.byKey(PlanEditScreen.addKey)), isFalse);
    });
  });

  group('plan editor moved step focus', () {
    // A on top, then enough steps on the 13th that a step moved to the 14th
    // lands far below the 600 px viewport.
    BeaconPlan longPlan() => _plan([
      _step('A', day: 12),
      for (var i = 0; i < 40; i++) _step('S$i', day: 13, hour: 8 + i % 10),
    ]);

    Future<PlanEditCubit> pumpAndMoveA(WidgetTester tester) async {
      final cubit = await _pump(
        tester,
        plan: longPlan(),
        size: const Size(800, 600),
      );
      expect(_row('A').hitTestable(), findsOneWidget);
      // The end of the list, where A is about to land, is out of view.
      expect(_row('S39').hitTestable(), findsNothing);
      final a = cubit.state.steps.firstWhere((s) => s.id == 'A');
      cubit.putStep(
        a.copyWith(startAt: () => DateTime(2026, 10, 14, 9).toUtc()),
      );
      await tester.pumpAndSettle();
      expect(cubit.state.movedSeq, greaterThan(0));
      return cubit;
    }

    testWidgets('a step edited to a place below the visible area is scrolled '
        'into view', (tester) async {
      await pumpAndMoveA(tester);

      expect(_row('A'), findsOneWidget);
      expect(_row('A').hitTestable(), findsOneWidget);
      final list = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(list.first).position.pixels,
        isPositive,
      );
    });

    testWidgets('the moved step is wrapped in an active focus flash', (
      tester,
    ) async {
      await pumpAndMoveA(tester);

      final flash = find.ancestor(
        of: _row('A'),
        matching: find.byType(FocusFlashHighlight),
      );
      expect(flash, findsOneWidget);
      expect(tester.widget<FocusFlashHighlight>(flash).active, isTrue);
    });

    Iterable<FocusFlashHighlight> activeFlashes(WidgetTester tester) => tester
        .widgetList<FocusFlashHighlight>(find.byType(FocusFlashHighlight))
        .where((w) => w.active);

    testWidgets('a later move of a different step scrolls back to that step '
        'and flashes only it', (tester) async {
      final cubit = await pumpAndMoveA(tester);
      final firstSeq = cubit.state.movedSeq;
      // The list now sits at its end; the top is not built.
      expect(_row('S5').hitTestable(), findsNothing);

      // S0 would stay first in the plan (no move reported); S5 really
      // changes its place.
      final s5 = cubit.state.steps.firstWhere((s) => s.id == 'S5');
      cubit.putStep(
        s5.copyWith(startAt: () => DateTime(2026, 10, 11, 9).toUtc()),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.movedSeq, greaterThan(firstSeq));
      expect(_row('S5').hitTestable(), findsOneWidget);
      final flash = find.ancestor(
        of: _row('S5'),
        matching: find.byType(FocusFlashHighlight),
      );
      expect(tester.widget<FocusFlashHighlight>(flash).active, isTrue);
      expect(activeFlashes(tester), hasLength(1));
    });

    testWidgets('moving the same step again scrolls to it again', (
      tester,
    ) async {
      final cubit = await pumpAndMoveA(tester);
      final firstSeq = cubit.state.movedSeq;

      final a = cubit.state.steps.firstWhere((s) => s.id == 'A');
      cubit.putStep(
        a.copyWith(startAt: () => DateTime(2026, 10, 11, 9).toUtc()),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.movedSeq, greaterThan(firstSeq));
      expect(_row('A').hitTestable(), findsOneWidget);
      final flash = find.ancestor(
        of: _row('A'),
        matching: find.byType(FocusFlashHighlight),
      );
      expect(tester.widget<FocusFlashHighlight>(flash).active, isTrue);
      expect(activeFlashes(tester), hasLength(1));
    });
  });

  // #445: a new step showed "Write what to do" before anything was typed.
  group('new step sheet', () {
    testWidgets('asks for a title only after the field was edited', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = lookupL10n(const Locale('en'));

      await tester.tap(find.byKey(PlanEditScreen.addKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.planValidationTitleRequired), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(PlanStepEditSheet.applyKey))
            .onPressed,
        isNull,
      );

      final title = find.byKey(PlanStepEditSheet.titleFieldKey);
      await tester.enterText(title, 'x');
      await tester.pump();
      await tester.enterText(title, '');
      await tester.pump();

      expect(find.text(l10n.planValidationTitleRequired), findsOneWidget);
    });
  });
}
