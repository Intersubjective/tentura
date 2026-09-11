import 'package:meta/meta.dart';

import 'constellation_anchor.dart';
import 'constellation_field.dart';

enum ConstellationProjection {
  full('FULL'),
  anchors('ANCHORS');

  const ConstellationProjection(this.wireValue);

  final String wireValue;

  static ConstellationProjection? fromWire(String wire) => switch (wire) {
        'FULL' => ConstellationProjection.full,
        'ANCHORS' => ConstellationProjection.anchors,
        _ => null,
      };
}

@immutable
class ConstellationFieldMembershipFilters {
  const ConstellationFieldMembershipFilters({
    this.showClosed = false,
    this.participatedOnly = false,
  });

  final bool showClosed;
  final bool participatedOnly;

  static const defaults = ConstellationFieldMembershipFilters();

  Map<String, Object> toFixtureMap() => {
        'showClosed': showClosed,
        'participatedOnly': participatedOnly,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationFieldMembershipFilters &&
          other.showClosed == showClosed &&
          other.participatedOnly == participatedOnly;

  @override
  int get hashCode => Object.hash(showClosed, participatedOnly);
}

const kConstellationUpsertEligibleBeaconStatuses = {0, 7, 8, 5, 4, 6};

const kConstellationDefaultFieldBeaconStatuses = {0, 7, 8};

const kConstellationShowClosedFieldBeaconStatuses = {0, 7, 8, 5, 4, 6};

bool isKnownConstellationBeaconStatus(int status) =>
    kConstellationUpsertEligibleBeaconStatuses.contains(status);

Set<int> constellationFieldBeaconStatuses({
  required bool showClosed,
}) =>
    showClosed
        ? kConstellationShowClosedFieldBeaconStatuses
        : kConstellationDefaultFieldBeaconStatuses;

bool constellationBeaconStatusPermittedInField({
  required int status,
  required bool showClosed,
}) =>
    isKnownConstellationBeaconStatus(status) &&
    constellationFieldBeaconStatuses(showClosed: showClosed).contains(status);

@immutable
class ConstellationAnchorProjection {
  const ConstellationAnchorProjection({
    required this.revision,
    required this.anchors,
    required this.pinnedPeers,
    required this.pinnedRequests,
    required this.supportPeers,
    required this.supportEdges,
    required this.serverFilteredBeaconIds,
    required this.serverFilteredBeaconCount,
  });

  final ConstellationAnchorRevision revision;
  final List<ConstellationAnchor> anchors;
  final List<ConstellationPeerRecord> pinnedPeers;
  final List<ConstellationRequestRecord> pinnedRequests;
  final List<ConstellationPeerRecord> supportPeers;
  final List<ConstellationEdgeRecord> supportEdges;
  final List<String> serverFilteredBeaconIds;
  final int serverFilteredBeaconCount;

  static final empty = ConstellationAnchorProjection(
    revision: ConstellationAnchorRevision.zero,
    anchors: const [],
    pinnedPeers: const [],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  );

  Map<String, Object> toFixtureMap() => {
        ...revision.toFixtureMap(),
        'serverFilteredBeaconCount': serverFilteredBeaconCount,
        'serverFilteredBeaconIds': serverFilteredBeaconIds,
        'anchorCount': anchors.length,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationAnchorProjection &&
          other.revision == revision &&
          _listEquals(other.anchors, anchors) &&
          _listEquals(other.pinnedPeers, pinnedPeers) &&
          _listEquals(other.pinnedRequests, pinnedRequests) &&
          _listEquals(other.supportPeers, supportPeers) &&
          _listEquals(other.supportEdges, supportEdges) &&
          _listEquals(other.serverFilteredBeaconIds, serverFilteredBeaconIds) &&
          other.serverFilteredBeaconCount == serverFilteredBeaconCount;

  @override
  int get hashCode => Object.hash(
        revision,
        Object.hashAll(anchors),
        Object.hashAll(pinnedPeers),
        Object.hashAll(pinnedRequests),
        Object.hashAll(supportPeers),
        Object.hashAll(supportEdges),
        Object.hashAll(serverFilteredBeaconIds),
        serverFilteredBeaconCount,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
