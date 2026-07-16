import 'dart:async';

import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';

import 'root_router.gr.dart';

/// Per-tab shell branches for [HomeRoute]'s [AutoTabsRouter]. Each shell hosts
/// its own nested `StackRouter` so browse details (beacon view, …) push onto
/// the active tab's own back stack instead of the shared root stack — see
/// `docs/adaptive-router-refactor-plan.md` (Phase 2, Step 1).
const workTabShell = EmptyShellRoute('WorkTabShell');
const inboxTabShell = EmptyShellRoute('InboxTabShell');
const networkTabShell = EmptyShellRoute('NetworkTabShell');
const meTabShell = EmptyShellRoute('MeTabShell');

/// Stable identity for a Home branch. Display order is owned by [HomeTabSpec],
/// not by enum ordinal or ad-hoc router integers.
enum HomeTab { work, inbox, network, me }

/// The single mapping between a semantic Home tab and AutoRoute mechanics.
///
/// Keep tab index, branch path, shell, and root together so adding Updates
/// cannot silently shift Network/Profile behavior.
final class HomeTabSpec {
  const HomeTabSpec({
    required this.tab,
    required this.index,
    required this.path,
    required this.shell,
    required this.rootRoute,
  });

  final HomeTab tab;
  final int index;
  final String path;
  final EmptyShellRoute shell;
  final PageRouteInfo Function() rootRoute;

  static final all = <HomeTabSpec>[
    HomeTabSpec(
      tab: HomeTab.work,
      index: 0,
      path: kPathMyWork,
      shell: workTabShell,
      rootRoute: MyWorkRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.inbox,
      index: 1,
      path: kPathInbox,
      shell: inboxTabShell,
      rootRoute: InboxRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.network,
      index: 2,
      path: kPathNetwork,
      shell: networkTabShell,
      rootRoute: FriendsRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.me,
      index: 3,
      path: kPathProfile,
      shell: meTabShell,
      rootRoute: ProfileRoute.new,
    ),
  ];

  static HomeTabSpec forTab(HomeTab tab) =>
      all.singleWhere((spec) => spec.tab == tab);

  static HomeTabSpec? fromIndex(int index) {
    for (final spec in all) {
      if (spec.index == index) return spec;
    }
    return null;
  }
}

/// Detail routes reachable from *any* browse tab while looking at content.
/// Shared across all four branches via one helper so the child list can't
/// drift between tabs — add new "browse cluster" routes here rather than
/// inline per branch.
///
/// [checkIfIsMe] backs the [ProfileViewRoute] "viewing my own profile"
/// redirect (see `root_router.dart`'s equivalent root-level guard, which this
/// mirrors for full branch URLs / browser refresh). It is threaded in rather
/// than read from a captured field so each call re-reads the live auth state.
List<AutoRoute> browseDetailChildren({
  required bool Function(String id) checkIfIsMe,
}) => [
  // Item discussion (more specific than beacon view — register first, same
  // reason as the root registration in `root_router.dart`).
  AutoRoute(
    usesPathAsKey: true,
    page: ItemDiscussionRoute.page,
    path: 'beacon/view/:beaconId/discussion/:itemId',
  ),
  AutoRoute(
    usesPathAsKey: true,
    page: BeaconViewRoute.page,
    path: 'beacon/view/:id',
  ),
  // Beacon View All
  AutoRoute(
    usesPathAsKey: true,
    page: BeaconRoute.page,
    path: 'beacon/all/:id',
  ),
  // Beacons authored by :id that the viewer was ever forwarded.
  AutoRoute(
    usesPathAsKey: true,
    page: InvolvedBeaconRoute.page,
    path: 'beacon/involved/:id',
  ),
  AutoRoute(
    usesPathAsKey: true,
    page: ReviewContributionsRoute.page,
    path: 'beacon/review/:id',
  ),
  // Profile View — same isMe redirect as the root registration: a full
  // branch URL / browser refresh at e.g. `/home/network/profile/view/:id`
  // never goes through the root redirect, so the check must also live here.
  //
  // Can't use `AutoRouteGuard.redirect` (bare `router.push(ProfileRoute())`):
  // `push`/`_findStackScope` only searches the *active* branch's ancestor
  // chain (`_topMostRouter` + `_buildRoutersHierarchy` walk up from wherever
  // navigation is currently focused), and `ProfileRoute` only exists inside
  // `meTabShell` — unreachable if e.g. Network is the active tab. `HomeRoute`
  // is always reachable (it's a direct root-level route), so — like
  // `BeaconViewRoute`'s root guard — rebuild the full path from there and
  // `navigate`, which merges into whatever Home shell already exists.
  AutoRoute(
    usesPathAsKey: true,
    page: ProfileViewRoute.page,
    path: 'profile/view/:id',
    guards: [
      AutoRouteGuard.simple((resolver, router) {
        final id = resolver.route.params.getString('id');
        if (!checkIfIsMe(id)) {
          resolver.next();
          return;
        }
        unawaited(
          router.navigate(
            HomeRoute(
              children: [
                meTabShell(children: [const ProfileRoute()]),
              ],
            ),
          ),
        );
        resolver.next(false);
      }),
    ],
  ),
  // Graph — register `graph/forwards/:id` before `graph/:id` so
  // `pushPath('/graph/forwards/B…')` does not match the trust graph route
  // with id `forwards` (same reason as the root registration order).
  AutoRoute(
    usesPathAsKey: true,
    page: ForwardsGraphRoute.page,
    path: 'graph/forwards/:id',
  ),
  AutoRoute(
    usesPathAsKey: true,
    page: GraphRoute.page,
    path: 'graph/:id',
  ),
  AutoRoute(
    usesPathAsKey: true,
    page: InviteGenealogyRoute.page,
    path: 'invite-genealogy',
  ),
  AutoRoute(
    usesPathAsKey: true,
    page: RatingRoute.page,
    path: 'rating',
  ),
  // Inbox rejected archive — relative segment differs from the root
  // `kPathInboxRejected` (`/home/inbox/rejected`) to avoid the doubled-up
  // `/home/work/inbox/rejected` a nested reuse of that constant would give;
  // URL shape here is free (see the refactor plan, decision 2).
  AutoRoute(
    page: InboxRejectedRoute.page,
    path: 'inbox-rejected',
  ),
  AutoRoute(
    page: NotificationCenterRoute.page,
    path: 'notifications',
  ),
];

