// #1124: ShowMessage then NavigateReplace must keep the snackbar after
// ClearSnackBarsOnPushObserver runs on the replacing push.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

final class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit()
    : _state = AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: 'U1',
      );

  final AuthState _state;

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _TestHomeShell extends StatelessWidget {
  const _TestHomeShell();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final spec in HomeTabSpec.all) spec.shell()],
    duration: Duration.zero,
    transitionBuilder: (_, child, _) => child,
    builder: (_, child) => child,
  );
}

PageInfo _labelPage(String name, String label) => PageInfo(
  name,
  builder: (_) => Text(label, textDirection: TextDirection.ltr),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RootRouter router;
  late UiEffectBus effects;
  late PageInfo homePage;
  late PageInfo workPage;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _TestHomeShell(),
    );
    MyWorkRoute.page = PageInfo(
      MyWorkRoute.name,
      builder: (_) => const Scaffold(
        body: Center(child: Text('work-root')),
      ),
    );
    for (final spec in HomeTabSpec.all) {
      if (spec.tab == HomeTab.work) continue;
      final name = spec.rootRoute().routeName;
      final page = PageInfo(
        name,
        builder: (_) => Text('$name-root', textDirection: TextDirection.ltr),
      );
      switch (spec.tab) {
        case HomeTab.conversations:
          ConversationsRoute.page = page;
        case HomeTab.inbox:
        case HomeTab.updates:
          InboxRoute.page = page;
        case HomeTab.constellation:
          ConstellationRoute.page = page;
        case HomeTab.network:
          FriendsRoute.page = page;
        case HomeTab.me:
          ProfileRoute.page = page;
        case HomeTab.work:
          break;
      }
    }
    AuthLoginRoute.page = PageInfo(
      AuthLoginRoute.name,
      builder: (_) => const Scaffold(
        body: Center(child: Text('auth-login')),
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
  });

  setUp(() {
    effects = UiEffectBus();
    router = RootRouter(
      Logger('UiEffectNavigateRaceTest'),
      _FakeAuthCubit(),
      _FakeSettingsCubit(),
      PostJoinNavigationCubit(),
    );
    GetIt.I
      ..reset()
      ..registerSingleton<AppNavigator>(router)
      ..registerSingleton<UiEffectPort>(effects);
  });

  tearDown(() {
    router.dispose();
    GetIt.I.reset();
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    required String initialPath,
    Locale locale = const Locale('ru'),
  }) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = initialPath;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: locale,
        theme: TenturaTheme.light(),
        scaffoldMessengerKey: snackbarKey,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => UiEffectHandler(
          effects: effects,
          child: child ?? const SizedBox.shrink(),
        ),
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          includePrefixMatches: false,
          navigatorObservers: () => [ClearSnackBarsOnPushObserver()],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ShowMessage survives NavigateReplace home with push observer', (
    tester,
  ) async {
    await pumpHarness(tester, initialPath: kPathHome);

    // Mirror AcceptInviteCubit._finishWithMessage ordering.
    effects.emit(const ShowMessage(InviteInvalidCodeMessage()));
    effects.emit(const NavigateReplace(NavigateReplaceTarget.home));

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('work-root'), findsOneWidget);
    expect(
      find.text('Этот код приглашения недействителен.', findRichText: true),
      findsOneWidget,
    );
  });
}
