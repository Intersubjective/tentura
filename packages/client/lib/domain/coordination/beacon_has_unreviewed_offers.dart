import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Author has help offers but has not moved past neutral open status.
bool beaconHasUnreviewedOffers(Beacon beacon) =>
    beacon.status == BeaconStatus.open && beacon.helpOfferCount > 0;
