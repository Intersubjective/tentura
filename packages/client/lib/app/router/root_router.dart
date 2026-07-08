import 'dart:async';
import 'package:logging/logging.dart';
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';

import 'package:tentura/features/auth/data/service/web_redirect.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

import 'accept_invite_guard.dart';
import 'beacon_legacy_path_deep_link.dart';
import 'credential_link_deep_link.dart';
import 'home_tab_branches.dart';
import 'invite_deep_link.dart';
import 'notification_deep_link.dart';
import 'root_router.gr.dart';

export 'package:auto_route/auto_route.dart';

export 'home_tab_branches.dart';
export 'root_router.gr.dart';

@singleton
@AutoRouterConfig()
class RootRouter extends RootStackRouter {
  RootRouter(
    this._logger,
    this._authCubit,
    this._settingsCubit,
    this._postJoinNavigationCubit,
  );

  late final reevaluateListenable = _ReevaluateFromStreams([
    _settingsCubit.stream.map((e) => e.introEnabled),
    _authCubit.stream.map((e) => (e.deferAuthRedirects, e.currentAccountId)),
  ]);

  final Logger _logger;

  final AuthCubit _authCubit;

  final SettingsCubit _settingsCubit;

  final PostJoinNavigationCubit _postJoinNavigationCubit;

  PageRouteInfo? _redirectIfUnauthenticated() {
    if (_authCubit.state.deferAuthRedirects) {
      return null;
    }
    return _authCubit.state.isNotAuthenticated ? const AuthLoginRoute() : null;
  }

  /// Web onboarding lives on the static landing (post-signup pager); the WASM
  /// app never shows IntroScreen. Native keeps the Drift-backed intro flag.
  bool get _introPending => !kIsWeb && _settingsCubit.state.introEnabled;

  /// Forwards a bare legacy detail path (e.g. `/beacon/view/:id`) into a
  /// [HomeRoute] tab branch, then aborts the root-level navigation via
  /// [resolver]`.next(false)` — the shared body of every root "redirect
  /// target" guard below.
  ///
  /// Warm shell (a tab branch is mounted): plain `push` onto the **active**
  /// branch. This must not be `navigate(HomeRoute(...))` — auto_route's
  /// `navigate` has replace semantics for browser history (it pops-until /
  /// merges to avoid duplicates), so pushing a second detail would swap the
  /// URL in place and silently shorten the browser back chain (regression:
  /// graph1 → profile → graph2, then back×2 could not reach graph1).
  ///
  /// Cold start (no shell yet): build the shell around the detail with
  /// `navigate`; there's no back chain to preserve, and the tab is picked by
  /// the route's semantic [owner] — see [homeTabShellFor].
  void _forwardIntoHomeBranch(
    NavigationResolver resolver, {
    required HomeTabOwner owner,
    required PageRouteInfo route,
  }) {
    final tabs = innerRouterOf<TabsRouter>(HomeRoute.name);
    final activeIndex = tabs?.activeIndex;
    final branch = activeIndex == null
        ? null
        : tabs?.stackRouterOfIndex(activeIndex);
    if (branch != null) {
      // Defer to avoid pushing while the router's RenderStack is mid-layout
      // (Flutter web can deliver early pointer events before first layout).
      scheduleMicrotask(() {
        unawaited(branch.push(route));
      });
    } else {
      scheduleMicrotask(() {
        unawaited(
          navigate(
            HomeRoute(
              children: [
                homeTabShellFor(activeIndex: activeIndex, owner: owner)(
                  children: [route],
                ),
              ],
            ),
          ),
        );
      });
    }
    resolver.next(false);
  }

  /// Backs the [ProfileViewRoute] "viewing my own profile" guard, threaded
  /// into [browseDetailChildren] as a live callback (not a torn-off getter)
  /// so each check re-reads the current auth state.
  bool _checkIfIsMe(String id) => _authCubit.state.checkIfIsMe(id);

  @override
  @disposeMethod
  void dispose() {
    reevaluateListenable.dispose();
    super.dispose();
  }

  @override
  RouteType get defaultRouteType => const RouteType.adaptive();

