import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Client-side gate for delete affordance (server enforces authoritatively).
bool beaconDeleteBlockedByCommitters(
  Beacon beacon, {
  bool? serverCanDelete,
}) =>
    serverCanDelete != null
        ? !serverCanDelete
        : beacon.status == BeaconStatus.reviewOpen ||
              beacon.status == BeaconStatus.closed ||
              (beacon.helpOfferCount > 0 &&
                  beacon.status != BeaconStatus.open);

bool beaconAllowsCancel(
  Beacon beacon, {
  bool? serverCanCancel,
}) =>
    serverCanCancel ??
    (beacon.status == BeaconStatus.open && beacon.helpOfferCount == 0);

/// Mirrors the server's edit gate (open-family or wrapping-up review window).
bool beaconAllowsEdit(Beacon beacon) =>
    beacon.status.isOpenFamily || beacon.status == BeaconStatus.reviewOpen;
