import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
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
  late PageInfo threadPage;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;
    beaconPage = BeaconViewRoute.page;
    operationalPage = BeaconViewOperationalRoute.page;
    threadPage = ThreadDetailRoute.page;
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
          const Expanded(child: AutoRouter()),
        ],
      ),
    );
    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (data) => Text(
        'operational:${data.queryParams.optString(kQueryMessageId) ?? ''}',
        textDirection: TextDirection.ltr,
      ),
    );
    ThreadDetailRoute.page = PageInfo(
      ThreadDetailRoute.name,
      builder: (data) => Text(
        'thread:${data.inheritedPathParams.getString('id', '')}:'
        '${data.pathParams.getString('threadId', '')}:'
        '${data.queryParams.optString(kQueryMessageId) ?? ''}',
        textDirection: TextDirection.ltr,
      ),
    );
  });

  tearDownAll(() {
    HomeRoute.page = homePage;
    MyWorkRoute.page = workPage;
    BeaconViewRoute.page = beaconPage;
    BeaconViewOperationalRoute.page = operationalPage;
    ThreadDetailRoute.page = threadPage;
  });

  setUp(() {
    router = RootRouter(
      Logger('RequestThreadRootRoutingTest'),
      _Auth(),
      _Settings(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() => router.dispose());

  testWidgets('cold canonical thread preserves path and query', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/beacon/view/B1/thread/T1?message=M1&entry=notification';
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

    expect(router.stackData.map((data) => data.name), [
      HomeRoute.name,
      BeaconViewRoute.name,
    ]);
    expect(find.text('request:B1'), findsOneWidget);
    expect(find.text('thread:B1:T1:M1'), findsOneWidget);
    expect(
      router.navigationHistory.urlState.url,
      '/beacon/view/B1/thread/T1?entry=notification&message=M1',
    );

    final nested = router.innerRouterOf<StackRouter>(BeaconViewRoute.name)!;
    unawaited(nested.maybePop());
    await tester.pumpAndSettle();
    expect(find.text('operational:M1'), findsOneWidget);
    expect(
      router.stackData.where((data) => data.name == BeaconViewRoute.name),
      hasLength(1),
    );
  });

  testWidgets('root request query remains a request URL', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/beacon/view/B1?tab=threads&thread=general&entry=my_work';
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

    final url = Uri.parse(router.navigationHistory.urlState.url);
    expect(url.path, '/beacon/view/B1');
    expect(url.queryParameters, {
      'tab': 'threads',
      'thread': 'general',
      'entry': 'my_work',
    });
    expect(router.stackData.map((data) => data.name), [
      HomeRoute.name,
      BeaconViewRoute.name,
    ]);
  });
}
