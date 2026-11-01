@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/widget/beacon_plan_surface.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_plan_rows.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/ui/beacon/beacon_surface.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../beacon_plan/beacon_plan_test_support.dart';
import 'beacon_view_screen_harness.dart';

/// #546: the Request plan stays out of the way until there is one. No plan
/// (or a plan whose steps were all removed): no Plan tab, no plan rows on
/// Now, a `tab=plan` link lands on Now; plan editors start a plan from the
/// Request's ⋮ menu («Add plan»), which opens the plan editor.

class _Threads extends Cubit<ThreadsState> implements ThreadsCubit {
  _Threads(super.initialState);

  void emitState(ThreadsState value) => emit(value);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

/// An editable plan of the harness Request with steps.
BeaconPlan _planWithSteps({bool editable = true}) {
  final json = jsonDecode(planJson(editable: editable)) as Map<String, Object?>;
  json['beaconId'] = kBeaconViewHarnessBeaconId;
  return BeaconPlan.decode(jsonEncode(json));
}

/// The plan of a Request nobody planned yet (or whose steps were all
/// removed): the server still answers with the viewer's rights.
BeaconPlan _emptyPlan({bool editable = true, int revisionSeq = 0}) =>
    BeaconPlan(
      beaconId: kBeaconViewHarnessBeaconId,
      editable: editable,
      tickable: editable,
      revisionSeq: revisionSeq,
    );

/// Runs [body] ignoring only RenderFlex overflow reports (the Ahem test font
/// overflows the Plan header row); every other error still fails the test.
Future<void> _ignoringOverflow(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlanCubit? planCubit;
  late BeaconViewHarnessRouter router;

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
    router = BeaconViewHarnessRouter();
  });

  tearDown(() async {
    await planCubit?.close();
    planCubit = null;
    await unregisterBeaconViewHarnessGetIt();
  });

  Future<void> pumpRequest(
    WidgetTester tester, {
    required BeaconPlan plan,
    String? viewTab,
  }) async {
    final cubit = planCubit = PlanCubit(
      beaconId: kBeaconViewHarnessBeaconId,
      viewerId: kBeaconViewHarnessAuthorId,
      planCase: planCaseFor(FakeBeaconPlanRepository(plan)),
    );
    await tester.runAsync(cubit.load);

    await tester.binding.setSurfaceSize(kBeaconViewHarnessCompact);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final threads = _Threads(
      beaconViewHarnessThreadsState().copyWith(status: const StateIsLoading()),
    );
    addTearDown(threads.close);

    await tester.pumpWidget(
      StackRouterScope(
        controller: router,
        stateHash: 0,
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: BeaconViewResizableMediaQuery(
            size: kBeaconViewHarnessCompact,
            child: buildBeaconViewHarnessWidget(
              beaconState: beaconViewHarnessAuthorState(),
              threadsState: beaconViewHarnessThreadsState(),
              viewTab: viewTab,
              planCubit: cubit,
              threadsCubit: threads,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    threads.emitState(beaconViewHarnessThreadsState());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final planTab = find.byKey(TestIds.key(TestIds.beaconTabPlan));
  final addPlan = find.byKey(TestIds.key(TestIds.beaconOverflowAddPlan));

  Future<void> openOverflow(WidgetTester tester) async {
    await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('no plan yet', () {
    testWidgets('no Plan tab and no plan rows on Now', (tester) async {
      await pumpRequest(tester, plan: _emptyPlan());

      expect(find.byType(BeaconNowSurface), findsOneWidget);
      expect(planTab, findsNothing);
      expect(find.byKey(BeaconHudPlanKeys.counter), findsNothing);
      expect(find.byKey(BeaconHudPlanKeys.next), findsNothing);
    });

    testWidgets('every step removed: no Plan tab either', (tester) async {
      await pumpRequest(tester, plan: _emptyPlan(revisionSeq: 3));

      expect(planTab, findsNothing);
      expect(find.byKey(BeaconHudPlanKeys.counter), findsNothing);
    });

    testWidgets('a tab=plan link lands on Now and the URL says so', (
      tester,
    ) async {
      await pumpRequest(
        tester,
        plan: _emptyPlan(),
        viewTab: kBeaconViewTabPlan,
      );

      expect(find.byType(BeaconPlanSurface), findsNothing);
      expect(find.byKey(BeaconPlanView.emptyKey), findsNothing);
      expect(find.byType(BeaconNowSurface), findsOneWidget);
      expect(planTab, findsNothing);
      expect(router.replacedPaths, isNotEmpty);
      final url = Uri.parse(router.replacedPaths.last);
      expect(url.queryParameters[kQueryBeaconViewTab], kBeaconViewTabNow);
      expect(beaconViewPopScope(tester).canPop, isTrue);
    });

    testWidgets('a plan editor gets «Add plan» in the menu; it opens the '
        'plan editor', (tester) async {
      await pumpRequest(tester, plan: _emptyPlan());
      router.replacedPaths.clear();

      await openOverflow(tester);
      expect(addPlan, findsOneWidget);
      expect(find.text('Add plan'), findsOneWidget);

      await tester.tap(addPlan);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final edits = [
        for (final path in router.replacedPaths)
          if (Uri.parse(path).queryParameters[kQueryPlanPage] == kPlanPageEdit)
            Uri.parse(path),
      ];
      expect(edits, isNotEmpty, reason: 'Add plan must open the plan editor');
      expect(
        edits.last.queryParameters[kQueryBeaconViewTab],
        kBeaconViewTabPlan,
      );
      // Waiting for the editor's URL must not bounce the screen to Now.
      expect(
        router.replacedPaths.where(
          (path) =>
              Uri.parse(path).queryParameters[kQueryBeaconViewTab] ==
              kBeaconViewTabNow,
        ),
        isEmpty,
      );
    });

    testWidgets('no «Add plan» for a viewer who cannot edit the plan', (
      tester,
    ) async {
      await pumpRequest(tester, plan: _emptyPlan(editable: false));

      await openOverflow(tester);
      expect(addPlan, findsNothing);
      expect(find.text('Add plan'), findsNothing);
    });
  });

  group('with a plan (guards)', () {
    testWidgets(
      'the Plan tab shows and a tab=plan link opens the plan',
      (
        tester,
      ) => _ignoringOverflow(() async {
        await pumpRequest(
          tester,
          plan: _planWithSteps(),
          viewTab: kBeaconViewTabPlan,
        );

        expect(planTab, findsOneWidget);
        expect(find.byType(BeaconPlanSurface), findsOneWidget);
        expect(find.text('Buy screws'), findsOneWidget);
        expect(
          router.replacedPaths.where(
            (path) =>
                Uri.parse(path).queryParameters[kQueryBeaconViewTab] ==
                kBeaconViewTabNow,
          ),
          isEmpty,
        );
      }),
    );

    testWidgets('the menu has no «Add plan» once the plan has steps', (
      tester,
    ) async {
      await pumpRequest(tester, plan: _planWithSteps());

      expect(planTab, findsOneWidget);
      await openOverflow(tester);
      expect(addPlan, findsNothing);
    });
  });

  test('a Plan tab only for a plan with a step', () {
    expect(beaconPlanHasSteps(null), isFalse);
    expect(beaconPlanHasSteps(_emptyPlan()), isFalse);
    expect(beaconPlanHasSteps(_planWithSteps()), isTrue);
    expect(beaconVisibleSurfaces(isSplit: false, hasPlan: false), [
      BeaconSurface.now,
      BeaconSurface.room,
      BeaconSurface.people,
    ]);
    expect(beaconVisibleSurfaces(isSplit: true, hasPlan: false), [
      BeaconSurface.now,
      BeaconSurface.people,
    ]);
    // A plan still loading keeps a tab=plan link waiting for it.
    expect(beaconPlanSurfaceAvailable(plan: null, loading: true), isTrue);
    expect(beaconPlanSurfaceAvailable(plan: null, loading: false), isFalse);
    expect(
      beaconPlanSurfaceAvailable(plan: _emptyPlan(), loading: false),
      isFalse,
    );
  });
}
