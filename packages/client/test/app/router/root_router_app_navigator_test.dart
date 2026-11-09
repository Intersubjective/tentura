import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

/// Pins the stack operation and the route (with all its args) behind each
/// [AppNavigator] intent of [RootRouter]: feature UI used to build these
/// routes itself, and its tests now assert intents (FakeAppNavigator), so
/// this is where "the same push / navigate / replace as before" is checked.
void main() {
  late _RecordingRootRouter router;
  late AppNavigator navigator;

  setUp(() {
    router = _RecordingRootRouter();
    navigator = router;
    addTearDown(router.dispose);
  });

  String push(PageRouteInfo route) => 'push ${_describe(route)}';

  test('openBeacon pushes BeaconViewRoute with every arg', () async {
    await navigator.openBeacon(
      'B1',
      entry: 'inbox',
      viewTab: 'people',
      threadId: 'T1',
      messageId: 'M1',
      peopleTabAttention: 'offers',
    );
    await navigator.openBeacon('B2');

    expect(router.calls, [
      push(
        BeaconViewRoute(
          id: 'B1',
          entry: 'inbox',
          viewTab: 'people',
          threadId: 'T1',
          messageId: 'M1',
          peopleTabAttention: 'offers',
        ),
      ),
      push(BeaconViewRoute(id: 'B2')),
    ]);
  });

  test('navigateToBeacon navigates (not pushes) to BeaconViewRoute', () async {
    await navigator.navigateToBeacon('B1', entry: 'forward');

    expect(router.calls, [
      'navigate ${_describe(BeaconViewRoute(id: 'B1', entry: 'forward'))}',
    ]);
  });

  test('openBeaconLobby, forwardBeacon, openProfile, openPeopleTags, '
      'openInboxWatching and openRecover push their routes', () async {
    await navigator.openBeaconLobby('B1');
    await navigator.forwardBeacon('B1');
    await navigator.forwardBeacon('B2', tags: 't1,t2');
    await navigator.openProfile('U1');
    await navigator.openPeopleTags();
    await navigator.openInboxWatching();
    await navigator.openInboxWatching(highlightBeaconId: 'B3');
    await navigator.openRecover();

    expect(router.calls, [
      push(BeaconLobbyRoute(beaconId: 'B1')),
      push(ForwardBeaconRoute(beaconId: 'B1')),
      push(ForwardBeaconRoute(beaconId: 'B2', tags: 't1,t2')),
      push(ProfileViewRoute(id: 'U1')),
      push(const PeopleTagsRoute()),
      push(InboxWatchingRoute()),
      push(InboxWatchingRoute(highlightBeaconId: 'B3')),
      push(RecoverRoute()),
    ]);
  });

  test('forwardBeacon puts the Request in the path and the tags in the '
      'query (the forward picker preselects them on a reload)', () async {
    await navigator.forwardBeacon('B2', tags: 't1,t2');

    final route = router.pushed.single;
    expect(route.rawPathParams, {'id': 'B2'});
    expect(route.rawQueryParams, {'tags': 't1,t2'});
  });

  test('createBeacon pushes BeaconCreateRoute with every arg', () async {
    void onRecipientsChanged(Set<String> ids, Map<String, String> notes) {}
    void onPublished() {}

    await navigator.createBeacon(
      draftId: 'D1',
      editId: 'E1',
      initialTab: 'plan',
      forwardToUserId: 'U1',
      parentBeaconId: 'P1',
      sourceMessageId: 'M1',
      forkSourceId: 'F1',
      forkPlanTimes: 'PS1',
      initialRecipientIds: const {'U2'},
      initialNotes: const {'U2': 'hi'},
      onRecipientsChanged: onRecipientsChanged,
      onPublished: onPublished,
    );
    await navigator.createBeacon();

    expect(router.calls, [
      push(
        BeaconCreateRoute(
          draftId: 'D1',
          editId: 'E1',
          initialTab: 'plan',
          forwardToUserId: 'U1',
          parentBeaconId: 'P1',
          sourceMessageId: 'M1',
          forkSourceId: 'F1',
          forkPlanTimes: 'PS1',
          initialRecipientIds: const {'U2'},
          initialNotes: const {'U2': 'hi'},
          onRecipientsChanged: onRecipientsChanged,
          onPublished: onPublished,
        ),
      ),
      push(BeaconCreateRoute()),
    ]);
  });

  test('createPost pushes PostCreateRoute with every arg', () async {
    void onRecipientsChanged(Set<String> ids, Map<String, String> notes) {}
    void onPublished() {}

    await navigator.createPost(
      draftId: 'D1',
      forwardToUserId: 'U1',
      initialRecipientIds: const {'U2'},
      onRecipientsChanged: onRecipientsChanged,
      onPublished: onPublished,
    );

    expect(router.calls, [
      push(
        PostCreateRoute(
          draftId: 'D1',
          forwardToUserId: 'U1',
          initialRecipientIds: const {'U2'},
          onRecipientsChanged: onRecipientsChanged,
          onPublished: onPublished,
        ),
      ),
    ]);
  });

  test('openInboxWatchingFromHome resets to Home > Activity, then pushes '
      'Watching with the Request highlighted', () async {
    await navigator.openInboxWatchingFromHome('B1');

    expect(router.calls, [
      'replaceAll [${_describe(
        HomeRoute(
          children: [
            inboxTabShell(children: [InboxRoute()]),
          ],
        ),
      )}]',
      push(InboxWatchingRoute(highlightBeaconId: 'B1')),
    ]);
  });

  test('resetToRecover and resetToLogin replace the whole stack', () async {
    await navigator.resetToRecover();
    await navigator.resetToLogin();

    expect(router.calls, [
      'replaceAll [${_describe(RecoverRoute())}]',
      'replaceAll [${_describe(const AuthLoginRoute())}]',
    ]);
  });

  test('resetToHome replaces the stack with Home, or Home on a tab', () async {
    await navigator.resetToHome();
    await navigator.resetToHome(tab: HomeTab.inbox);

    expect(router.calls, [
      'replaceAll [${_describe(const HomeRoute())}]',
      'replaceAll [${_describe(
        HomeRoute(
          children: [
            inboxTabShell(children: [InboxRoute()]),
          ],
        ),
      )}]',
    ]);
  });

  test('openPath pushes the path with prefix matches', () async {
    await navigator.openPath('/beacon/B1');

    expect(router.calls, ['pushPath /beacon/B1 includePrefixMatches: true']);
  });

  test('popOrGoHome pops with the result when something can pop', () async {
    router.canMaybePop = true;
    await navigator.popOrGoHome('done');

    expect(router.calls, ['maybePop done']);
  });

  test('popOrGoHome replaces the stack with Home when nothing pops', () async {
    router.canMaybePop = false;
    await navigator.popOrGoHome();

    expect(router.calls, [
      'maybePop null',
      'replaceAll [${_describe(const HomeRoute())}]',
    ]);
  });

  test('back is the root router back', () {
    navigator.back();

    expect(router.calls, ['back']);
  });
}

