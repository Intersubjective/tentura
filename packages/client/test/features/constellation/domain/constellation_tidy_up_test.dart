import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_nearest_ring.dart';
import 'package:tentura/features/constellation/domain/constellation_tidy_up.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

import '../fixtures/constellation_tidy_overlap.dart';

/// «Tidy up» resolves node and label overlaps with the fewest, smallest moves:
/// people keep their trust ring and their angular order around the viewer,
/// pinned people never move, and the same input always gives the same output.

const LPoint _ego = (x: 0, y: 0);
const _radius = 20.0;
const _diameter = 2 * _radius;
const LSize _label = (w: 36, h: 12);
const _ring = 2 * kConstellationRingUnitPixels;

LPoint _onRing(double angle, [double radius = _ring]) =>
    (x: math.cos(angle) * radius, y: math.sin(angle) * radius);

ConstellationTidyNode _node(String id, LPoint at, {bool pinned = false}) => (
  id: id,
  position: at,
  radius: _radius,
  labelSize: _label,
  pinned: pinned,
);

/// Five people on one ring, 15 px apart along the arc: every neighbour pair
/// overlaps, but a spread of at most 1.5 diameters resolves them.
List<ConstellationTidyNode> _crowd() => [
  for (var i = 0; i < 5; i++)
    _node('P$i', _onRing(-math.pi / 2 + i * 15 / _ring)),
];

