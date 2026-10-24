import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// The × remove affordance, whether drawn as a text glyph or a close icon.
final _removeControl = find.byWidgetPredicate(
  (widget) =>
      (widget is Text && widget.data == '×') ||
      (widget is Icon &&
          (widget.icon == Icons.close || widget.icon == Icons.clear)),
);

/// The ✦ mark, whether drawn as plain text, a rich text span or an icon.
final _sparkle = find.byWidgetPredicate(
  (widget) =>
      (widget is Text &&
          (widget.data ?? widget.textSpan?.toPlainText() ?? '').contains(
            '✦',
          )) ||
      (widget is RichText && widget.text.toPlainText().contains('✦')) ||
      (widget is Icon && widget.icon == Icons.auto_awesome),
);

/// A circular shape: circle box decoration, circle border or oval clip.
final _circleShape = find.byWidgetPredicate((widget) {
  if (widget is ClipOval || widget is CircleAvatar) return true;
  if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) {
      return decoration.shape == BoxShape.circle;
    }
    if (decoration is ShapeDecoration) return decoration.shape is CircleBorder;
  }
  return false;
});

final _chipBoundaryKey = GlobalKey();

Future<void> _pump(
  WidgetTester tester,
  Widget chip, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Center(
            child: RepaintBoundary(key: _chipBoundaryKey, child: chip),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

enum _Outline { none, dashed, solid }

/// Rasterises the chip (at 1 logical pixel per image pixel, so the result
/// does not depend on the test device pixel ratio) and classifies its
/// outline from the pixels of the straight middle of both the top and the
/// bottom edge: [_Outline.solid] when both edges have a row inked across the
/// whole run, [_Outline.dashed] when both edges carry ink but have gaps,
/// [_Outline.none] otherwise.
Future<_Outline> _classifyOutline(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_chipBoundaryKey),
  );
  late final Uint8List rgba;
  late final int width;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    width = image.width;
    rgba = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
  });
  final height = rgba.length ~/ 4 ~/ width;

  int pixel(int x, int y) {
    final i = (y * width + x) * 4;
    return (rgba[i] << 24) |
        (rgba[i + 1] << 16) |
        (rgba[i + 2] << 8) |
        rgba[i + 3];
  }

  bool differs(int a, int b) {
    for (var shift = 0; shift < 32; shift += 8) {
      if (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF) > 24 ||
          ((b >> shift) & 0xFF) - ((a >> shift) & 0xFF) > 24) {
        return true;
      }
    }
    return false;
  }

  // Background = most common colour of the whole chip (fill or transparent).
  final counts = <int, int>{};
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      counts.update(pixel(x, y), (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final background = counts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;

  final from = width ~/ 4;
  final to = width - width ~/ 4;
  _Outline classifyBand(Iterable<int> rows) {
    var anyInk = false;
    for (final y in rows) {
      var inked = 0;
      for (var x = from; x < to; x++) {
        if (differs(pixel(x, y), background)) inked++;
      }
      if (inked > 0) anyInk = true;
      if (inked == to - from) return _Outline.solid;
    }
    return anyInk ? _Outline.dashed : _Outline.none;
  }

  final rows = height < 8 ? height : 4;
  final top = classifyBand([for (var y = 0; y < rows; y++) y]);
  final bottom = classifyBand([
    for (var y = height - 1; y >= height - rows; y--) y,
  ]);
  return top == bottom ? top : _Outline.none;
}

void main() {
  group('PersonTagChip', () {
    testWidgets('shows the glyph circle and the tag name', (tester) async {
      await _pump(
        tester,
        const PersonTagChip(glyph: 'N', name: 'Neighbour', colorIndex: 2),
      );

      expect(find.text('Neighbour'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PersonTagChip),
          matching: find.byType(TagGlyph),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TagGlyph),
          matching: find.text('N'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('draws the glyph inside a square circular shape', (
      tester,
    ) async {
      await _pump(
        tester,
        const PersonTagChip(glyph: 'N', name: 'Neighbour', colorIndex: 2),
      );

      final circle = find.descendant(
        of: find.byType(TagGlyph),
        matching: _circleShape,
      );
      expect(circle, findsWidgets);
      final size = tester.getSize(circle.first);
      expect(size.width, size.height);
      expect(size.width, greaterThan(0));
    });

    testWidgets('has no × without onRemove', (tester) async {
      await _pump(
        tester,
        const PersonTagChip(glyph: 'N', name: 'Neighbour', colorIndex: 0),
      );

      expect(_removeControl, findsNothing);
    });

    testWidgets('shows a × that calls onRemove once when given onRemove', (
      tester,
    ) async {
      var removed = 0;
      await _pump(
        tester,
        PersonTagChip(
          glyph: 'N',
          name: 'Neighbour',
          colorIndex: 0,
          onRemove: () => removed++,
        ),
      );

      expect(_removeControl, findsOneWidget);
      await tester.tap(_removeControl);
      await tester.pump();
      expect(removed, 1);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('$brightness: fill and name use the swatch of its colour', (
        tester,
      ) async {
        await _pump(
          tester,
          const PersonTagChip(glyph: 'N', name: 'Neighbour', colorIndex: 5),
          theme: brightness == Brightness.light
              ? TenturaTheme.light()
              : TenturaTheme.dark(),
        );

        final swatch =
            (brightness == Brightness.light
                    ? TenturaTagColors.light
                    : TenturaTagColors.dark)
                .swatchFor(5);
        final fills = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(PersonTagChip),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.color);
        expect(fills, contains(swatch.container));
        expect(
          tester.widget<Text>(find.text('Neighbour')).style!.color,
          swatch.onContainer,
        );
      });
    }

    testWidgets('speaks "<name>, tag" once', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const PersonTagChip(glyph: 'N', name: 'Neighbour', colorIndex: 0),
      );

      expect(find.bySemanticsLabel('Neighbour, tag'), findsOneWidget);
      handle.dispose();
    });
  });

  group('AutoTagChip', () {
    for (final enabled in [true, false]) {
      testWidgets('enabled=$enabled: shows the sparkle mark and the name', (
        tester,
      ) async {
        await _pump(
          tester,
          AutoTagChip(name: 'Mutual contact', enabled: enabled),
        );

        expect(_sparkle, findsOneWidget);
        expect(find.text('Mutual contact'), findsOneWidget);
      });

      testWidgets('enabled=$enabled: never offers a ×', (tester) async {
        await _pump(
          tester,
          AutoTagChip(name: 'Mutual contact', enabled: enabled),
        );

        expect(_removeControl, findsNothing);
      });

      testWidgets('enabled=$enabled: speaks "<name>, automatic tag" once', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          AutoTagChip(name: 'Mutual contact', enabled: enabled),
        );

        expect(
          find.bySemanticsLabel('Mutual contact, automatic tag'),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    testWidgets('is outlined with a solid border while enabled', (
      tester,
    ) async {
      await _pump(tester, const AutoTagChip(name: 'Mutual contact'));

      expect(await _classifyOutline(tester), _Outline.solid);
    });

    testWidgets('keeps its outline but draws it dashed when disabled', (
      tester,
    ) async {
      await _pump(
        tester,
        const AutoTagChip(name: 'Mutual contact', enabled: false),
      );

      expect(await _classifyOutline(tester), _Outline.dashed);
    });
  });
}
