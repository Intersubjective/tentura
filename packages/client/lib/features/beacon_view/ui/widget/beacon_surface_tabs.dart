import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'beacon_view_constants.dart';

/// Surface tab row for the request detail screen (NOW / CHAT / People).
class BeaconSurfaceTabs extends StatelessWidget {
  const BeaconSurfaceTabs({
    required this.isSplit,
    required this.selectedSurface,
    required this.onSurfaceSelected,
    this.onSurfaceReselected,
    this.peopleTabAttentionActive = false,
    super.key,
  });

  final bool isSplit;
  final BeaconSurface selectedSurface;
  final ValueChanged<BeaconSurface> onSurfaceSelected;

  /// Called when the already-selected tab is tapped again (fold remount, etc.).
  final ValueChanged<BeaconSurface>? onSurfaceReselected;

  final bool peopleTabAttentionActive;

  static IconData _iconFor(BeaconSurface surface) => switch (surface) {
    BeaconSurface.now => Icons.bolt_outlined,
    BeaconSurface.room => Icons.forum_outlined,
    BeaconSurface.people => Icons.people_outline,
  };

  static String _labelFor(BeaconSurface surface, L10n l10n) =>
      switch (surface) {
        BeaconSurface.now => l10n.labelBeaconTabNow,
        BeaconSurface.room => l10n.labelBeaconTabChat,
        BeaconSurface.people => l10n.labelBeaconTabPeople,
      };

  static String _tabIdFor(BeaconSurface surface) => switch (surface) {
    BeaconSurface.now => TestIds.beaconTabNow,
    BeaconSurface.room => TestIds.beaconTabRoom,
    BeaconSurface.people => TestIds.beaconTabPeople,
  };

  void _onTabTap(List<BeaconSurface> visible, int index) {
    final surface = visible[index];
    if (surface == selectedSurface) {
      onSurfaceReselected?.call(surface);
    } else {
      onSurfaceSelected(surface);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visible = beaconVisibleSurfaces(isSplit: isSplit);

    var selectedIndex = visible.indexOf(selectedSurface);
    if (selectedIndex < 0) {
      selectedIndex = visible.indexOf(BeaconSurface.now);
    }

    final peopleIndex = visible.indexOf(BeaconSurface.people);
    final compactIconTabs = peopleIndex >= 0 ? {peopleIndex} : const <int>{};

    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      buildWhen: (p, c) =>
          p.isBeaconMine != c.isBeaconMine ||
          p.unansweredHelpOffersCount != c.unansweredHelpOffersCount ||
          p.needCoordinationHelpOffersCount != c.needCoordinationHelpOffersCount,
      builder: (context, beaconState) {
        final peopleTabBadge =
            beaconState.isBeaconMine && beaconState.unansweredHelpOffersCount > 0
            ? beaconState.unansweredHelpOffersCount
            : null;
        final peopleTabSecondaryBadge =
            beaconState.needCoordinationHelpOffersCount > 0
            ? beaconState.needCoordinationHelpOffersCount
            : null;

        return BlocBuilder<ThreadsCubit, ThreadsState>(
          buildWhen: (p, c) =>
              p.threads != c.threads ||
              p.resolvedUnreadByThreadId != c.resolvedUnreadByThreadId,
          builder: (context, threadsState) {
            final threadsTabBadge = threadsState.threadsTabUnreadCount > 0
                ? threadsState.threadsTabUnreadCount
                : null;

            final badges = visible.map((surface) {
              return switch (surface) {
                BeaconSurface.room => threadsTabBadge,
                BeaconSurface.people => peopleTabBadge,
                BeaconSurface.now => null,
              };
            }).toList();

            final badgeBackgroundColors = visible.map((surface) {
              return switch (surface) {
                BeaconSurface.people =>
                  peopleTabBadge != null ? tt.danger : null,
                _ => null,
              };
            }).toList();

            final secondaryBadges = visible.map((surface) {
              return switch (surface) {
                BeaconSurface.people => peopleTabSecondaryBadge,
                _ => null,
              };
            }).toList();

            return TenturaUnderlineTabs(
              tabs: visible.map((s) => _labelFor(s, l10n)).toList(),
              icons: visible.map(_iconFor).toList(),
              tabIds: visible.map(_tabIdFor).toList(),
              selectedIndex: selectedIndex,
              onChanged: (i) => _onTabTap(visible, i),
              badges: badges,
              badgeBackgroundColors: badgeBackgroundColors,
              secondaryBadges: secondaryBadges,
              compactIconTabs: compactIconTabs,
              attentionIndex: peopleIndex >= 0 ? peopleIndex : null,
              attentionActive: peopleTabAttentionActive,
            );
          },
        );
      },
    );
  }
}
