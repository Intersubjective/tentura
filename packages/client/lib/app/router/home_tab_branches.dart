import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/navigation/home_tab.dart';

import 'root_router.gr.dart';

export 'package:tentura/ui/navigation/home_tab.dart';

/// Per-tab shell branches for [HomeRoute]'s [AutoTabsRouter]. Each shell keeps
/// its tab root and independent tab state while browse details live on the
/// shared root stack above [HomeRoute].
const workTabShell = EmptyShellRoute('WorkTabShell');
const conversationsTabShell = EmptyShellRoute('ConversationsTabShell');
const inboxTabShell = EmptyShellRoute('InboxTabShell');
const constellationTabShell = EmptyShellRoute('ConstellationTabShell');
const networkTabShell = EmptyShellRoute('NetworkTabShell');
const meTabShell = EmptyShellRoute('MeTabShell');

/// The AutoRoute half of [HomeTabSpec]: each tab's branch shell and root
/// route. Router-side only; feature UI uses the route-free [HomeTabSpec].
extension HomeTabSpecRoutes on HomeTabSpec {
  EmptyShellRoute get shell => switch (tab) {
    HomeTab.work => workTabShell,
    HomeTab.conversations => conversationsTabShell,
    HomeTab.inbox || HomeTab.updates => inboxTabShell,
    HomeTab.constellation => constellationTabShell,
    HomeTab.network => networkTabShell,
    HomeTab.me => meTabShell,
  };

  PageRouteInfo Function() get rootRoute => switch (tab) {
    HomeTab.work => MyWorkRoute.new,
    HomeTab.conversations => ConversationsRoute.new,
    HomeTab.inbox || HomeTab.updates => InboxRoute.new,
    HomeTab.constellation => ConstellationRoute.new,
    HomeTab.network => FriendsRoute.new,
    HomeTab.me => ProfileRoute.new,
  };
}
