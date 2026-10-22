import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const _peerCount = 60;

ConstellationLayout _chainLayout() {
  const peers = {'a', 'b', 'c'};
  return computeConstellationLayout(
    egoId: 'ego',
    paths: resolveConstellationPaths(
      egoId: 'ego',
      visiblePeerIds: peers,
      holderIds: peers,
      edges: [
        (src: 'ego', dst: 'a', tier: 1),
        (src: 'a', dst: 'b', tier: 1),
        (src: 'b', dst: 'c', tier: 1),
      ],
    ),
    keptPeerIds: peers,
    visibleRequestsByAuthor: {
      'b': ['rb'],
    },
    egoOwnRequestIds: {'re'},
  );
}

/// Size map that counts keyed reads, so the overlap scan's cost is bounded by
/// work done rather than by wall-clock or source spelling.
class _CountingSizes extends MapBase<String, ConstellationSize> {
  _CountingSizes(this._inner);

  final Map<String, ConstellationSize> _inner;
  int reads = 0;

  @override
  ConstellationSize? operator [](Object? key) {
    reads++;
    return _inner[key];
  }

  @override
  void operator []=(String key, ConstellationSize value) => _inner[key] = value;

  @override
  void clear() => _inner.clear();

  @override
  Iterable<String> get keys => _inner.keys;

  @override
  ConstellationSize? remove(Object? key) => _inner.remove(key);
}

const _defaultNodeSize = (width: 64.0, height: 64.0);

Set<String> get _peers => {for (var i = 0; i < _peerCount; i++) 'p$i'};

/// Every second peer authors one visible Request.
Map<String, List<String>> get _requests => {
  for (var i = 0; i < _peerCount; i += 2) 'p$i': ['r$i'],
};

Set<String> get _requestIds => {
  for (final ids in _requests.values) ...ids,
};

Map<String, ConstellationSize> _sizes({
  required ConstellationSize ego,
  required ConstellationSize peer,
  required ConstellationSize request,
}) => {
  'ego': ego,
  for (final id in _peers) id: peer,
  for (final id in _requestIds) id: request,
};

/// Large bodies on a dense ring: not every node can be seated clear of the
/// others, so the layout falls back to the least-bad seat.
final _crowdedSizes = _sizes(
  ego: (width: 200, height: 200),
  peer: (width: 160, height: 120),
  request: (width: 140, height: 90),
);

final _regularSizes = _sizes(
  ego: (width: 64, height: 64),
  peer: (width: 72, height: 48),
  request: (width: 56, height: 40),
);

ConstellationLayout _layout(Map<String, ConstellationSize> sizes) {
  final peers = _peers;
  return computeConstellationLayout(
    egoId: 'ego',
    paths: resolveConstellationPaths(
      egoId: 'ego',
      visiblePeerIds: peers,
      holderIds: peers,
      edges: [for (final id in peers) (src: 'ego', dst: id, tier: 1)],
    ),
    keptPeerIds: peers,
    visibleRequestsByAuthor: _requests,
    egoOwnRequestIds: const {},
    nodeSizes: sizes,
  );
}

/// Area of the rectangle shared by two nodes' bodies (0 when they only touch).
double _overlapArea({
  required ConstellationPoint a,
  required ConstellationSize sizeA,
  required ConstellationPoint b,
  required ConstellationSize sizeB,
}) {
  final overlapX = (sizeA.width + sizeB.width) / 2 - (a.x - b.x).abs();
  final overlapY = (sizeA.height + sizeB.height) / 2 - (a.y - b.y).abs();
  return overlapX > 0 && overlapY > 0 ? overlapX * overlapY : 0;
}

List<(String, String)> _overlappingPairs(
  ConstellationLayout layout,
  Map<String, ConstellationSize> sizes,
) {
  final ids = layout.positions.keys.toList()..sort();
  return [
    for (var i = 0; i < ids.length; i++)
      for (var j = i + 1; j < ids.length; j++)
        if (_overlapArea(
              a: layout.positions[ids[i]]!,
              sizeA: sizes[ids[i]] ?? _defaultNodeSize,
              b: layout.positions[ids[j]]!,
              sizeB: sizes[ids[j]] ?? _defaultNodeSize,
            ) >
            0)
          (ids[i], ids[j]),
  ];
}

