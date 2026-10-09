import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

import 'synthetic_field.dart';

ConstellationAnchorPosition layoutAnchor(double x, double y) =>
    ConstellationAnchorPosition(
      xUnits: x,
      yUnits: y,
      coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
    );

ConstellationPlacedLayoutInput _input({
  String egoId = 'ego',
  Set<String> people = const {},
  Set<String>? automatic,
  Set<String> holders = const {},
  Iterable<ConstellationEdgeRef> edges = const [],
  Set<String> pinnedPeople = const {},
  Set<String> pinnedRequests = const {},
  Set<String> support = const {},
  Map<String, ConstellationAnchorPosition> anchors = const {},
  Map<String, List<String>> requests = const {},
  Set<String> egoRequests = const {},
  Map<String, ConstellationSize> sizes = const {},
  Map<String, ConstellationFootprint> footprints = const {},
  ConstellationLayoutPriorHints? prior,
  ConstellationViewportClass viewport = ConstellationViewportClass.expanded,
  int maxHops = 3,
}) => (
  egoId: egoId,
  paths: resolveConstellationPaths(
    egoId: egoId,
    visiblePeerIds: people,
    holderIds: holders,
    edges: edges,
    maxHops: maxHops,
  ),
  automaticKeptPeerIds: automatic ?? people,
  pinnedPersonIds: pinnedPeople,
  pinnedRequestIds: pinnedRequests,
  supportPersonIds: support,
  anchorByNodeId: anchors,
  priorHints: prior,
  nodeSizes: sizes,
  satelliteRequestIdsByAuthor: requests,
  requestAuthorById: {
    for (final entry in requests.entries)
      for (final id in entry.value) id: entry.key,
  },
  egoOwnRequestIds: egoRequests,
  spacing: 16,
  maxHops: maxHops,
  viewportClass: viewport,
  footprints: footprints,
);

ConstellationPlacedLayoutInput withLayoutChanges(
  ConstellationPlacedLayoutInput input, {
  ConstellationPathResolution? paths,
  Map<String, ConstellationAnchorPosition>? anchors,
  Map<String, ConstellationSize>? sizes,
  Map<String, List<String>>? requests,
  Map<String, String>? authors,
  Map<String, ConstellationFootprint>? footprints,
  Set<String>? automatic,
  Set<String>? pinnedPeople,
  Set<String>? pinnedRequests,
  Set<String>? support,
  Set<String>? egoRequests,
  ConstellationLayoutPriorHints? prior,
  ConstellationViewportClass? viewport,
}) => (
  egoId: input.egoId,
  paths: paths ?? input.paths,
  automaticKeptPeerIds: automatic ?? input.automaticKeptPeerIds,
  pinnedPersonIds: pinnedPeople ?? input.pinnedPersonIds,
  pinnedRequestIds: pinnedRequests ?? input.pinnedRequestIds,
  supportPersonIds: support ?? input.supportPersonIds,
  anchorByNodeId: anchors ?? input.anchorByNodeId,
  priorHints: prior ?? input.priorHints,
  nodeSizes: sizes ?? input.nodeSizes,
  satelliteRequestIdsByAuthor: requests ?? input.satelliteRequestIdsByAuthor,
  requestAuthorById: authors ?? input.requestAuthorById,
  egoOwnRequestIds: egoRequests ?? input.egoOwnRequestIds,
  spacing: input.spacing,
  maxHops: input.maxHops,
  viewportClass: viewport ?? input.viewportClass,
  footprints: footprints ?? input.footprints,
);

