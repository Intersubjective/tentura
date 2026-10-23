import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';

/// Paint state captured at the moment of the draw call, so a Paint that the
/// painter reuses (and mutates between calls) is still checked as drawn.
typedef _PaintSnapshot = ({
  Paint paint,
  Color color,
  PaintingStyle style,
  double strokeWidth,
  StrokeCap strokeCap,
});

/// One recorded canvas draw operation.
typedef _DrawOp = ({
  String name,
  List<Object?> args,
  List<_PaintSnapshot> paints,
});

/// Canvas that only records `draw*` calls (the Skia/CanvasKit conversion cost
/// the edge painter pays per call), so the tests count work, not wall-clock.
class _RecordingCanvas implements Canvas {
  final ops = <_DrawOp>[];

  Iterable<_DrawOp> named(String name) => ops.where((o) => o.name == name);

  Iterable<_DrawOp> get strokeOps => ops.where((o) => o.name != 'drawCircle');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll(
      RegExp(r'Symbol\("|"\)'),
      '',
    );
    if (name.startsWith('draw')) {
      ops.add((
        name: name,
        args: invocation.positionalArguments,
        paints: [
          for (final p in invocation.positionalArguments.whereType<Paint>())
            (
              paint: p,
              color: p.color,
              style: p.style,
              strokeWidth: p.strokeWidth,
              strokeCap: p.strokeCap,
            ),
        ],
      ));
    }
    return null;
  }
}

Paint _strokePaint({double width = 2, Color color = const Color(0xFF336699)}) =>
    Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

_RecordingCanvas _stroke({
  required double length,
  required double dash,
  required double gap,
  bool endDots = false,
  Paint? paint,
}) {
  final canvas = _RecordingCanvas();
  paintConstellationEdgeStroke(
    canvas,
    Offset.zero,
    Offset(length, 0),
    paint ?? _strokePaint(),
    dash: dash,
    gap: gap,
    endDots: endDots,
  );
  return canvas;
}

Future<ui.Image> _render(
  void Function(Canvas canvas) draw, {
  required int width,
  required int height,
}) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  return recorder.endRecording().toImage(width, height);
}