Map<String, ConstellationSize> _sceneSizes({
  required int peerCount,
  bool crowded = false,
}) => {
  'ego': crowded ? (width: 200, height: 200) : (width: 64, height: 64),
  for (var i = 0; i < peerCount; i++)
    'p$i': crowded ? (width: 160, height: 120) : (width: 72, height: 48),
  for (var i = 0; i < peerCount; i += 2)
    'r$i': crowded ? (width: 140, height: 90) : (width: 56, height: 40),
};

/// Runs the layout one cooperative checkpoint at a time and returns the most
/// size lookups made between two consecutive checkpoints.
int _drainSteps(_CountingSizes sizes, {required int peerCount}) {
  final peers = {for (var i = 0; i < peerCount; i++) 'p$i'};
  final input = (
    egoId: 'ego',
    paths: resolveConstellationPaths(
      egoId: 'ego',
      visiblePeerIds: peers,
      holderIds: peers,
      edges: [for (final id in peers) (src: 'ego', dst: id, tier: 1)],
    ),
    automaticKeptPeerIds: peers,
    pinnedPersonIds: const <String>{},
    pinnedRequestIds: const <String>{},
    supportPersonIds: const <String>{},
    anchorByNodeId: const <String, ConstellationAnchorPosition>{},
    priorHints: null as ConstellationLayoutPriorHints?,
    nodeSizes: sizes,
    satelliteRequestIdsByAuthor: {
      for (var i = 0; i < peerCount; i += 2) 'p$i': ['r$i'],
    },
    requestAuthorById: const <String, String>{},
    egoOwnRequestIds: const <String>{},
    spacing: 16.0,
    maxHops: 3,
    viewportClass: ConstellationViewportClass.expanded,
    footprints: const <String, ConstellationFootprint>{},
  );
  var maxReads = 0;
  var readsAtLastCheckpoint = 0;
  for (final _ in constellationPlacedLayoutSteps(
    input: input,
    onComplete: (_) {},
  )) {
    maxReads = math.max(maxReads, sizes.reads - readsAtLastCheckpoint);
    readsAtLastCheckpoint = sizes.reads;
  }
  return maxReads;
}

