import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import 'fixtures/edge_stroke_recording.dart';

/// Dash geometry is expensive (one path segment per dash, per edge, per moved
/// frame). `constellationEdgeDashPathBuildCount` counts every time dashed
/// stroke geometry is constructed, whether into a cached per-edge Path or into
/// a cached layer, so these tests pin the work and not how it is cached.
int _buildsDuring(void Function() body) {
  final before = constellationEdgeDashPathBuildCount;
  body();
  return constellationEdgeDashPathBuildCount - before;
}

void main() {
  group('constellation dashed edge geometry build counts', () {
    test(
      'the first frame builds the dash geometry of each dashed edge once',
      () {
        final scene = edgeScene(
          links: [
            for (var i = 0; i < 12; i++)
              ('h', 's$i', ConstellationEdgeKind.tier2Path),
            for (var i = 0; i < 5; i++)
              ('s$i', 'x$i', ConstellationEdgeKind.tier1Path),
          ],
        );
        Offset at(NodeDetails n) {
          final id = personId(n);
          return id == 'h'
              ? Offset.zero
              : Offset(37.0 * id.hashCode.abs() % 400 + 80, 90);
        }

        expect(_buildsDuring(() => paintFrame(scene, at)), 12);
      },
    );

    test('frames with nothing moved build no dash geometry', () {
      final scene = edgeScene(
        links: [
          for (var i = 0; i < 30; i++)
            ('n$i', 'n${i + 1}', ConstellationEdgeKind.webForwarded),
        ],
      );
      Offset at(NodeDetails n) {
        final i = int.parse(personId(n).substring(1));
        return Offset(40.0 * i, 20.0 * (i % 5));
      }

      paintFrame(scene, at);

      expect(
        _buildsDuring(() {
          for (var frame = 0; frame < 5; frame++) {
            paintFrame(scene, at);
          }
        }),
        0,
      );
    });

    test('moving one node builds geometry only for the edges touching it', () {
      // Hub 'h' with 40 dashed spokes plus 20 dotted spoke-to-spoke edges.
      // Moving spoke s3 changes h->s3 and s2->s3; the other 58 stay as built.
      final scene = edgeScene(
        links: [
          for (var i = 0; i < 40; i++)
            ('h', 's$i', ConstellationEdgeKind.tier2Path),
          for (var i = 0; i < 20; i++)
            ('s${2 * i}', 's${2 * i + 1}', ConstellationEdgeKind.ringStub),
        ],
      );
      final positions = <String, Offset>{
        'h': Offset.zero,
        for (var i = 0; i < 40; i++)
          's$i': Offset(80.0 * (i % 8) + 60, 60.0 * (i ~/ 8) + 90),
      };
      Offset at(NodeDetails n) => positions[personId(n)]!;
      paintFrame(scene, at);

      positions['s3'] = positions['s3']! + const Offset(25, 18);

      expect(_buildsDuring(() => paintFrame(scene, at)), 2);
      // Held still afterwards: nothing more to build.
      expect(_buildsDuring(() => paintFrame(scene, at)), 0);
    });

    test('a drag of one node over many frames builds only its own edges', () {
      final scene = edgeScene(
        links: [
          for (var i = 0; i < 40; i++)
            ('h', 's$i', ConstellationEdgeKind.tier2Path),
        ],
      );
      final positions = <String, Offset>{
        'h': Offset.zero,
        for (var i = 0; i < 40; i++)
          's$i': Offset(80.0 * (i % 8) + 60, 60.0 * (i ~/ 8) + 90),
      };
      Offset at(NodeDetails n) => positions[personId(n)]!;
      paintFrame(scene, at);

      const frames = 20;
      final builds = _buildsDuring(() {
        for (var f = 1; f <= frames; f++) {
          positions['s7'] = positions['s7']! + const Offset(3, 2);
          paintFrame(scene, at);
        }
      });

      // One edge touches s7: one rebuild per moved frame, never 40.
      expect(builds, frames);
    });

    test('moving the hub builds each of its edges once per frame', () {
      final scene = edgeScene(
        links: [
          for (var i = 0; i < 10; i++)
            ('h', 's$i', ConstellationEdgeKind.tier2Path),
          for (var i = 0; i < 6; i++)
            ('s${2 * i}', 's${2 * i + 1}', ConstellationEdgeKind.tier2Path),
        ],
      );
      final positions = <String, Offset>{
        'h': Offset.zero,
        for (var i = 0; i < 12; i++)
          's$i': Offset(70.0 * (i % 6) + 60, 80.0 * (i ~/ 6) + 90),
      };
      Offset at(NodeDetails n) => positions[personId(n)]!;
      paintFrame(scene, at);

      positions['h'] = const Offset(15, 10);

      expect(_buildsDuring(() => paintFrame(scene, at)), 10);
    });

    test('zooming out rebuilds dash geometry because dash lengths change', () {
      var scale = 1.0;
      final scene = edgeScene(
        links: [
          for (var i = 0; i < 8; i++)
            ('h', 's$i', ConstellationEdgeKind.tier2Path),
        ],
        cameraScale: () => scale,
      );
      Offset at(NodeDetails n) {
        final id = personId(n);
        return id == 'h'
            ? Offset.zero
            : Offset(60.0 * int.parse(id.substring(1)) + 80, 40);
      }

      paintFrame(scene, at);

      scale = 0.5;
      expect(_buildsDuring(() => paintFrame(scene, at)), 8);
      expect(_buildsDuring(() => paintFrame(scene, at)), 0);
    });

    test('dashed and dotted edges on the same endpoints each build once', () {
      final scene = edgeScene(
        links: [
          ('a', 'b', ConstellationEdgeKind.tier2Path),
          ('a', 'b', ConstellationEdgeKind.ringStub),
        ],
      );
      Offset at(NodeDetails n) =>
          personId(n) == 'a' ? Offset.zero : const Offset(400, 0);

      expect(_buildsDuring(() => paintFrame(scene, at)), 2);
      expect(_buildsDuring(() => paintFrame(scene, at)), 0);
    });

    test('solid edges never build dash geometry', () {
      final scene = edgeScene(
        links: [
          ('a', 'b', ConstellationEdgeKind.tier1Path),
          ('b', 'c', ConstellationEdgeKind.webInside),
          ('c', 'd', ConstellationEdgeKind.attachment),
        ],
      );
      var shift = 0.0;
      Offset at(NodeDetails n) =>
          Offset(100.0 * (personId(n).codeUnitAt(0) - 97) + shift, 0);

      expect(
        _buildsDuring(() {
          for (var f = 0; f < 4; f++) {
            shift += 7;
            paintFrame(scene, at);
          }
        }),
        0,
      );
    });
  });
}
