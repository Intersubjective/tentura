import '../constellation_field_patches.dart';
import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_field.dart';

/// Small authorized reads that keep an open field fresh between FULL reads
/// (#672, #671). Neither reads MeritRank scores or the visible set.
abstract interface class ConstellationTargetedReadPort {
  /// At most this many people per [readViewerRelations] call.
  static const maxRelationIds = 10;

  /// At most this many Requests per [fetchRequests] call.
  static const maxRequestIds = 20;

  /// The viewer's explicit trust to and from each of [personIds] (at most
  /// [maxRelationIds]). Someone the viewer may not see is left out.
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  );

  /// Those of [beaconIds] (at most [maxRequestIds]) that are published,
  /// discoverable Requests the viewer may read under [membershipFilters].
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  });
}
