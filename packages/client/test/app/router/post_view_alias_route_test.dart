import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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
  late PageInfo conversationsPage;
  late PageInfo beaconPage;
  late PageInfo postPage;
  late PageInfo operationalPage;

  setUpAll(() {
    homePage = HomeRoute.page;
    workPage = MyWorkRoute.page;
    conversationsPage = ConversationsRoute.page;
    beaconPage = BeaconViewRoute.page;
    postPage = PostViewRoute.page;
    operationalPage = BeaconViewOperationalRoute.page;

    HomeRoute.page = PageInfo(HomeRoute.name, builder: (_) => const _Home());
    MyWorkRoute.page = PageInfo(
      MyWorkRoute.name,
      builder: (_) => const Text('work-root', textDirection: TextDirection.ltr),
    );
    ConversationsRoute.page = PageInfo(
      ConversationsRoute.name,
      builder: (_) => const Text(
        'conversations-root',
        textDirection: TextDirection.ltr,
      ),
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
    PostViewRoute.page = PageInfo(
      PostViewRoute.name,
      builder: (data) => Column(
        children: [
          Text(
            'post:${data.inheritedPathParams.getString('id', '')}',
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
    ConversationsRoute.page = conversationsPage;
    BeaconViewRoute.page = beaconPage;
    PostViewRoute.page = postPage;
    BeaconViewOperationalRoute.page = operationalPage;
  });

  setUp(() {
    router = RootRouter(
      Logger('PostViewAliasRouteTest'),
      _Auth(),
      _Settings(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() => router.dispose());

  group('buildBrowseDeepLinkStack', () {
    test('resolves /post/view/<id> to PostViewRoute with that id', () {
      const id = 'Bpostalias001';
      final stack = buildBrowseDeepLinkStack(
        Uri.parse('$kPathPostView/$id'),
      );
      expect(stack, isNotNull);
      expect(stack!.detail.routeName, PostViewRoute.name);
      final route = stack.detail as PostViewRoute;
      expect(route.rawPathParams['id'], id);
    });

    test(
      'resolves legacy /beacon/view/<id> to BeaconViewRoute with that id',
      () {
        const id = 'Blegacyalias01';
        final stack = buildBrowseDeepLinkStack(
          Uri.parse('$kPathBeaconView/$id'),
        );
        expect(stack, isNotNull);
        expect(stack!.detail.routeName, BeaconViewRoute.name);
        final route = stack.detail as BeaconViewRoute;
        expect(route.rawPathParams['id'], id);
      },
    );

    test('ignores a literal :id segment', () {
      expect(
        buildBrowseDeepLinkStack(Uri.parse('$kPathPostView/:id')),
        isNull,
      );
      expect(
        buildBrowseDeepLinkStack(Uri.parse('$kPathBeaconView/:id')),
        isNull,
      );
    });
  });

  Future<void> pumpPath(WidgetTester tester, String path) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = path;
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
  }

  testWidgets('/post/view/<id> substitutes the path param into PostViewRoute', (
    tester,
  ) async {
    const id = 'Bpostdeeplink1';
    await pumpPath(tester, '$kPathPostView/$id');
    expect(find.text('post:$id'), findsOneWidget);
    expect(find.text('post::id'), findsNothing);
    expect(find.text('request:$id'), findsNothing);
  });

  testWidgets(
    'legacy /beacon/view/<id> still substitutes into BeaconViewRoute',
    (
      tester,
    ) async {
      const id = 'Breqdeeplink01';
      await pumpPath(tester, '$kPathBeaconView/$id');
      expect(find.text('request:$id'), findsOneWidget);
      expect(find.text('request::id'), findsNothing);
    },
  );

  testWidgets('literal /post/view/:id does not mount PostViewRoute', (
    tester,
  ) async {
    await pumpPath(tester, '$kPathPostView/:id');
    expect(find.textContaining('post::id'), findsNothing);
    expect(find.textContaining('request::id'), findsNothing);
    expect(
      router.stackData.where((route) => route.name == PostViewRoute.name),
      isEmpty,
    );
  });
}
