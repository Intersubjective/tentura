@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/widget/beacon_plan_surface.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_step_row.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_step_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_plan_test_support.dart';

final _now = DateTime.utc(2026, 10, 12, 10, 20);

const _people = [
  Profile(id: 'U2', displayName: 'Olga'),
  Profile(id: 'ME', displayName: 'Ivan'),
];

Future<PlanCubit> _pump(
  WidgetTester tester,
  FakeBeaconPlanRepository repo, {
  Locale locale = const Locale('en'),
  String? initialStepId,
  PlanCantMakeChatCallback? onCantMakeChat,
}) async {
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
      locale: locale,
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: BeaconPlanView(
            admitted: _people,
            planCase: planCaseFor(repo),
            clock: () => _now,
            initialStepId: initialStepId,
            onCantMakeChat: onCantMakeChat,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  testWidgets('renders steps, now line, assignees and markers', (tester) async {
    final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
    final cubit = await _pump(tester, repo);

    expect(find.text('Buy screws'), findsOneWidget);
    expect(find.text('Bring boards'), findsOneWidget);
    expect(find.text('Return the cart'), findsOneWidget);
    expect(find.byKey(PlanNowLine.lineKey), findsOneWidget);
    expect(find.text('no assignee'), findsOneWidget);
    // Editors see the pending confirmation of the assignee.
    expect(find.text('awaiting confirmation: Ivan'), findsOneWidget);
    expect(find.textContaining('Plan · 1/4'), findsOneWidget);
    expect(find.byKey(BeaconPlanView.editKey), findsOneWidget);
    expect(find.byKey(BeaconPlanView.historyKey), findsOneWidget);
    expect(find.byKey(BeaconPlanView.ackKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('Mine filter dims neighbours and hides the rest', (
    tester,
  ) async {
    final repo = FakeBeaconPlanRepository(
      BeaconPlan.decode(planJson()).withSteps([
        ...BeaconPlan.decode(planJson()).steps,
        const PlanStep(id: 'PS000000000005', title: 'Lunch', assigneeId: 'U2'),
        const PlanStep(id: 'PS000000000006', title: 'Photos', assigneeId: 'U2'),
      ]),
    );
    final cubit = await _pump(tester, repo);
    expect(find.text('Photos'), findsOneWidget);

    await tester.tap(find.byKey(BeaconPlanView.mineKey));
    await tester.pump();
    expect(cubit.state.filter, const PlanFilter.mine());
    expect(find.text('Photos'), findsNothing);
    expect(find.text('Bring boards'), findsOneWidget);
    // Neighbour of my step stays, dimmed.
    expect(
      find.ancestor(
        of: find.text('Buy screws'),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('tick box ticks optimistically', (tester) async {
    final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
    final cubit = await _pump(tester, repo);

    final row = find.byKey(PlanStepRow.keyFor('PS000000000003'));
    await tester.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
    await tester.pump();
    expect(repo.setDoneCalls, [('PS000000000003', true)]);
    expect(cubit.state.plan!.stepById('PS000000000003')!.isDone, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('pending changes card with Got it', (tester) async {
    final repo = FakeBeaconPlanRepository(
      BeaconPlan.decode(
        planJson(
          viewerPending: {
            'fromSeq': 3,
            'headSeq': 4,
            'changes': [
              {
                'op': 'reassigned',
                'stepId': 'PS000000000002',
                'title': 'Bring boards',
                'toAssigneeId': 'ME',
                'seq': 3,
              },
            ],
            'actorIds': ['U2'],
          },
        ),
      ),
    );
    final cubit = await _pump(tester, repo);

    expect(find.text('Your steps changed'), findsOneWidget);
    expect(
      find.textContaining('«Bring boards» assigned to you'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(BeaconPlanView.ackKey));
    await tester.pump();
    expect(repo.ackCalls, [4]);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('empty plan shows the empty state (ru)', (tester) async {
    final repo = FakeBeaconPlanRepository(
      const BeaconPlan(beaconId: 'B1', editable: true, tickable: true),
    );
    final cubit = await _pump(tester, repo, locale: const Locale('ru'));

    expect(find.byKey(BeaconPlanView.emptyKey), findsOneWidget);
    expect(find.text('Плана пока нет.'), findsOneWidget);
    expect(find.text('Составить план'), findsOneWidget);
    expect(find.text('История плана ›'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  test('Plan tab sits after Now; split hides only Chat', () {
    expect(beaconVisibleSurfaces(isSplit: false), [
      BeaconSurface.now,
      BeaconSurface.plan,
      BeaconSurface.room,
      BeaconSurface.people,
    ]);
    expect(beaconVisibleSurfaces(isSplit: true), [
      BeaconSurface.now,
      BeaconSurface.plan,
      BeaconSurface.people,
    ]);
    expect(
      beaconVisibleSurfaces(isSplit: false, planEnabled: false),
      [BeaconSurface.now, BeaconSurface.room, BeaconSurface.people],
    );
    expect(beaconViewSurfaceForTab('plan'), BeaconSurface.plan);
    expect(beaconSurfaceViewTab(BeaconSurface.plan), 'plan');
  });

  testWidgets('deep link step= opens that step card once (#220)', (
    tester,
  ) async {
    final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
    final cubit = await _pump(tester, repo, initialStepId: 'PS000000000003');
    await tester.pumpAndSettle();

    expect(find.byType(PlanStepSheet), findsOneWidget);
    expect(find.text('Step 3 of 4'), findsOneWidget);

    // A refetch does not open it again.
    Navigator.of(tester.element(find.byType(PlanStepSheet))).pop();
    await tester.pumpAndSettle();
    await tester.runAsync(cubit.refresh);
    await tester.pumpAndSettle();
    expect(find.byType(PlanStepSheet), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('an unknown step= opens nothing', (tester) async {
    final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
    final cubit = await _pump(tester, repo, initialStepId: 'PSgone');
    await tester.pumpAndSettle();
    expect(find.byType(PlanStepSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets(
    "Can't make it → Write in the discussion hands the step over and "
    'records nothing yet',
    (tester) async {
      final repo = FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));
      final chats = <PlanStep>[];
      final cubit = await _pump(
        tester,
        repo,
        initialStepId: 'PS000000000003',
        onCantMakeChat: chats.add,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("Can't make it"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write in the discussion'));
      await tester.pumpAndSettle();

      expect(chats.map((s) => s.id), ['PS000000000003']);
      expect(repo.cantMakeCalls, isEmpty);
      // Both sheets are gone: the person is on the way to the discussion.
      expect(find.byType(PlanStepSheet), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(cubit.close);
    },
  );
}
