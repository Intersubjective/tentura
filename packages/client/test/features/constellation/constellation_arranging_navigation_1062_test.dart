// Refs #938, #1062 — Arranging must not undo navigation (open Post/Profile, tab
// switch) via the browser-back sentinel.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/features/home/ui/widget/home_tab_transition_listener.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

void main() {
  testWidgets(
    'first tab leave while Arranging switches tab and clears arranging',
    (tester) async {
      final selection = ConstellationSelectionCubit()..enterArranging();
      addTearDown(selection.close);
      final fieldIndex = HomeTabSpec.forTab(HomeTab.constellation).index;
      final workIndex = HomeTabSpec.forTab(HomeTab.work).index;
      final tabs = _FakeTabsRouter(fieldIndex);

      await tester.pumpWidget(
        HomeTabTransitionListener(
          tabsRouter: tabs,
          tab: HomeTab.constellation,
          onLeave: selection.exitArrangingForNavigation,
          onEnter: selection.exitArrangingForNavigation,
          child: const SizedBox(),
        ),
      );
      expect(selection.state.arranging, isTrue);

      tabs.setActiveIndex(workIndex);
      await tester.pump();
      expect(selection.state.arranging, isFalse);
      expect(tabs.activeIndex, workIndex);
    },
  );

  testWidgets('375×667 RU open Request while Arranging calls openBeacon', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final navigator = registerFakeAppNavigator();
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    await pumpConstellationBody(
      tester,
      cubit,
      locale: const Locale('ru'),
      arrangeV2Enabled: true,
    );
    final selection = tester.constellationSelectionUnderTest()
      ..enterArranging();
    await tester.pumpAndSettle();

    const requestId = 'req-ego-1';
    cubit.focusBeacon(requestId, insets: EdgeInsets.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final requestNode = find.byKey(TestIds.key(TestIds.graphNode(requestId)));
    expect(requestNode, findsOneWidget);
    await tester.tap(requestNode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final open = find.widgetWithText(FilledButton, L10nRu().openBeacon);
    expect(open, findsOneWidget);
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(selection.state.arranging, isFalse);
    expect(navigator.named('openBeacon'), isNotEmpty);
    expect(navigator.named('openBeacon').last.args['id'], requestId);
  });

  testWidgets(
    '375×667 RU Profile from context panel exits Arranging before navigate',
    (tester) async {
      await usePhoneSurface(tester);
      final fx = FakeUiEffectPort();
      final selection = ConstellationSelectionCubit()..enterArranging();
      addTearDown(selection.close);
      const profile = Profile(id: 'am', displayName: 'Агент');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(375, 667)),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: selection),
                  BlocProvider<GraphPersonContextCubit>(
                    create: (_) => _StubContextCubit(),
                  ),
                  BlocProvider(
                    create: (_) => ScreenCubit(fx),
                  ),
                ],
                child: Scaffold(
                  body: GraphPersonContextPanel(
                    profile: profile,
                    focusedNode: const UserNode(user: profile),
                    peopleTagsEnabled: false,
                    onBeforeOpenProfile: selection.exitArrangingForNavigation,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, L10nRu().profile),
      );
      await tester.pumpAndSettle();

      expect(selection.state.arranging, isFalse);
      expect(
        fx.emitted.whereType<NavigatePush>(),
        isNotEmpty,
      );
    },
  );
}

class _FakeTabsRouter extends Fake with ChangeNotifier implements TabsRouter {
  _FakeTabsRouter(this._index);

  int _index;

  @override
  int get activeIndex => _index;

  @override
  void setActiveIndex(int value, {bool notify = true}) {
    _index = value;
    if (notify) notifyListeners();
  }
}