double _gap(LPoint a, LPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

LPoint _labelCentre(LPoint at) => (x: at.x, y: at.y + _radius + _label.h / 2);

bool _labelsOverlap(LPoint a, LPoint b) =>
    (_labelCentre(a).x - _labelCentre(b).x).abs() < _label.w &&
    (_labelCentre(a).y - _labelCentre(b).y).abs() < _label.h;

Map<String, LPoint> _after(
  List<ConstellationTidyNode> nodes,
  Map<String, LPoint> moves,
) => {for (final n in nodes) n.id: moves[n.id] ?? n.position};

ConstellationTidyResult _tidy(
  List<ConstellationTidyNode> nodes, {
  Set<String>? selection,
  LRect? visibleRect,
}) => constellationTidyUp(
  ego: _ego,
  nodes: nodes,
  selection: selection,
  visibleRect: visibleRect,
);

void main() {
  group('tidy up', () {
    test('leaves no node or label overlapping another', () {
      final nodes = _crowd();
      final placed = _after(nodes, _tidy(nodes).moves);

      expect(
        tidyOverlaps(placed, radius: _radius, labelSize: _label),
        isEmpty,
      );
    });

    test('moves no node further than 1.5 node diameters', () {
      final nodes = _crowd();
      final result = _tidy(nodes);

      expect(result.moves, isNotEmpty);
      for (final node in nodes) {
        final to = result.moves[node.id];
        if (to == null) continue;
        expect(
          _gap(node.position, to),
          lessThanOrEqualTo(1.5 * _diameter + 1e-6),
          reason: node.id,
        );
      }
    });

    test('never moves a pinned node', () {
      final nodes = [
        for (final n in _crowd()) _node(n.id, n.position, pinned: n.id == 'P2'),
      ];
      final result = _tidy(nodes);

      expect(result.moves.containsKey('P2'), isFalse);
      final placed = _after(nodes, result.moves);
      for (final id in ['P0', 'P1', 'P3', 'P4']) {
        expect(
          _gap(placed[id]!, placed['P2']!),
          greaterThanOrEqualTo(_diameter),
        );
      }
    });

    test('keeps every person on their trust ring', () {
      final nodes = _crowd();
      final placed = _after(nodes, _tidy(nodes).moves);

      for (final node in nodes) {
        expect(
          constellationNearestRing(centre: _ego, point: placed[node.id]!).steps,
          constellationNearestRing(centre: _ego, point: node.position).steps,
          reason: node.id,
        );
      }
    });

    test('keeps the angular order around the viewer', () {
      final nodes = _crowd();
      final placed = _after(nodes, _tidy(nodes).moves);

      double angle(LPoint p) => math.atan2(p.y - _ego.y, p.x - _ego.x);
      final before = [...nodes]
        ..sort((a, b) => angle(a.position).compareTo(angle(b.position)));
      final ids = placed.keys.toList()
        ..sort((a, b) => angle(placed[a]!).compareTo(angle(placed[b]!)));

      expect(ids, before.map((n) => n.id).toList());
    });

    test('gives the same moves for the same input', () {
      final first = _tidy(_crowd()).moves;
      final second = _tidy(_crowd()).moves;

      expect(second, first);
    });

    test('moves nobody when nothing overlaps', () {
      final nodes = [
        for (var i = 0; i < 5; i++) _node('P$i', _onRing(i * 1.0)),
      ];

      expect(_tidy(nodes).moves, isEmpty);
    });

    test('resolves overlaps inside the selection and touches nobody else', () {
      // P0 / P1 overlap each other; P2 / P3 overlap each other too, but are
      // not selected.
      final nodes = [
        _node('P0', _onRing(0.4)),
        _node('P1', _onRing(0.4 + 15 / _ring)),
        _node('P2', _onRing(2.4)),
        _node('P3', _onRing(2.4 + 15 / _ring)),
      ];
      final result = _tidy(nodes, selection: {'P0', 'P1'});
      final placed = _after(nodes, result.moves);

      expect(result.moves.keys.toSet(), {'P0', 'P1'});
      expect(
        _gap(placed['P0']!, placed['P1']!),
        greaterThanOrEqualTo(_diameter - 1e-6),
      );
      expect(placed['P2'], nodes[2].position);
      expect(placed['P3'], nodes[3].position);
    });

    test('resolves overlaps inside the visible rectangle only', () {
      final nodes = [
        _node('A0', (x: 0, y: 300)),
        _node('A1', (x: 10, y: 300)),
        _node('B0', (x: 2000, y: 300)),
        _node('B1', (x: 2010, y: 300)),
      ];
      final result = _tidy(
        nodes,
        visibleRect: (left: -200, top: 100, right: 200, bottom: 500),
      );
      final placed = _after(nodes, result.moves);

      expect(result.moves.keys.toSet(), {'A0', 'A1'});
      expect(
        _gap(placed['A0']!, placed['A1']!),
        greaterThanOrEqualTo(_diameter - 1e-6),
      );
      expect(placed['B0'], nodes[2].position);
      expect(placed['B1'], nodes[3].position);
    });

    test('lists exactly the people who were displaced and counts them', () {
      final nodes = [
        ..._crowd(),
        _node('Far', _onRing(3.5)),
        _node('Pinned', _onRing(5), pinned: true),
      ];
      final result = _tidy(nodes);
      final displaced = {
        for (final n in nodes)
          if (_gap(n.position, result.moves[n.id] ?? n.position) > 1e-9) n.id,
      };

      expect(result.moves.keys.toSet(), displaced);
      expect(result.movedCount, displaced.length);
      expect(result.moves.containsKey('Far'), isFalse);
    });

    test(
      'tidies a 400-person Field within the move cap and without overlaps',
      () {
        // A timing bench rather than a gate: the elapsed time is printed, not
        // asserted.
        final nodes = <ConstellationTidyNode>[];
        for (var ring = 1; ring <= 8 && nodes.length < 400; ring++) {
          for (var i = 0; i < 12 * ring && nodes.length < 400; i++) {
            final base = i / (12 * ring) * 2 * math.pi;
            final nudge = i.isOdd
                ? 15 / (ring * kConstellationRingUnitPixels)
                : 0;
            nodes.add(
              _node(
                'R${ring}_$i',
                _onRing(base + nudge, ring * kConstellationRingUnitPixels),
              ),
            );
          }
        }
        final watch = Stopwatch()..start();
        final result = _tidy(nodes);
        watch.stop();
        // ignore: avoid_print
        print(
          'tidy up of ${nodes.length} people: ${watch.elapsedMilliseconds} ms',
        );

        final placed = _after(nodes, result.moves);
        for (final node in nodes) {
          expect(
            _gap(node.position, placed[node.id]!),
            lessThanOrEqualTo(1.5 * _diameter + 1e-6),
          );
        }
        expect(
          tidyOverlaps(placed, radius: _radius, labelSize: _label),
          isEmpty,
        );
      },
    );
  });
}