/// Uses the existing deterministic field fixture without composition's caps.
/// [nodeCount] counts ego, people and Requests, including anchored nodes.
ConstellationPlacedLayoutInput syntheticLayoutInput(int nodeCount) {
  final peopleCount = (nodeCount - 1) ~/ 2;
  final field = syntheticConstellationField(size: peopleCount);
  final requests = field.requests.take(nodeCount - 1 - peopleCount).toList();
  final requestIds = requests.map((request) => request.id).toSet();
  final projection = field.resolvedAnchorProjection;
  final anchors = <String, ConstellationAnchorPosition>{};
  final pinnedPeople = <String>{};
  final pinnedRequests = <String>{};
  for (final anchor in projection.anchors) {
    final target = anchor.target;
    switch (target.kind) {
      case ConstellationAnchorTargetKind.person:
        anchors[target.id] = anchor.position;
        pinnedPeople.add(target.id);
      case ConstellationAnchorTargetKind.beacon:
        if (requestIds.contains(target.id)) {
          anchors[target.id] = anchor.position;
          pinnedRequests.add(target.id);
        }
    }
  }
  // Add one Request when an even node count cannot be split into equal halves.
  final missing = nodeCount - 1 - peopleCount - requests.length;
  final byAuthor = <String, List<String>>{};
  for (final request in requests) {
    byAuthor.putIfAbsent(request.authorId, () => []).add(request.id);
  }
  for (var i = 0; i < missing; i++) {
    byAuthor.putIfAbsent('p0', () => []).add('extra-request-$i');
  }
  final allRequests = byAuthor.values.expand((ids) => ids).toSet();
  const metrics = (
    labelGap: 2.0,
    personLabelWidth: 120.0,
    personLabelHeight: 22.0,
    requestLabelWidth: 144.0,
    requestLabelHeight: 40.0,
    chipWidth: 110.0,
    chipHeight: 44.0,
    badgeOverhang: 8.0,
  );
  return _input(
    people: field.peers.map((person) => person.id).toSet(),
    // Every person is a holder so the placed layout keeps all [nodeCount] nodes.
    holders: {...field.peers.map((person) => person.id), ...byAuthor.keys},
    edges: field.edges.map(
      (edge) => (src: edge.src, dst: edge.dst, tier: edge.tier),
    ),
    pinnedPeople: pinnedPeople,
    pinnedRequests: pinnedRequests,
    anchors: anchors,
    requests: byAuthor,
    sizes: {
      'ego': (width: 40.0, height: 40.0),
      for (final person in field.peers) person.id: (width: 40.0, height: 40.0),
      for (final id in allRequests) id: (width: 36.0, height: 36.0),
    },
    footprints: {
      for (final id in ['ego', ...field.peers.map((person) => person.id)])
        id: constellationNodeFootprint(
          kind: ConstellationFootprintKind.person,
          bodySize: 40,
          hasAuthorChip: false,
          metrics: metrics,
        ),
      for (final id in allRequests)
        id: constellationNodeFootprint(
          kind: ConstellationFootprintKind.request,
          bodySize: 36,
          hasAuthorChip: true,
          metrics: metrics,
        ),
    },
  );
}

