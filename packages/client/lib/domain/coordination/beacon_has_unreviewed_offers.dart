import '../entity/beacon.dart';
import '../entity/coordination_status.dart';

/// Author has help offers but has not set coordination status yet.
bool beaconHasUnreviewedOffers(Beacon beacon) =>
    beacon.coordinationStatus == BeaconCoordinationStatus.neutral &&
    beacon.helpOfferCount > 0;
