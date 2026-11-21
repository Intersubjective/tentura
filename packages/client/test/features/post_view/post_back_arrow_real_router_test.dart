// The Post screen's back arrow over the real RootRouter stack (only Home is
// stubbed; the real /beacon/view and /post/view pages build the real Post
// screen from the URL). Entry paths: a Home stub button (the list), a cold
// /post/view link, a cold /beacon/view link that the router canonicalises to
// /post/view, and a focus_fact link. A tap must leave the Post and land on
// Home, a following tap on the list must work, and an unsent composer draft
// asks first (Cancel keeps the Post and the draft, Discard leaves).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/service/unsaved_changes_guard_impl.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/unsaved_changes_guard_port.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/people_tags_widget_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _author = Profile(id: 'Uauthor000001', displayName: 'Author');

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: _viewer.id);

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

const _postId = 'Bbackpost0001';
const _activityPostId = 'post-1';

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
  Future<BeaconKind> fetchKind(String beaconId) async {
    return kinds[beaconId]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

final _l10n = L10nEn();

Future<RootRouter> _pump(
  WidgetTester tester,
  String location, {
  String postId = _postId,
  Widget? home,
}) async {
  await registerBeaconViewHarnessGetIt(profile: _viewer);
  registerEmptyPeopleTags();
  for (final unregister in [
    () async => GetIt.I.unregister<BeaconKindRepository>(),
    () async => GetIt.I.unregister<BeaconRepository>(),
    () async => GetIt.I.unregister<UnsavedChangesGuardPort>(),
  ]) {
    try {
      await unregister();
    } on Object {
      // Not registered by the harness.
    }
  }
  GetIt.I
    ..registerSingleton<BeaconKindRepository>(
      _FakeBeaconKindRepository({postId: BeaconKind.post}),
    )
    ..registerSingleton<BeaconRepository>(
      _BeaconOnlyRepository({postId: _beacon(postId, BeaconKind.post)}),
    )
    ..registerSingleton<UnsavedChangesGuardPort>(UnsavedChangesGuard());
  addTearDown(() async {
    await GetIt.I.unregister<BeaconKindRepository>();
    await GetIt.I.unregister<BeaconRepository>();
    await GetIt.I.unregister<UnsavedChangesGuardPort>();
    await unregisterBeaconViewHarnessGetIt();
  });

  final homePage = HomeRoute.page;
  addTearDown(() => HomeRoute.page = homePage);
  HomeRoute.page = PageInfo(
    HomeRoute.name,
    builder: (ctx) =>
        home ??
        Scaffold(
          body: Column(
            children: [
              const Text('home-stub'),
              TextButton(
                onPressed: () =>
                    unawaited(ctx.router.root.push(PostViewRoute(id: _postId))),
                child: const Text('open-detail'),
              ),
            ],
          ),
        ),
  );

  final router = RootRouter(
    Logger('PostBackArrowRouter'),
    _Auth(),
    _Settings(),
    PostJoinNavigationCubit(),
  );
  addTearDown(router.dispose);
  // Back goes through the real navigator, not the harness's fake.
  if (GetIt.I.isRegistered<AppNavigator>()) {
    await GetIt.I.unregister<AppNavigator>();
  }
  GetIt.I.registerSingleton<AppNavigator>(router);

  tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _ProfileCubit(),
      child: MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          includePrefixMatches: false,
        ),
      ),
    ),
  );
  await _settle(tester);
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await _settle(tester);
}

Future<void> _openFromList(WidgetTester tester) async {
  await tester.tap(find.text('open-detail'));
  await _settle(tester);
  expect(find.byType(PostViewScreen), findsOneWidget);
}