  @override
  List<AutoRoute> get routes => [
    // Home
    AutoRoute(
      initial: true,
      page: HomeRoute.page,
      path: kPathHome,
      children: [
        // My Work (default home tab)
        AutoRoute(
          initial: true,
          page: workTabShell.page,
          path: kPathMyWork.split('/').last,
          children: [
            AutoRoute(initial: true, page: MyWorkRoute.page, path: ''),
            ...browseDetailChildren(checkIfIsMe: _checkIfIsMe),
          ],
        ),
        // Inbox (tab body only; rejected archive is a root-level full-screen route)
        AutoRoute(
          page: inboxTabShell.page,
          path: kPathInbox.split('/').last,
          children: [
            AutoRoute(initial: true, page: InboxRoute.page, path: ''),
            ...browseDetailChildren(checkIfIsMe: _checkIfIsMe),
          ],
        ),
        // Network (Friends)
        AutoRoute(
          page: networkTabShell.page,
          path: kPathNetwork.split('/').last,
          children: [
            AutoRoute(initial: true, page: FriendsRoute.page, path: ''),
            ...browseDetailChildren(checkIfIsMe: _checkIfIsMe),
          ],
        ),
        // Me (Profile)
        AutoRoute(
          page: meTabShell.page,
          path: kPathProfile.split('/').last,
          children: [
            AutoRoute(initial: true, page: ProfileRoute.page, path: ''),
            ...browseDetailChildren(checkIfIsMe: _checkIfIsMe),
          ],
        ),
      ],
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? const IntroRoute() : null,
        ),
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    // Inbox rejected archive — root registration only exists as a redirect
    // target (see the BeaconViewRoute comment below for the pattern); the
    // real registration lives under each tab branch via
    // `browseDetailChildren()`. Intro/auth checks aren't re-declared here —
    // navigating into `HomeRoute` below re-runs its own guards.
    AutoRoute(
      page: InboxRejectedRoute.page,
      path: kPathInboxRejected,
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.inbox,
            route: const InboxRejectedRoute(),
          ),
        ),
      ],
    ),

    // Notification Center — same pattern as InboxRejectedRoute above.
    AutoRoute(
      page: NotificationCenterRoute.page,
      path: kPathNotifications,
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.inbox,
            route: const NotificationCenterRoute(),
          ),
        ),
      ],
    ),

    // Notification settings (full-screen stack route; no bottom tabs)
    AutoRoute(
      page: NotificationSettingsRoute.page,
      path: kPathNotificationSettings,
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? const IntroRoute() : null,
        ),
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    AutoRoute(
      page: DebugSettingsRoute.page,
      path: kPathDebugSettings,
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? const IntroRoute() : null,
        ),
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    // Intro (native only — web onboarding is on the static landing)
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      page: IntroRoute.page,
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? null : const AuthLoginRoute(),
        ),
      ],
    ),

    // Login — web has no login UI: bounce unauthenticated users to the landing
    // (`goToLanding` is a no-op on native, where the login screen still shows).
    AutoRoute(
      maintainState: false,
      page: AuthLoginRoute.page,
      path: kPathSignIn,
      guards: [
        AutoRouteGuard.redirect((_) {
          if (_authCubit.state.deferAuthRedirects) {
            return null;
          }
          if (_authCubit.state.isAuthenticated) return const ProfileRoute();
          goToLanding();
          return null;
        }),
      ],
    ),

    // Seed recovery — web entry without session; native uses AuthLoginScreen too.
    AutoRoute(
      maintainState: false,
      page: RecoverRoute.page,
      path: kPathRecover,
      guards: [
        AutoRouteGuard.redirect((_) {
          if (_authCubit.state.deferAuthRedirects) {
            return null;
          }
          return _authCubit.state.isAuthenticated ? const HomeRoute() : null;
        }),
      ],
    ),

    // Profile Register — web invite deep-links belong to the landing; bounce to
    // its `/invite/:id` page. Native keeps the in-app register screen.
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      fullscreenDialog: true,
      page: AuthRegisterRoute.page,
      path: '$kPathSignUp/:id',
      guards: [
        AutoRouteGuard.redirect((resolver) {
          if (_authCubit.state.isAuthenticated) {
            if (_postJoinNavigationCubit.hasPending) {
              return HomeRoute(
                children: [
                  inboxTabShell(children: [const InboxRoute()]),
                ],
              );
            }
            return const ProfileRoute();
          }
          goToLanding(
            invitePath: '/invite/${resolver.route.params.getString('id')}',
          );
          return null;
        }),
      ],
    ),

    // Accept invite — existing authenticated user confirms, then befriends issuer.
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      fullscreenDialog: true,
      page: AcceptInviteRoute.page,
      path: '$kPathAcceptInvite/:id',
      guards: [
        AutoRouteGuard.redirect((resolver) {
          final code = resolver.route.params.getString('id');
          if (_authCubit.state.isAuthenticated) {
            return null;
          }
          final bounced = goToLanding(invitePath: '/invite/$code');
          return switch (resolveAcceptInviteGuard(
            isAuthenticated: false,
            code: code,
            bouncedToLanding: bounced,
          )) {
            AcceptInviteGuardAllow() => null,
            AcceptInviteGuardLeaving() => null,
            AcceptInviteGuardSignup(:final code) => AuthRegisterRoute(id: code),
          };
        }),
      ],
    ),

    // Profile View — root registration only exists as a redirect target (see
    // the BeaconViewRoute comment below for the pattern); the real
    // registration lives under each tab branch via `browseDetailChildren()`,
    // which also carries the "viewing my own profile" isMe guard (it must be
    // checked there too, for full branch URLs that never reach this root
    // entry).
    AutoRoute(
      usesPathAsKey: true,
      page: ProfileViewRoute.page,
      path: '$kPathProfileView/:id',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.network,
            route: ProfileViewRoute(
              id: resolver.route.params.getString('id'),
            ),
          ),
        ),
      ],
    ),

    // Profile Edit — do not set maintainState: false: gallery + image_cropper
    // push routes while this screen is covered; that disposed BlocProvider and
    // closed ProfileEditCubit before pickAndCropImage completed (emit after close).
    AutoRoute(
      keepHistory: false,
      fullscreenDialog: true,
      page: ProfileEditRoute.page,
      path: kPathProfileEdit,
    ),

    // Settings
    AutoRoute(
      maintainState: false,
      fullscreenDialog: true,
      page: SettingsRoute.page,
      path: kPathSettings,
      guards: [
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    // Settings > Sign-in methods (list / remove account credentials)
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      fullscreenDialog: true,
      page: CredentialsRoute.page,
      path: kPathSignInMethods,
      guards: [
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    // Beacon Create New
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      fullscreenDialog: true,
      page: BeaconCreateRoute.page,
      path: kPathBeaconNew,
    ),

    // Item discussion (more specific than beacon view — register first, same
    // reason as `browseDetailChildren()`'s ordering). Root registration only
    // exists as a redirect target — see the BeaconViewRoute comment below.
    AutoRoute(
      usesPathAsKey: true,
      page: ItemDiscussionRoute.page,
      path: '$kPathBeaconView/:beaconId/discussion/:itemId',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.work,
            route: ItemDiscussionRoute(
              beaconId: resolver.route.params.getString('beaconId'),
              itemId: resolver.route.params.getString('itemId'),
            ),
          ),
        ),
      ],
    ),

    // Beacon View — root registration only exists as a redirect target: the
    // real (rendered) registration is nested under each tab branch via
    // `browseDetailChildren()` above, so a full branch URL resolves there
    // directly. This entry catches bare `/beacon/view/:id` pushes (all the
    // legacy pushPath call sites) and forwards them into whichever tab is
    // currently active — see [_forwardIntoHomeBranch] for the warm-push /
    // cold-navigate split and its browser-history rationale.
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          final qp = resolver.route.queryParams;
          _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.work,
            route: BeaconViewRoute(
              id: resolver.route.params.getString('id'),
              isDeepLink: qp.optString(kQueryIsDeepLink),
              viewTab: qp.optString(kQueryBeaconViewTab),
              peopleTabAttention: qp.optString(
                kQueryBeaconPeopleTabAttention,
              ),
              surface: qp.optString(kQueryBeaconSurface),
              entry: qp.optString(kQueryBeaconEntry),
              coordinationItemId: qp.optString(kQueryCoordinationItemId),
            ),
          );
        }),
      ],
    ),

    // Beacon coordination room (V2 chat) — legacy path redirects into unified view.
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconRoomRoute.page,
      path: '$kPathBeaconRoom/:id',
      guards: [
        AutoRouteGuard.redirect((resolver) {
          final id = resolver.route.params.getString('id');
          return BeaconViewRoute(
            id: id,
            isDeepLink: 'true',
            viewTab: 'room',
            entry: kBeaconEntryDeepLink,
          );
        }),
      ],
    ),

    // Review contributions — root registration only exists as a redirect
    // target; see the BeaconViewRoute comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: ReviewContributionsRoute.page,
      path: '$kPathReviewContributions/:id',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.work,
            route: ReviewContributionsRoute(
              id: resolver.route.params.getString('id'),
              draft: resolver.route.queryParams.getBool('draft', false),
            ),
          ),
        ),
      ],
    ),

    // Forward Beacon
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      fullscreenDialog: true,
      page: ForwardBeaconRoute.page,
      path: '$kPathForwardBeacon/:id',
    ),

    // Beacon View All — root registration only exists as a redirect target;
    // see the BeaconViewRoute comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconRoute.page,
      path: '$kPathBeaconViewAll/:id',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.work,
            route: BeaconRoute(id: resolver.route.params.getString('id')),
          ),
        ),
      ],
    ),

    // Beacons authored by :id that the viewer was ever forwarded. Root
    // registration only exists as a redirect target; see the BeaconViewRoute
    // comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: InvolvedBeaconRoute.page,
      path: '$kPathBeaconInvolvedAll/:id',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.work,
            route: InvolvedBeaconRoute(
              id: resolver.route.params.getString('id'),
            ),
          ),
        ),
      ],
    ),

    // Legacy `/beacon/:id` (missing `/view`) → unified beacon view.
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconLegacyPathRoute.page,
      path: '/beacon/:id',
      guards: [
        AutoRouteGuard.redirect((resolver) {
          final id = resolver.route.params.getString('id');
          return BeaconViewRoute(
            id: id,
            isDeepLink: 'true',
            entry: kBeaconEntryDeepLink,
          );
        }),
      ],
    ),

    // Rating — root registration only exists as a redirect target; see the
    // BeaconViewRoute comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: RatingRoute.page,
      path: kPathRating,
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.network,
            route: const RatingRoute(),
          ),
        ),
      ],
    ),

    // Root registration only exists as a redirect target; see the
    // BeaconViewRoute comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: InviteGenealogyRoute.page,
      path: kPathInviteGenealogy,
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.network,
            route: InviteGenealogyRoute(
              targetId: resolver.route.queryParams.optString(
                kQueryGenealogyWith,
              ),
            ),
          ),
        ),
      ],
    ),

    // Graph — register `/graph/forwards/:id` before `/graph/:id` so
    // `pushPath('/graph/forwards/B…')` does not match the trust graph route
    // with id `forwards` (which would leave an empty graph when popping back).
    // Root registrations only exist as redirect targets; see the
    // BeaconViewRoute comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: ForwardsGraphRoute.page,
      path: '$kPathForwardsGraph/:id',
      guards: [
        AutoRouteGuard.simple((resolver, _) {
          final qp = resolver.route.queryParams;
          _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.network,
            route: ForwardsGraphRoute(
              focus: resolver.route.params.getString('id'),
              helpOffererId: qp.optString('committer'),
              helpOffererName: qp.optString('committerName'),
            ),
          );
        }),
      ],
    ),

    AutoRoute(
      usesPathAsKey: true,
      page: GraphRoute.page,
      path: '$kPathGraph/:id',
      guards: [
        AutoRouteGuard.simple(
          (resolver, _) => _forwardIntoHomeBranch(
            resolver,
            owner: HomeTabOwner.network,
            route: GraphRoute(focus: resolver.route.params.getString('id')),
          ),
        ),
      ],
    ),

    // Complaint
    AutoRoute(
      keepHistory: false,
      usesPathAsKey: true,
      maintainState: false,
      fullscreenDialog: true,
      page: ComplaintRoute.page,
      path: '$kPathComplaint/:id',
    ),

    // default
    RedirectRoute(
      path: '*',
      redirectTo: kPathHome,
    ),
  ];

  FutureOr<DeepLink> deepLinkBuilder(PlatformDeepLink deepLink) {
    _logger.info('DeepLinkBuilder: ${deepLink.uri}');
    return deepLink;
  }

  Future<Uri> deepLinkTransformer(Uri uri) => SynchronousFuture(
    _prefixBrowseBranch(_transformDeepLink(uri)),
  );

  /// Final transformer stage: nests bare browse-detail paths under their
  /// `/home/<tab>` branch so platform navigations (URL bar, hash change,
  /// notification links) match the nested registration directly with a
  /// single history entry — see [homeBranchPathPrefixFor].
  Uri _prefixBrowseBranch(Uri uri) {
    final prefix = homeBranchPathPrefixFor(
      path: uri.path,
      activeIndex: innerRouterOf<TabsRouter>(HomeRoute.name)?.activeIndex,
    );
    if (prefix == null) {
      return uri;
    }
    return uri.replace(path: '$prefix${uri.path}');
  }

  Uri _transformDeepLink(Uri uri) {
    final credentialLink = transformCredentialLinkDeepLink(uri: uri);
    if (credentialLink.path == kPathSignInMethods &&
        credentialLink.queryParameters.containsKey(kQueryCredentialLinked)) {
      return credentialLink;
    }
    final invitePath = transformInviteDeepLink(
      uri: uri,
      isAuthenticated: _authCubit.state.isAuthenticated,
    );
    if (invitePath.path != uri.path) {
      return invitePath;
    }
    final legacyBeacon = transformLegacyBeaconPath(uri);
    if (legacyBeacon.path != uri.path) {
      return legacyBeacon;
    }
    if (uri.path != kPathAppLinkView) {
      return uri;
    }
    return switch (uri.queryParameters['id']) {
      final String id when id.startsWith('B') || id.startsWith('C') =>
        transformBeaconAppLink(uri, id),
      final String id when id.startsWith('O') || id.startsWith('U') =>
        uri.replace(
          path: '$kPathProfileView/$id',
          queryParameters: {
            kQueryIsDeepLink: 'true',
          },
        ),
      final String id when id.startsWith('I') =>
        transformSharedViewInviteDeepLink(
          uri: uri,
          id: id,
          isAuthenticated: _authCubit.state.isAuthenticated,
        ),
      _ => uri.replace(
        path: kPathNetwork,
        queryParameters: {
          kQueryIsDeepLink: 'true',
        },
      ),
    };
  }

  /// Opens a notification [rawLink] (`/#/shared/view?…` or absolute URL).
  ///
  /// Deep-link pipeline (same for platform links and notification taps):
  /// 1. [_transformDeepLink] normalizes legacy/app-link shapes to canonical
  ///    paths (credential, invite, `/beacon/:id`, `/shared/view?id=…`);
  /// 2. [_prefixBrowseBranch] nests bare browse paths under the owning
  ///    `/home/<tab>` branch ([homeBranchPathPrefixFor]) so they match the
  ///    nested registration directly with one history entry;
  /// 3. anything that still arrives bare (in-app `pushPath` from effects)
  ///    is caught by the root redirect-target guards, which forward into
  ///    the active branch ([_forwardIntoHomeBranch]).
  Future<void> openFromNotificationLink(String rawLink) async {
    final uri = _notificationUriFromRaw(rawLink);
    if (uri.path.startsWith(kPathReviewContributions)) {
      await pushPath(uri.path);
      return;
    }
    final destRoom =
        uri.queryParameters['dest'] == 'room' ||
        (uri.path == kPathAppLinkView && uri.queryParameters['dest'] == 'room');
    // Normalize only (no branch prefix): the bare path goes through
    // `pushPath`, whose root redirect-target guard pushes onto the active
    // branch — one history entry. The branch prefix stage is for
    // platform-parsed links, where the browser already owns the entry.
    var transformed = _transformDeepLink(uri);
    if (destRoom && transformed.path.startsWith(kPathBeaconView)) {
      final q = Map<String, String>.from(transformed.queryParameters);
      q[kQueryBeaconEntry] = kBeaconEntryRoomNotification;
      transformed = transformed.replace(queryParameters: q);
    }
    final qp = transformed.queryParameters;
    var path = transformed.path;
    if (qp.isNotEmpty) {
      final q = Uri(queryParameters: qp).query;
      if (q.isNotEmpty) {
        path = '$path?$q';
      }
    }
    await pushPath(path);
  }

  Uri _notificationUriFromRaw(String raw) {
    final idx = raw.indexOf('/#/');
    final s = idx == -1 ? raw : raw.substring(idx + 2);
    return Uri.parse(s.startsWith('/') ? s : '/$s');
  }
}

class _ReevaluateFromStreams extends ChangeNotifier {
  final _subscriptions = <StreamSubscription<dynamic>>[];

  _ReevaluateFromStreams(List<Stream<dynamic>> streams) {
    for (final stream in streams) {
      _subscriptions.add(stream.listen((_) => notifyListeners()));
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
