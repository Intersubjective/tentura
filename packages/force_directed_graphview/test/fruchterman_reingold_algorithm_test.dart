import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show mintGraphLayoutTicket;

GraphLayoutRequest _request({
  required Object owner,
  required Map<GraphNodeId, GraphLayoutNode> nodes,
  Map<GraphEdgeId, GraphLayoutEdge> edges = const {},
}) {
  final ticket = mintGraphLayoutTicket(
    owner: owner,
    topologyRevision: 1,
    generation: 1,
  );
  return GraphLayoutRequest(
    ticket: ticket,
    canvasSize: SceneSize(width: 500, height: 500),
    nodesById: nodes,
    edgesById: edges,
  );
}

GraphLayoutNode _layoutNode(String id) => GraphLayoutNode(
      id: id,
      size: SceneSize(width: 100, height: 100),
    );

void main() {
  final owner = Object();

  test('showIterations emits intermediate frames then completes', () async {
    final request = _request(
      owner: owner,
      nodes: {
        '1': _layoutNode('1'),
        '2': _layoutNode('2'),
      },
      edges: {
        'e': const GraphLayoutEdge(
          id: 'e',
          sourceId: '1',
          destinationId: '2',
        ),
      },
    );
    const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(
      iterations: 20,
      showIterations: true,
    );

    var yieldedFrames = 0;
    await for (final frame in GraphLayoutFrameIngress.enforce(
      algorithm.layout(request),
      request,
    )) {
      yieldedFrames++;
      expect(frame.positions.keys, containsAll(['1', '2']));
    }

    expect(yieldedFrames, greaterThan(1));
  });

  test('terminal frame includes every requested node', () async {
    const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(iterations: 5);
    final request = _request(
      owner: owner,
      nodes: {'1': _layoutNode('1')},
      edges: {
        'loop': const GraphLayoutEdge(
          id: 'loop',
          sourceId: '1',
          destinationId: '1',
        ),
      },
    );

    final terminal = await GraphLayoutFrameIngress.enforce(
      algorithm.layout(request),
      request,
    ).last;

    expect(terminal.isTerminal, isTrue);
    expect(terminal.positions.keys, ['1']);
    expect(terminal.positions['1']!.x.isFinite, isTrue);
    expect(terminal.positions['1']!.y.isFinite, isTrue);
  });
}
