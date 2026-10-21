@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';

import 'fixtures/constellation_reference_fixture.dart';

/// Moves every node to a fixed grid shifted by [shift].
final class _ShiftedGridAlgorithm implements SceneLayoutAlgorithm {
  const _ShiftedGridAlgorithm(this.shift);

  final double shift;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    var index = 0;
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(
            x: 120.0 + shift + 70 * index,
            y: 90.0 + shift + 45 * index++,
          ),
      },
      isTerminal: true,
    );
  }
}

/// Counts the [TextPainter] layouts run on behalf of chip measurement: a
/// text layout asks its scaler for the scaled size, so the call stack tells a
/// real measurement from a render-object layout or a label plate measurement.
final class _PainterCountingTextScaler extends TextScaler {
  _PainterCountingTextScaler({this.factor = 1});

  final double factor;
  int painterLayouts = 0;

  @override
  double scale(double fontSize) {
    final stack = StackTrace.current.toString();
    if (stack.contains('TextPainter') &&
        !stack.contains('RenderParagraph') &&
        !stack.contains('measureConstellationLabelPlate')) {
      painterLayouts++;
    }
    return fontSize * factor;
  }

  @override
  double get textScaleFactor => factor;

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = 1e9}) =>
      this;
}

/// Mounts a single [Builder] under [theme] and [scaler]; re-pumping with other
/// values rebuilds the same tree, so a cache survives between calls.
Future<Size> _measureChip(
  WidgetTester tester, {
  required ThemeData theme,
  required TextScaler scaler,
  String label = '+12 more',
}) async {
  late Size size;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: Builder(
          builder: (c) {
            size = constellationOverflowChipSize(c, label);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  // Theme changes animate; settle so the new style is the one measured.
  await tester.pumpAndSettle();
  return size;
}

ThemeData _themeWithLabelLargeSize(double fontSize) {
  final base = TenturaTheme.light();
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      labelLarge: base.textTheme.labelLarge!.copyWith(fontSize: fontSize),
    ),
  );
}

bool _isLabelKey(Widget w) {
  final key = w.key;
  return key is ValueKey<String> && key.value.startsWith('constellation.label.');
}