void main() {
  final expectedIds = {'ego', ..._peers, ..._requestIds};

  group('constellation layout placement', () {
    test('places the ego, every kept peer and every visible Request', () {
      final layout = _layout(_regularSizes);

      expect(layout.positions.keys.toSet(), expectedIds);
    });

    test('places every node when no node sizes are known', () {
      final layout = _layout(const {});

      expect(layout.positions.keys.toSet(), expectedIds);
    });

    test('keeps node bodies apart when the scene has room for them', () {
      final layout = _layout(_regularSizes);

      expect(_overlappingPairs(layout, _regularSizes), isEmpty);
    });

    test('keeps node bodies apart when node sizes are unknown', () {
      final layout = _layout(const {});

      expect(_overlappingPairs(layout, const {}), isEmpty);
    });

    test('gives positions only finite coordinates', () {
      final layout = _layout(_regularSizes);

      for (final entry in layout.positions.entries) {
        expect(entry.value.x.isFinite, isTrue, reason: entry.key);
        expect(entry.value.y.isFinite, isTrue, reason: entry.key);
      }
    });

    test(
      'gives identical positions and rings for two runs of the same input',
      () {
        final first = _layout(_regularSizes);
        final second = _layout(_regularSizes);

        expect(second.positions, first.positions);
        expect(second.ring, first.ring);
      },
    );

    test('does not depend on the iteration order of the node size map', () {
      final reversed = Map<String, ConstellationSize>.fromEntries(
        _regularSizes.entries.toList().reversed,
      );

      final forward = _layout(_regularSizes);
      final backward = _layout(reversed);

      expect(backward.positions, forward.positions);
      expect(backward.ring, forward.ring);
    });

    test('puts the ego on ring 0 and its direct peers on ring 1', () {
      final layout = _layout(_regularSizes);

      expect(layout.ring['ego'], 0);
      for (final id in _peers) {
        expect(layout.ring[id], 1, reason: id);
      }
    });

    test(
      'seats direct peers further from the ego than the ego body radius',
      () {
        final layout = _layout(_regularSizes);
        final ego = layout.positions['ego']!;

        for (final id in _peers) {
          final p = layout.positions[id]!;
          final distance =
              (p.x - ego.x) * (p.x - ego.x) + (p.y - ego.y) * (p.y - ego.y);
          expect(distance, greaterThan(32 * 32), reason: id);
        }
      },
    );
  });

  group('constellation layout under crowding', () {
    // Intended tolerance: when the scene cannot fit every body the layout may
    // seat some bodies overlapping (no zero-overlap seat exists), but it must
    // still place every node, on the canvas, and deterministically.
    test('still places every node', () {
      final layout = _layout(_crowdedSizes);

      expect(layout.positions.keys.toSet(), expectedIds);
    });

    test('keeps every node centre on the canvas', () {
      final layout = _layout(_crowdedSizes);

      for (final entry in layout.positions.entries) {
        expect(entry.value.x, inInclusiveRange(0, kConstellationCanvasExtent));
        expect(entry.value.y, inInclusiveRange(0, kConstellationCanvasExtent));
      }
    });

    test(
      'gives identical positions and rings for two runs of the same input',
      () {
        final first = _layout(_crowdedSizes);
        final second = _layout(_crowdedSizes);

        expect(second.positions, first.positions);
        expect(second.ring, first.ring);
      },
    );
  });

  group('constellation layout rings', () {
    test('only rings nodes that are placed', () {
      final layout = _layout(_regularSizes);

      expect(layout.positions.keys, containsAll(layout.ring.keys));
    });

    test('rings a Request, when it has one, like its author', () {
      final layout = _layout(_regularSizes);

      for (final entry in _requests.entries) {
        final requestRing = layout.ring[entry.value.single];
        if (requestRing != null) {
          expect(requestRing, layout.ring[entry.key], reason: entry.key);
        }
      }
    });

    test('rings peers by hop distance from the ego along a chain', () {
      final layout = _chainLayout();

      expect(layout.ring['ego'], 0);
      expect(layout.ring['a'], 1);
      expect(layout.ring['b'], 2);
      expect(layout.ring['c'], 3);
    });

    test('seats peers of deeper rings further from the ego', () {
      final layout = _chainLayout();
      final ego = layout.positions['ego']!;
      double distanceOf(String id) {
        final p = layout.positions[id]!;
        return math.sqrt(math.pow(p.x - ego.x, 2) + math.pow(p.y - ego.y, 2));
      }

      expect(distanceOf('a'), lessThan(distanceOf('b')));
      expect(distanceOf('b'), lessThan(distanceOf('c')));
    });

    test('places Requests of a chain peer and of the ego', () {
      final layout = _chainLayout();

      expect(layout.positions.keys, containsAll(['rb', 're']));
    });
  });

  group('constellation layout size lookups', () {
    // Intended complexity: a node's size is resolved a handful of times
    // (own footprint, author seat, flattening), so total lookups grow
    // linearly with node count, and no single cooperative checkpoint (one
    // chunk of the overlap scan) spends more than a few lookups.
    test('reads each node size a bounded number of times', () {
      final sizes = _CountingSizes(_regularSizes);

      final layout = _layout(sizes);

      expect(layout.positions.length, expectedIds.length);
      expect(sizes.reads, lessThanOrEqualTo(expectedIds.length * 8));
    });

    test('reads an empty size map a bounded number of times', () {
      final sizes = _CountingSizes({});

      final layout = _layout(sizes);

      expect(layout.positions.length, expectedIds.length);
      expect(sizes.reads, lessThanOrEqualTo(expectedIds.length * 8));
    });

    test('reads crowded node sizes a bounded number of times', () {
      final sizes = _CountingSizes(_crowdedSizes);

      final layout = _layout(sizes);

      expect(layout.positions.length, expectedIds.length);
      expect(sizes.reads, lessThanOrEqualTo(expectedIds.length * 8));
    });

    test('grows size lookups linearly when the scene doubles', () {
      final small = _CountingSizes(_sceneSizes(peerCount: 30));
      final large = _CountingSizes(_sceneSizes(peerCount: 60));

      _drainSteps(small, peerCount: 30);
      _drainSteps(large, peerCount: 60);

      expect(large.reads, lessThanOrEqualTo(small.reads * 5 ~/ 2));
    });

    for (final (name, build) in [
      ('regular', () => _sceneSizes(peerCount: 60)),
      ('crowded', () => _sceneSizes(peerCount: 60, crowded: true)),
    ]) {
      test(
        'does no per-node size lookups between checkpoints in a $name scene',
        () {
          final sizes = _CountingSizes(build());

          final maxReadsPerCheckpoint = _drainSteps(sizes, peerCount: 60);

          expect(maxReadsPerCheckpoint, lessThanOrEqualTo(4));
        },
      );
    }
  });
}
