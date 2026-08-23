import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/app/platform/landing_redirect.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

import 'accept_invite_guard.dart';
import 'beacon_legacy_path_deep_link.dart';
import 'browse_deep_link.dart';
import 'credential_link_deep_link.dart';
import 'home_tab_branches.dart';
import 'invite_deep_link.dart';
import 'notification_deep_link.dart';
import 'recover_route_guard.dart';
import 'root_router.gr.dart';

export 'package:auto_route/auto_route.dart';

export 'home_tab_branches.dart';
export 'root_router.gr.dart';

PageRouteInfo beaconViewOperationalChildFromQuery(Parameters qp) =>
    BeaconViewOperationalRoute(
      isDeepLink: qp.optString(kQueryIsDeepLink),
      viewTab: qp.optString(kQueryBeaconViewTab),
      peopleTabAttention: qp.optString(kQueryBeaconPeopleTabAttention),
      entry: qp.optString(kQueryBeaconEntry),
      threadId: qp.optString(kQueryThreadId),
      messageId: qp.optString(kQueryMessageId),
    );

List<PageRouteInfo> beaconViewChildRoutesFromQuery(
  Parameters qp, {
  String? matchedThreadId,
}) {
  if (matchedThreadId != null) {
    return [
      beaconViewOperationalChildFromQuery(qp),
      ThreadDetailRoute(
        threadId: matchedThreadId,
        isDeepLink: qp.optString(kQueryIsDeepLink),
        viewTab: qp.optString(kQueryBeaconViewTab),
        peopleTabAttention: qp.optString(kQueryBeaconPeopleTabAttention),
        entry: qp.optString(kQueryBeaconEntry),
        messageId: qp.optString(kQueryMessageId),
      ),
    ];
  }
  return [beaconViewOperationalChildFromQuery(qp)];
}

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

  /// Backs the [ProfileViewRoute] "viewing my own profile" guard and re-reads
  /// the current auth state for every navigation.
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
          ],
        ),
        // Inbox (tab body only; rejected archive is a root-level full-screen route)
        AutoRoute(
          page: inboxTabShell.page,
          path: kPathInbox.split('/').last,
          children: [
            AutoRoute(initial: true, page: InboxRoute.page, path: ''),
          ],
        ),
        AutoRoute(
          page: updatesTabShell.page,
          path: kPathUpdates.split('/').last,
          children: [
            AutoRoute(initial: true, page: UpdatesRoute.page, path: ''),
          ],
        ),
        // Network (Friends)
        AutoRoute(
          page: networkTabShell.page,
          path: kPathNetwork.split('/').last,
          children: [
            AutoRoute(initial: true, page: FriendsRoute.page, path: ''),
            AutoRoute(page: BlockedUsersRoute.page, path: 'blocked'),
          ],
        ),
        // Me (Profile)
        AutoRoute(
          page: meTabShell.page,
          path: kPathProfile.split('/').last,
          children: [
            AutoRoute(initial: true, page: ProfileRoute.page, path: ''),
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

    // Inbox rejected archive belongs to the root browse-detail stack.
    AutoRoute(
      page: InboxRejectedRoute.page,
      path: kPathInboxRejected,
    ),

    RedirectRoute(path: kPathNotifications, redirectTo: kPathUpdates),

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
      page: RoutingMuteRoute.page,
      path: kPathRoutingMute,
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
        AutoRouteGuard.redirect((resolver) {
          if (_authCubit.state.deferAuthRedirects) {
            return null;
          }
          if (!_authCubit.state.isAuthenticated) {
            return null;
          }
          return resolveRecoverAuthenticatedRedirect(
            inviteQuery: resolver.route.queryParams.optString('invite'),
          );
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

    // Other-user profiles live on the root browse stack. Viewing my own
    // profile remains the documented Home/Me special case.
    AutoRoute(
      usesPathAsKey: true,
      page: ProfileViewRoute.page,
      path: '$kPathProfileView/:id',
      guards: [
        AutoRouteGuard.simple((resolver, router) {
          final id = resolver.route.params.getString('id');
          if (!_checkIfIsMe(id)) {
            resolver.next();
            return;
          }
          resolver.next(false);
          unawaited(
            router.navigate(
              HomeRoute(
                children: [
                  meTabShell(children: [const ProfileRoute()]),
                ],
              ),
            ),
          );
        }),
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

    // Beacon Create — do not set maintainState: false: image_cropper (and the
    // gallery picker) push routes while this screen is covered; that disposed
    // BlocProvider and closed BeaconCreateCubit before adjustCoverCrop /
    // pickImages completed (emit after close).
    AutoRoute(
      keepHistory: false,
      fullscreenDialog: true,
      page: BeaconCreateRoute.page,
      path: kPathBeaconNew,
    ),

    // Request detail and its nested thread route live on the root browse
    // stack, preserving the mounted Home or Forward source below them.
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
        AutoRoute(
          page: ThreadDetailRoute.page,
          path: 'thread/:threadId',
        ),
      ],
    ),

    // Review contributions — root registration only exists as a redirect
    // target; see the BeaconViewRoute comment above for the pattern.
    AutoRoute(
      usesPathAsKey: true,
      page: ReviewContributionsRoute.page,
      path: '$kPathReviewContributions/:id',
    ),

    AutoRoute(
      usesPathAsKey: true,
      page: ReceivedReviewsRoute.page,
      path: '$kPathReceivedReviews/:id',
    ),

    // Forward Beacon
    AutoRoute(
      usesPathAsKey: true,
      fullscreenDialog: true,
      page: ForwardBeaconRoute.page,
      path: '$kPathForwardBeacon/:id',
    ),

    // Forward existing request to a person (profile entry point)
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      page: PersonForwardRoute.page,
      path: '$kPathForwardPerson/:id',
    ),

    // All Requests authored by this person.
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconRoute.page,
      path: '$kPathBeaconViewAll/:id',
    ),

    // Requests authored by :id that the viewer was ever forwarded.
    AutoRoute(
      usesPathAsKey: true,
      page: InvolvedBeaconRoute.page,
      path: '$kPathBeaconInvolvedAll/:id',
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
            children: [
              BeaconViewOperationalRoute(
                isDeepLink: 'true',
                entry: kBeaconEntryDeepLink,
              ),
            ],
          );
        }),
      ],
    ),

    // Rating browse detail.
    AutoRoute(
      usesPathAsKey: true,
      page: RatingRoute.page,
      path: kPathRating,
    ),

    // Genealogy browse detail.
    AutoRoute(
      usesPathAsKey: true,
      page: InviteGenealogyRoute.page,
      path: kPathInviteGenealogy,
    ),

    // Register the forwards graph before the trust graph so
    // /graph/forwards/:id cannot match /graph/:id as id "forwards".
    AutoRoute(
      usesPathAsKey: true,
      page: ForwardsGraphRoute.page,
      path: '$kPathForwardsGraph/:id',
    ),

    AutoRoute(
      usesPathAsKey: true,
      page: GraphRoute.page,
      path: '$kPathGraph/:id',
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
    final transformed = _transformDeepLink(deepLink.uri);
    final browseStack = buildBrowseDeepLinkStack(transformed);
    if (browseStack != null) {
      return deepLink.initial
          ? DeepLink([browseStack.home, browseStack.detail])
          : DeepLink([browseStack.detail], navigate: false);
    }
    return deepLink;
  }

  Future<Uri> deepLinkTransformer(Uri uri) => SynchronousFuture(
    _transformDeepLink(uri),
  );

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

  /// Opens a notification [rawLink] above the current root source.
  ///
  /// Cold starts use the typed semantic Home owner from
  /// [buildBrowseDeepLinkStack]. Warm starts keep the mounted Home tab (or
  /// Forward flow) in place and push the canonical root detail above it.
  Future<void> openFromNotificationLink(
    String rawLink, {
    bool preferUpdatesBranch = false,
  }) async {
    if (rawLink.isEmpty) return;

    final rawUri = _notificationUriFromRaw(rawLink);
    final destRoom =
        rawUri.queryParameters['dest'] == 'room' ||
        (rawUri.path == kPathAppLinkView &&
            rawUri.queryParameters['dest'] == 'room');
    var normalized = _transformDeepLink(rawUri);
    if (destRoom && normalized.path.startsWith(kPathBeaconView)) {
      final query = Map<String, String>.from(normalized.queryParameters)
        ..[kQueryBeaconEntry] = kBeaconEntryRoomNotification;
      normalized = normalized.replace(queryParameters: query);
    }

    final browseStack = buildBrowseDeepLinkStack(normalized);
    final tabs = innerRouterOf<TabsRouter>(HomeRoute.name);
    if (tabs == null && browseStack != null) {
      final home = preferUpdatesBranch
          ? HomeRoute(
              children: [
                updatesTabShell(children: [const UpdatesRoute()]),
              ],
            )
          : browseStack.home;
      await replaceAll([home, browseStack.detail]);
      return;
    }
    if (preferUpdatesBranch && tabs != null) {
      tabs.setActiveIndex(HomeTabSpec.forTab(HomeTab.updates).index);
    }

    final query = normalized.queryParameters.isEmpty
        ? ''
        : Uri(queryParameters: normalized.queryParameters).query;
    await pushPath(
      query.isEmpty ? normalized.path : '${normalized.path}?$query',
    );
  }

  Future<void> openFromUpdate(AttentionReceipt receipt) =>
      openFromNotificationLink(
        attentionDestination(receipt).toString(),
        preferUpdatesBranch: true,
      );

  /// Activates Network and opens the Invitations tab on [FriendsRoute].
  ///
  /// Pops root overlays (beacon create / forward) first: `pushPath` of
  /// `/home/network?tab=…` cannot switch a mounted tabs shell, and those
  /// overlays use `keepHistory: false` so a naive push left Work (My Desk)
  /// visible. Scoped [popUntilRouteWithName] does not clear nested tab stacks.
  /// Cold-start (no mounted home tabs) builds
  /// `HomeRoute → NetworkTabShell → FriendsRoute(tab=invitations)`.
  Future<void> openInvitations() async {
    popUntilRouteWithName(HomeRoute.name);
    final tabs = innerRouterOf<TabsRouter>(HomeRoute.name);
    if (tabs != null) {
      final networkSpec = HomeTabSpec.forTab(HomeTab.network);
      tabs.setActiveIndex(networkSpec.index);
      final branch = tabs.stackRouterOfIndex(networkSpec.index);
      if (branch != null) {
        await branch.replaceAll([
          FriendsRoute(initialTab: kHomeTabInvitations),
        ]);
        return;
      }
    }
    await navigate(
      HomeRoute(
        children: [
          networkTabShell(
            children: [
              FriendsRoute(initialTab: kHomeTabInvitations),
            ],
          ),
        ],
      ),
    );
  }

  /// Activates Network, normalizes the branch to [FriendsRoute], then pushes
  /// [BlockedUsersRoute]. Cold-start (no mounted home tabs) builds
  /// `HomeRoute → NetworkTabShell → FriendsRoute → BlockedUsersRoute`.
  Future<void> openBlockedUsers() async {
    final tabs = innerRouterOf<TabsRouter>(HomeRoute.name);
    if (tabs != null) {
      final networkSpec = HomeTabSpec.forTab(HomeTab.network);
      tabs.setActiveIndex(networkSpec.index);
      final branch = tabs.stackRouterOfIndex(networkSpec.index);
      if (branch != null) {
        await branch.replaceAll([FriendsRoute()]);
        unawaited(branch.push(const BlockedUsersRoute()));
        return;
      }
    }
    await navigate(
      HomeRoute(
        children: [
          networkTabShell(
            children: [
              FriendsRoute(),
              const BlockedUsersRoute(),
            ],
          ),
        ],
      ),
    );
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