void main() {
  group('dashed constellation edge stroke draw calls', () {
    test('a long dashed edge is issued as at most one draw call', () {
      final canvas = _stroke(length: 2000, dash: 6, gap: 4);

      expect(canvas.strokeOps.length, lessThanOrEqualTo(1));
      expect(canvas.named('drawLine'), isEmpty);
    });

    test('draw-call count does not grow with the edge length', () {
      final shortEdge = _stroke(length: 60, dash: 2, gap: 4);
      final longEdge = _stroke(length: 3000, dash: 2, gap: 4);

      expect(longEdge.ops.length, shortEdge.ops.length);
    });

    test('a solid edge is still a single draw call', () {
      final canvas = _stroke(length: 500, dash: 0, gap: 0);

      expect(canvas.ops, hasLength(1));
    });

    test('a zero-length dashed edge draws no strokes', () {
      final canvas = _stroke(length: 0, dash: 6, gap: 4);

      expect(canvas.strokeOps, isEmpty);
    });
  });

  group('constellation edge end dots', () {
    test('both ends get a dot at the edge endpoints', () {
      final canvas = _stroke(length: 80, dash: 0, gap: 0, endDots: true);

      final circles = canvas.named('drawCircle').toList();
      expect(circles, hasLength(2));
      expect(circles.map((c) => c.args[0]), [Offset.zero, const Offset(80, 0)]);
      expect(circles.every((c) => c.args[1] == 2 * 1.6), isTrue);
    });

    test(
      'dashed edge with end dots stays within one stroke call plus the dots',
      () {
        final canvas = _stroke(length: 2000, dash: 2, gap: 4, endDots: true);

        expect(canvas.strokeOps.length, lessThanOrEqualTo(1));
        expect(canvas.named('drawCircle'), hasLength(2));
      },
    );

    test('end dots are filled with the edge color', () {
      for (final color in const [Color(0xFF112233), Color(0x80445566)]) {
        final canvas = _stroke(
          length: 80,
          dash: 6,
          gap: 4,
          endDots: true,
          paint: _strokePaint(color: color),
        );

        for (final circle in canvas.named('drawCircle')) {
          expect(circle.paints.single.color.toARGB32(), color.toARGB32());
          expect(circle.paints.single.style, PaintingStyle.fill);
        }
      }
    });

    test('dot paints are pooled across many edges instead of one per edge', () {
      const edges = 40;
      final distinctDotPaints = <Paint>{};
      for (var i = 0; i < edges; i++) {
        final color = i.isEven
            ? const Color(0xFF112233)
            : const Color(0xFF445566);
        final canvas = _stroke(
          length: 80,
          dash: 0,
          gap: 0,
          endDots: true,
          paint: _strokePaint(color: color),
        );
        for (final circle in canvas.named('drawCircle')) {
          distinctDotPaints.add(circle.paints.single.paint);
          // A reused Paint must still carry this edge's own color when drawn.
          expect(circle.paints.single.color.toARGB32(), color.toARGB32());
        }
      }

      expect(
        distinctDotPaints.length,
        lessThanOrEqualTo(2),
        reason: '$edges edges with end dots must not allocate a Paint each',
      );
    });
  });

  group('constellation edge stroke rendering', () {
    const width = 200;
    const height = 64;

    // Reference: the original rendering, one drawLine per dash plus filled
    // end dots drawn after the stroke.
    void referenceStroke(
      Canvas canvas,
      Offset a,
      Offset b,
      Paint paint,
      double dash,
      double gap,
      bool endDots,
    ) {
      final delta = b - a;
      final length = delta.distance;
      if (dash <= 0) {
        canvas.drawLine(a, b, paint);
      } else {
        final direction = delta / length;
        var travelled = 0.0;
        while (travelled < length) {
          final end = travelled + dash < length ? travelled + dash : length;
          canvas.drawLine(
            a + direction * travelled,
            a + direction * end,
            paint,
          );
          travelled += dash + gap;
        }
      }
      if (endDots) {
        final dotPaint = Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas
          ..drawCircle(a, paint.strokeWidth * 1.6, dotPaint)
          ..drawCircle(b, paint.strokeWidth * 1.6, dotPaint);
      }
    }

    // Premultiplied RGBA of pixel [i]; Image.toByteData already yields
    // premultiplied channels, so transparent pixels compare equal whatever
    // their hidden color would be.
    List<int> premultiplied(ByteData bytes, int i) => [
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
      bytes.getUint8(i + 3),
    ];

    final cases =
        <
          ({
            String name,
            double dash,
            double gap,
            double width,
            bool endDots,
            Color color,
            Offset a,
            Offset b,
          })
        >[
          (
            name: 'dashed 6/4',
            dash: 6,
            gap: 4,
            width: 2,
            endDots: false,
            color: const Color(0xFF336699),
            a: const Offset(8, 12),
            b: const Offset(192, 52),
          ),
          (
            name: 'dotted 2/4',
            dash: 2,
            gap: 4,
            width: 1.5,
            endDots: false,
            color: const Color(0xFFCC5522),
            a: const Offset(8, 12),
            b: const Offset(192, 52),
          ),
          (
            name: 'dashed 6/4 with translucent color',
            dash: 6,
            gap: 4,
            width: 2,
            endDots: false,
            color: const Color(0x80336699),
            a: const Offset(10, 50),
            b: const Offset(190, 14),
          ),
          (
            name: 'solid',
            dash: 0,
            gap: 0,
            width: 2,
            endDots: false,
            color: const Color(0xFF336699),
            a: const Offset(8, 12),
            b: const Offset(192, 52),
          ),
          (
            name: 'solid with end dots',
            dash: 0,
            gap: 0,
            width: 1.5,
            endDots: true,
            color: const Color(0xFF229955),
            a: const Offset(12, 32),
            b: const Offset(188, 32),
          ),
          (
            name: 'dashed 6/4 with end dots',
            dash: 6,
            gap: 4,
            width: 1.5,
            endDots: true,
            color: const Color(0xFF229955),
            a: const Offset(12, 20),
            b: const Offset(187, 44),
          ),
        ];

    for (final c in cases) {
      testWidgets('pixels match per-dash drawing for ${c.name}', (
        tester,
      ) async {
        final paint = _strokePaint(width: c.width, color: c.color);

        final expected = await tester.runAsync(
          () => _render(
            (canvas) => referenceStroke(
              canvas,
              c.a,
              c.b,
              paint,
              c.dash,
              c.gap,
              c.endDots,
            ),
            width: width,
            height: height,
          ),
        );
        final actual = await tester.runAsync(
          () => _render(
            (canvas) => paintConstellationEdgeStroke(
              canvas,
              c.a,
              c.b,
              paint,
              dash: c.dash,
              gap: c.gap,
              endDots: c.endDots,
            ),
            width: width,
            height: height,
          ),
        );

        final expectedBytes = (await tester.runAsync(
          () => expected!.toByteData(),
        ))!;
        final actualBytes = (await tester.runAsync(
          () => actual!.toByteData(),
        ))!;

        var inked = 0;
        var worstDiff = 0;
        var worstAt = '';
        var stray = 0;
        for (var i = 0; i < expectedBytes.lengthInBytes; i += 4) {
          final e = premultiplied(expectedBytes, i);
          final a = premultiplied(actualBytes, i);
          if (e[3] > 0 || a[3] > 0) {
            inked++;
          }
          if (e[3] == 0 && a[3] > 32) {
            stray++;
          }
          for (var k = 0; k < 4; k++) {
            final d = (e[k] - a[k]).abs();
            if (d > worstDiff) {
              worstDiff = d;
              worstAt = 'pixel (${i ~/ 4 % width}, ${i ~/ 4 ~/ width})';
            }
          }
        }
        expect(inked, greaterThan(0));
        expect(
          stray,
          0,
          reason: 'implementation drew ink outside the reference',
        );
        // No aggregate allowance: a single wrong dash, cap or dot pixel fails.
        expect(
          worstDiff,
          lessThanOrEqualTo(24),
          reason: 'largest premultiplied channel difference at $worstAt',
        );
      });
    }
  });

  group('constellation edge stroke pixel geometry', () {
    const width = 140;
    const height = 64;
    const color = Color(0xFF336699);

    Future<ByteData> renderEdge(
      WidgetTester tester, {
      required Offset a,
      required Offset b,
      required double dash,
      required double gap,
      required double strokeWidth,
      required bool endDots,
      bool twin = false,
    }) async {
      final image = await tester.runAsync(
        () => _render(
          (canvas) => paintConstellationEdgeStroke(
            canvas,
            a,
            b,
            _strokePaint(width: strokeWidth),
            dash: dash,
            gap: gap,
            endDots: endDots,
            twin: twin,
          ),
          width: width,
          height: height,
        ),
      );
      return (await tester.runAsync(() => image!.toByteData()))!;
    }

    int alphaAt(ByteData bytes, int x, int y) =>
        bytes.getUint8((y * width + x) * 4 + 3);

    // Opaque pixels must carry exactly the edge colour.
    void expectColor(ByteData bytes, int x, int y) {
      final i = (y * width + x) * 4;
      final argb = color.toARGB32();
      for (final (offset, shift) in [(0, 16), (1, 8), (2, 0)]) {
        expect(
          bytes.getUint8(i + offset),
          closeTo((argb >> shift) & 0xFF, 2),
          reason: 'channel $offset at ($x, $y)',
        );
      }
    }

    testWidgets('dashes sit at the dash period with clear gaps', (
      tester,
    ) async {
      // Horizontal edge y = 32 (rows 31 and 32 carry the 2 px stroke),
      // dashes cover [10, 16], [20, 26], ... ; round caps reach 1 px further.
      final bytes = await renderEdge(
        tester,
        a: const Offset(10, 32),
        b: const Offset(110, 32),
        dash: 6,
        gap: 4,
        strokeWidth: 2,
        endDots: false,
      );

      for (var k = 0; k < 10; k++) {
        final start = 10 + 10 * k;
        for (var x = start + 1; x <= start + 4; x++) {
          for (final y in [31, 32]) {
            expect(
              alphaAt(bytes, x, y),
              greaterThanOrEqualTo(250),
              reason: 'dash $k core at ($x, $y)',
            );
            expectColor(bytes, x, y);
          }
        }
        // Two fully clear pixel columns in every gap.
        for (final x in [start + 7, start + 8]) {
          for (final y in [30, 31, 32, 33]) {
            expect(alphaAt(bytes, x, y), 0, reason: 'gap $k at ($x, $y)');
          }
        }
        // The stroke is exactly two rows tall.
        for (final y in [29, 30, 33, 34]) {
          expect(
            alphaAt(bytes, start + 3, y),
            0,
            reason: 'row $y beside dash $k',
          );
        }
      }
    });

    testWidgets('dash ends are round-capped, not butt', (tester) async {
      final bytes = await renderEdge(
        tester,
        a: const Offset(10, 32),
        b: const Offset(110, 32),
        dash: 6,
        gap: 4,
        strokeWidth: 2,
        endDots: false,
      );

      // A round cap of radius 1 around (10, 32) covers most of pixel (9, 31)
      // and (9, 32); a butt cap would leave them empty. Same at the dash end.
      for (final (x, y) in [(9, 31), (9, 32), (16, 31), (16, 32)]) {
        expect(
          alphaAt(bytes, x, y),
          inInclusiveRange(150, 230),
          reason: 'cap pixel ($x, $y)',
        );
      }
      // ...and no further than the cap radius.
      for (final x in [8, 17]) {
        expect(alphaAt(bytes, x, 31), 0, reason: 'beyond the cap at x=$x');
      }
    });

    testWidgets('a trailing partial dash is clipped to the edge end', (
      tester,
    ) async {
      // Dashes start at 10, 20, ..., 100; the last would be [100, 106] but the
      // edge ends at 104, so it is [100, 104] plus a round cap.
      final bytes = await renderEdge(
        tester,
        a: const Offset(10, 32),
        b: const Offset(104, 32),
        dash: 6,
        gap: 4,
        strokeWidth: 2,
        endDots: false,
      );

      for (var x = 101; x <= 102; x++) {
        expect(alphaAt(bytes, x, 31), greaterThanOrEqualTo(250));
      }
      expect(alphaAt(bytes, 104, 31), inInclusiveRange(150, 230));
      for (final x in [106, 107, 108]) {
        expect(alphaAt(bytes, x, 31), 0, reason: 'past the edge end at x=$x');
      }
    });

    testWidgets('a solid edge is continuous with no gaps', (tester) async {
      final bytes = await renderEdge(
        tester,
        a: const Offset(10, 32),
        b: const Offset(110, 32),
        dash: 0,
        gap: 0,
        strokeWidth: 2,
        endDots: false,
      );

      for (var x = 11; x <= 109; x++) {
        expect(
          alphaAt(bytes, x, 31),
          greaterThanOrEqualTo(250),
          reason: 'x=$x',
        );
        expect(
          alphaAt(bytes, x, 32),
          greaterThanOrEqualTo(250),
          reason: 'x=$x',
        );
      }
    });

    testWidgets('end dots are filled discs of 1.6 times the stroke width', (
      tester,
    ) async {
      // Stroke width 2 -> dot radius 3.2, centred on both endpoints; the dot
      // is wider than the stroke so it shows above and below it.
      final bytes = await renderEdge(
        tester,
        a: const Offset(20, 32),
        b: const Offset(120, 32),
        dash: 0,
        gap: 0,
        strokeWidth: 2,
        endDots: true,
      );

      for (final cx in [20, 120]) {
        // Solid disc centre and well inside the radius, above the stroke rows.
        for (final (dx, dy) in [(0, -2), (-1, -2), (0, 2), (-2, -1)]) {
          final x = cx + dx;
          final y = 31 + dy;
          expect(
            alphaAt(bytes, x, y),
            greaterThanOrEqualTo(250),
            reason: 'inside dot at ($x, $y)',
          );
          expectColor(bytes, x, y);
        }
        // Outside the radius (3.2) on every side.
        for (final (dx, dy) in [(0, -5), (0, 5), (-5, -4), (5, -4), (0, -6)]) {
          final x = cx + dx;
          final y = 31 + dy;
          if (cx == 20 && dx > 0 || cx == 120 && dx < 0) {
            continue; // that side is covered by the stroke itself
          }
          expect(alphaAt(bytes, x, y), 0, reason: 'outside dot at ($x, $y)');
        }
      }
      // No dot between the endpoints.
      expect(alphaAt(bytes, 70, 29), 0);
      expect(alphaAt(bytes, 70, 34), 0);
    });

    testWidgets('dashed edge with end dots keeps dots and dashes apart', (
      tester,
    ) async {
      final bytes = await renderEdge(
        tester,
        a: const Offset(20, 32),
        b: const Offset(120, 32),
        dash: 6,
        gap: 4,
        strokeWidth: 2,
        endDots: true,
      );

      // Both end dots are drawn even though the dashes only touch them.
      for (final x in [20, 120]) {
        expect(
          alphaAt(bytes, x, 29),
          greaterThanOrEqualTo(250),
          reason: 'dot at $x',
        );
      }
      // Mid-edge the dash pattern is intact: dash core, then clear gap.
      expect(alphaAt(bytes, 51, 31), greaterThanOrEqualTo(250));
      expect(alphaAt(bytes, 57, 31), 0);
      expect(alphaAt(bytes, 58, 31), 0);
      expect(alphaAt(bytes, 51, 28), 0);
    });

    testWidgets('a twin edge is two strokes with clear space between', (
      tester,
    ) async {
      // Horizontal edge y = 32, 2 px strokes 1.5 widths (3 px) to either
      // side: rows 28-29 and 34-35 carry ink, the middle stays clear.
      final bytes = await renderEdge(
        tester,
        a: const Offset(20, 32),
        b: const Offset(120, 32),
        dash: 0,
        gap: 0,
        strokeWidth: 2,
        endDots: false,
        twin: true,
      );

      for (final y in [28, 29, 34, 35]) {
        expect(alphaAt(bytes, 70, y), greaterThanOrEqualTo(250), reason: '$y');
        expectColor(bytes, 70, y);
      }
      for (final y in [31, 32]) {
        expect(alphaAt(bytes, 70, y), 0, reason: 'row $y between the strokes');
      }
    });
  });
}
