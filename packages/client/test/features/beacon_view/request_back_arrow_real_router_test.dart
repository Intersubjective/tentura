// The Request screen's back arrow over the real RootRouter stack (only page
// bodies and Home are stubbed). Entry paths: a Home stub whose button pushes
// the Request (the list), a Request pushed over another Request (stands in
// for the fact origin line, which pushes the same route), a cold deep link
// (stack depth 1) and a focus_fact link. Also: another surface selected, a
// bottom sheet opened and dismissed, and an unsent composer draft. A tap must
// leave the screen and a following tap must work too. Plan needs a PlanCubit
// the route scope does not provide, so People stands in as the non-Now
// surface; the origin-line widget itself is covered in fact_origin tests.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/people_tags_widget_harness.dart';
import 'beacon_view_screen_harness.dart';

const _first = 'Bfirst0000001';
const _second = 'Bsecond000001';
const _viewer = 'Uviewer000001';

/// Every beacon is a Request (so `/post/view/<id>` must canonicalise).
final class _RequestKinds extends Fake implements BeaconKindRepository {
  @override
  Future<BeaconKind> fetchKind(String beaconId) async => BeaconKind.request;
}

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: _viewer);

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

/// Pumps the real [RootRouter] at [location]; every Request page mounts the
/// real Request screen (author view) for the id in its URL.
Future<RootRouter> _pump(WidgetTester tester, String location) async {
  await registerBeaconViewHarnessGetIt();
  registerEmptyPeopleTags();
  if (GetIt.I.isRegistered<BeaconKindRepository>()) {
    await GetIt.I.unregister<BeaconKindRepository>();
  }
  GetIt.I.registerSingleton<BeaconKindRepository>(_RequestKinds());
  addTearDown(() async {
    if (GetIt.I.isRegistered<BeaconKindRepository>()) {
      await GetIt.I.unregister<BeaconKindRepository>();
    }
  });
  addTearDown(unregisterBeaconViewHarnessGetIt);
  final homePage = HomeRoute.page;
  final beaconPage = BeaconViewRoute.page;
  addTearDown(() {
    HomeRoute.page = homePage;
    BeaconViewRoute.page = beaconPage;
  });
  final savedPages = [
    MyWorkRoute.page,
    ConversationsRoute.page,
    InboxRoute.page,
    ConstellationRoute.page,
  ];
  addTearDown(() {
    MyWorkRoute.page = savedPages[0];
    ConversationsRoute.page = savedPages[1];
    InboxRoute.page = savedPages[2];
    ConstellationRoute.page = savedPages[3];
  });
  PageInfo label(String name) =>
      PageInfo(name, builder: (_) => const SizedBox.shrink());
  MyWorkRoute.page = label(MyWorkRoute.name);
  ConversationsRoute.page = label(ConversationsRoute.name);
  InboxRoute.page = label(InboxRoute.name);
  ConstellationRoute.page = label(ConstellationRoute.name);
  HomeRoute.page = PageInfo(
    HomeRoute.name,
    builder: (_) => AutoTabsRouter(
      routes: [
        workTabShell(),
        conversationsTabShell(),
        inboxTabShell(),
        constellationTabShell(),
      ],
      duration: Duration.zero,
      transitionBuilder: (_, child, _) => child,
      builder: (ctx, child) => Scaffold(
        body: Column(
          children: [
            const Text('home-stub'),
            TextButton(
              onPressed: () =>
                  unawaited(ctx.router.root.push(BeaconViewRoute(id: _first))),
              child: const Text('open-detail'),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
  BeaconViewRoute.page = PageInfo(
    BeaconViewRoute.name,
    builder: (data) {
      final id =
          data.params.optString('id') ??
          data.inheritedPathParams.optString('id') ??
          '';
      return beaconViewHarnessRouteScope(
        beaconState: beaconViewHarnessAuthorState(
          beaconId: id,
          authorId: _viewer,
        ),
        threadsState: beaconViewHarnessThreadsState(authorId: _viewer),
        child: const AutoRouter(),
      );
    },
  );

  final router = RootRouter(
    Logger('BackArrowRouter'),
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
    MaterialApp.router(
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
  );
  await _settle(tester);
  return router;
}

/// Bounded pumps: the Request screen never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapBack(WidgetTester tester) async {
  // The topmost route's arrow is the last one in tree order.
  await tester.tap(find.byIcon(Icons.arrow_back).last);
  await _settle(tester);
}

Future<void> _selectPeople(WidgetTester tester) async {
  await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
  await _settle(tester);
}

Future<void> _openFromList(WidgetTester tester) async {
  await tester.tap(find.text('open-detail'));
  await _settle(tester);
  expect(find.byType(BeaconViewScreen), findsOneWidget);
}

final _l10n = L10nEn();

int _activeHomeTab(RootRouter r) =>
    r.innerRouterOf<TabsRouter>(HomeRoute.name)!.activeIndex;

Uri _location(RootRouter r) => Uri.parse(r.navigationHistory.urlState.url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Request back arrow, warm stack', () {
    testWidgets('a Request pushed over another Request: one tap returns to '
        'the first, a second tap leaves that one too', (tester) async {
      final router = await _pump(tester, '/beacon/view/$_first');
      unawaited(router.push(BeaconViewRoute(id: _second)));
      await _settle(tester);
      expect(_location(router).path, '/beacon/view/$_second');
      final depth = router.stack.length;

      await _tapBack(tester);
      expect(router.stack.length, depth - 1);
      expect(_location(router).path, '/beacon/view/$_first');
      expect(find.byType(BeaconViewScreen), findsOneWidget);

      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('with another surface selected, one tap still leaves the '
        'Request', (tester) async {
      final router = await _pump(tester, '/beacon/view/$_first');
      unawaited(router.push(BeaconViewRoute(id: _second)));
      await _settle(tester);
      final depth = router.stack.length;

      await _selectPeople(tester);
      await _tapBack(tester);

      expect(router.stack.length, depth - 1);
      expect(_location(router).path, '/beacon/view/$_first');
    });

    testWidgets('with an unsent draft: Cancel keeps the screen and the '
        'draft, Discard leaves and clears it', (tester) async {
      resetBeaconRoomComposerDraftStoreForTest();
      final router = await _pump(tester, '/beacon/view/$_first');
      unawaited(router.push(BeaconViewRoute(id: _second)));
      await _settle(tester);
      final depth = router.stack.length;
      writeBeaconRoomComposerDraft(beaconId: _second, body: 'unsent text');

      await _tapBack(tester);
      expect(find.text(_l10n.composerDiscardTitle), findsOneWidget);
      await tester.tap(find.text(_l10n.composerDiscardKeepEditing));
      await _settle(tester);
      expect(router.stack.length, depth);
      expect(readBeaconRoomComposerDraft(_second), 'unsent text');

      await _tapBack(tester);
      expect(find.text(_l10n.composerDiscardTitle), findsOneWidget);
      await tester.tap(find.text(_l10n.composerDiscardConfirm));
      await _settle(tester);
      expect(router.stack.length, depth - 1);
      expect(readBeaconRoomComposerDraft(_second), isNull);
    });
  });

  group('Request back arrow, opened from the list', () {
    testWidgets('one tap returns to the list and the list works again', (
      tester,
    ) async {
      final router = await _pump(tester, kPathMyWork);
      await _openFromList(tester);
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
      expect(_location(router).path, kPathMyWork);

      // Reopen and leave again: no stuck re-entry guard.
      await _openFromList(tester);
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
    });

    testWidgets('after a bottom sheet is opened and dismissed one tap '
        'leaves', (tester) async {
      await _pump(tester, kPathMyWork);
      await _openFromList(tester);
      final ctx = tester.element(find.byType(BeaconViewScreen));
      unawaited(
        showModalBottomSheet<void>(
          context: ctx,
          builder: (_) => const SizedBox(height: 200, child: Text('a-sheet')),
        ),
      );
      await _settle(tester);
      expect(find.text('a-sheet'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
      expect(find.text('a-sheet'), findsNothing);

      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
    });

    testWidgets('with an unsent draft: Cancel keeps the Request and the '
        'draft, Discard returns to the list', (tester) async {
      resetBeaconRoomComposerDraftStoreForTest();
      await _pump(tester, kPathMyWork);
      await _openFromList(tester);
      writeBeaconRoomComposerDraft(beaconId: _first, body: 'unsent');

      await _tapBack(tester);
      expect(find.text(_l10n.composerDiscardTitle), findsOneWidget);
      await tester.tap(find.text(_l10n.composerDiscardKeepEditing));
      await _settle(tester);
      expect(find.byType(BeaconViewScreen), findsOneWidget);
      expect(readBeaconRoomComposerDraft(_first), 'unsent');

      await _tapBack(tester);
      await tester.tap(find.text(_l10n.composerDiscardConfirm));
      await _settle(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
    });

    testWidgets('with People selected one tap leaves to the list', (
      tester,
    ) async {
      await _pump(tester, kPathMyWork);
      await _openFromList(tester);
      await _selectPeople(tester);
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('open-detail'), findsOneWidget);
    });
  });

  group('Request back arrow, canonical replace', () {
    testWidgets('/post/view/<requestId> is replaced by /beacon/view and one '
        'tap leaves', (tester) async {
      final router = await _pump(tester, '$kPathPostView/$_first');
      expect(_location(router).path, '$kPathBeaconView/$_first');
      expect(find.byType(BeaconViewScreen), findsOneWidget);
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('home-stub'), findsOneWidget);
      expect(router.stack.map((e) => e.name), [HomeRoute.name]);
    });
  });

  group('Request back arrow, link opened while Home is on another tab', () {
    testWidgets('back lands on Home with the Requests tab selected', (
      tester,
    ) async {
      final router = await _pump(tester, kPathConversations);
      expect(
        _activeHomeTab(router),
        HomeTabSpec.forTab(HomeTab.conversations).index,
      );
      unawaited(
        router.push(BeaconViewRoute(id: _first, isDeepLink: 'true')),
      );
      await _settle(tester);
      expect(find.byType(BeaconViewScreen), findsOneWidget);

      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(_activeHomeTab(router), HomeTabSpec.forTab(HomeTab.work).index);
    });
  });

  group('Request back arrow, deep link', () {
    testWidgets('cold link (stack depth 1): one tap leaves to Home', (
      tester,
    ) async {
      final router = await _pump(tester, '/beacon/view/$_first');
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('home-stub'), findsOneWidget);
      // Home retargets to the Requests tab.
      expect(_location(router).path, kPathMyWork);

      await _openFromList(tester);
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
    });

    testWidgets('focus_fact link: one tap leaves to Home', (tester) async {
      final router = await _pump(
        tester,
        '/beacon/view/$_first?focus_fact=Ffact0000001',
      );
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(find.text('home-stub'), findsOneWidget);
      expect(_location(router).path, kPathMyWork);

      await _openFromList(tester);
      await _tapBack(tester);
      expect(find.byType(BeaconViewScreen), findsNothing);
    });
  });
}
