// Issue #458: opening a preview / context panel must not leave the tapped
// node under it. The camera pans (no zoom change) so the node sits beside the
// side sheet on wide windows and above the bottom sheet on compact ones; the
// pan animates instead of jumping; a node already clear of the panel stays put.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/test_ids.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _wide = Size(1280, 800);
const _compact = Size(390, 844);
const _requestId = 'req-in-2';
const _requestGraphId = '${TenturaGraphNodeKind.fieldRequest}:$_requestId';
const _personId = 'am';
const _personGraphId = '${TenturaGraphNodeKind.fieldPerson}:$_personId';
// A small window's label budget keeps one beacon per author (req-in-2 is
// dropped at 390x844), so the compact case uses am's only beacon.
const _compactRequestId = 'req-am-1';
const _compactRequestGraphId =
    '${TenturaGraphNodeKind.fieldRequest}:$_compactRequestId';
const _previewKey = Key('constellation.request_preview');

Finder _nodeFinder(String domainId) =>
    find.byKey(TestIds.key(TestIds.graphNode(domainId)));

Finder get _node => _nodeFinder(_requestId);
Finder get _person => _nodeFinder(_personId);
Finder get _preview => find.byKey(_previewKey);
Finder get _personPanel => find.byType(GraphPersonContextPanel);

Offset _sceneOf(ConstellationCubit cubit, String graphId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  expect(point, isNotNull, reason: '$graphId must be laid out');
  return Offset(point!.x, point.y);
}

/// Where the camera currently draws [graphId]'s scene centre, in viewport
/// coordinates. Only the camera moves it (the scene point is fixed).
Offset _viewportOf(ConstellationCubit cubit, String graphId) =>
    cubit.graphController.sceneToViewportLocal(_sceneOf(cubit, graphId));

/// Pans (never zooms) so the node widget [finder] (scene id [graphId]) is
/// centred at the global point [target].
Future<void> _parkAtGlobal(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required Finder finder,
  required String graphId,
  required Offset target,
}) async {
  final controller = cubit.graphController;
  // Constant gap between the widget's global centre and the camera's
  // viewport-local projection of its scene point (header rows, widget box).
  final gap = tester.getCenter(finder) - _viewportOf(cubit, graphId);
  final wantedLocal = target - gap;
  final viewportCentre = controller.viewportSize!.center(Offset.zero);
  final scale = controller.cameraScale;
  controller.jumpToPosition(
    _sceneOf(cubit, graphId) - (wantedLocal - viewportCentre) / scale,
  );
  await tester.pumpAndSettle();
  expect(
    (tester.getCenter(finder) - target).distance,
    lessThan(1.5),
    reason: 'test setup must park $graphId at $target',
  );
}

Future<ConstellationCubit> _pump(
  WidgetTester tester, {
  Size size = _wide,
}) async {
  final cubit = await loadReferenceCubit();
  addTearDown(cubit.close);
  await pumpConstellationBody(
    tester,
    cubit,
    size: size,
    locale: const Locale('en'),
  );
  await tester.pumpAndSettle();
  if (size == _wide) {
    expect(_node, findsOneWidget);
    expect(_person, findsOneWidget);
  }
  return cubit;
}

Future<void> _tapNode(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.tap(_node);
  await tester.pump();
  await tester.pumpAndSettle();
  expect(cubit.state.selectedRequestId, _requestId);
  expect(_preview, findsOneWidget);
}

/// x where the right rail opens on a wide window (middle of the rail).
double _railCentreX(WidgetTester tester, Size size) {
  final tt = tester.element(find.byType(ConstellationBody)).tt;
  return size.width - tt.screenHPadding - tt.graphPersonContextWidth / 2;
}

void _expectUnder(Rect panel, Offset before) {
  expect(
    panel.contains(before),
    isTrue,
    reason:
        'test setup must park the node under the panel '
        '(node centre $before, panel $panel)',
  );
}

