import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Client-side gate for delete affordance (server enforces authoritatively).
bool beaconDeleteBlockedByCommitters(Beacon beacon) =>
    beacon.status == BeaconStatus.reviewOpen ||
    beacon.status == BeaconStatus.closed ||
    (beacon.helpOfferCount > 0 &&
        beacon.status !=
            BeaconStatus.open);

bool beaconAllowsCancel(Beacon beacon) =>
    beacon.status == BeaconStatus.open && beacon.helpOfferCount == 0;
