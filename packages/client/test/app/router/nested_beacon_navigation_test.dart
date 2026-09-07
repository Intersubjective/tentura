import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime(2026),
    currentAccountId: 'U1',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootRouter router;
  late PageInfo homePage;
  late PageInfo workPage;
  late PageInfo beaconPage;
  late PageInfo operationalPage;

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
    BeaconViewRoute.page = PageInfo(
      BeaconViewRoute.name,
      builder: (data) => Column(
        children: [
          Text(
            'request:${data.inheritedPathParams.getString('id', '')}',
            textDirection: TextDirection.ltr,
          ),
          Text(
            'thread-query:${data.queryParams.optString(kQueryThreadId) ?? ''}',
            textDirection: TextDirection.ltr,
          ),
          const Expanded(child: AutoRouter()),
        ],
      ),
    );
    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (_) => const Text(
        'operational',
        textDirection: TextDirection.ltr,
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
    BeaconViewRoute.page = beaconPage;
    BeaconViewOperationalRoute.page = operationalPage;
  });

  setUp(() {
    router = RootRouter(
      Logger('NestedBeaconNavigationTest'),
      _Auth(),
      _Settings(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() => router.dispose());

  test('browse deep link resolves legacy thread path to normalized query', () {
    final stack = buildBrowseDeepLinkStack(
      Uri.parse('/beacon/view/B1/thread/legacy-item'),
    );
    expect(stack, isNotNull);
    expect(stack!.detail.routeName, BeaconViewRoute.name);
    final route = stack.detail as BeaconViewRoute;
    expect(route.rawQueryParams['thread'], 'legacy-item');
    expect(route.rawQueryParams['tab'], kBeaconViewTabThreads);
  });

  testWidgets('legacy thread URL lands on operational ROOM query', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/beacon/view/B1/thread/legacy-item';
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

    expect(find.text('request:B1'), findsOneWidget);
    expect(find.text('thread-query:legacy-item'), findsOneWidget);
    expect(find.text('operational'), findsOneWidget);
    expect(
      router.navigationHistory.urlState.url,
      '/beacon/view/B1?tab=threads&thread=legacy-item',
    );
  });

  test('buildBrowseDeepLinkStack resolves child beacon URL', () {
    final stack = buildBrowseDeepLinkStack(Uri.parse('/beacon/view/child-1'));
    expect(stack, isNotNull);
    expect(stack!.detail.routeName, BeaconViewRoute.name);
  });

  testWidgets('router pop after nested push drops child from stack', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/beacon/view/parent-1';
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
    await tester.pump();

    unawaited(router.push(BeaconViewRoute(id: 'child-1')));
    await tester.pumpAndSettle();
    expect(router.stackData.last.name, BeaconViewRoute.name);

    router.pop();
    await tester.pump();
    expect(
      router.stackData.where((data) => data.name == BeaconViewRoute.name),
      hasLength(1),
    );
  });

  testWidgets('general deep link stays on request overview without thread page', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/beacon/view/B1?tab=threads&thread=general';
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

    expect(find.text('request:B1'), findsOneWidget);
    expect(find.text('thread-query:general'), findsOneWidget);
    expect(find.text('operational'), findsOneWidget);
    final url = Uri.parse(router.navigationHistory.urlState.url);
    expect(url.path, '/beacon/view/B1');
    expect(url.queryParameters['thread'], 'general');
  });
}
