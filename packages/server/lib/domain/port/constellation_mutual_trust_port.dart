import 'package:tentura_server/domain/entity/constellation_field.dart';

/// Explicit trust of one person on the viewer's field, read when the viewer
/// selects them. The field itself cannot answer for everyone on it: it holds
/// no edges of the people the anchors reserve (pinned and support peers).
// ignore: one_member_abstracts -- narrow read boundary, like the field port
abstract interface class ConstellationMutualTrustPort {
  /// The explicit (tier 1, `vote_user`) trust edges between [personId] and
  /// the people they trust both ways, in either direction, under exactly the
  /// rules of the field's own edges (`constellation_trust_edges`): both ends
  /// are the viewer or in the viewer's visible set, and there is no block
  /// either way between the viewer and either end or between the two ends.
  /// Order: src, then dst.
  Future<List<ConstellationEdgeRecord>> explicitTrustEdgesOf({
    required String viewerId,
    required String context,
    required String personId,
  });
}
