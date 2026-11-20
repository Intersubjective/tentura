import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/router/unknown_hash_route_notice.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

final class _Auth extends Fake implements AuthCubit {
  _Auth(String accountId)
    : state = AuthState(
        updatedAt: DateTime(2026),
        currentAccountId: accountId,
      );

  @override
  final AuthState state;

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

void main() {
  late RootRouter router;
  late PageInfo lobbyPage;
  late PageInfo homePage;
  late PageInfo loginPage;

  setUpAll(() {
    lobbyPage = BeaconLobbyRoute.page;
    homePage = HomeRoute.page;
    loginPage = AuthLoginRoute.page;

    BeaconLobbyRoute.page = PageInfo(
      BeaconLobbyRoute.name,
      builder: (data) => Text('Lobby for ${data.params.getString('id')}'),
    );
    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const Text('Home'),
    );
    AuthLoginRoute.page = PageInfo(
      AuthLoginRoute.name,
      builder: (_) => const Text('Sign in'),
    );
  });

  tearDownAll(() {
    BeaconLobbyRoute.page = lobbyPage;
    HomeRoute.page = homePage;
    AuthLoginRoute.page = loginPage;
  });

  tearDown(() {
    router.dispose();
    UnknownHashRouteNotice.instance.resetForTest();
  });

  group('Opening a Questions link at launch', () {
    for (final (session, accountId) in [
      ('signed in', 'U1'),
      ('signed out', ''),
    ]) {
      testWidgets('shows the requested lobby when $session', (tester) async {
        const requestId = 'Bquestionsvm01';
        router = RootRouter(
          Logger('QuestionsDeepLinkRouteTest'),
          _Auth(accountId),
          _Settings(),
          PostJoinNavigationCubit(),
        );
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            '/beacon/questions/$requestId';
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );

        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router.config(
              deepLinkBuilder: router.deepLinkBuilder,
              deepLinkTransformer: router.deepLinkTransformer,
              reevaluateListenable: router.reevaluateListenable,
              includePrefixMatches: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final stack = router.stackData;
        expect(stack, isNotEmpty);
        expect(stack.last.name, BeaconLobbyRoute.name);
        expect(stack.last.params.optString('id'), requestId);
        expect(
          stack.map((route) => route.name),
          isNot(contains(AuthLoginRoute.name)),
        );
        expect(find.text('Lobby for $requestId'), findsOneWidget);
        expect(find.textContaining(':id'), findsNothing);
      });
    }
  });
}
