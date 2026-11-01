import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';

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
/// PLAN is shown only when [hasPlan] (#546: a Request without a plan step has
/// no Plan tab; a plan is started from the overflow menu).
List<BeaconSurface> beaconVisibleSurfaces({
  required bool isSplit,
  required bool hasPlan,
}) => [
  BeaconSurface.now,
  if (hasPlan) BeaconSurface.plan,
  if (!isSplit) BeaconSurface.room,
  BeaconSurface.people,
];

/// #546: the Request has a plan worth a Plan tab and Now plan rows — at
/// least one step. No plan, or a plan whose steps were all removed, has none.
bool beaconPlanHasSteps(BeaconPlan? plan) => plan != null && !plan.isEmpty;

/// #546: the Plan surface can be shown — the plan has a step, or it is still
/// loading (a `tab=plan` deep link waits for it instead of leaving at once).
bool beaconPlanSurfaceAvailable({
  required BeaconPlan? plan,
  required bool loading,
}) => plan == null ? loading : !plan.isEmpty;