void main() {
  group('Constellation overlay during a layout transition', () {
    testWidgets('builds label plates and chips a bounded number of times '
        'across the whole transition, not once per frame', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      final scaler = _PainterCountingTextScaler();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        textScaler: scaler,
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();

      final labelCount = holder.frame!.labels.length;
      final chipCount = holder.frame!.chips.length;
      expect(labelCount, greaterThan(3));
      expect(chipCount, greaterThan(0), reason: 'fixture must mount chips');
      final labelKeysBefore = holder.frame!.labels.keys.toSet();
      final controller = cubit.graphController;
      double chipDistance(String authorId, Rect chip) =>
          (chip.center -
                  controller.sceneToViewportLocal(
                    controller.getPositionForId('fp:$authorId'),
                  ))
              .distance;
      final chipDistancesBefore = {
        for (final e in holder.frame!.chips.entries)
          e.key: chipDistance(e.key, e.value),
      };
      final chipCentresBefore = {
        for (final e in holder.frame!.chips.entries) e.key: e.value.center,
      };
      final maxChipDistance = chipDistancesBefore.values.reduce(
        (a, b) => a > b ? a : b,
      );
      final centresBefore = {
        for (final e in holder.frame!.labels.entries) e.key: e.value.center,
      };

      var plateBuilds = 0;
      var plateMounts = 0;
      var chipBuilds = 0;
      var overlayBuilderBuilds = 0;
      final overlay = tester.element(find.byType(ConstellationViewportOverlay));
      final previousCallback = debugOnRebuildDirtyWidget;
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousCallback?.call(element, builtOnce);
        final type = element.widget.runtimeType.toString();
        if (_isLabelKey(element.widget)) {
          plateBuilds++;
          if (!builtOnce) plateMounts++;
        }
        if (element.widget is ConstellationOverflowGroup) chipBuilds++;
        if (type == 'ListenableBuilder') {
          var below = false;
          element.visitAncestorElements((a) {
            if (identical(a, overlay)) below = true;
            return !below;
          });
          if (below) overlayBuilderBuilds++;
        }
      };

      scaler.painterLayouts = 0;
      cubit.requestConstellationLayoutForTest(
        algorithm: const _ShiftedGridAlgorithm(60),
      );
      tester.binding.scheduleFrame();
      await tester.pump();
      final layersBefore = find
          .descendant(
            of: find.byType(ConstellationViewportOverlay),
            matching: find.byType(RepaintBoundary),
          )
          .evaluate()
          .length;
      var maxLayerDrift = 0;
      var framesWithMotion = 0;
      var previous = holder.frame!.labels.values.map((r) => r.center).toList();
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = holder.frame!.labels.values.map((r) => r.center).toList();
        if (now.length == previous.length) {
          for (var j = 0; j < now.length; j++) {
            if (now[j] != previous[j]) {
              framesWithMotion++;
              break;
            }
          }
        }
        previous = now;
        final layers = find
            .descendant(
              of: find.byType(ConstellationViewportOverlay),
              matching: find.byType(RepaintBoundary),
            )
            .evaluate()
            .length;
        maxLayerDrift = maxLayerDrift > (layers - layersBefore).abs()
            ? maxLayerDrift
            : (layers - layersBefore).abs();
        expect(
          holder.frame!.chips.keys.toSet(),
          chipCentresBefore.keys.toSet(),
          reason: 'chips must stay present on every transition frame',
        );
        for (final e in holder.frame!.chips.entries) {
          expect(
            chipDistance(e.key, e.value),
            lessThanOrEqualTo(1.5 * maxChipDistance + 50),
            reason: 'chip ${e.key} must stay attached to its author node',
          );
        }
      }
      await tester.pumpAndSettle();

      // Positive control: the transition really ran for many frames.
      expect(
        framesWithMotion,
        greaterThan(5),
        reason: 'labels must keep following the nodes through the transition',
      );
      expect(
        overlayBuilderBuilds,
        lessThanOrEqualTo(4),
        reason:
            'transition frames must not each rebuild the overlay builder '
            '(structure change at start, at most a few at the end)',
      );
      expect(
        plateBuilds,
        lessThanOrEqualTo(2 * labelCount),
        reason: 'each label plate may be rebuilt for the new layout only a '
            'couple of times, not on every one of ~22 transition frames',
      );
      expect(
        plateMounts,
        lessThanOrEqualTo(labelCount),
        reason: 'label plates must not be torn down and mounted afresh on '
            'transition frames',
      );
      expect(
        maxLayerDrift,
        0,
        reason: 'the overlay must keep the same number of repaint layers '
            'through the transition',
      );
      expect(
        chipBuilds,
        lessThanOrEqualTo(2 * chipCount),
        reason: 'overflow chips must not be rebuilt every transition frame',
      );

      expect(
        scaler.painterLayouts,
        lessThanOrEqualTo(2 * chipCount),
        reason:
            'chip text must not be laid out afresh on every transition '
            'frame',
      );
      expect(
        holder.frame!.chips.entries.any(
          (e) => (e.value.center - chipCentresBefore[e.key]!).distance > 5,
        ),
        isTrue,
        reason: 'chips must end up beside their moved author nodes',
      );

      // Visible behaviour is unchanged: same labels, and they ended up
      // where the moved nodes are.
      expect(holder.frame!.labels.keys.toSet(), labelKeysBefore);
      final moved = holder.frame!.labels.entries.where(
        (e) => (e.value.center - centresBefore[e.key]!).distance > 5,
      );
      expect(moved, isNotEmpty);
    });
  });

  group('Overflow chip size measurement', () {
    testWidgets('does not lay text out again for a label already measured at '
        'the same style and text scale', (tester) async {
      final scaler = _PainterCountingTextScaler();
      final theme = TenturaTheme.light();
      final first = await _measureChip(tester, theme: theme, scaler: scaler);
      expect(
        scaler.painterLayouts,
        greaterThan(0),
        reason: 'first measurement must lay the label text out',
      );

      scaler.painterLayouts = 0;
      final context = tester.element(find.byType(SizedBox).first);
      for (var i = 0; i < 20; i++) {
        expect(constellationOverflowChipSize(context, '+12 more'), first);
      }
      expect(
        scaler.painterLayouts,
        0,
        reason: 'repeated measurement of the same label must hit a cache',
      );

      final other = constellationOverflowChipSize(context, '+1234567 more');
      expect(
        scaler.painterLayouts,
        greaterThan(0),
        reason: 'a new label text must be measured',
      );
      expect(other.width, greaterThan(first.width));
    });

    testWidgets('re-measures after the text scale changes and again when it '
        'changes back', (tester) async {
      final theme = TenturaTheme.light();
      final one = _PainterCountingTextScaler();
      final two = _PainterCountingTextScaler(factor: 2);
      final atOne = await _measureChip(tester, theme: theme, scaler: one);
      expect(one.painterLayouts, greaterThan(0));

      final atTwo = await _measureChip(tester, theme: theme, scaler: two);
      expect(
        two.painterLayouts,
        greaterThan(0),
        reason: 'a cached size from another text scale must not be reused',
      );
      expect(atTwo.width, greaterThan(atOne.width));

      final backAtOne = await _measureChip(tester, theme: theme, scaler: one);
      expect(backAtOne, atOne);
    });

    testWidgets('re-measures after the label text style changes', (
      tester,
    ) async {
      final scaler = _PainterCountingTextScaler();
      final small = await _measureChip(
        tester,
        theme: _themeWithLabelLargeSize(12),
        scaler: scaler,
      );
      expect(scaler.painterLayouts, greaterThan(0));

      scaler.painterLayouts = 0;
      final large = await _measureChip(
        tester,
        theme: _themeWithLabelLargeSize(30),
        scaler: scaler,
      );
      expect(
        scaler.painterLayouts,
        greaterThan(0),
        reason: 'a cached size from another text style must not be reused',
      );
      expect(large.width, greaterThan(small.width));
    });
  });
}
