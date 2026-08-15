// Routing contract for nested beacon-view thread detail (UNIT 11): the parent
// host shares cubits with operational + detail children; the root redirect guard
// must preserve a matched thread child on cold loads.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_host_screen.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

import 'package:tentura/env.dart';

import '../../features/beacon_threads/room_cubit_fakes.dart';
import '../../features/beacon_threads/fake_coordination_item_case.dart';
import '../../support/test_realtime_sync.dart';

class _FakeAuthCubit extends Fake implements AuthCubit {
  _FakeAuthCubit()
    : _state = AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

  final AuthState _state;

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

BeaconThreadsCase _threadsCaseWithMessageTarget(RoomMessage message) {
  final fakeRoom = FakeBeaconThreadsRepository(userId: 'U1')
    ..fetchMessageTargetsById[message.id] = message;
  return BeaconThreadsCase(
    fakeRoom,
    FakeBeaconFactCardRepository(),
    FakePollingRepository(),
    FakeBeaconRoomHintsRepository(),
    RoomReadWatermarkStore.testing(),
    const FakeCoordinationItemCaseForRoom(),
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('request_thread_routing_test'),
  );
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

int _countRoutePages(List<AutoRoute> routes, String pageName) {
  var count = 0;
  for (final route in routes) {
    if (route.page.name == pageName) {
      count++;
    }
    final children = route.children;
    if (children != null) {
      count += _countRoutePages(children, pageName);
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final PageInfo realHomePage;
  late final PageInfo realMyWorkPage;
  late final PageInfo realBeaconViewPage;
  late final PageInfo realBeaconViewOperationalPage;
  late final PageInfo realThreadDetailPage;

  setUpAll(() {
    realHomePage = HomeRoute.page;
    realMyWorkPage = MyWorkRoute.page;
    realBeaconViewPage = BeaconViewRoute.page;
    realBeaconViewOperationalPage = BeaconViewOperationalRoute.page;
    realThreadDetailPage = ThreadDetailRoute.page;

    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => const _TestHomeShell(),
    );
    MyWorkRoute.page = PageInfo(
      MyWorkRoute.name,
      builder: (_) =>
          const Text('my-work-root', textDirection: TextDirection.ltr),
    );

    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        final entry = data.queryParams.optString('entry') ?? '';
        return Text(
          'beacon-operational:$id:$entry',
          textDirection: TextDirection.ltr,
        );
      },
    );

    ThreadDetailRoute.page = PageInfo(
      ThreadDetailRoute.name,
      builder: (data) {
        final id = data.inheritedPathParams.getString('id', '');
        final threadId = data.pathParams.getString('threadId', '');
        final messageId = data.queryParams.optString(kQueryMessageId) ?? '';
        return Text(
          'thread-detail:$id:$threadId:$messageId',
          textDirection: TextDirection.ltr,
        );
      },
    );

    BeaconViewRoute.page = PageInfo(
      BeaconViewRoute.name,
      builder: (data) {
        final id = data.pathParams.getString('id', '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('beacon-host:$id', textDirection: TextDirection.ltr),
            const Expanded(child: AutoRouter()),
          ],
        );
      },
    );
  });

  tearDownAll(() {
    HomeRoute.page = realHomePage;
    MyWorkRoute.page = realMyWorkPage;
    BeaconViewRoute.page = realBeaconViewPage;
    BeaconViewOperationalRoute.page = realBeaconViewOperationalPage;
    ThreadDetailRoute.page = realThreadDetailPage;
  });

  late RootRouter router;
  var _routerPumped = false;

