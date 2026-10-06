@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_plan_test_support.dart';

/// «Скопировать план» on «Создать на основе» (#220, plan §5.11).
void main() {
  final plan = BeaconPlan.decode(planJson());

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onTap, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => onTap(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('sheet previews new times and notes assignees are not copied', (
    tester,
  ) async {
    PlanCopyChoice? choice;
    await pumpHost(tester, (context) async {
      choice = await showPlanCopySheet(
        context,
        plan: plan,
        clock: () => DateTime.utc(2026, 10, 2),
      );
    });

    expect(find.text('Copy plan'), findsOneWidget);
    expect(find.text('PLAN · 4 steps'), findsOneWidget);
    expect(find.text('First timed step starts'), findsOneWidget);
    // The source start is still ahead: nothing moves yet.
    expect(find.text('times stay the same'), findsOneWidget);
    expect(find.text('Buy screws'), findsOneWidget);
    expect(find.text('Return the cart'), findsOneWidget);
    expect(find.text('Assignees are not copied'), findsOneWidget);
    // No former assignee anywhere.
    expect(find.textContaining('Olga'), findsNothing);
    expect(find.textContaining('was:'), findsNothing);

    await tester.tap(find.byKey(PlanCopySheet.confirmKey));
    await tester.pumpAndSettle();
    final times = choice!.stepTimes!;
    expect(times.map((t) => t.sourceStepId), [
      for (final s in plan.steps) s.id,
    ]);
    expect(times.first.startAt, plan.steps.first.startAt);
    expect(times.last.startAt, isNull);
  });

  testWidgets('toggle off continues without the plan', (tester) async {
    PlanCopyChoice? choice;
    await pumpHost(tester, (context) async {
      choice = await showPlanCopySheet(context, plan: plan);
    });
    await tester.tap(find.byKey(PlanCopySheet.toggleKey));
    await tester.pumpAndSettle();
    expect(find.text('Assignees are not copied'), findsNothing);
    await tester.tap(find.byKey(PlanCopySheet.confirmKey));
    await tester.pumpAndSettle();
    expect(choice, isNotNull);
    expect(choice!.copyPlan, isFalse);
  });

  testWidgets('a plan without times hides the picker (ru)', (tester) async {
    final untimed = plan.withSteps([
      for (final s in plan.steps)
        PlanStep(id: s.id, index: s.index, title: s.title),
    ]);
    await pumpHost(tester, (context) async {
      await showPlanCopySheet(context, plan: untimed);
    }, locale: const Locale('ru'));
    expect(find.text('Скопировать план'), findsOneWidget);
    expect(find.text('ПЛАН · 4 шага'), findsOneWidget);
    expect(
      find.text('В плане нет шагов со временем — время задавать не нужно'),
      findsOneWidget,
    );
    expect(find.text('Исполнители не копируются'), findsOneWidget);
    expect(find.text('Начало первого шага со временем'), findsNothing);
  });

  testWidgets('create-from: plan → sheet → forkWithPlan; dismiss → no fork', (
    tester,
  ) async {
    final calls = <String>[];
    List<PlanStepTime>? sent;
    Future<void> run(BuildContext context) => runBeaconCreateFromAction(
      context,
      fork: () async {
        calls.add('fork');
        return null;
      },
      sourcePlan: plan,
      forkWithPlan: (times) async {
        calls.add('forkWithPlan');
        sent = times;
        return null;
      },
    );

    await pumpHost(tester, run);
    await tester.tap(find.byKey(PlanCopySheet.confirmKey));
    await tester.pumpAndSettle();
    expect(calls, ['forkWithPlan']);
    expect(sent, hasLength(plan.steps.length));

    // Dismissed: no copy at all.
    calls.clear();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(PlanCopySheet), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('create-from without a plan forks straight away', (
    tester,
  ) async {
    final calls = <String>[];
    await pumpHost(
      tester,
      (context) => runBeaconCreateFromAction(
        context,
        fork: () async {
          calls.add('fork');
          return null;
        },
        sourcePlan: plan.withSteps(const []),
        forkWithPlan: (_) async {
          calls.add('forkWithPlan');
          return null;
        },
      ),
    );
    expect(find.byType(PlanCopySheet), findsNothing);
    expect(calls, ['fork']);
  });
}
