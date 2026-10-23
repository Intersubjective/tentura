import 'constellation_anchor_composition.dart';
import 'constellation_trust_badge.dart';
import 'entity/constellation_field.dart';

/// The people on the field whose online presence the field asks for.
///
/// The server reports presence only for friends (mutual positive trust) and
/// people who share a Request chat with the viewer; it silently drops every
/// other id, and it reads presence once per id on each watch update. So the
/// field asks only for its direct contacts (and mutual-trust people, should a
/// field carry one outside the contact list) that are on the map now — the
/// set the server can answer — instead of everyone on it. Never the viewer.
Set<String> constellationPresenceWatchIds({
  required ConstellationField? field,
  required ConstellationComposedPresentation? composition,
  required String viewerId,
}) {
  if (field == null || composition == null || viewerId.isEmpty) {
    return const <String>{};
  }
  final onField = composition.eligiblePersonIds;
  final badges = constellationTrustBadges(field: field, viewerId: viewerId);
  return Set.unmodifiable(<String>{
    for (final id in field.directContactIds)
      if (id != viewerId && onField.contains(id)) id,
    for (final MapEntry(key: id, value: badge) in badges.entries)
      if (badge == ConstellationTrustBadge.mutual &&
          id != viewerId &&
          onField.contains(id))
        id,
  });
}