  tearDown(() {
    if (_routerPumped) {
      router.dispose();
      _routerPumped = false;
    }
    if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
      GetIt.I.unregister<BeaconThreadsCase>();
    }
  });

  Future<void> pumpRouter(
    WidgetTester tester, {
    required String initialPath,
    bool viaPlatform = false,
  }) async {
    router = RootRouter(
      Logger('test'),
      _FakeAuthCubit(),
      _FakeSettingsCubit(),
      PostJoinNavigationCubit(),
    );
    _routerPumped = true;
    if (viaPlatform) {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = initialPath;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
    }
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: viaPlatform
              ? router.deepLinkBuilder
              : (_) => DeepLink.path(initialPath),
          deepLinkTransformer: router.deepLinkTransformer,
          includePrefixMatches: false,
          reevaluateListenable: router.reevaluateListenable,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String currentUrl() => router.navigationHistory.urlState.url;

  group('request thread routing', () {
    test('registers nested thread detail only under beacon view', () {
      final children = browseDetailChildren(checkIfIsMe: (_) => false);
      expect(
        _countRoutePages(children, ThreadDetailRoute.name),
        1,
        reason: 'ThreadDetailRoute must be registered exactly once as a child',
      );
      expect(
        _countRoutePages(children, BeaconViewOperationalRoute.name),
        1,
      );
    });

    testWidgets(
      'cold root detail URL preserves the matched thread child through the '
      'redirect guard',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/beacon/view/B1/thread/T1?message=M1',
          viaPlatform: true,
        );

        expect(find.text('beacon-host:B1'), findsOneWidget);
        expect(find.text('thread-detail:B1:T1:M1'), findsOneWidget);
        expect(
          currentUrl(),
          '/home/work/beacon/view/B1/thread/T1?message=M1',
        );
      },
    );

    testWidgets(
      'branch pop from detail reveals one operational page without duplicate '
      'beacon hosts',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B1/thread/T1',
        );

        expect(find.text('thread-detail:B1:T1:'), findsOneWidget);

        final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
        final workBranch = tabsRouter?.stackRouterOfIndex(
          HomeTabSpec.forTab(HomeTab.work).index,
        );
        final beaconNested = workBranch?.innerRouterOf<StackRouter>(
          BeaconViewRoute.name,
        );
        expect(beaconNested, isNotNull);
        expect(beaconNested!.stack.length, 2);
        expect(beaconNested.stack.last.name, ThreadDetailRoute.name);

        await beaconNested.maybePop();
        await tester.pumpAndSettle();

        expect(find.text('beacon-operational:B1:'), findsOneWidget);
        expect(find.textContaining('thread-detail:'), findsNothing);
        expect(currentUrl(), '/home/work/beacon/view/B1');
        expect(beaconNested.stack.length, 1);
        expect(beaconNested.stack.single.name, BeaconViewOperationalRoute.name);
        expect(
          workBranch!.stack.where((r) => r.name == BeaconViewRoute.name),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'second back after thread pop leaves beacon to My Work',
      (tester) async {
        await pumpRouter(
          tester,
          initialPath: '/home/work/beacon/view/B1/thread/T1',
        );

        final tabsRouter = router.innerRouterOf<TabsRouter>(HomeRoute.name);
        final workBranch = tabsRouter?.stackRouterOfIndex(
          HomeTabSpec.forTab(HomeTab.work).index,
        );
        final beaconNested = workBranch?.innerRouterOf<StackRouter>(
          BeaconViewRoute.name,
        );
        expect(beaconNested, isNotNull);

        // General chat → request
        await beaconNested!.maybePop();
        await tester.pumpAndSettle();
        expect(find.text('beacon-operational:B1:'), findsOneWidget);
        expect(workBranch!.stackData.length, greaterThan(1));

        // Request → My Desk (app-bar back / maybePopTop)
        expect(await router.maybePopTop(), isTrue);
        await tester.pumpAndSettle();

        expect(find.text('my-work-root'), findsOneWidget);
        expect(currentUrl(), '/home/work');
        expect(
          workBranch.stackData.length,
          1,
          reason: 'second back must pop BeaconView off the work branch',
        );
      },
    );

    test(
      'message-only URL resolves semantic thread id instead of General',
      () async {
        final message = RoomMessage(
          id: 'M42',
          beaconId: 'B9',
          authorId: 'U1',
          body: 'hello',
          createdAt: DateTime.utc(2026, 1, 1),
          threadItemId: 'item-9',
        );
        final case_ = _threadsCaseWithMessageTarget(message);

        final threadId = await resolveCanonicalThreadIdForMessage(
          threadsCase: case_,
          beaconId: 'B9',
          messageId: 'M42',
        );

        expect(threadId, 'item-9');
      },
    );

    test(
      'message-only URL without item thread falls back to General',
      () async {
        final message = RoomMessage(
          id: 'M43',
          beaconId: 'B9',
          authorId: 'U1',
          body: 'hello',
          createdAt: DateTime.utc(2026, 1, 1),
        );
        final case_ = _threadsCaseWithMessageTarget(message);

        final threadId = await resolveCanonicalThreadIdForMessage(
          threadsCase: case_,
          beaconId: 'B9',
          messageId: 'M43',
        );

        expect(threadId, RequestThread.generalId);
      },
    );
  });
}
