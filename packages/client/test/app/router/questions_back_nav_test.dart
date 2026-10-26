// #689: leaving Questions with the app-bar arrow, then pressing the system
// Back, returned to Questions instead of where the Request was opened from.
// Questions was already left, so it must not be in the history any more.
//
// What a widget test can show: the router stack after the arrow and after
// Back (the browser's own history list is not simulated here; the web path,
// which steps back through that history, is covered by the e2e back-nav
// suite, scenario D8).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/screen/beacon_lobby_screen.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _requestPath = '/beacon/view/B1';
const _questionsPath = '/beacon/lobby/B1';

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

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
  late PageInfo lobbyPage;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;
    beaconPage = BeaconViewRoute.page;
    operationalPage = BeaconViewOperationalRoute.page;
    lobbyPage = BeaconLobbyRoute.page;
    HomeRoute.page = PageInfo(HomeRoute.name, builder: (_) => const _Home());
    MyWorkRoute.page = PageInfo(
      MyWorkRoute.name,
      builder: (_) => const Text('work-root'),
    );
    BeaconViewRoute.page = PageInfo(
      BeaconViewRoute.name,
      builder: (_) => const AutoRouter(),
    );
    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (_) => const Text('request-page'),
    );
    // The real Questions arrow over a stand-in body.
    BeaconLobbyRoute.page = PageInfo(
      BeaconLobbyRoute.name,
      builder: (data) => Scaffold(
        appBar: AppBar(
          leading: BeaconLobbyBackButton(
            beaconId: data.params.optString('id') ?? '',
          ),
        ),
        body: const Text('questions-page'),
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
    BeaconViewRoute.page = beaconPage;
    BeaconViewOperationalRoute.page = operationalPage;
    BeaconLobbyRoute.page = lobbyPage;
  });

  setUp(() {
    router = RootRouter(
      Logger('QuestionsBackNavTest'),
      _Auth(),
      _Settings(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() => router.dispose());

  Future<void> pumpAt(WidgetTester tester, String url) async {
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

  List<String> stack() => [for (final r in router.stackData) r.name];

  /// The Request opened from Home, then its Questions.
  Future<void> openQuestionsFromRequest(WidgetTester tester) async {
    await pumpAt(tester, _requestPath);
    expect(stack(), [HomeRoute.name, BeaconViewRoute.name]);
    // push completes only when the route is popped; do not wait on it.
    unawaited(router.push(BeaconLobbyRoute(beaconId: 'B1')));
    await tester.pumpAndSettle();
    expect(find.text('questions-page'), findsOneWidget);
  }

  Future<void> tapArrow(WidgetTester tester) async {
    await tester.tap(find.byType(BeaconLobbyBackButton));
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('arrow, then Back, leaves the Request for Home', (tester) async {
    await openQuestionsFromRequest(tester);

    await tapArrow(tester);
    expect(stack(), [HomeRoute.name, BeaconViewRoute.name]);
    expect(find.text('request-page'), findsOneWidget);

    await systemBack(tester);
    expect(stack(), [HomeRoute.name]);
    expect(find.text('questions-page'), findsNothing);
  });

  testWidgets('on the web the arrow steps back through the history, and the '
      'Request page is where it lands', (tester) async {
    await openQuestionsFromRequest(tester);

    await leaveBeaconLobby(router, beaconId: 'B1', web: true);
    await tester.pumpAndSettle();
    expect(stack(), [HomeRoute.name, BeaconViewRoute.name]);

    await systemBack(tester);
    expect(stack(), [HomeRoute.name]);
  });

  testWidgets('browser Back from Questions returns to the Request below, '
      'not a second copy of it', (tester) async {
    await openQuestionsFromRequest(tester);

    await _deliverBrowserRoute(tester, _requestPath);

    expect(stack(), [HomeRoute.name, BeaconViewRoute.name]);
    expect(find.text('request-page'), findsOneWidget);
    expect(find.text('questions-page'), findsNothing);
  });

  testWidgets('opened cold (a link, a reload): the arrow replaces Questions '
      'with its Request, and Back does not return to Questions', (
    tester,
  ) async {
    await pumpAt(tester, _questionsPath);
    expect(stack(), [BeaconLobbyRoute.name]);

    await tapArrow(tester);
    expect(stack(), [HomeRoute.name, BeaconViewRoute.name]);
    expect(find.text('request-page'), findsOneWidget);

    await systemBack(tester);
    expect(stack(), [HomeRoute.name]);
    expect(find.text('questions-page'), findsNothing);
  });
}
