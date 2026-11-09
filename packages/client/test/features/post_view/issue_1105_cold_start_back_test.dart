// #1105: cold start on `/beacon/view/<postId>` (and alias `/post/view/`) must
// return to Posts on in-app Back, and unsent reply drafts ask before leaving.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/service/unsaved_changes_guard_impl.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/unsaved_changes_guard_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart' show kPhoneSurface, usePhoneSurface;
import '../../support/remote_wire_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart';

const _postId = 'B1105postcold1';
const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _author = Profile(id: 'Uauthor', displayName: 'Author');

Beacon _beacon(String id, BeaconKind kind) => Beacon(
  id: id,
  title: 'Route beacon',
  kind: kind,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: _author,
);

class _BeaconOnlyRepository implements BeaconRepository {
  _BeaconOnlyRepository(this.beacons);

  final Map<String, Beacon> beacons;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => beacons[id]!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconKindRepository implements BeaconKindRepository {
  _FakeBeaconKindRepository(this.kinds);

  final Map<String, BeaconKind> kinds;

  @override
  Future<BeaconKind> fetchKind(String beaconId) async => kinds[beaconId]!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

PageInfo _rootLabel(String name, String label) => PageInfo(
  name,
  builder: (_) => Text(label, textDirection: TextDirection.ltr),
);

class _ColdStartRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: HomeRoute.page,
      path: '/home',
      children: [
        AutoRoute(
          initial: true,
          page: workTabShell.page,
          path: 'work',
          children: [
            AutoRoute(initial: true, page: MyWorkRoute.page, path: ''),
          ],
        ),
        AutoRoute(
          page: conversationsTabShell.page,
          path: 'conversations',
          children: [
            AutoRoute(initial: true, page: ConversationsRoute.page, path: ''),
          ],
        ),
      ],
    ),
    AutoRoute(
      page: BeaconViewRoute.page,
      path: '/beacon/view/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
    AutoRoute(
      page: PostViewRoute.page,
      path: '/post/view/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
  ];
}

class _RoutingAppNavigator extends FakeAppNavigator {
  late StackRouter router;

  @override
  int? get activeHomeTabIndex => homeTabIndex;

  @override
  Future<void> openHomeTab(HomeTab tab) async {
    await super.openHomeTab(tab);
    final spec = HomeTabSpec.forTab(tab);
    homeTabIndex = spec.index;
    router
        .innerRouterOf<TabsRouter>(HomeRoute.name)
        ?.setActiveIndex(spec.index);
    await router.replacePath(spec.path);
  }