String _url(RootRouter r) => r.navigationHistory.urlState.url;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Grouped Post Activity navigation', () {
    testWidgets('with Home open, switches to Inbox and opens the message in '
        'the Post room', (tester) async {
      _stubActivityNavigationPages();
      final reselect = HomeTabReselectCubit();
      GetIt.I.registerSingleton(reselect);
      addTearDown(() async {
        await GetIt.I.unregister<HomeTabReselectCubit>();
        await reselect.close();
      });
      final router = await _pump(
        tester,
        kPathConversations,
        postId: _activityPostId,
        home: _activityNavigationHome(),
      );
      expect(router.stackData.map((route) => route.name), [HomeRoute.name]);
      final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name)!;
      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.conversations).index);

      unawaited(router.openFromUpdate(_groupedPostReceipt()));
      await _settle(tester);

      expect(router.stackData.map((route) => route.name), [
        HomeRoute.name,
        PostViewRoute.name,
      ]);
      expect(tabs.activeIndex, HomeTabSpec.forTab(HomeTab.inbox).index);
      expect(reselect.state.inboxReceiptsOpenCount, 1);
      final postScreen = find.byType(PostViewScreen);
      final roomSurface = find.descendant(
        of: postScreen,
        matching: find.byType(BeaconRoomSurface),
      );
      expect(postScreen, findsOneWidget);
      expect(roomSurface, findsOneWidget);
      final detail = router.stackData.last;
      final screen = tester.widget<PostViewScreen>(postScreen);
      final room = tester.widget<BeaconRoomSurface>(roomSurface);
      expect(detail.params.getString('id'), _activityPostId);
      expect(screen.id, _activityPostId);
      expect(
        {
          'route': Uri.parse(router.currentUrl).queryParameters['message'],
          'screen': screen.messageId,
          'room': room.messageId,
        },
        {'route': 'M1', 'screen': 'M1', 'room': 'M1'},
      );
    });

    testWidgets('without Home open, creates a Home stack with the message '
        'on the Post detail route', (tester) async {
      _stubActivityNavigationPages();
      final router = await _pump(
        tester,
        kPathDebugSettings,
        postId: _activityPostId,
        home: _activityNavigationHome(),
      );
      expect(router.stackData.map((route) => route.name), [
        DebugSettingsRoute.name,
      ]);

      await router.openFromUpdate(_groupedPostReceipt());
      await _settle(tester);

      expect(router.stackData.map((route) => route.name), [
        HomeRoute.name,
        PostViewRoute.name,
      ]);
      final detail = router.stackData.last.argsAs<PostViewRouteArgs>();
      expect(detail.id, _activityPostId);
      expect(detail.messageId, 'M1');
    });
  });

  group('Post back arrow, opened from the list', () {
    testWidgets('one tap returns to the list and a second open and back '
        'works too', (tester) async {
      final router = await _pump(tester, kPathConversations);
      await _openFromList(tester);
      final depth = router.stack.length;
      await _tapBack(tester);
      expect(router.stack.length, depth - 1);
      expect(find.byType(PostViewScreen), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
      expect(_url(router), kPathConversations);

      await _openFromList(tester);
      await _tapBack(tester);
      expect(find.byType(PostViewScreen), findsNothing);
    });

    testWidgets('unsent draft: Cancel keeps the Post and the draft, '
        'Discard leaves', (tester) async {
      resetBeaconRoomComposerDraftStoreForTest();
      await _pump(tester, kPathConversations);
      await _openFromList(tester);
      writeBeaconRoomComposerDraft(beaconId: _postId, body: 'unsent');

      await _tapBack(tester);
      expect(find.text(_l10n.composerDiscardTitle), findsOneWidget);
      await tester.tap(find.text(_l10n.composerDiscardKeepEditing));
      await _settle(tester);
      expect(find.byType(PostViewScreen), findsOneWidget);
      expect(readBeaconRoomComposerDraft(_postId), 'unsent');

      await _tapBack(tester);
      expect(find.text(_l10n.composerDiscardTitle), findsOneWidget);
      await tester.tap(find.text(_l10n.composerDiscardConfirm));
      await _settle(tester);
      expect(find.byType(PostViewScreen), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
    });
  });

  group('Post back arrow, deep links', () {
    for (final entry in {
      'a cold /post/view link': '$kPathPostView/$_postId',
      'a cold /beacon/view link canonicalised to /post/view':
          '$kPathBeaconView/$_postId',
      'a focus_fact link': '$kPathPostView/$_postId?focus_fact=Ffact0000001',
    }.entries) {
      testWidgets('${entry.key}: one tap lands on Conversations', (
        tester,
      ) async {
        final router = await _pump(tester, entry.value);
        expect(find.byType(PostViewScreen), findsOneWidget);
        expect(Uri.parse(_url(router)).path, '$kPathPostView/$_postId');
        await _tapBack(tester);
        expect(find.byType(PostViewScreen), findsNothing);
        expect(find.text('home-stub'), findsOneWidget);
        expect(_url(router), kPathConversations);

        // The list underneath still works.
        await _openFromList(tester);
        await _tapBack(tester);
        expect(find.byType(PostViewScreen), findsNothing);
      });
    }
  });
}

AttentionReceipt _groupedPostReceipt() {
  final message = AttentionReceipt(
    id: 'chat-receipt',
    category: 'coordination',
    kind: 'roomActivityLowPriority',
    priority: 'normal',
    title: 'New reply',
    body: 'I can bring a book',
    actionUrl: '/#/view?id=$_activityPostId',
    createdAt: DateTime.utc(2026, 11, 11, 12),
    collapsedCount: 1,
    presentationKey: 'room_message_posted',
    presentationPayloadJson: '{"eventType":"roomMessagePosted"}',
    surface: AttentionSurface.activity,
    beaconId: _activityPostId,
    beaconKind: 1,
    destinationKind: 'beacon_room_message',
    targetEntityId: 'M1',
  );
  return message.copyWith(
    id: 'group-$_activityPostId',
    collapsedCount: 0,
    itemKind: AttentionItemKind.requestActivity,
    destinationKind: 'beacon',
    targetEntityId: _activityPostId,
    presentationKey: 'request_status_changed',
    presentationPayloadJson: '{}',
    eventTotal: 1,
    eventsPreview: [message],
  );
}

Widget _activityNavigationHome() => AutoTabsRouter(
  routes: [for (final spec in HomeTabSpec.all) spec.shell()],
  duration: Duration.zero,
  transitionBuilder: (_, child, _) => child,
  builder: (_, child) => child,
);

void _stubActivityNavigationPages() {
  final conversations = ConversationsRoute.page;
  final inbox = InboxRoute.page;
  final settings = DebugSettingsRoute.page;
  addTearDown(() {
    ConversationsRoute.page = conversations;
    InboxRoute.page = inbox;
    DebugSettingsRoute.page = settings;
  });
  ConversationsRoute.page = PageInfo(
    ConversationsRoute.name,
    builder: (_) => const Text('Conversations'),
  );
  InboxRoute.page = PageInfo(
    InboxRoute.name,
    builder: (_) => const Text('Inbox'),
  );
  DebugSettingsRoute.page = PageInfo(
    DebugSettingsRoute.name,
    builder: (_) => const Text('Debug settings'),
  );
}
