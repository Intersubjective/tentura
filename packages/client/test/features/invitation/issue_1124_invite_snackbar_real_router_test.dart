// #1124: invalid / used invite links must show feedback on Requests after
// resetToHome — real RootRouter, AppNavigator, UiEffectHandler, and observers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/invite_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/bloc/register_invite_cubit.dart';
import 'package:tentura/features/auth/ui/screen/auth_register_screen.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../support/phone_surface.dart';
import 'accept_invite_cubit_test.dart' show FakeInvitationAcceptPort;

final class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit({this.authenticated = true})
    : _state = AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: authenticated ? 'U1' : '',
      );

  final bool authenticated;
  final AuthState _state;

  @override
  AuthState get state => _state;

  @override
  bool get isClosed => false;

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
  late FakeInvitationAcceptPort repo;
  late PageInfo homePage;
  late PageInfo workPage;
  late PageInfo acceptInvitePage;
  late PageInfo authRegisterPage;

  const testEnv = Env(needInviteCode: true);

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;
    acceptInvitePage = AcceptInviteRoute.page;
    authRegisterPage = AuthRegisterRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _TestHomeShell(),
    );
    MyWorkRoute.page = _labelPage(MyWorkRoute.name, 'work-root');
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
    AcceptInviteRoute.page = PageInfo(
      AcceptInviteRoute.name,
      builder: (data) => AcceptInviteScreen(
        id: data.inheritedPathParams.getString('id', ''),
      ),
    );
    AuthRegisterRoute.page = PageInfo(
      AuthRegisterRoute.name,
      builder: (data) => AuthRegisterScreen(
        id: data.inheritedPathParams.getString('id', ''),
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
    AcceptInviteRoute.page = acceptInvitePage;
    AuthRegisterRoute.page = authRegisterPage;
  });

  setUp(() async {
    await GetIt.I.reset();
    repo = FakeInvitationAcceptPort();
    effects = UiEffectBus();
    final postJoin = PostJoinNavigationCubit();
    router = RootRouter(
      Logger('Issue1124InviteSnackTest'),
      _FakeAuthCubit(),
      _FakeSettingsCubit(),
      postJoin,
    );
    GetIt.I
      ..registerSingleton<AppNavigator>(router)
      ..registerSingleton<UiEffectPort>(effects)
      ..registerSingleton<PostJoinNavigationCubit>(postJoin)
      ..registerSingleton<Env>(testEnv)
      ..registerSingleton<AuthCubit>(_FakeAuthCubit())
      ..registerSingleton<RegisterInviteCubit>(
        RegisterInviteCubit.withPort(
          repo,
          effects: effects,
        ),
      )
      ..registerSingleton<AcceptInviteCubit>(
        AcceptInviteCubit.withPort(
          repo,
          effects: effects,
          postJoinNavigation: postJoin,
        ),
      );
  });

  tearDown(() async {
    router.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpInviteDeepLink(
    WidgetTester tester, {
    required String rawInvitePath,
    Locale locale = const Locale('ru'),
    bool authenticated = true,
    bool skipDeepLinkTransform = false,
  }) async {
    router.dispose();
    final postJoin = GetIt.I<PostJoinNavigationCubit>();
    router = RootRouter(
      Logger('Issue1124InviteSnackTest'),
      _FakeAuthCubit(authenticated: authenticated),
      _FakeSettingsCubit(),
      postJoin,
    );
    GetIt.I
      ..unregister<AppNavigator>()
      ..registerSingleton<AppNavigator>(router)
      ..unregister<AuthCubit>()
      ..registerSingleton<AuthCubit>(
        _FakeAuthCubit(authenticated: authenticated),
      );

    final initial = skipDeepLinkTransform
        ? rawInvitePath
        : () {
            final transformed = transformInviteDeepLink(
              uri: Uri.parse(rawInvitePath),
              isAuthenticated: authenticated,
            );
            return transformed.hasQuery
                ? '${transformed.path}?${transformed.query}'
                : transformed.path;
          }();
    tester.binding.platformDispatcher.defaultRouteNameTestValue = initial;
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
        builder: (context, child) => TenturaResponsiveScope(
          child: UiEffectHandler(
            effects: effects,
            child: child ?? const SizedBox.shrink(),
          ),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  String snackPlainText(WidgetTester tester) {
    return find
        .descendant(
          of: find.byType(SnackBar),
          matching: find.byType(RichText),
        )
        .evaluate()
        .map((e) => (e.widget as RichText).text.toPlainText())
        .join(' ');
  }

  testWidgets('/invite/BADCODE123 RU phone shows invalid copy on work tab', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await pumpInviteDeepLink(tester, rawInvitePath: '/invite/BADCODE123');

    expect(find.text('work-root'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      snackPlainText(tester),
      contains('Этот код приглашения недействителен.'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'signed-in /invite/IQAFX0000000- shows trailing-dash hint (RU phone)',
    (tester) async {
      await usePhoneSurface(tester);
      await pumpInviteDeepLink(
        tester,
        rawInvitePath: '/invite/IQAFX0000000-',
      );

      expect(find.text('work-root'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        snackPlainText(tester),
        contains('лишний дефис'),
      );
    },
  );

  testWidgets(
    'used invite shows no-longer-valid copy EN on work tab',
    (tester) async {
      repo.previewResult = const InvitePreview(
        codeStatus: InviteCodeStatus.consumed,
        callerStatus: InviteCallerStatus.existingUser,
        inviter: InvitePreviewInviter(id: 'U2', displayName: 'Bob'),
      );
      await usePhoneSurface(tester);
      await pumpInviteDeepLink(
        tester,
        rawInvitePath: '/invite/I1761b784b1cb',
        locale: const Locale('en'),
      );

      expect(find.text('work-root'), findsOneWidget);
      expect(
        find.text('This invite is no longer valid.', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'signed-out /invite/BADCODE123 cold start prefills code and shows invalid (RU phone)',
    (tester) async {
      await usePhoneSurface(tester);
      await pumpInviteDeepLink(
        tester,
        rawInvitePath: '/invite/BADCODE123',
        authenticated: false,
      );

      expect(find.byType(AuthRegisterScreen), findsOneWidget);
      final inviteField = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .first;
      expect(inviteField.controller?.text, 'BADCODE123');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        snackPlainText(tester),
        contains('Этот код приглашения недействителен.'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'signed-out /invite/IQAFX0000000- shows trailing-dash hint EN phone',
    (tester) async {
      await usePhoneSurface(tester);
      await pumpInviteDeepLink(
        tester,
        rawInvitePath: '/invite/IQAFX0000000-',
        authenticated: false,
        locale: const Locale('en'),
      );

      expect(find.byType(AuthRegisterScreen), findsOneWidget);
      final inviteField = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .first;
      expect(inviteField.controller?.text, 'IQAFX0000000-');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        snackPlainText(tester),
        contains('extra dash'),
      );
    },
  );
}
