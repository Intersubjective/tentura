@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';
import 'fixtures/synthetic_field.dart';

// Run with test/support/browser/run_overlapping_dot_touch.mjs. Native CDP
// input goes to this mounted Flutter widget's real web engine and DOM.
// No copied semantics DOM, guessed Chrome scoring or widget-tap fallback.
// B is 4.27 px below/right of C, inside C's expanded touch target; E is 7 px
// below C. The last person is isolated to protect the 16 px touch reach.
const _offsets = <String, Offset>{
  'p0': Offset(4, 1.5), // B, Dave
  'p1': Offset.zero, // C, Frank, painted above B
  'p2': Offset(0, 7), // E, Masha
  'p3': Offset(-9, -7),
  'p4': Offset(10, -9),
  'p5': Offset(-12, 8),
  'p6': Offset(13, 9),
  'p7': Offset(2, -16),
  'p8': Offset(100, 0), // lone person
};

ConstellationField _field() {
  final base = syntheticConstellationField(size: _offsets.length);
  final revision = base.anchorProjection!.revision;
  return base.copyWith(
    requests: const [],
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: [
        for (final entry in _offsets.entries)
          ConstellationAnchor(
            target: ConstellationAnchorTarget.person(entry.key),
            position: ConstellationAnchorPosition(
              xUnits: -2 + entry.value.dx / 25.5,
              yUnits: 2 + entry.value.dy / 25.5,
              coordinateSpaceVersion: 1,
            ),
            revision: revision,
            placedAt: base.loadedAt,
          ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

const _broker = String.fromEnvironment('NATIVE_TOUCH_BROKER');

Future<void> _nativeInput(Map<String, Object> input) async {
  final response = await web.window
      .fetch(
        _broker.toJS,
        web.RequestInit(method: 'POST', body: jsonEncode(input).toJS),
      )
      .toDart;
  if (!response.ok) {
    throw StateError('Native input broker: ${await response.text().toDart}');
  }
  // Let the click settle and the engine's 500 ms gesture-mode debounce
  // expire, so each fresh press can exercise the semantics path again.
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

Offset _browserPoint(Offset local) {
  var result = local;
  var window = web.window;
  while (window.frameElement != null) {
    final frame = window.frameElement!.getBoundingClientRect();
    result += Offset(frame.left, frame.top);
    window = window.parent!;
  }
  return result;
}

void main() {
  testWidgets(
    'minimum-zoom native touch and mouse select hidden and nearby dot centres '
    'and the nearer dot between centres while retaining lone-dot reach',
    (tester) async {
      expect(
        _broker,
        isNotEmpty,
        reason: 'run test/support/browser/run_overlapping_dot_touch.mjs',
      );
      // The web test launcher also fakes the engine's screen (800x600 at
      // DPR 3). Native browser input needs the real screen and DPR instead.
      final view = ui.PlatformDispatcher.instance.implicitView!;
      final oldPhysicalSize = view.physicalSize;
      final oldDpr = view.devicePixelRatio;
      // The SDK exposes this test override only on its legacy window.
      // ignore: deprecated_member_use
      ui.window.debugPhysicalSizeOverride = null;
      ui_web.debugOverrideDevicePixelRatio(null);
      addTearDown(() {
        // Restore the same SDK test override on its legacy window.
        // ignore: deprecated_member_use
        ui.window.debugPhysicalSizeOverride = oldPhysicalSize;
        ui_web.debugOverrideDevicePixelRatio(oldDpr);
      });
      await tester.runAsync(() => _nativeInput({'configure': true}));
      // Flutter's default widget-test environment intentionally suppresses
      // the real semantics DOM. Enable the engine's production semantics
      // updates while retaining every other test-environment setting.
      final environment = ui_web.TestEnvironment.instance;
      ui_web.TestEnvironment.setUp(
        ui_web.TestEnvironment(
          ignorePlatformMessages: environment.ignorePlatformMessages,
          forceTestFonts: environment.forceTestFonts,
          disableFontFallbacks: environment.disableFontFallbacks,
          defaultToTestUrlStrategy: environment.defaultToTestUrlStrategy,
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        final cubit = await loadReferenceCubit(field: _field());
        addTearDown(cubit.close);
        final holder = ConstellationPresentationFrameHolder();
        await pumpConstellationBody(
          tester,
          cubit,
          size: const Size(375, 667),
          locale: const Locale('en'),
          presentationFrameHolder: holder,
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 80; i++) {
          cubit.graphController.zoomBy(0.9);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final frame = holder.frame!;
        expect(frame.detail, ConstellationDetailLevel.overview);
        for (final entry in _offsets.entries.where(
          (entry) => entry.key != 'p8',
        )) {
          expect(
            (frame.bodies['fp:${entry.key}']!.center -
                    frame.bodies['fp:p1']!.center -
                    entry.value)
                .distance,
            lessThan(0.5),
            reason: '${entry.key} retains its screen geometry',
          );
        }
        final b = frame.bodies['fp:p0']!;
        final c = frame.bodies['fp:p1']!;
        expect((b.center - c.center).distance, inInclusiveRange(4, 7));
        expect(
          (b.center - c.center).distance,
          lessThan((b.width + c.width) / 2),
          reason: 'the painted circular dots overlap',
        );
        expect(
          frame.paintOrder.indexOf('fp:p1'),
          greaterThan(frame.paintOrder.indexOf('fp:p0')),
        );
        expect(
          constellationTapTargetContains(frame.tapTargets['fp:p1']!, b.center),
          isTrue,
          reason: "C's touch target can swallow the lower overlapping B centre",
        );
        for (final entry in frame.bodies.entries) {
          if (entry.key == 'fp:p8') continue;
          expect(
            (entry.value.center - frame.bodies['fp:p8']!.center).distance,
            greaterThan(kMinInteractiveDimension + 16),
            reason: 'the lone node is clear of competing dot targets',
          );
        }

        final misses = <String>[];
        // Fractions avoid an exact nearest-centre tie. Both sides of each
        // segment must resolve by distance, even inside C's expanded target.
        for (final (label, from, to, fraction, expected, offset) in [
          ('B centre', 'p0', 'p0', 0.0, 'p0', Offset.zero),
          ('E centre', 'p2', 'p2', 0.0, 'p2', Offset.zero),
          ('between C and B, nearer B', 'p1', 'p0', 0.75, 'p0', Offset.zero),
          ('between C and B, nearer C', 'p1', 'p0', 0.25, 'p1', Offset.zero),
          ('between C and E, nearer E', 'p1', 'p2', 0.75, 'p2', Offset.zero),
          ('between C and E, nearer C', 'p1', 'p2', 0.25, 'p1', Offset.zero),
          for (final direction in const [
            Offset(1, 0),
            Offset(-1, 0),
            Offset(0, 1),
            Offset(0, -1),
            Offset(1, 1),
            Offset(-1, 1),
            Offset(1, -1),
            Offset(-1, -1),
          ])
            (
              '16 px from lone node toward $direction',
              'p8',
              'p8',
              0.0,
              'p8',
              direction * (16 / direction.distance),
            ),
        ]) {
          if (expected == 'p8') {
            expect(offset.distance, closeTo(16, 1e-9));
          }
          for (final kind in [
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
          ]) {
            for (var repeat = 0; repeat < 2; repeat++) {
              cubit.selectPerson(null);
              await tester.pumpAndSettle();
              final current = holder.frame!;
              final a = current.bodies['fp:$from']!.center;
              final z = current.bodies['fp:$to']!.center;
              final origin = tester.getTopLeft(
                find.byType(ConstellationViewportOverlay),
              );
              final point = _browserPoint(
                origin + a + (z - a) * fraction + offset,
              );
              await tester.runAsync(
                () => _nativeInput({
                  'kind': kind.name,
                  'x': point.dx,
                  'y': point.dy,
                }),
              );
              await tester.pumpAndSettle();
              if (cubit.state.selectedPersonId != expected) {
                misses.add(
                  '${kind.name} $label: selected '
                  '${cubit.state.selectedPersonId} (expected $expected)',
                );
              }
              if (cubit.state.selectedPersonId == expected) {
                final rings = find.byKey(
                  const ValueKey('constellation.nodeRings'),
                );
                final ring =
                    tester.widget<CustomPaint>(rings).painter!
                        as ConstellationNodeRingPainter;
                final body = holder.frame!.bodies['fp:$expected']!;
                expect(ring.selectedGraphId, 'fp:$expected');
                expect(body.longestSide, lessThan(kMinInteractiveDimension));
                expect(
                  rings,
                  paints..something(
                    (method, args) =>
                        method == #drawCircle &&
                        ((args[0] as Offset) - body.center).distance < 0.01 &&
                        (args[1] as double) >= kMinInteractiveDimension / 2 &&
                        (args[2] as Paint).style == PaintingStyle.stroke,
                  ),
                );
              }
            }
          }
        }
        debugPrint('Native selection checks completed: ${jsonEncode(misses)}');
        expect(
          misses,
          isEmpty,
          reason: 'native browser input must select the expected person',
        );
      } finally {
        ui_web.TestEnvironment.setUp(environment);
        // Real web semantics also creates a platform-owned handle. Release
        // that request before our test handle, then restore the dispatcher
        // override through the normal test teardown.
        tester.platformDispatcher.semanticsEnabledTestValue = false;
        addTearDown(tester.platformDispatcher.clearSemanticsEnabledTestValue);
        semantics.dispose();
      }
    },
  );
}
