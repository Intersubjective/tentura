import 'package:tentura/domain/entity/beacon.dart';

/// Author has active help offers without a coordination response (open-family).
bool beaconHasUnreviewedOffers(Beacon beacon) =>
    beacon.status.isOpenFamily && beacon.unansweredHelpOfferCount > 0;
