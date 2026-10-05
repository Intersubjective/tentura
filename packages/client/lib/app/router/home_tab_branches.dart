import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';

import 'root_router.gr.dart';

/// Per-tab shell branches for [HomeRoute]'s [AutoTabsRouter]. Each shell keeps
/// its tab root and independent tab state while browse details live on the
/// shared root stack above [HomeRoute].
const workTabShell = EmptyShellRoute('WorkTabShell');
const conversationsTabShell = EmptyShellRoute('ConversationsTabShell');
const inboxTabShell = EmptyShellRoute('InboxTabShell');
const constellationTabShell = EmptyShellRoute('ConstellationTabShell');
const networkTabShell = EmptyShellRoute('NetworkTabShell');
const meTabShell = EmptyShellRoute('MeTabShell');

/// Stable identity for a Home branch. Display order is owned by [HomeTabSpec],
/// not by enum ordinal or ad-hoc router integers.
enum HomeTab { work, conversations, inbox, constellation, updates, network, me }

/// The single mapping between a semantic Home tab and AutoRoute mechanics.
///
/// Keep tab index, branch path, shell, and root together so adding a branch
/// cannot silently shift sibling tab behavior.
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
      tab: HomeTab.conversations,
      index: 1,
      path: kPathConversations,
      shell: conversationsTabShell,
      rootRoute: ConversationsRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.inbox,
      index: 2,
      path: kPathInbox,
      shell: inboxTabShell,
      rootRoute: InboxRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.constellation,
      index: 3,
      path: kPathConstellation,
      shell: constellationTabShell,
      rootRoute: ConstellationRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.network,
      index: 4,
      path: kPathNetwork,
      shell: networkTabShell,
      rootRoute: FriendsRoute.new,
    ),
    HomeTabSpec(
      tab: HomeTab.me,
      index: 5,
      path: kPathProfile,
      shell: meTabShell,
      rootRoute: ProfileRoute.new,
    ),
  ];

  /// Whether the tab is a navigation destination. Me is not: it is opened
  /// from the account avatar (rail bottom, compact top bar).
  bool get isDestination => tab != HomeTab.me;

  /// Navigation destinations in display order. Me is last in [all], so a
  /// destination's position equals its tab [index].
  static final destinations = [
    for (final spec in all)
      if (spec.isDestination) spec,
  ];

  /// The rail / bottom bar selection for the active tab [index]; null while
  /// Me is open (the avatar shows that instead).
  static int? destinationIndexFor(int index) {
    final spec = fromIndex(index);
    return spec == null || !spec.isDestination ? null : spec.index;
  }

  static HomeTabSpec forTab(HomeTab tab) {
    if (tab == HomeTab.updates) {
      return forTab(HomeTab.inbox);
    }
    return all.singleWhere((spec) => spec.tab == tab);
  }

  static HomeTabSpec? fromIndex(int index) {
    for (final spec in all) {
      if (spec.index == index) return spec;
    }
    return null;
  }
}
