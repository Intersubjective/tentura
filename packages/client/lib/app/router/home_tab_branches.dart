import 'package:auto_route/auto_route.dart';

import 'root_router.gr.dart';

/// Per-tab shell branches for [HomeRoute]'s [AutoTabsRouter]. Each shell hosts
/// its own nested `StackRouter` so browse details (beacon view, …) push onto
/// the active tab's own back stack instead of the shared root stack — see
/// `docs/adaptive-router-refactor-plan.md` (Phase 2, Step 1).
const workTabShell = EmptyShellRoute('WorkTabShell');
const inboxTabShell = EmptyShellRoute('InboxTabShell');
const networkTabShell = EmptyShellRoute('NetworkTabShell');
const meTabShell = EmptyShellRoute('MeTabShell');

/// Detail routes reachable from *any* browse tab while looking at content.
/// Shared across all four branches via one helper so the child list can't
/// drift between tabs — add new "browse cluster" routes here (Step 2) rather
/// than inline per branch.
List<AutoRoute> browseDetailChildren() => [
  AutoRoute(
    usesPathAsKey: true,
    page: BeaconViewRoute.page,
    path: 'beacon/view/:id',
  ),
];

/// Maps [TabsRouter.activeIndex] on [HomeRoute] to its shell branch. Used by
/// root-level redirect guards to forward a bare path (e.g. `/beacon/view/:id`)
/// into whichever tab branch is currently active; cold start (no active
/// index yet) defaults to the MyWork branch (index 0).
EmptyShellRoute homeTabShellForIndex(int index) => switch (index) {
  1 => inboxTabShell,
  2 => networkTabShell,
  3 => meTabShell,
  _ => workTabShell,
};
