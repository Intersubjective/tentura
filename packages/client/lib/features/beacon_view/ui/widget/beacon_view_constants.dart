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
      return kPlanEnabled ? BeaconSurface.plan : BeaconSurface.now;
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
/// PLAN (#220) is shown only while [planEnabled] (`kPlanEnabled`).
List<BeaconSurface> beaconVisibleSurfaces({
  required bool isSplit,
  bool planEnabled = kPlanEnabled,
}) => [
  BeaconSurface.now,
  if (planEnabled) BeaconSurface.plan,
  if (!isSplit) BeaconSurface.room,
  BeaconSurface.people,
];
