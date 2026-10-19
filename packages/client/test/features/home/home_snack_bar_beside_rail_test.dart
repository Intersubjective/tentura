// #495: on a wide window Home's notice bars were drawn across the side rail.
// The side-nav Scaffold wraps the rail AND the tab content, so it is the
// messenger's only root scaffold and every SnackBar spans it from x = 0: the
// bar covered the rail (and its Profile avatar on short screens).
//
// Spec: a bar raised on a Home tab sits right of the rail, and a tab whose
// page is two side-by-side panes (list beside detail, as Posts is) still shows
// exactly one bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../my_work/my_work_test_support.dart';

const _helpOffered = 'Help offered';
const _busy = 'Busy right now. Try again in a few seconds.';

class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _OrientationPreferences implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoInviteHandoff implements PostJoinBeaconHandoffPort {
  @override
  PostJoinDestination? readAndClear() => null;
}

/// Signed out: Home skips the account-scoped Inbox / My Work providers, so
/// only the shell chrome (rail + tab content) is under test.
class _SignedOutAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(updatedAt: DateTime.utc(2026, 10, 19));

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

/// A Home tab page laid out as list beside detail, each pane its own
/// Scaffold (the Posts tab shape), with buttons that raise the two kinds of
/// bar from the detail pane.
class _SplitTabPage extends StatelessWidget {
  const _SplitTabPage();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(
        width: 440,
        child: Scaffold(body: Text('list pane')),
      ),
      Expanded(
        child: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => showSnackBar(context, text: _helpOffered),
                  child: const Text('notice'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      showSnackBar(context, text: _busy, isError: true),
                  child: const Text('error'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final homeActivation = HomeActivationCubit(_OrientationPreferences());
  final homeAttention = HomeAttentionCubit(
    buildStubAttentionCase(),
    _Accounts(),
    Logger('home-attention'),
  );
  final inbox = InboxOperationalCubit();
  final reselect = HomeTabReselectCubit();
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  final postJoin = PostJoinNavigationCubit();
  GetIt.I
    ..registerSingleton<AuthCubit>(_SignedOutAuthCubit())
    ..registerSingleton<ScreenCubit>(screen)
    ..registerSingleton<HomeTabReselectCubit>(reselect)
    ..registerSingleton<InboxOperationalCubit>(inbox)
    ..registerSingleton<HomeActivationCubit>(homeActivation)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<Logger>(Logger('home-snack-bar'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NoInviteHandoff());

  // The real HomeRoute page and shell; every tab root is a stand-in, the
  // Work tab the split page above.
  final router = RootStackRouter.build(
    routes: [
      AutoRoute(
        page: HomeRoute.page,
        path: '/home',
        initial: true,
        children: [
          for (final spec in HomeTabSpec.all)
            AutoRoute(
              page: spec.shell.page,
              path: spec.path.split('/').last,
              initial: spec.tab == HomeTab.work,
              children: [
                AutoRoute(
                  page: PageInfo(
                    spec.rootRoute().routeName,
                    builder: (_) => spec.tab == HomeTab.work
                        ? const _SplitTabPage()
                        : const SizedBox.shrink(),
                  ),
                  path: '',
                  initial: true,
                ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await homeActivation.close();
    await homeAttention.close();
    await inbox.close();
    await reselect.close();
    await screen.close();
    router.dispose();
    await GetIt.I.reset();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: TenturaTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      scaffoldMessengerKey: snackbarKey,
      routerConfig: router.config(),
      builder: (_, child) => TenturaResponsiveScope(child: child!),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.text('list pane'), findsOneWidget);
  expect(find.byType(NavigationRail), findsOneWidget);
}

/// The bar's own surface (outermost Material under the SnackBar); for a
/// floating bar the SnackBar widget itself also spans its margin.
Rect _barRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
      .first,
);

void main() {
  for (final (label, button, message) in [
    ('notice bar', 'notice', _helpOffered),
    ('error bar', 'error', _busy),
  ]) {
    testWidgets('Home side rail: one $label, right of the rail', (
      tester,
    ) async {
      await _pumpHome(tester);

      await tester.tap(find.text(button));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      // Exactly one bar, even though the tab shows two sibling panes.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(message, findRichText: true),
        ),
        findsOneWidget,
      );

      final rail = tester.getRect(find.byType(NavigationRail));
      final bar = _barRect(tester);
      expect(
        bar.left,
        greaterThanOrEqualTo(rail.right),
        reason: 'The bar must not be drawn over the rail ($rail): $bar',
      );
      // Still on screen, along the bottom of the content area.
      expect(bar.bottom, greaterThan(1100 - 120));
      expect(bar.right, lessThanOrEqualTo(1280));
    });
  }
}
