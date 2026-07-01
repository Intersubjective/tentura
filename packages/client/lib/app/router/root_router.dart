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
import 'invite_deep_link.dart';
import 'notification_deep_link.dart';
import 'root_router.gr.dart';

export 'package:auto_route/auto_route.dart';

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
          page: MyWorkRoute.page,
          path: kPathMyWork.split('/').last,
        ),
        // Inbox (tab body only; rejected archive is a root-level full-screen route)
        AutoRoute(
          page: InboxRoute.page,
          path: kPathInbox.split('/').last,
        ),
        // Network (Friends)
        AutoRoute(
          page: FriendsRoute.page,
          path: kPathNetwork.split('/').last,
        ),
        // Me (Profile)
        AutoRoute(
          page: ProfileRoute.page,
          path: kPathProfile.split('/').last,
        ),
      ],
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? const IntroRoute() : null,
        ),
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    // Inbox rejected archive (full-screen stack route; no bottom tabs)
    AutoRoute(
      page: InboxRejectedRoute.page,
      path: kPathInboxRejected,
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? const IntroRoute() : null,
        ),
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
      ],
    ),

    // Notification Center (full-screen stack route; no bottom tabs)
    AutoRoute(
      page: NotificationCenterRoute.page,
      path: kPathNotifications,
      guards: [
        AutoRouteGuard.redirect(
          (_) => _introPending ? const IntroRoute() : null,
        ),
        AutoRouteGuard.redirect((_) => _redirectIfUnauthenticated()),
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
              return const HomeRoute(children: [InboxRoute()]);
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

    // Profile View
    AutoRoute(
      usesPathAsKey: true,
      page: ProfileViewRoute.page,
      path: '$kPathProfileView/:id',
      guards: [
        AutoRouteGuard.redirect(
          (r) => _authCubit.state.checkIfIsMe(r.route.params.getString('id'))
              ? const ProfileRoute()
              : null,
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
      keepHistory: false,
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

    // Item discussion (more specific than beacon view — register first).
    AutoRoute(
      usesPathAsKey: true,
      page: ItemDiscussionRoute.page,
      path: '$kPathBeaconView/:beaconId/discussion/:itemId',
    ),

    // Beacon View
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
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

    AutoRoute(
      usesPathAsKey: true,
      page: ReviewContributionsRoute.page,
      path: '$kPathReviewContributions/:id',
    ),

    // Forward Beacon
    AutoRoute(
      keepHistory: false,
      maintainState: false,
      fullscreenDialog: true,
      page: ForwardBeaconRoute.page,
      path: '$kPathForwardBeacon/:id',
    ),

    // Beacon View All
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconRoute.page,
      path: '$kPathBeaconViewAll/:id',
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

    // Rating
    AutoRoute(
      usesPathAsKey: true,
      page: RatingRoute.page,
      path: kPathRating,
      //
    ),

    AutoRoute(
      usesPathAsKey: true,
      page: InviteGenealogyRoute.page,
      path: kPathInviteGenealogy,
    ),

    // Graph — register `/graph/forwards/:id` before `/graph/:id` so
    // `pushPath('/graph/forwards/B…')` does not match the trust graph route
    // with id `forwards` (which would leave an empty graph when popping back).
    AutoRoute(
      usesPathAsKey: true,
      page: ForwardsGraphRoute.page,
      path: '$kPathForwardsGraph/:id',
    ),

    AutoRoute(
      usesPathAsKey: true,
      page: GraphRoute.page,
      path: '$kPathGraph/:id',
      //
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

  /// Opens a notification [rawLink] (`/#/shared/view?…` or absolute URL).
  Future<void> openFromNotificationLink(String rawLink) async {
    final uri = _notificationUriFromRaw(rawLink);
    if (uri.path.startsWith(kPathReviewContributions)) {
      await pushPath(uri.path);
      return;
    }
    final destRoom =
        uri.queryParameters['dest'] == 'room' ||
        (uri.path == kPathAppLinkView && uri.queryParameters['dest'] == 'room');
    var transformed = await deepLinkTransformer(uri);
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
