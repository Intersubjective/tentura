import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/exception.dart';

/// Shared visibility gate for fork and lineage-suggestion reads.
///
/// Loads by id without author filter; rejects DELETED and other users' drafts.
void assertBeaconLineageSourceVisible({
  required BeaconEntity beacon,
  required String userId,
}) {
  if (beacon.isDeleted) {
    throw const BeaconCreateException(
      description: 'Cannot use a deleted beacon as a lineage source',
    );
  }
  if (beacon.state == 3 && beacon.author.id != userId) {
    throw const BeaconCreateException(
      description: "Cannot use another user's draft as a lineage source",
    );
  }
}

/// DRAFT = 3
const kBeaconStateDraft = 3;

/// DELETED = 2
const kBeaconStateDeleted = 2;
