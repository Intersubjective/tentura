import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

/// Size map that counts keyed reads, so the overlap scan's per-candidate cost
/// is pinned by work done rather than by wall-clock.
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

const _peerCount = 60;

({
  ConstellationPathResolution paths,
  Set<String> peers,
  Map<String, List<String>> requests,
})
_scene() {
  final peers = {for (var i = 0; i < _peerCount; i++) 'p$i'};
  final paths = resolveConstellationPaths(
    egoId: 'ego',
    visiblePeerIds: peers,
    holderIds: peers,
    edges: [for (final id in peers) (src: 'ego', dst: id, tier: 1)],
    maxHops: 3,
  );
  return (
    paths: paths,
    peers: peers,
    requests: {
      for (var i = 0; i < _peerCount; i += 2) 'p$i': ['r$i'],
    },
  );
}

ConstellationLayout _layout(Map<String, ConstellationSize> sizes) {
  final scene = _scene();
  return computeConstellationLayout(
    egoId: 'ego',
    paths: scene.paths,
    keptPeerIds: scene.peers,
    visibleRequestsByAuthor: scene.requests,
    egoOwnRequestIds: const {},
    nodeSizes: sizes,
  );
}

const _recordedDefaultFingerprint = '91/e4c5fea0';
const _recordedCrowdedFingerprint = '91/191c1371';
const _recordedFingerprint = '91/cc713b5d';

/// FNV-1a over every seat (exact double text) and ring, in key order.
String _fingerprint(ConstellationLayout layout) {
  final keys = layout.positions.keys.toList()..sort();
  final text = StringBuffer();
  for (final k in keys) {
    final p = layout.positions[k]!;
    text.write('$k:${p.x},${p.y},${layout.ring[k]};');
  }
  var hash = 0x811c9dc5;
  for (final unit in text.toString().codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return '${keys.length}/${hash.toRadixString(16)}';
}

/// Source of the overlap scan, up to the next top-level function.
String _overlapScanSource() {
  final source = File(
    'lib/features/constellation/domain/constellation_layout.dart',
  ).readAsStringSync();
  final start = source.indexOf('Iterable<void> _totalIntersectionArea({');
  final end = source.indexOf('Iterable<void> _totalObstacleIntersectionArea');
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  group('constellation layout overlap scan', () {
    test('reads each node size a bounded number of times, not once per '
        'candidate per placed node', () {
      final scene = _scene();
      final nodeCount = 1 + scene.peers.length + scene.requests.length;
      final sizes = _CountingSizes({
        'ego': (width: 64, height: 64),
        for (final id in scene.peers) id: (width: 72, height: 48),
        for (final ids in scene.requests.values)
          for (final id in ids) id: (width: 56, height: 40),
      });

      final layout = _layout(sizes);

      expect(layout.positions.length, nodeCount);
      // Each node's size may be resolved a handful of times (own footprint,
      // author seat, flattening) but never per scan iteration.
      expect(sizes.reads, lessThanOrEqualTo(nodeCount * 8));
    });

    test('seats and rings keep their recorded values', () {
      final scene = _scene();
      final layout = _layout({
        'ego': (width: 64, height: 64),
        for (final id in scene.peers) id: (width: 72, height: 48),
        for (final ids in scene.requests.values)
          for (final id in ids) id: (width: 56, height: 40),
      });

      expect(_fingerprint(layout), _recordedFingerprint);
    });

    test('reads an empty size map a bounded number of times', () {
      final sizes = _CountingSizes({});
      final layout = _layout(sizes);

      expect(layout.positions.length, 91);
      expect(sizes.reads, lessThanOrEqualTo(91 * 8));
    });

    test('seats and rings with default sizes keep their recorded values', () {
      expect(_fingerprint(_layout(const {})), _recordedDefaultFingerprint);
    });

    test('seats and rings of a crowded scene with large sizes keep their '
        'recorded values', () {
      final scene = _scene();
      final layout = _layout({
        'ego': (width: 200, height: 200),
        for (final id in scene.peers) id: (width: 160, height: 120),
        for (final ids in scene.requests.values)
          for (final id in ids) id: (width: 140, height: 90),
      });

      expect(_fingerprint(layout), _recordedCrowdedFingerprint);
    });

    test('scan loop does no per-node map lookups and builds no default size '
        'record per iteration', () {
      final body = _overlapScanSource();

      expect(body, isNot(contains('placed[')));
      expect(body, isNot(contains('placedSizes[')));
      expect(body, isNot(contains('(width: 64, height: 64)')));
    });
  });
}
