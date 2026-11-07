import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/router/unknown_hash_route_notice.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../support/phone_surface.dart';

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

class _NoticeHarness extends StatelessWidget {
  const _NoticeHarness();

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      routes: [for (final spec in HomeTabSpec.all) spec.shell()],
      duration: Duration.zero,
      transitionBuilder: (_, child, _) => child,
      builder: (context, child) {
        return Scaffold(
          body: UnknownHashRouteNoticeListener(
            tabsRouter: context.tabsRouter,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

PageInfo _labelPage(String name, String label) => PageInfo(
  name,
  builder: (_) => Text(label, textDirection: TextDirection.ltr),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RootRouter router;
  late PageInfo homePage;
  late PageInfo workPage;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _NoticeHarness(),
    );
    MyWorkRoute.page = _labelPage(MyWorkRoute.name, 'work-root');
    for (final spec in HomeTabSpec.all) {
      final route = spec.rootRoute();
      switch (spec.tab) {
        case HomeTab.work:
          continue;
        default:
          final name = route.routeName;
          final page = PageInfo(
            name,
            builder: (_) =>
                Text('$name-root', textDirection: TextDirection.ltr),
          );
          switch (spec.tab) {
            case HomeTab.conversations:
              ConversationsRoute.page = page;
            case HomeTab.inbox:
              InboxRoute.page = page;
            case HomeTab.constellation:
              ConstellationRoute.page = page;
            case HomeTab.network:
              FriendsRoute.page = page;
            case HomeTab.me:
              ProfileRoute.page = page;
            case HomeTab.work:
            case HomeTab.updates:
              break;
          }
      }
    }
    AuthLoginRoute.page = _labelPage(AuthLoginRoute.name, 'auth-login');
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
  });

  setUp(() {
    UnknownHashRouteNotice.instance.resetForTest();
    router = RootRouter(
      Logger('UnknownHashNoticeRuTest'),
      _FakeAuthCubit(),
      _FakeSettingsCubit(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() => router.dispose());

  Future<void> pumpUnknownHashRoute(WidgetTester tester) async {
    await usePhoneSurface(tester);
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/doesnotexist';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('ru'),
        scaffoldMessengerKey: snackbarKey,
        localizationsDelegates: const [
          ...L10n.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
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

  testWidgets('shows the RU snackbar once on wildcard fallback', (
    tester,
  ) async {
    await pumpUnknownHashRoute(tester);
    if (!UnknownHashRouteNotice.instance.hasPending) {
      router.deepLinkTransformer(Uri.parse('/doesnotexist'));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    final messageText = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Эта ссылка недоступна',
      ),
    );
    expect(messageText, findsOneWidget);

    final box = tester.getRect(messageText);
    expect(box.width, lessThanOrEqualTo(kPhoneSurface.width));
    expect(box.bottom, lessThanOrEqualTo(kPhoneSurface.height));

    unawaited(router.pushPath('/settings/zzz'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
