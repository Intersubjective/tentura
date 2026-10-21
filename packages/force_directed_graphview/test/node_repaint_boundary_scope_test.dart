import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';
import 'support/settle_graph_layout.dart';

typedef _Controller = GraphController<Node<int>, Edge<Node<int>, int>>;

void main() {
  group('Node repaint boundary scope', () {
    testWidgets(
      'a resting scene gives no node its own repaint boundary',
      (tester) async {
        final harness = await _pumpGraph(tester);

        expect(find.byType(_Content), findsNWidgets(_nodes.length));
        for (final node in _nodes) {
          expect(
            _nodeBoundaryCount(tester, node.data),
            0,
            reason: 'Node ${node.data} is not moving and must paint into the '
                'shared scene layer',
          );
        }
        expect(_nodesLayerBoundaryCount(tester), 0);
        harness.controller.dispose();
      },
    );

    testWidgets(
      'only the dragged node gets a repaint boundary while it is dragged',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(220, 140));
        await tester.pump();

        expect(_nodeBoundaryCount(tester, 1), 1);
        expect(_nodeBoundaryCount(tester, 2), 0);
        expect(_nodeBoundaryCount(tester, 3), 0);
        expect(_nodesLayerBoundaryCount(tester), 1);

        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();

        expect(
          _nodesLayerBoundaryCount(tester),
          0,
          reason: 'The boundary is dropped once the drag is over',
        );
        controller.dispose();
      },
    );

    testWidgets(
      'a node keeps its state when its boundary is added and removed',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;
        final initial = harness.statesCreated['1'];

        final token = controller.beginNodePresentationDragForId(
          '1',
          const Offset(100, 100),
        );
        controller.updateNodePresentationDrag(token, const Offset(200, 120));
        await tester.pump();
        controller.cancelNodePresentationDrag(token);
        await tester.pump();
        await tester.pump();

        expect(harness.statesCreated['1'], initial);
        expect(harness.statesCreated['2'], 1);
        expect(find.byType(_Content), findsNWidgets(_nodes.length));
        controller.dispose();
      },
    );

    testWidgets(
      'a node animating towards a new layout stays in the shared resting layer',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        controller.requestSceneLayout(
          algorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 380, y: 100),
            '2': ScenePoint(x: 300, y: 300),
            '3': ScenePoint(x: 100, y: 400),
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.isLayoutTransitioning, isTrue);
        expect(
          _nodeBoundaryCount(tester, 1),
          _nodeBoundaryCount(tester, 3),
          reason: 'A transition mover shares the resting layer instead of '
              'getting a boundary (and a GlobalKey re-parent) of its own',
        );

        await tester.pumpAndSettle();

        expect(controller.isLayoutTransitioning, isFalse);
        expect(_nodesLayerBoundaryCount(tester), 0);
        controller.dispose();
      },
    );

    testWidgets(
      'nodes animating towards a new layout are not isolated from resting ones',
      (tester) async {
        final harness = await _pumpGraph(tester);
        final controller = harness.controller;

        controller.requestSceneLayout(
          algorithm: FixedSceneLayoutAlgorithm({
            '1': ScenePoint(x: 380, y: 100),
            '2': ScenePoint(x: 300, y: 120),
            '3': ScenePoint(x: 100, y: 400),
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.isLayoutTransitioning, isTrue);
        expect(
          _nodeBoundaryCount(tester, 1),
          _nodeBoundaryCount(tester, 3),
        );
        expect(
          _nodeBoundaryCount(tester, 2),
          _nodeBoundaryCount(tester, 3),
          reason: 'Node 3 keeps its position and is not animating',
        );

        await tester.pumpAndSettle();

        expect(controller.isLayoutTransitioning, isFalse);
        expect(_nodesLayerBoundaryCount(tester), 0);
        controller.dispose();
      },
    );
  });
}

const _nodes = [
  Node<int>(data: 1, size: 40),
  Node<int>(data: 2, size: 40),
  Node<int>(data: 3, size: 40),
];

final class _Harness {
  _Harness(this.controller, this.statesCreated);

  final _Controller controller;
  final Map<String, int> statesCreated;
}

Future<_Harness> _pumpGraph(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = testIntIntGraphController();
  final statesCreated = <String, int>{};

  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, int>>(
        controller: controller,
        canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
        layoutAlgorithm: FixedSceneLayoutAlgorithm({
          '1': ScenePoint(x: 100, y: 100),
          '2': ScenePoint(x: 300, y: 300),
          '3': ScenePoint(x: 100, y: 400),
        }),
        layoutTransitionDuration: const Duration(milliseconds: 300),
        nodeBuilder: (context, node) => _Content(
          key: ValueKey('node-${node.data}'),
          size: node.size,
          onStateCreated: () => statesCreated.update(
            node.data.toString(),
            (count) => count + 1,
            ifAbsent: () => 1,
          ),
        ),
      ),
    ),
  );
  controller.reconcileTopology({..._nodes}, const {});
  await settleGraphLayout(tester, controller);
  await tester.pumpAndSettle();
  return _Harness(controller, statesCreated);
}

class _Content extends StatefulWidget {
  const _Content({
    required this.size,
    required this.onStateCreated,
    super.key,
  });

  final double size;
  final VoidCallback onStateCreated;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  @override
  void initState() {
    super.initState();
    widget.onStateCreated();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: widget.size, height: widget.size);
}

/// Repaint boundaries between the node [data]'s content and the node layer.
int _nodeBoundaryCount(WidgetTester tester, int data) {
  var count = 0;
  final element = tester.element(find.byKey(ValueKey('node-$data')));
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is CustomMultiChildLayout) {
      return false;
    }
    if (widget is RepaintBoundary) {
      count++;
    }
    return true;
  });
  return count;
}

/// Repaint boundaries anywhere in the node layer, summed over all nodes.
int _nodesLayerBoundaryCount(WidgetTester tester) {
  var count = 0;
  for (final node in _nodes) {
    count += _nodeBoundaryCount(tester, node.data);
  }
  return count;
}
