import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/exception.dart';

/// Shared visibility gate for fork and lineage-suggestion reads.
void assertBeaconLineageSourceVisible({
  required BeaconEntity beacon,
  required String userId,
}) {
  if (beacon.isDeleted) {
    throw const BeaconCreateException(
      description: 'Cannot use a deleted beacon as a lineage source',
    );
  }
  if (beacon.status == BeaconStatus.draft && beacon.author.id != userId) {
    throw const BeaconCreateException(
      description: "Cannot use another user's draft as a lineage source",
    );
  }
}

const kBeaconStateDraft = 3;
const kBeaconStateDeleted = 2;
