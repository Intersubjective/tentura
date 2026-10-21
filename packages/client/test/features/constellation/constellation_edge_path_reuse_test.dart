import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import 'fixtures/edge_stroke_recording.dart';

/// What the edge painter must keep drawing while it avoids rebuilding dash
/// geometry: every `paint` call still strokes its edge, in the right place.
void main() {
  group('constellation edge painting stays correct across frames', () {
    test('an unmoved dashed edge is stroked again on every frame', () {
      final scene = edgeScene(
        links: [('a', 'b', ConstellationEdgeKind.tier2Path)],
      );
      Offset at(NodeDetails n) =>
          personId(n) == 'a' ? Offset.zero : const Offset(300, 120);

      final first = paintFrame(scene, at);
      final second = paintFrame(scene, at);
      final third = paintFrame(scene, at);

      for (final frame in [first, second, third]) {
        expect(frame.opsPerEdge, [greaterThan(0)]);
      }
      // Whatever is drawn as a path shows the same dashes each frame.
      expect(first.canvas.pathDraws, hasLength(1));
      for (final frame in [second, third]) {
        for (final d in frame.canvas.pathDraws) {
          expect(
            pathSignature(d),
            pathSignature(first.canvas.pathDraws.single),
          );
          expect(d.color, first.canvas.pathDraws.single.color);
          expect(d.strokeWidth, first.canvas.pathDraws.single.strokeWidth);
        }
      }
    });

    test('every edge of an unmoved scene is stroked on every frame', () {
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

      final first = paintFrame(scene, at);
      final second = paintFrame(scene, at);

      expect(second.opsPerEdge, everyElement(greaterThan(0)));
      expect(second.opsPerEdge, hasLength(30));
      expect(
        second.canvas.pathDraws.map(pathSignature).toList(),
        first.canvas.pathDraws.map(pathSignature).toList(),
      );
    });

    test('a moved endpoint is drawn at its new position, not the old one', () {
      final scene = edgeScene(
        links: [('a', 'b', ConstellationEdgeKind.tier2Path)],
      );
      var bEnd = const Offset(300, 0);
      Offset at(NodeDetails n) => personId(n) == 'a' ? Offset.zero : bEnd;

      final first = paintFrame(scene, at).canvas.pathDraws.single;
      bEnd = const Offset(300, 200);
      final second = paintFrame(scene, at).canvas.pathDraws.single;

      expect(first.bounds.bottom, lessThan(10));
      expect(second.bounds.bottom, greaterThan(100));
      expect(second.totalLength, greaterThan(first.totalLength));
    });

    test('moving back and forth never draws a stale path', () {
      final scene = edgeScene(
        links: [('a', 'b', ConstellationEdgeKind.tier2Path)],
      );
      var bEnd = const Offset(300, 0);
      Offset at(NodeDetails n) => personId(n) == 'a' ? Offset.zero : bEnd;

      final lengths = <double>[];
      for (final y in [0.0, 150.0, 0.0, 250.0, 150.0]) {
        bEnd = Offset(300, y);
        lengths.add(
          paintFrame(scene, at).canvas.pathDraws.single.totalLength,
        );
      }

      expect(lengths[0], closeTo(lengths[2], 0.001));
      expect(lengths[1], closeTo(lengths[4], 0.001));
      expect(lengths[3], greaterThan(lengths[1]));
      expect(lengths[1], greaterThan(lengths[0]));
    });

    test('zooming out changes the dash pattern of an edge drawn before', () {
      var scale = 1.0;
      final scene = edgeScene(
        links: [('a', 'b', ConstellationEdgeKind.tier2Path)],
        cameraScale: () => scale,
      );
      Offset at(NodeDetails n) =>
          personId(n) == 'a' ? Offset.zero : const Offset(400, 0);

      final atOne = paintFrame(scene, at).canvas.pathDraws.single;
      scale = 0.5;
      final atHalf = paintFrame(scene, at).canvas.pathDraws.single;

      // Below scale 1 dash and gap are doubled: fewer, wider dashes.
      expect(atHalf.contours, lessThan(atOne.contours));
      expect(atHalf.strokeWidth, atOne.strokeWidth * 2);
    });

    test('edges with the same endpoints but another kind keep their own '
        'dash pattern on every frame', () {
      final dashed = edgeScene(
        links: [('a', 'b', ConstellationEdgeKind.tier2Path)],
      );
      final dotted = edgeScene(
        links: [('a', 'b', ConstellationEdgeKind.ringStub)],
      );
      Offset at(NodeDetails n) =>
          personId(n) == 'a' ? Offset.zero : const Offset(400, 0);

      final dashes = paintFrame(dashed, at).canvas.pathDraws.single;
      final dots = paintFrame(dotted, at).canvas.pathDraws.single;
      expect(dots.contours, greaterThan(dashes.contours));

      for (var frame = 0; frame < 3; frame++) {
        final dashesAgain = paintFrame(dashed, at);
        final dotsAgain = paintFrame(dotted, at);
        expect(dashesAgain.opsPerEdge, [greaterThan(0)]);
        expect(dotsAgain.opsPerEdge, [greaterThan(0)]);
        for (final d in dashesAgain.canvas.pathDraws) {
          expect(pathSignature(d), pathSignature(dashes));
        }
        for (final d in dotsAgain.canvas.pathDraws) {
          expect(pathSignature(d), pathSignature(dots));
        }
      }
    });

    test('solid edges are one drawLine on every frame and never a path', () {
      final scene = edgeScene(
        links: [
          ('a', 'b', ConstellationEdgeKind.tier1Path),
          ('b', 'c', ConstellationEdgeKind.webInside),
        ],
      );
      Offset at(NodeDetails n) => switch (personId(n)) {
        'a' => Offset.zero,
        'b' => const Offset(200, 0),
        _ => const Offset(400, 100),
      };

      for (var frame = 0; frame < 3; frame++) {
        final result = paintFrame(scene, at);
        expect(result.canvas.pathDraws, isEmpty, reason: 'frame $frame');
        expect(result.canvas.lineDraws, 2, reason: 'frame $frame');
        expect(result.opsPerEdge, [1, 1], reason: 'frame $frame');
      }
    });
  });
}
