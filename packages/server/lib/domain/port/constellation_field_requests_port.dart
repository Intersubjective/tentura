import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';

/// Targeted Request read for an open field (#671): the client asks for the
/// few Requests a `constellation_item` hint named instead of a FULL read.
// ignore: one_member_abstracts -- narrow read boundary, like the field port
abstract interface class ConstellationFieldRequestsPort {
  /// Those of [beaconIds] that a FULL read would list as discoverable peer
  /// Requests of [viewerId] under [filters], minus the visible-set join:
  /// published, discoverable, a Request (not a Post), of an allowed status,
  /// not the viewer's own, no block either way, and readable by the viewer
  /// (`beacon_readable_ids`). Order: author, then id.
  Future<List<ConstellationRequestRecord>> discoverableRequestsByIds({
    required String viewerId,
    required Set<String> beaconIds,
    required ConstellationFieldMembershipFilters filters,
  });
}