/// Route name, generated args (their toString lists every field) and
/// initial children, recursively.
String _describe(PageRouteInfo route) {
  final args = route.args;
  final children = route.initialChildren;
  return [
    route.routeName,
    if (args != null) ' $args',
    if (children != null && children.isNotEmpty)
      '[${children.map(_describe).join(', ')}]',
  ].join();
}

/// A real [RootRouter] whose stack operations are recorded, not performed.
class _RecordingRootRouter extends RootRouter {
  _RecordingRootRouter()
    : super(
        Logger('RootRouterAppNavigatorTest'),
        _FakeAuthCubit(),
        _FakeSettingsCubit(),
        PostJoinNavigationCubit(),
      );

  final calls = <String>[];

  /// The routes [push] received.
  final pushed = <PageRouteInfo>[];

  bool canMaybePop = true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    calls.add('push ${_describe(route)}');
    pushed.add(route);
    return null;
  }

  @override
  Future<dynamic> navigate(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    calls.add('navigate ${_describe(route)}');
  }

  @override
  Future<void> replaceAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool updateExistingRoutes = true,
  }) async {
    calls.add('replaceAll [${routes.map(_describe).join(', ')}]');
  }

  @override
  Future<T?> pushPath<T extends Object?>(
    String path, {
    bool includePrefixMatches = true,
    OnNavigationFailure? onFailure,
  }) async {
    calls.add('pushPath $path includePrefixMatches: $includePrefixMatches');
    return null;
  }

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    calls.add('maybePop $result');
    return canMaybePop;
  }

  @override
  void back() => calls.add('back');
}

final class _FakeAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime(2026),
    currentAccountId: 'U1',
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}
