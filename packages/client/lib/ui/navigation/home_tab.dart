import 'package:tentura/consts.dart';

/// Stable identity for a Home branch. Display order is owned by [HomeTabSpec],
/// not by enum ordinal or ad-hoc router integers.
enum HomeTab { work, conversations, inbox, constellation, updates, network, me }

/// The single mapping between a semantic Home tab, its tab index and its
/// branch path.
///
/// Route-free on purpose (feature UI imports it); the branch shell and root
/// route of each tab live beside the router in `home_tab_branches.dart`.
/// Keep tab index and branch path together so adding a branch cannot
/// silently shift sibling tab behavior.
final class HomeTabSpec {
  const HomeTabSpec._({
    required this.tab,
    required this.index,
    required this.path,
  });

  final HomeTab tab;
  final int index;
  final String path;

  static const all = <HomeTabSpec>[
    HomeTabSpec._(tab: HomeTab.work, index: 0, path: kPathMyWork),
    HomeTabSpec._(
      tab: HomeTab.conversations,
      index: 1,
      path: kPathConversations,
    ),
    HomeTabSpec._(tab: HomeTab.inbox, index: 2, path: kPathInbox),
    HomeTabSpec._(
      tab: HomeTab.constellation,
      index: 3,
      path: kPathConstellation,
    ),
    HomeTabSpec._(tab: HomeTab.network, index: 4, path: kPathNetwork),
    HomeTabSpec._(tab: HomeTab.me, index: 5, path: kPathProfile),
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