void main() {
  group('request preview keeps the selected node visible (#458)', () {
    testWidgets('a node under the side sheet is panned beside it', (
      tester,
    ) async {
      final cubit = await _pump(tester);
      await _parkAtGlobal(
        tester,
        cubit,
        finder: _node,
        graphId: _requestGraphId,
        target: Offset(_railCentreX(tester, _wide), _wide.height / 2),
      );
      final scaleBefore = cubit.graphController.cameraScale;
      final centreBefore = tester.getCenter(_node);

      await _tapNode(tester, cubit);

      final panel = tester.getRect(_preview);
      _expectUnder(panel, centreBefore);

      final node = tester.getRect(_node);
      expect(
        node.right,
        lessThanOrEqualTo(panel.left),
        reason:
            'the selected node must sit beside the preview sheet, not under '
            'it (node $node, sheet $panel)',
      );
      expect(node.left, greaterThanOrEqualTo(0));
      expect(node.top, greaterThanOrEqualTo(0));
      expect(node.bottom, lessThanOrEqualTo(_wide.height));
      expect(
        cubit.graphController.cameraScale,
        closeTo(scaleBefore, 0.001),
        reason: 'revealing the node pans the camera; it must not zoom',
      );
    });

    testWidgets('a node already clear of the sheet does not move the camera', (
      tester,
    ) async {
      final cubit = await _pump(tester);
      await _parkAtGlobal(
        tester,
        cubit,
        finder: _node,
        graphId: _requestGraphId,
        target: Offset(_wide.width * 0.3, _wide.height / 2),
      );
      final scaleBefore = cubit.graphController.cameraScale;
      final centreBefore = tester.getCenter(_node);

      await _tapNode(tester, cubit);

      final panel = tester.getRect(_preview);
      expect(tester.getRect(_node).right, lessThanOrEqualTo(panel.left));
      final centreAfter = tester.getCenter(_node);
      expect(
        (centreAfter - centreBefore).distance,
        lessThan(1),
        reason: 'no recentring when the node is already visible',
      );
      expect(cubit.graphController.cameraScale, closeTo(scaleBefore, 0.001));
    });

    testWidgets('a person under the context panel is panned beside it', (
      tester,
    ) async {
      final cubit = await _pump(tester);
      await _parkAtGlobal(
        tester,
        cubit,
        finder: _person,
        graphId: _personGraphId,
        target: Offset(_railCentreX(tester, _wide), _wide.height / 2),
      );
      final scaleBefore = cubit.graphController.cameraScale;
      final centreBefore = tester.getCenter(_person);

      await tester.tap(_person);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(cubit.state.selectedPersonId, _personId);
      expect(_personPanel, findsOneWidget);

      final panel = tester.getRect(_personPanel);
      _expectUnder(panel, centreBefore);

      final node = tester.getRect(_person);
      expect(
        node.right,
        lessThanOrEqualTo(panel.left),
        reason:
            'the selected person must sit beside the context panel, not '
            'under it (node $node, panel $panel)',
      );
      expect(node.left, greaterThanOrEqualTo(0));
      expect(node.top, greaterThanOrEqualTo(0));
      expect(node.bottom, lessThanOrEqualTo(_wide.height));
      expect(
        cubit.graphController.cameraScale,
        closeTo(scaleBefore, 0.001),
        reason: 'revealing the person pans the camera; it must not zoom',
      );
    });

    testWidgets('the reveal pan animates instead of jumping', (tester) async {
      final cubit = await _pump(tester);
      await _parkAtGlobal(
        tester,
        cubit,
        finder: _node,
        graphId: _requestGraphId,
        target: Offset(_railCentreX(tester, _wide), _wide.height / 2),
      );
      final scaleBefore = cubit.graphController.cameraScale;
      final start = _viewportOf(cubit, _requestGraphId);

      // Sample the camera frame by frame from the tap on (2 s at ~60 fps
      // covers a double-tap disambiguation delay plus the pan).
      await tester.tap(_node);
      await tester.pump();
      final samples = <Offset>[_viewportOf(cubit, _requestGraphId)];
      final scales = <double>[cubit.graphController.cameraScale];
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        samples.add(_viewportOf(cubit, _requestGraphId));
        scales.add(cubit.graphController.cameraScale);
      }
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, _requestId);
      final end = _viewportOf(cubit, _requestGraphId);

      final travel = (end - start).distance;
      expect(
        travel,
        greaterThan(20),
        reason: 'the node under the sheet must be panned into view',
      );

      final firstMoved = samples.firstWhere(
        (s) => (s - start).distance > 1,
        orElse: () => end,
      );
      expect(
        (firstMoved - end).distance,
        greaterThan(1),
        reason:
            'the first frame that moves the camera must not already be the '
            'final position (a jump); start $start, end $end',
      );

      final between = samples.where(
        (s) => (s - start).distance > 1 && (s - end).distance > 1,
      );
      expect(
        between,
        isNotEmpty,
        reason: 'at least one frame must show the camera mid-pan',
      );
      for (final s in between) {
        // A pan moves along the straight line from start to end.
        expect(
          (s - start).distance + (s - end).distance,
          lessThan(travel + 2),
          reason: 'mid-pan frame $s is off the start→end line',
        );
      }
      for (final scale in scales) {
        expect(
          scale,
          closeTo(scaleBefore, 0.001),
          reason: 'the animated reveal pans; it must never zoom',
        );
      }
    });

    testWidgets('compact: a node under the bottom sheet ends up above it', (
      tester,
    ) async {
      final cubit = await _pump(tester, size: _compact);
      final compactNode = _nodeFinder(_compactRequestId);
      if (compactNode.evaluate().isEmpty) {
        // Off-screen nodes are culled; centre it (pan only) so it is built.
        cubit.graphController.jumpToPosition(
          _sceneOf(cubit, _compactRequestGraphId),
        );
        await tester.pumpAndSettle();
      }
      expect(compactNode, findsOneWidget);
      // Low in the window: the bottom-docked preview will open over it.
      await _parkAtGlobal(
        tester,
        cubit,
        finder: compactNode,
        graphId: _compactRequestGraphId,
        target: Offset(_compact.width / 2, _compact.height - 120),
      );
      final scaleBefore = cubit.graphController.cameraScale;
      final centreBefore = tester.getCenter(compactNode);

      await tester.tap(compactNode);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, _compactRequestId);
      expect(_preview, findsOneWidget);

      final panel = tester.getRect(_preview);
      _expectUnder(panel, centreBefore);

      final node = tester.getRect(compactNode);
      expect(
        node.bottom,
        lessThanOrEqualTo(panel.top),
        reason:
            'the selected node must sit above the bottom sheet, not under '
            'it (node $node, sheet $panel)',
      );
      expect(node.top, greaterThanOrEqualTo(0));
      expect(node.left, greaterThanOrEqualTo(0));
      expect(node.right, lessThanOrEqualTo(_compact.width));
      expect(
        cubit.graphController.cameraScale,
        closeTo(scaleBefore, 0.001),
        reason: 'revealing the node pans the camera; it must not zoom',
      );
    });
  });
}
