import 'entity/constellation_field.dart';

/// Scene graph id prefix for a person on the Field map (`fp:`).
const kConstellationFieldPersonGraphPrefix = 'fp:';

/// Scene graph id prefix for a Request or Post satellite (`fr:`).
const kConstellationFieldBeaconGraphPrefix = 'fr:';

String constellationFieldPersonGraphId(String personId) =>
    '$kConstellationFieldPersonGraphPrefix$personId';

String constellationFieldBeaconGraphId(String beaconId) =>
    '$kConstellationFieldBeaconGraphPrefix$beaconId';

/// Every Request or Post on [field] that still carries unread state (#256).
Iterable<({String beaconId, String authorId})>
constellationFieldUnreadBeaconEntries(ConstellationField field) sync* {
  for (final request in field.requests) {
    if (request.hasUnread) {
      yield (beaconId: request.id, authorId: request.authorId);
    }
  }
  for (final post in field.posts) {
    if (post.hasUnread) {
      yield (beaconId: post.id, authorId: post.authorId);
    }
  }
  for (final request in field.resolvedAnchorProjection.pinnedRequests) {
    if (request.hasUnread) {
      yield (beaconId: request.id, authorId: request.authorId);
    }
  }
}

/// Resolves where the unread ambient glow is drawn: under the item when its
/// body is on the map, otherwise rolled up under the author's person node
/// (#256 xdle.3).
Map<String, String> constellationFieldUnreadGlowGraphIds({
  required ConstellationField field,
  required Set<String> beaconGraphIdsOnMap,
  required Set<String> personGraphIdsOnMap,
}) {
  final glow = <String, String>{};
  for (final entry in constellationFieldUnreadBeaconEntries(field)) {
    final beaconGraph = constellationFieldBeaconGraphId(entry.beaconId);
    if (beaconGraphIdsOnMap.contains(beaconGraph)) {
      glow[beaconGraph] = entry.authorId;
      continue;
    }
    final authorGraph = constellationFieldPersonGraphId(entry.authorId);
    if (personGraphIdsOnMap.contains(authorGraph)) {
      glow[authorGraph] = entry.authorId;
    }
  }
  return glow;
}
