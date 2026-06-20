import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';

/// Client-side gate for delete affordance (server enforces authoritatively).
bool beaconDeleteBlockedByCommitters(Beacon beacon) =>
    beacon.lifecycle == BeaconLifecycle.reviewOpen ||
    beacon.lifecycle == BeaconLifecycle.closed ||
    (beacon.helpOfferCount > 0 &&
        beacon.coordinationStatus !=
            BeaconCoordinationStatus.noHelpOffersYet);

bool beaconAllowsCancel(Beacon beacon) =>
    beacon.lifecycle == BeaconLifecycle.open && beacon.helpOfferCount == 0;
