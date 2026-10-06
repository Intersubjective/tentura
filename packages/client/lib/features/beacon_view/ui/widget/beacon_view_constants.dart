import 'package:tentura/consts.dart';

/// Logical surface ids for the request detail screen. Stable across window
/// classes — the visible tab set is a subset, never a re-index.
enum BeaconSurface { now, plan, room, people }

/// Query [kQueryBeaconViewTab] → [BeaconSurface].
BeaconSurface beaconViewSurfaceForTab(String? viewTab) {
  switch (viewTab) {
    case kBeaconViewTabNow:
    case 'log':
      return BeaconSurface.now;
    case kBeaconViewTabPlan:
      return BeaconSurface.plan;
    case kBeaconViewTabPeople:
    case kBeaconViewTabHelpOffers:
      return BeaconSurface.people;
    case kBeaconViewTabThreads:
    case kBeaconViewTabRoomLegacy:
      return BeaconSurface.room;
    default:
      return BeaconSurface.now;
  }
}

String beaconSurfaceViewTab(BeaconSurface surface) => switch (surface) {
  BeaconSurface.now => kBeaconViewTabNow,
  BeaconSurface.plan => kBeaconViewTabPlan,
  BeaconSurface.room => kBeaconViewTabThreads,
  BeaconSurface.people => kBeaconViewTabPeople,
};

/// ROOM is hidden only when the expanded split is actually active, because the
/// conversation is then permanently visible in the right pane (plan D1/§4.1).
List<BeaconSurface> beaconVisibleSurfaces({required bool isSplit}) => [
  BeaconSurface.now,
  BeaconSurface.plan,
  if (!isSplit) BeaconSurface.room,
  BeaconSurface.people,
];
