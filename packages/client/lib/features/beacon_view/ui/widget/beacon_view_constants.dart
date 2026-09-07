import 'package:flutter/material.dart';

/// Operational tab indices for [BeaconViewScreen].
const int kBeaconTabThreads = 0;
const int kBeaconTabPeople = 1;
const int kBeaconTabLog = 2;
const int kBeaconTabCount = 3;

/// Icons for [TenturaUnderlineTabs] on the request detail screen.
const List<IconData> kBeaconTabIcons = [
  Icons.forum_outlined,
  Icons.people_outline,
  Icons.history_outlined,
];

/// Logical surface ids for the request detail screen. Stable across window
/// classes — the visible tab set is a subset, never a re-index.
enum BeaconSurface { now, room, people }

/// ROOM is hidden only when the expanded split is actually active, because the
/// conversation is then permanently visible in the right pane (plan D1/§4.1).
List<BeaconSurface> beaconVisibleSurfaces({required bool isSplit}) =>
    isSplit
        ? const [BeaconSurface.now, BeaconSurface.people]
        : const [BeaconSurface.now, BeaconSurface.room, BeaconSurface.people];