/// Input cases from the existing ring-seat, placement and footprint tests.
Map<String, ConstellationPlacedLayoutInput> legacyLayoutInputs() {
  final seats = _input(
    people: {'a', 'b', 'q', 'r'},
    automatic: {'a', 'b', 'r'},
    holders: {'b', 'r'},
    edges: [
      (src: 'ego', dst: 'a', tier: 1),
      (src: 'a', dst: 'b', tier: 1),
      (src: 'b', dst: 'q', tier: 1),
      (src: 'ego', dst: 'q', tier: 2),
      (src: 'q', dst: 'r', tier: 2),
    ],
    requests: {
      'a': ['req1', 'req2'],
      'b': ['req3'],
    },
    egoRequests: {'reqE1', 'reqE2'},
  );
  final pinnedAuthor = _input(
    egoId: 'U_ego',
    people: {'peer-a', 'peer-b'},
    automatic: {'peer-a'},
    holders: {'peer-a'},
    edges: [(src: 'U_ego', dst: 'peer-a', tier: 1)],
    pinnedPeople: {'peer-a'},
    anchors: {'peer-a': layoutAnchor(4, 0)},
    requests: {
      'peer-a': ['B1'],
    },
  );
  final reference = _input(
    people: {'am', 'in', 'sm'},
    holders: {'in'},
    edges: [
      (src: 'ego', dst: 'am', tier: 1),
      (src: 'ego', dst: 'in', tier: 1),
      (src: 'ego', dst: 'sm', tier: 1),
    ],
    requests: {
      'in': ['req-in-1'],
    },
    egoRequests: {'req-ego-1', 'req-ego-2', 'req-ego-3'},
    sizes: {
      for (final id in ['ego', 'am', 'in', 'sm'])
        id: (width: 40.0, height: 40.0),
    },
  );
  const metrics = (
    labelGap: 2.0,
    personLabelWidth: 120.0,
    personLabelHeight: 22.0,
    requestLabelWidth: 144.0,
    requestLabelHeight: 40.0,
    chipWidth: 110.0,
    chipHeight: 44.0,
    badgeOverhang: 8.0,
  );
  final inputs = <String, ConstellationPlacedLayoutInput>{
    'ego without neighbours': _input(),
    'ring seats, satellite fans and residual ring': seats,
    'independent person and Request anchors': _input(
      egoId: 'U_ego',
      people: {'peer-a', 'peer-b'},
      automatic: {'peer-a'},
      holders: {'peer-a'},
      edges: [(src: 'U_ego', dst: 'peer-a', tier: 1)],
      pinnedPeople: {'peer-b'},
      pinnedRequests: {'B1'},
      anchors: {'peer-b': layoutAnchor(4, -3), 'B1': layoutAnchor(-2, 5)},
      requests: {
        'peer-a': ['B-auto'],
      },
    ),
    'unpinned Request attached to pinned author': pinnedAuthor,
    'coincident hard anchors': _input(
      pinnedPeople: {'p1', 'p2'},
      anchors: {'p1': layoutAnchor(1, 1), 'p2': layoutAnchor(1, 1)},
    ),
    'automatic person avoiding pinned obstacle': _input(
      people: {'pinned-peer', 'auto-peer'},
      holders: {'pinned-peer', 'auto-peer'},
      edges: [
        (src: 'ego', dst: 'pinned-peer', tier: 1),
        (src: 'ego', dst: 'auto-peer', tier: 1),
      ],
      pinnedPeople: {'pinned-peer'},
      anchors: {'pinned-peer': layoutAnchor(2, 0)},
      sizes: const {
        'pinned-peer': (width: 120.0, height: 120.0),
        'auto-peer': (width: 120.0, height: 120.0),
      },
    ),
    'reference field with body footprints': reference,
    'reference field with label and author chip footprints': _input(
      people: reference.automaticKeptPeerIds,
      holders: {'in'},
      edges: [
        (src: 'ego', dst: 'am', tier: 1),
        (src: 'ego', dst: 'in', tier: 1),
        (src: 'ego', dst: 'sm', tier: 1),
      ],
      requests: reference.satelliteRequestIdsByAuthor,
      egoRequests: reference.egoOwnRequestIds,
      sizes: reference.nodeSizes,
      footprints: {
        for (final id in ['ego', 'am', 'in', 'sm'])
          id: constellationNodeFootprint(
            kind: ConstellationFootprintKind.person,
            bodySize: 40,
            hasAuthorChip: false,
            metrics: metrics,
          ),
        for (final id in [
          'req-in-1',
          'req-ego-1',
          'req-ego-2',
          'req-ego-3',
        ])
          id: constellationNodeFootprint(
            kind: ConstellationFootprintKind.request,
            bodySize: 36,
            hasAuthorChip: true,
            metrics: metrics,
          ),
      },
    ),
    'support people outside automatic selection': _input(
      people: {'support', 'pinned'},
      automatic: const {},
      holders: {'pinned'},
      edges: [
        (src: 'ego', dst: 'support', tier: 1),
        (src: 'support', dst: 'pinned', tier: 1),
      ],
      support: {'support'},
      pinnedPeople: {'pinned'},
      anchors: {'pinned': layoutAnchor(3, -4)},
    ),
  };
  final previous = computeConstellationPlacedLayout(input: seats);
  final prior = (
    positions: previous.positions,
    ring: previous.ring,
    viewportClass: ConstellationViewportClass.expanded,
  );
  inputs['same viewport prior geometry'] = withLayoutChanges(
    seats,
    prior: prior,
  );
  inputs['changed viewport prior geometry'] = withLayoutChanges(
    seats,
    prior: prior,
    viewport: ConstellationViewportClass.compact,
  );
  for (final x in [-10.0, 10.0]) {
    for (final y in [-10.0, 10.0]) {
      inputs['envelope corner $x,$y'] = withLayoutChanges(
        pinnedAuthor,
        anchors: {'peer-a': layoutAnchor(x, y)},
      );
    }
  }
  for (final n in [100, 300, 600]) {
    inputs['deterministic synthetic field with $n nodes'] =
        syntheticLayoutInput(n);
  }
  return inputs;
}

Map<String, Object> layoutGeometry(ConstellationLayout layout) => {
  'positions': {
    for (final entry in layout.positions.entries)
      entry.key: {'x': entry.value.x, 'y': entry.value.y},
  },
  'ring': layout.ring,
};
