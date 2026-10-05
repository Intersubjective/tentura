import 'package:flutter/material.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'constellation_navbar_item.dart';
import 'conversations_navbar_item.dart';
import 'friends_navbar_item.dart';
import 'inbox_navbar_item.dart';
import 'my_work_navbar_item.dart';

/// One Home navigation destination, shared by the rail, the bottom bar and
/// [HomeRailFrame] so their lists cannot drift apart.
typedef HomeNavDestinationData = ({
  Widget icon,
  Widget selectedIcon,
  String label,
});

/// Home's destinations in [HomeTabSpec.destinations] order; position equals
/// the tab index. Me is not among them: the account avatar opens it.
///
/// [badged] items read Home's attention state; without it (a route rendered
/// outside Home's providers, isolated tests) they fall back to plain glyphs.
List<HomeNavDestinationData> homeNavDestinations(
  L10n l10n, {
  bool badged = true,
}) => [
  for (final spec in HomeTabSpec.destinations)
    switch (spec.tab) {
      HomeTab.work => (
        icon: badged
            ? const MyWorkNavbarItem()
            : const Icon(Icons.work_outline),
        selectedIcon: badged
            ? const MyWorkNavbarItem(selected: true)
            : const Icon(Icons.work),
        label: l10n.myWork,
      ),
      HomeTab.conversations => (
        icon: const ConversationsNavbarItem(),
        selectedIcon: const ConversationsNavbarItem(selected: true),
        label: l10n.activityTabConversations,
      ),
      HomeTab.inbox => (
        icon: badged
            ? const InboxNavbarItem()
            : const Icon(Icons.inbox_outlined),
        selectedIcon: badged
            ? const InboxNavbarItem(selected: true)
            : const Icon(Icons.inbox),
        label: l10n.inbox,
      ),
      HomeTab.constellation => (
        icon: badged
            ? const ConstellationNavbarItem()
            : const Icon(TenturaIcons.graph),
        selectedIcon: badged
            ? const ConstellationNavbarItem(selected: true)
            : const Icon(TenturaIcons.graph),
        label: l10n.constellationNavLabel,
      ),
      HomeTab.network => (
        icon: badged
            ? const FriendsNavbarItem()
            : const Icon(Icons.people_outline),
        selectedIcon: badged
            ? const FriendsNavbarItem(selected: true)
            : const Icon(Icons.people),
        label: l10n.network,
      ),
      // Not destinations: Updates is an Inbox alias, Me sits on the avatar.
      HomeTab.updates || HomeTab.me => throw StateError('${spec.tab}'),
    },
];