  @override
  Future<void> resetToHome({HomeTab? tab}) async {
    await super.resetToHome(tab: tab);
    final spec = tab == null ? null : HomeTabSpec.forTab(tab);
    homeTabIndex = spec?.index;
    if (spec != null) {
      await router.replaceAll([
        HomeRoute(
          children: [
            spec.shell(children: [spec.rootRoute()]),
          ],
        ),
      ]);
    }
  }
}

late PageInfo _savedHomePage;
late PageInfo _savedWorkPage;
late PageInfo _savedConversationsPage;

Future<_ColdStartRouter> _pumpAt(
  WidgetTester tester, {
  required Uri coldUri,
  Locale locale = const Locale('en'),
  Size? surfaceSize,
}) async {
  _savedHomePage = HomeRoute.page;
  _savedWorkPage = MyWorkRoute.page;
  _savedConversationsPage = ConversationsRoute.page;
  addTearDown(() {
    HomeRoute.page = _savedHomePage;
    MyWorkRoute.page = _savedWorkPage;
    ConversationsRoute.page = _savedConversationsPage;
  });

  HomeRoute.page = PageInfo(
    HomeRoute.name,
    builder: (_) => AutoTabsRouter(
      routes: [workTabShell(), conversationsTabShell()],
      duration: Duration.zero,
      transitionBuilder: (_, child, _) => child,
      builder: (_, child) => child,
    ),
  );
  MyWorkRoute.page = _rootLabel(MyWorkRoute.name, 'work-root');
  ConversationsRoute.page = _rootLabel(
    ConversationsRoute.name,
    'conversations-root',
  );

  final beaconId = coldUri.pathSegments.last;
  final kinds = _FakeBeaconKindRepository({beaconId: BeaconKind.post});
  final beacons = _BeaconOnlyRepository({
    beaconId: _beacon(beaconId, BeaconKind.post),
  });

  await registerBeaconViewHarnessGetIt(profile: _viewer);
  if (GetIt.I.isRegistered<BeaconKindRepository>()) {
    await GetIt.I.unregister<BeaconKindRepository>();
  }
  if (GetIt.I.isRegistered<BeaconRepository>()) {
    await GetIt.I.unregister<BeaconRepository>();
  }
  if (GetIt.I.isRegistered<UnsavedChangesGuardPort>()) {
    await GetIt.I.unregister<UnsavedChangesGuardPort>();
  }
  if (GetIt.I.isRegistered<AppNavigator>()) {
    await GetIt.I.unregister<AppNavigator>();
  }
  final navigator = _RoutingAppNavigator();
  final router = _ColdStartRouter();
  navigator.router = router;
  GetIt.I
    ..registerSingleton<BeaconKindRepository>(kinds)
    ..registerSingleton<BeaconRepository>(beacons)
    ..registerSingleton<UnsavedChangesGuardPort>(UnsavedChangesGuard())
    ..registerSingleton<AppNavigator>(navigator);
  navigator.homeTabIndex = HomeTabSpec.forTab(HomeTab.work).index;

  addTearDown(() async {
    await GetIt.I.unregister<BeaconKindRepository>();
    await GetIt.I.unregister<BeaconRepository>();
    await GetIt.I.unregister<UnsavedChangesGuardPort>();
    await GetIt.I.unregister<AppNavigator>();
    await unregisterBeaconViewHarnessGetIt();
  });

  final stack = buildBrowseDeepLinkStack(coldUri)!;

  final size = surfaceSize ?? kBeaconViewHarnessCompact;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _ProfileCubit(),
      child: MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink([stack.home, stack.detail]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#1105 cold start back', () {
    testWidgets('Post at /beacon/view back opens Conversations not Requests', (
      tester,
    ) async {
      final router = await _pumpAt(
        tester,
        coldUri: Uri.parse('$kPathBeaconView/$_postId'),
      );
      expect(find.byType(PostViewScreen), findsOneWidget);

      await _tapBack(tester);

      expect(find.byType(PostViewScreen), findsNothing);
      expect(find.text('conversations-root'), findsOneWidget);
      expect(find.text('work-root'), findsNothing);
      expect(router.navigationHistory.urlState.url, kPathConversations);
    });

    testWidgets('/post/view/<id> cold start back opens Conversations', (
      tester,
    ) async {
      final router = await _pumpAt(
        tester,
        coldUri: Uri.parse('$kPathPostView/$_postId'),
      );
      expect(find.byType(PostViewScreen), findsOneWidget);
      await _tapBack(tester);
      expect(router.navigationHistory.urlState.url, kPathConversations);
    });

    testWidgets('375×667 RU: back with reply draft asks, cancel keeps text', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      resetBeaconRoomComposerDraftStoreForTest();

      await _pumpAt(
        tester,
        coldUri: Uri.parse('$kPathBeaconView/$_postId'),
        locale: const Locale('ru'),
        surfaceSize: kPhoneSurface,
      );

      const draftBody =
          'Черновик ответа в чате поста с длинным русским текстом для проверки.';
      writeBeaconRoomComposerDraft(beaconId: _postId, body: draftBody);

      await _tapBack(tester);
      expect(find.text('Выйти без сохранения?'), findsOneWidget);

      await tester.tap(find.text('Вернуться к заполнению'));
      await tester.pumpAndSettle();

      expect(find.byType(PostViewScreen), findsOneWidget);
      expect(readBeaconRoomComposerDraft(_postId), draftBody);

      await _tapBack(tester);
      await tester.tap(find.text('Выйти и сбросить'));
      await tester.pumpAndSettle();

      expect(find.byType(PostViewScreen), findsNothing);
      expect(find.text('conversations-root'), findsOneWidget);
    });
  });

  test(
    'BeaconViewRoute cold path still resolves Post kind on the wire',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'BeaconKindFetch': {
            '__typename': 'query_root',
            'beacon_by_pk': {
              '__typename': 'beacon',
              'id': _postId,
              'kind': 1,
            },
          },
        },
        sent,
        (remote) async {
          await remote.setSessionAuth();
          final repo = BeaconKindRepository(remote);
          await repo.fetchKind(_postId);
        },
      );
      expect(sent.map((w) => w.operationName), contains('BeaconKindFetch'));
    },
  );
}
