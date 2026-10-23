@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_plan_test_support.dart';

Widget _withRouter(StackRouter? router, Widget child) => router == null
    ? child
    : RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: child,
        ),
      );

/// «Скопировать план» on «Создать на основе» (#220, plan §5.11).
void main() {
  final plan = BeaconPlan.decode(planJson());

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onTap, {
    Locale locale = const Locale('en'),
    StackRouter? router,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: _withRouter(
          router,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onTap(context),
                child: const Text('go'),
              ),
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

  // #493: «Create from this request» saves nothing; it only opens the
  // editor on the source, carrying the plan choice to the first save.
  testWidgets('create-from: plan → sheet → editor carries the step times', (
    tester,
  ) async {
    final router = _PushRouter();
    await pumpHost(
      tester,
      (context) => runBeaconCreateFromAction(
        context,
        sourceBeaconId: 'src',
        sourcePlan: plan,
      ),
      router: router,
    );
    await tester.tap(find.byKey(PlanCopySheet.confirmKey));
    await tester.pumpAndSettle();
    expect(router.pushed, hasLength(1));
    final route = router.pushed.single as BeaconCreateRoute;
    final args = route.args!;
    expect(args.forkSourceId, 'src');
    expect(args.draftId, isEmpty);
    // #607: the times ride in the URL, so a web reload (args rebuilt from
    // the query alone) still copies the plan at the chosen times.
    final fromUrl = decodePlanStepTimesQuery(
      route.queryParams.getString(kQueryBeaconForkPlan, ''),
    );
    expect(fromUrl, hasLength(plan.steps.length));
    expect(
      fromUrl!.map((t) => t.sourceStepId),
      plan.steps.map((s) => s.id),
    );
    expect(
      fromUrl.where((t) => t.startAt != null),
      hasLength(plan.steps.where((s) => s.startAt != null).length),
    );
    expect(decodePlanStepTimesQuery(args.forkPlanTimes), fromUrl);

    // Dismissed: the editor does not open at all.
    router.pushed.clear();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(PlanCopySheet), findsNothing);
    expect(router.pushed, isEmpty);
  });

  testWidgets('create-from without a plan opens the editor straight away', (
    tester,
  ) async {
    final router = _PushRouter();
    await pumpHost(
      tester,
      (context) => runBeaconCreateFromAction(
        context,
        sourceBeaconId: 'src',
        sourcePlan: plan.withSteps(const []),
      ),
      router: router,
    );
    expect(find.byType(PlanCopySheet), findsNothing);
    expect(router.pushed, hasLength(1));
    final args = (router.pushed.single as BeaconCreateRoute).args!;
    expect(args.forkSourceId, 'src');
    expect(args.draftId, isEmpty);
    expect(args.forkPlanTimes, isEmpty);
    expect(
      decodePlanStepTimesQuery(
        router.pushed.single.queryParams.getString(kQueryBeaconForkPlan, ''),
      ),
      isNull,
    );
  });
}

/// Records pushes instead of navigating.
class _PushRouter extends Mock implements StackRouter {
  final pushed = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }
}