/// Semantic tab owner for a route family, used by [homeTabShellFor] as the
/// cold-start (no active tab yet) fallback — see call sites in
/// `root_router.dart` for the beacon/profile/inbox/notifications mapping.
/// Maps [TabsRouter.activeIndex] on [HomeRoute] to its shell branch. Used by
/// root-level redirect guards to forward a bare path (e.g. `/beacon/view/:id`)
/// into whichever tab branch is currently active.
///
/// Warm (`activeIndex` non-null): forwards into whichever tab is currently
/// active, regardless of the route's semantic owner — the user shouldn't be
/// yanked to another tab mid-browse.
/// Cold (`activeIndex` null — shell hasn't mounted a tab yet, e.g. first deep
/// link): falls back to [owner].
EmptyShellRoute homeTabShellFor({
  required int? activeIndex,
  required HomeTab owner,
}) {
  final tab = activeIndex == null
      ? owner
      : HomeTabSpec.fromIndex(activeIndex)?.tab ?? HomeTab.work;
  return HomeTabSpec.forTab(tab).shell;
}

/// Browse-detail path families and their semantic tab owners — one source for
/// both the root redirect guards and [homeBranchPathPrefixFor]. Order
/// matters: more specific prefixes first (`/graph/forwards` before `/graph`).
/// `/beacon/room/:id` and legacy `/beacon/:id` are deliberately absent: their
/// root redirect guards normalize them to `/beacon/view` first.
const _browsePathOwners = <(String, HomeTab)>[
  (kPathBeaconView, HomeTab.work),
  (kPathBeaconViewAll, HomeTab.work),
  (kPathBeaconInvolvedAll, HomeTab.work),
  (kPathReviewContributions, HomeTab.work),
  (kPathForwardsGraph, HomeTab.network),
  (kPathGraph, HomeTab.network),
  (kPathProfileView, HomeTab.network),
  (kPathInviteGenealogy, HomeTab.network),
  (kPathRating, HomeTab.network),
  (kPathNotifications, HomeTab.inbox),
];

/// Returns the `/home/<tab>` prefix a bare browse-detail [path] should be
/// nested under, or null when [path] is not a browse detail (leave it alone).
///
/// Used by the root router's deep-link transformer so platform-originated
/// navigations (URL bar edits, hash changes, notification links) resolve
/// directly to the nested branch route with a **single** browser history
/// entry. Without this the raw path matches the root-level redirect guard,
/// whose branch push adds a second entry — browser back then lands on the
/// raw entry and gets re-forwarded, wedging the back chain.
///
/// Warm (non-null [activeIndex]): the active tab wins. Cold: the route
/// family's semantic owner.
String? homeBranchPathPrefixFor({
  required String path,
  required int? activeIndex,
}) {
  HomeTab? owner;
  for (final (prefix, o) in _browsePathOwners) {
    if (path == prefix || path.startsWith('$prefix/')) {
      owner = o;
      break;
    }
  }
  if (owner == null) {
    return null;
  }
  final effective = activeIndex == null
      ? owner
      : HomeTabSpec.fromIndex(activeIndex)?.tab ?? HomeTab.work;
  return HomeTabSpec.forTab(effective).path;
}
