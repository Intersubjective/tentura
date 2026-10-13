import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/screen/plan_edit_screen.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../features/beacon_plan/beacon_plan_test_support.dart';
import '../../features/beacon_view/beacon_view_screen_harness.dart';

const _editedTitle = 'Bring boards, edited';
const _discardTitle = 'Discard changes?';
const _discardBody = 'Unsaved edits will be lost.';
const _discardKeep = 'Keep editing';
const _discardConfirm = 'Discard';

const _requestPath = '/beacon/view/$kBeaconViewHarnessBeaconId';

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime(2026),
    currentAccountId: kBeaconViewHarnessAuthorId,
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final spec in HomeTabSpec.all) spec.shell()],
    duration: Duration.zero,
    transitionBuilder: (_, child, _) => child,
    builder: (_, child) => child,
  );
}

/// An editable plan of the harness Request.
BeaconPlan _plan() {
  final json = jsonDecode(planJson()) as Map<String, Object?>;
  json['beaconId'] = kBeaconViewHarnessBeaconId;
  return BeaconPlan.decode(jsonEncode(json));
}

/// What the browser tells the app when its Back button is pressed.
Future<void> _deliverBrowserRoute(WidgetTester tester, String location) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootRouter router;
  late PageInfo homePage;
  late PageInfo workPage;
  late PageInfo beaconPage;
  late PageInfo operationalPage;
  late PlanCubit planCubit;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;
    beaconPage = BeaconViewRoute.page;
    operationalPage = BeaconViewOperationalRoute.page;
    HomeRoute.page = PageInfo(HomeRoute.name, builder: (_) => const _Home());
    MyWorkRoute.page = PageInfo(
      MyWorkRoute.name,
      builder: (_) => const Text('work-root', textDirection: TextDirection.ltr),
    );
    // The host keeps the plan above the page it shows, as the route's scope
    // does; the Request screen itself is the real one, fed from the URL.
    BeaconViewRoute.page = PageInfo(
      BeaconViewRoute.name,
      builder: (_) => BlocProvider<PlanCubit>.value(
        value: planCubit,
        child: const AutoRouter(),
      ),
    );
    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (data) => buildBeaconViewHarnessWidget(
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        viewTab: data.queryParams.optString(kQueryBeaconViewTab),
        planPage: data.queryParams.optString(kQueryPlanPage),
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
    BeaconViewRoute.page = beaconPage;
    BeaconViewOperationalRoute.page = operationalPage;
  });

  setUp(() async {
    final repo = FakeBeaconPlanRepository(_plan());
    planCubit = PlanCubit(
      beaconId: kBeaconViewHarnessBeaconId,
      viewerId: kBeaconViewHarnessAuthorId,
      planCase: planCaseFor(repo),
    );
    // Loaded before the editor opens, as when the Plan tab was shown first.
    await planCubit.load();
    await registerBeaconViewHarnessGetIt();
    router = RootRouter(
      Logger('PlanEditorBrowserBackTest'),
      _Auth(),
      _Settings(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() async {
    router.dispose();
    await planCubit.close();
    await unregisterBeaconViewHarnessGetIt();
  });

  Future<void> pumpEditorAt(WidgetTester tester, String url) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          includePrefixMatches: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Renames the first step in the open editor, as typing in its sheet does.
  void editFirstStep(WidgetTester tester) {
    final cubit = tester
        .element(find.byType(PlanEditScreen))
        .read<PlanEditCubit>();
    cubit.putStep(cubit.state.steps.first.copyWith(title: _editedTitle));
  }

  PlanEditCubit editorCubit(WidgetTester tester) =>
      tester.element(find.byType(PlanEditScreen)).read<PlanEditCubit>();

  void expectDraftHeld(WidgetTester tester, {required String reason}) {
    final draft = editorCubit(tester).state;
    expect(draft.isDirty, isTrue, reason: reason);
    expect(
      draft.steps.map((step) => step.title),
      contains(_editedTitle),
      reason: reason,
    );
  }

  void expectOnPlanTab() {
    final url = Uri.parse(router.navigationHistory.urlState.url);
    expect(url.path, _requestPath);
    expect(url.queryParameters, {kQueryBeaconViewTab: kBeaconViewTabPlan});
  }

  /// Opens the editor, edits a step, then the browser goes back to the plan.
  /// Returns whether the user was asked what to do with the edit; while
  /// asked, the editor and the draft are still in place.
  Future<bool> editThenBrowserBack(WidgetTester tester) async {
    await pumpEditorAt(tester, '$_requestPath?tab=plan&page=edit');
    expect(find.byType(PlanEditScreen), findsOneWidget);
    editFirstStep(tester);
    await tester.pumpAndSettle();
    expectDraftHeld(tester, reason: 'the edit did not reach the draft');

    await _deliverBrowserRoute(tester, '$_requestPath?tab=plan');

    final dialog = find.byType(TenturaConfirmDialog);
    if (dialog.evaluate().isEmpty) return false;
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text(_discardTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(_discardBody)),
      findsOneWidget,
    );
    expect(
      find.byType(PlanEditScreen),
      findsOneWidget,
      reason: 'the editor went away before the user could answer',
    );
    expectDraftHeld(tester, reason: 'the draft was dropped before asking');
    return true;
  }

  /// No question was asked: the page is gone from the route, so the draft
  /// must be waiting in the editor opened next.
  Future<void> expectDraftSurvivesReopen(WidgetTester tester) async {
    expectOnPlanTab();
    expect(find.byType(PlanEditScreen), findsNothing);

    await _deliverBrowserRoute(tester, '$_requestPath?tab=plan&page=edit');
    expect(find.byType(PlanEditScreen), findsOneWidget);
    expectDraftHeld(tester, reason: 'Back dropped the edit without asking');
  }

  group('plan editor under browser Back', () {
    testWidgets(
      'keeping the edit after Back leaves the editor and its draft intact, '
      'or the draft is still there when the editor opens again',
      (tester) async {
        if (!await editThenBrowserBack(tester)) {
          await expectDraftSurvivesReopen(tester);
          return;
        }

        await tester.tap(find.text(_discardKeep));
        await tester.pumpAndSettle();

        expect(find.byType(TenturaConfirmDialog), findsNothing);
        expect(find.byType(PlanEditScreen), findsOneWidget);
        expectDraftHeld(tester, reason: 'keep editing lost the draft');
      },
    );

    testWidgets(
      'discarding the edit after Back leaves the plan and starts the next '
      'editor clean, or the draft is still there when the editor opens again',
      (tester) async {
        if (!await editThenBrowserBack(tester)) {
          await expectDraftSurvivesReopen(tester);
          return;
        }

        await tester.tap(find.text(_discardConfirm));
        await tester.pumpAndSettle();

        expect(find.byType(TenturaConfirmDialog), findsNothing);
        expect(find.byType(PlanEditScreen), findsNothing);
        expectOnPlanTab();

        await _deliverBrowserRoute(tester, '$_requestPath?tab=plan&page=edit');
        expect(editorCubit(tester).state.isDirty, isFalse);
      },
    );
  });
}
