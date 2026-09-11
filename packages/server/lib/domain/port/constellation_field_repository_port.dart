import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';

/// Parameters for the C4 `readSnapshot` boundary (implemented in P03).
typedef ConstellationFieldReadParams = ({
  ConstellationFieldMembershipFilters filters,
  ConstellationProjection projection,
});

abstract interface class ConstellationFieldRepositoryPort {
  /// C4 read boundary: one repeatable-read snapshot for automatic field,
  /// anchor projection, and revision watermark.
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  });

  /// The **graph** peer set: the first [cap] symmetric (D14) peers by id, via
  /// `person_visible_peers_symmetric`. `capped` is true iff more existed.
  /// These are the only ids edges may span.
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
  });

  Future<List<ConstellationEdgeRecord>> trustEdges({
    required String viewerId,
    required String context,
    required Set<String> nodeIds,
  });

  /// Ego's own active requests. Never subject to `is_discoverable` and never
  /// subject to the peer-request cap (D16 — they are ego's, always shown).
  Future<List<ConstellationRequestRecord>> ownRequests({
    required String viewerId,
  });

  /// Peers' discoverable requests, over the **whole** symmetric peer set — it
  /// joins `person_visible_peers_symmetric` itself rather than taking author ids,
  /// so the graph cap cannot narrow it and no oversized `IN` list is built. Never
  /// returns ego's own. Carries its **own** authorization predicate, independent
  /// of the graph query (UNIT 07): `NOT block_hides(viewer, author)` and
  /// `beacon_can_read_content(b.id, viewer)`, applied before the limit.
  Future<List<ConstellationRequestRecord>> discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
  });

  /// Profiles for the graph peers ∪ every returned request's author.
  Future<List<ConstellationPeerRecord>> peerProfiles({
    required Set<String> ids,
  });
}
